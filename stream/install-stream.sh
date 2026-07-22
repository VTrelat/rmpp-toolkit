#!/usr/bin/env bash
#
# Install goMarkableStream on a reMarkable Paper Pro as a persistent systemd
# service, giving you the live screen in a browser without a Connect
# subscription.
#
#   ./install-stream.sh                      # generate a password, USB-only bind
#   ./install-stream.sh --password 'hunter2'
#   ./install-stream.sh --bind 0.0.0.0:2001  # expose on wifi too -- read the warning
#   ./install-stream.sh --status
#   ./install-stream.sh --uninstall
#
# Upstream: https://github.com/owulveryck/goMarkableStream

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

REPO=owulveryck/goMarkableStream
VERSION="${GMS_VERSION:-v1.3.1}"     # pinned; --version latest to track upstream
ASSET=gomarkablestream-RMPRO         # Paper Pro is aarch64; RM2 asset will not run
REMOTE_BIN=/home/root/goMarkableStream
REMOTE_ENV=/home/root/.gms.env
UNIT_PATH=/etc/systemd/system/gomarkablestream.service
UNIT_NAME=gomarkablestream

BIND="10.11.99.1:2001"
USERNAME=admin
PASSWORD=""
ACTION=install

while [ $# -gt 0 ]; do
  case "$1" in
    --password)  PASSWORD="${2:?--password needs a value}"; shift 2 ;;
    --username)  USERNAME="${2:?--username needs a value}"; shift 2 ;;
    --bind)      BIND="${2:?--bind needs host:port}"; shift 2 ;;
    --version)   VERSION="${2:?--version needs a tag or 'latest'}"; shift 2 ;;
    --status)    ACTION=status; shift ;;
    --uninstall) ACTION=uninstall; shift ;;
    -h|--help)   awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

resolve_version() {
  [ "$VERSION" = latest ] || return 0
  require_cmd curl
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
  [ -n "$VERSION" ] || die "could not resolve latest release tag"
}

# Download the binary and verify it against the release's published checksums.
# We are about to run this as root on the device -- an unverified download is
# not acceptable.
fetch_verified() {
  local dir="$1"
  require_cmd curl
  require_cmd shasum
  local base="https://github.com/$REPO/releases/download/$VERSION"
  say "downloading $ASSET $VERSION"
  curl -fsSL -o "$dir/$ASSET" "$base/$ASSET" || die "download failed"
  curl -fsSL -o "$dir/checksums.txt" "$base/checksums.txt" || die "checksums download failed"
  local want got
  want="$(grep " $ASSET\$" "$dir/checksums.txt" | awk '{print $1}')"
  got="$(shasum -a 256 "$dir/$ASSET" | awk '{print $1}')"
  [ -n "$want" ] || die "no checksum published for $ASSET"
  [ "$want" = "$got" ] || die "CHECKSUM MISMATCH
    expected $want
    got      $got
    Refusing to install. Do not run this binary."
  say "checksum verified: $got"
}

gen_password() {
  require_cmd python3
  python3 -c "import secrets,string; a=string.ascii_letters+string.digits; print(''.join(secrets.choice(a) for _ in range(20)))"
}

do_install() {
  require_device; require_paper_pro
  resolve_version
  [ -n "$PASSWORD" ] || { PASSWORD="$(gen_password)"; GENERATED=1; }

  case "$BIND" in
    0.0.0.0:*|:*|"[::]:"*)
      warn "binding to $BIND exposes the live screen on EVERY interface.
    Anyone on the same wifi who guesses the password sees your tablet.
    The safe default is 10.11.99.1:2001 (USB only)." ;;
  esac

  local tmp; tmp="$(mktemp -d -t rmpp-gms)"
  trap 'rm -rf "$tmp"' RETURN
  fetch_verified "$tmp"

  say "installing binary to $REMOTE_BIN"
  rpush "$tmp/$ASSET" "$REMOTE_BIN"
  rsh "chmod +x $REMOTE_BIN"
  local rgot
  rgot="$(rsh "sha256sum $REMOTE_BIN" | awk '{print $1}')"
  [ "$rgot" = "$(shasum -a 256 "$tmp/$ASSET" | awk '{print $1}')" ] \
    || die "binary corrupted in transfer"

  say "writing credentials to $REMOTE_ENV (mode 600, on encrypted /home)"
  cat > "$tmp/gms.env" <<EOF
