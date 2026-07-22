#!/usr/bin/env bash
#
# rmpp-toolkit -- entry point.
#
#   ./setup.sh doctor                    check the connection and report device state
#   ./setup.sh stream                    install the live-screen service
#   ./setup.sh splash --image cat.png    replace boot / sleep / deep-sleep screens
#   ./setup.sh all --image cat.png       both
#
# Every subcommand passes remaining arguments through, so:
#   ./setup.sh splash --status
#   ./setup.sh stream --uninstall
#   ./setup.sh stream --bind 0.0.0.0:2001

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

# Print the leading comment block (line 2 up to the first non-comment line) as
# help text. A fixed line range drifts out of date as soon as the header grows.
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; }

doctor() {
  say "checking $RM_HOST"
  if ! rsh true; then
    die "cannot reach the tablet.
    - plug it in over USB and wake it (deep sleep drops USB ethernet)
    - confirm the interface:  ifconfig | grep 10.11.99
    - developer mode must already be enabled. Enabling it ERASES the tablet,
      so if SSH has never worked, back up your notebooks first."
  fi
  say "connected"
  # /etc/os-release values are quoted; strip them remotely to keep the nesting
  # of quotes here manageable.
  osfield() { rsh "grep '^$1=' /etc/os-release | cut -d= -f2- | tr -d '\"'"; }
  info "host:      $(rsh 'cat /etc/hostname')"
  info "firmware:  $(osfield IMG_VERSION)"
  info "os:        $(osfield PRETTY_NAME)"
  info "uptime:    $(rsh 'uptime')"
  echo
  say "storage"
  rsh 'df -h / /home | grep -v ^Filesystem' | sed 's/^/    /'
  echo
  say "mount state"
  info "rootfs:  $(rsh "mount | grep ' / ' | sed 's/.*type //'")"
  info "/etc:    $(rsh "mount | grep ' /etc ' >/dev/null && echo 'overlay on tmpfs (writes are VOLATILE)' || echo 'plain'")"
  echo
  say "toolkit components"
  info "stream service: $(rsh 'systemctl is-active gomarkablestream 2>&1') / $(rsh 'systemctl is-enabled gomarkablestream 2>&1')"
  info "splash boot:    $(rsh 'test -f /usr/share/remarkable/starting.png.orig && echo customised || echo stock')"
  info "splash sleep:   $(rsh 'test -f /usr/share/remarkable/suspended.png.orig && echo customised || echo stock')"
}

cmd="${1:-}"
[ $# -gt 0 ] && shift || true

case "$cmd" in
  doctor|"")
    doctor
    [ -n "$cmd" ] || { echo; usage; }
    ;;
  stream) exec "$HERE/stream/install-stream.sh" "$@" ;;
  splash) exec "$HERE/splash/apply-splash.sh" "$@" ;;
  all)
    "$HERE/splash/apply-splash.sh" "$@"
    echo
    "$HERE/stream/install-stream.sh"
    ;;
  -h|--help) usage ;;
  *) die "unknown command: $cmd (try: doctor, stream, splash, all)" ;;
esac
