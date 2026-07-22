#!/usr/bin/env bash
#
# Replace the reMarkable Paper Pro's boot / sleep / shutdown screens with an
# image of your choice.
#
#   ./apply-splash.sh --image cat.png
#   ./apply-splash.sh --image cat.png --targets boot,sleep,deep-sleep,battery-empty
#   ./apply-splash.sh --status
#   ./apply-splash.sh --revert
#
# Firmware updates replace the whole rootfs and wipe this. Re-run afterwards.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

REMOTE_DIR=/usr/share/remarkable
PANEL_W=1620
PANEL_H=2160
BACKUP_DIR="$HERE/../.backups"

# friendly name -> file in /usr/share/remarkable
target_file() {
  case "$1" in
    boot)          echo starting.png ;;
    first-boot)    echo starting_first.png ;;
    sleep)         echo suspended.png ;;
    deep-sleep)    echo hibernate.png ;;
    poweroff)      echo poweroff.png ;;
    reboot)        echo rebooting.png ;;
    battery-empty) echo batteryempty.png ;;
    *) die "unknown target '$1'. Valid: boot, first-boot, sleep, deep-sleep, poweroff, reboot, battery-empty" ;;
  esac
}

IMAGE=""
TARGETS="boot,sleep,deep-sleep"
ACTION=apply

while [ $# -gt 0 ]; do
  case "$1" in
    --image)   IMAGE="${2:?--image needs a path}"; shift 2 ;;
    --targets) TARGETS="${2:?--targets needs a list}"; shift 2 ;;
    --revert)  ACTION=revert; shift ;;
    --status)  ACTION=status; shift ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

files_for_targets() {
  local out=""
  local IFS=,
  for t in $TARGETS; do out="$out $(target_file "$t")"; done
  echo "$out"
}

# Reject a bad --targets now rather than after the device round-trip, so a typo
# fails immediately instead of looking like a connectivity problem.
files_for_targets >/dev/null

# Compose the source image to exactly panel size.
#
# Stock starting.png/suspended.png are 8-bit grayscale, but factory.png in the
# same directory is 8-bit colormap and renders in color -- verified on the boot
# splash. So we emit PNG8 colormap to get color on the Gallery 3 panel.
compose() {
  local src="$1" out="$2"
  require_cmd magick "Install ImageMagick:  brew install imagemagick"
  [ -f "$src" ] || die "no such image: $src"
  say "composing ${PANEL_W}x${PANEL_H} from $(basename "$src")"
  magick "$src" -background white -alpha remove -alpha off \
    -resize "${PANEL_W}x${PANEL_H}" -gravity center \
    -extent "${PANEL_W}x${PANEL_H}" -background white \
    -colors 256 "PNG8:$out"
}

backup_originals() {
  local files="$1"
  mkdir -p "$BACKUP_DIR"
  # On-device backup: cp -n never clobbers an existing .orig, so re-running
  # after a firmware update captures the new stock file only if none is saved.
  rsh "cd $REMOTE_DIR && for f in $files; do cp -n \"\$f\" \"\$f.orig\" 2>/dev/null || true; done"
  # Local backup too, in case the rootfs is ever reflashed.
  for f in $files; do
    if [ ! -f "$BACKUP_DIR/$f" ]; then
      rsh "cat $REMOTE_DIR/$f.orig 2>/dev/null || cat $REMOTE_DIR/$f" > "$BACKUP_DIR/$f" || true
      [ -s "$BACKUP_DIR/$f" ] || rm -f "$BACKUP_DIR/$f"
    fi
  done
  say "originals preserved (device: *.orig, local: .backups/)"
}

do_apply() {
  [ -n "$IMAGE" ] || die "need --image PATH (or --revert / --status)"
  require_device; require_paper_pro
  local files staged want
  files="$(files_for_targets)"
  staged="$(mktemp -t rmpp-splash).png"
  compose "$IMAGE" "$staged"
  want="$(md5 -q "$staged")"

  local free
  free="$(rsh "df -k / | tail -n 1 | awk '{print \$4}'")"
  info "rootfs free: $((free/1024)) MB"
  [ "${free:-0}" -gt 4096 ] || die "less than 4 MB free on /; refusing to write"

  backup_originals "$files"
  rootfs_rw
  for f in $files; do
    rpush "$staged" "$REMOTE_DIR/$f.new"
    rsh "cd $REMOTE_DIR && mv '$f.new' '$f' && chmod 644 '$f'"
    local got
    got="$(rsh "md5sum $REMOTE_DIR/$f" | cut -d' ' -f1)"
    [ "$got" = "$want" ] || die "checksum mismatch on $f (got $got, want $want)"
    info "$f  ok"
  done
  restore_rootfs_ro
  rm -f "$staged"
  say "done. Reboot to see the boot splash; press power to see the sleep screen."
}

do_revert() {
  require_device
  local files; files="$(files_for_targets)"
  rootfs_rw
  for f in $files; do
    if rsh "test -f $REMOTE_DIR/$f.orig"; then
      rsh "cd $REMOTE_DIR && cp '$f.orig' '$f'"
      info "$f  restored from device backup"
    elif [ -f "$BACKUP_DIR/$f" ]; then
      rpush "$BACKUP_DIR/$f" "$REMOTE_DIR/$f"
      info "$f  restored from local backup"
    else
      warn "$f: no backup found, left as-is"
    fi
  done
  restore_rootfs_ro
  say "reverted"
}

do_status() {
  require_device
  printf '%-16s %-34s %s\n' TARGET MD5 NOTE
  local IFS=,
  for t in $TARGETS; do
    local f got orig
    f="$(target_file "$t")"
    got="$(rsh "md5sum $REMOTE_DIR/$f 2>/dev/null" | cut -d' ' -f1)"
    orig=$(rsh "test -f $REMOTE_DIR/$f.orig && echo yes || echo no")
    printf '%-16s %-34s %s\n' "$t" "${got:-?}" "backup=$orig"
  done
  rsh 'df -h / | tail -n 1'
}

case "$ACTION" in
  apply)  do_apply ;;
  revert) do_revert ;;
  status) do_status ;;
esac