RK_SERVER_BIND_ADDR=$BIND
RK_SERVER_USERNAME=$USERNAME
RK_SERVER_PASSWORD=$PASSWORD
EOF
  rpush "$tmp/gms.env" "$REMOTE_ENV"
  rsh "chmod 600 $REMOTE_ENV"

  # Any instance started by hand would hold the port and make the service fail
  # with "address already in use".
  kill_remote "[/.]goMarkableStream" >/dev/null || true

  say "installing systemd unit (persistently -- see docs/CAVEATS.md)"
  push_persistent "$HERE/gomarkablestream.service" "$UNIT_PATH" 644
  symlink_persistent "$UNIT_PATH" "/etc/systemd/system/multi-user.target.wants/$UNIT_NAME.service"
  restore_rootfs_ro

  rsh "systemctl daemon-reload && systemctl restart $UNIT_NAME"
  sleep 5

  local active; active="$(rsh "systemctl is-active $UNIT_NAME")"
  [ "$active" = active ] || {
    rsh "journalctl -u $UNIT_NAME -n 15 --no-pager"
    die "service failed to start"
  }

  say "service is $(rsh "systemctl is-enabled $UNIT_NAME") and $active"
  rsh "netstat -ltn 2>/dev/null | grep 2001" || true
  echo
  say "Live screen:  https://${BIND%:*}:${BIND##*:}"
  info "username: $USERNAME"
  info "password: $PASSWORD"
  [ "${GENERATED:-0}" = 1 ] && info "(generated -- save it now, it is not stored on this machine)"
  info "The TLS certificate is self-signed, so your browser will warn once."
}

do_status() {
  require_device
  echo "unit:    $(rsh "systemctl is-enabled $UNIT_NAME 2>&1"), $(rsh "systemctl is-active $UNIT_NAME 2>&1")"
  echo "binary:  $(rsh "test -x $REMOTE_BIN && echo present || echo missing")"
  echo "env:     $(rsh "test -f $REMOTE_ENV && echo present || echo missing")"
  echo "bind:    $(rsh "grep BIND_ADDR $REMOTE_ENV 2>/dev/null | cut -d= -f2")"
  echo "persist: $(rsh "mount --bind / /mnt/rootfs 2>/dev/null; test -f /mnt/rootfs$UNIT_PATH && echo 'unit on real rootfs' || echo 'VOLATILE ONLY - will not survive reboot'; umount /mnt/rootfs 2>/dev/null")"
  rsh "netstat -ltn 2>/dev/null | grep 2001" || echo "not listening"
}

do_uninstall() {
  require_device
  rsh "systemctl disable --now $UNIT_NAME 2>/dev/null" || true
  kill_remote "[/.]goMarkableStream" >/dev/null || true
  rootfs_rw
  rsh "
    mkdir -p /mnt/rootfs; mount --bind / /mnt/rootfs
    rm -f /mnt/rootfs$UNIT_PATH /mnt/rootfs/etc/systemd/system/multi-user.target.wants/$UNIT_NAME.service
    umount /mnt/rootfs
    rm -f $UNIT_PATH /etc/systemd/system/multi-user.target.wants/$UNIT_NAME.service
    sync
  "
  restore_rootfs_ro
  rsh "systemctl daemon-reload"
  rsh "rm -f $REMOTE_BIN $REMOTE_ENV; rm -rf /home/root/.config/goMarkableStream"
  say "removed service, binary, credentials and generated certificates"
}

case "$ACTION" in
  install)   do_install ;;
  status)    do_status ;;
  uninstall) do_uninstall ;;
esac
