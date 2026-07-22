# shellcheck shell=bash
#
# Shared helpers for rmpp-toolkit. Sourced by every script; not executable.
#
# The two things worth understanding before editing anything here:
#
#   1. The rootfs is mounted read-only. Every write to it must be bracketed by
#      rootfs_rw ... restore_rootfs_ro, and the restore has to happen even if the
#      script dies halfway through. rootfs_rw installs an EXIT trap for that.
#
#   2. /etc is an overlayfs whose upper layer sits on /var/volatile, which is
#      tmpfs. Writing to /etc "works", survives until reboot, and then silently
#      disappears. push_persistent bypasses the overlay -- see its comment.

RM_HOST="${RM_HOST:-root@10.11.99.1}"
RM_IP="${RM_HOST##*@}"
RM_SSH_TIMEOUT="${RM_SSH_TIMEOUT:-10}"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Run a command on the tablet. stderr is dropped because recent OpenSSH prints a
# post-quantum key-exchange warning on every connection that would otherwise
# drown out real output.
rsh() { ssh -o BatchMode=yes -o ConnectTimeout="$RM_SSH_TIMEOUT" "$RM_HOST" "$@" 2>/dev/null; }

# Copy a local file to the tablet (stdin redirect avoids scp's lack of brace
# expansion against the BusyBox shell).
rpush() { ssh -o BatchMode=yes -o ConnectTimeout="$RM_SSH_TIMEOUT" "$RM_HOST" "cat > '$2'" < "$1" 2>/dev/null; }

require_device() {
  rsh true || die "cannot reach $RM_HOST.
    - is the tablet plugged in over USB and awake?
    - deep sleep tears down USB ethernet; wake the tablet and retry
    - check the interface exists:  ifconfig | grep 10.11.99"
}

require_paper_pro() {
  local host
  host="$(rsh 'cat /etc/hostname 2>/dev/null')"
  case "$host" in
    *ferrari*|*chiappa*|*tatsu*) return 0 ;;
    "") die "could not read /etc/hostname from the device" ;;
    *) warn "device reports '$host', which is not a known Paper Pro codename.
    This toolkit is Paper Pro only. reMarkable 1/2 use a different CPU
    architecture and a real /dev/fb0; nothing here will work correctly.
    Set RMPP_FORCE=1 to proceed anyway."
       [ "${RMPP_FORCE:-0}" = 1 ] || exit 1 ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found.${2:+ $2}"
}

# --- read-only rootfs handling ----------------------------------------------

_ROOTFS_RW=0
restore_rootfs_ro() {
  [ "$_ROOTFS_RW" = 1 ] || return 0
  rsh 'sync; mount -o remount,ro /' >/dev/null 2>&1 || true
  _ROOTFS_RW=0
}

rootfs_rw() {
  [ "$_ROOTFS_RW" = 1 ] && return 0
  rsh 'mount -o remount,rw /' || die "could not remount / read-write"
  _ROOTFS_RW=1
  # Restore read-only no matter how we exit -- an interrupted run must never
  # leave the system partition writable.
  trap restore_rootfs_ro EXIT INT TERM
}

# --- persistent writes under / ----------------------------------------------

# push_persistent <local-file> <absolute-remote-path> [mode]
#
# Writes to the *real* on-disk filesystem, not the volatile overlay. A plain
# (non-recursive) bind mount of / exposes the underlying tree without any of the
# submounts, so /mnt/rootfs/etc is the real /etc rather than the tmpfs overlay.
# A copy also goes to the live path so the change takes effect immediately.
push_persistent() {
  local src="$1" dest="$2" mode="${3:-644}" tmp="/home/root/.rmpp-stage"
  [ -f "$src" ] || die "push_persistent: no such file: $src"
  rpush "$src" "$tmp" || die "failed to stage $src on device"
  rootfs_rw
  rsh "
    set -e
    mkdir -p /mnt/rootfs
    mount --bind / /mnt/rootfs
    mkdir -p \"\$(dirname /mnt/rootfs${dest})\"
    cp '$tmp' '/mnt/rootfs${dest}'
    chmod $mode '/mnt/rootfs${dest}'
    umount /mnt/rootfs
    mkdir -p \"\$(dirname ${dest})\"
    cp '$tmp' '${dest}'
    chmod $mode '${dest}'
    rm -f '$tmp'
    sync
  " || { rsh 'umount /mnt/rootfs 2>/dev/null'; die "failed to write $dest"; }
}

# symlink_persistent <link-target> <absolute-link-path>
#
# `systemctl enable` writes its symlink into the volatile overlay, so unit
# enablement does not survive a reboot. This creates the link in the real rootfs.
symlink_persistent() {
  local target="$1" link="$2"
  rootfs_rw
  rsh "
    set -e
    mkdir -p /mnt/rootfs
    mount --bind / /mnt/rootfs
    mkdir -p \"\$(dirname /mnt/rootfs${link})\"
    ln -sf '${target}' '/mnt/rootfs${link}'
    umount /mnt/rootfs
    mkdir -p \"\$(dirname ${link})\"
    ln -sf '${target}' '${link}'
    sync
  " || { rsh 'umount /mnt/rootfs 2>/dev/null'; die "failed to link $link"; }
}

# --- process control ---------------------------------------------------------

# Kill a process by matching its command. Deliberately NOT pkill -f: the pattern
# would also match the SSH shell running the pkill, which kills the session
# instead of the target.
kill_remote() {
  local pattern="$1"
  rsh "PIDS=\$(ps w | grep '$pattern' | grep -v 'grep\|-sh' | awk '{print \$1}');
       for p in \$PIDS; do kill -9 \$p 2>/dev/null; done;
       [ -n \"\$PIDS\" ] && echo \"killed: \$PIDS\" || true"
}
