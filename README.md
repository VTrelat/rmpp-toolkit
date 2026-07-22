# rmpp-toolkit

Scripts for customising a **reMarkable Paper Pro** over SSH from macOS:

- **Live screen** in your browser — the feature otherwise gated behind the
  Connect subscription — installed as a persistent systemd service.
- **Custom splash screens** for boot, sleep, deep sleep and friends, in colour.

Paper Pro only. reMarkable 1/2 have a different CPU architecture and a real
`/dev/fb0`; use [Toltec](https://toltec-dev.org/) for those.

## Requirements

- Paper Pro with **developer mode already enabled** and working SSH key access.
  Enabling developer mode **erases the tablet** — this toolkit will not do it for
  you. Verify with `ssh root@10.11.99.1 true`.
- Tablet connected over USB (`10.11.99.1`).
- macOS with `imagemagick` (splash only): `brew install imagemagick`.

## Quick start

```bash
git clone <this-repo> ~/Documents/rmpp-toolkit
cd ~/Documents/rmpp-toolkit
./setup.sh doctor
```

`doctor` verifies the connection and prints firmware, storage, mount state and
which components are already installed. Then pick what you want:

```bash
./setup.sh stream                     # live screen -> https://10.11.99.1:2001
./setup.sh splash --image ~/cat.png   # boot + sleep + deep-sleep screens
./setup.sh all --image ~/cat.png      # both
```

## Live screen

```bash
./setup.sh stream
```

Downloads [goMarkableStream](https://github.com/owulveryck/goMarkableStream),
**verifies it against the release's published SHA-256** before installing,
generates a 20-character password, and registers a systemd unit that survives
reboots. It prints the URL and credentials at the end — save them, the password
is not stored on your Mac.

The TLS certificate is self-signed, so your browser warns once. That is expected.

| Flag | Effect |
|---|---|
| `--password 'x'` | use your own instead of a generated one |
| `--bind 0.0.0.0:2001` | expose on all interfaces (**read the warning**) |
| `--version latest` | track upstream instead of the pinned release |
| `--status` | report unit state, bind address, and whether it will survive reboot |
| `--uninstall` | remove service, binary, credentials, certificates |
| `--uninstall --keep-config` | keep the JWT key and TLS cert so browser sessions survive a reinstall |

If you reinstall without `--keep-config`, a new JWT signing key is generated and
every browser holding a saved session starts showing
`Reconnecting (attempt N/10)` — which looks like a network fault but is just a
stale token. Run `localStorage.clear(); location.reload()` in the browser console
and log in again. The installer warns you when this applies.

By default it binds to `10.11.99.1:2001` — the USB address only — so it is not
reachable over wifi.

## Splash screens

```bash
./setup.sh splash --image ~/cat.png
./setup.sh splash --status
./setup.sh splash --revert
```

Any image works; it is flattened onto white, fitted to 1620×2160 and written as
an 8-bit colormap PNG, which renders **in colour** on the Gallery 3 panel.

Targets default to `boot,sleep,deep-sleep`. Pick your own with `--targets`:

| Name | File | Shown |
|---|---|---|
| `boot` | `starting.png` | while booting (a few seconds) |
| `first-boot` | `starting_first.png` | first boot after a reset |
| `sleep` | `suspended.png` | **whenever the tablet sleeps — the one you actually look at** |
| `deep-sleep` | `hibernate.png` | deep sleep |
| `poweroff` | `poweroff.png` | shutting down |
| `reboot` | `rebooting.png` | rebooting |
| `battery-empty` | `batteryempty.png` | flat battery |

Originals are backed up twice: on the device as `*.orig`, and into `.backups/`
here (gitignored). `--revert` restores from either.

## Read this before filing a bug against yourself

[`docs/CAVEATS.md`](docs/CAVEATS.md) — the traps, several of which fail
*silently*:

- `/etc` is a **tmpfs overlay**; unit files written normally vanish on reboot
  with no error
- firmware updates wipe the rootfs — re-run after each one
- deep sleep drops USB ethernet and looks exactly like a crash
- BusyBox is not coreutils (`head -3` fails, no `strings`, no brace expansion)
- `pkill -f` over SSH kills its own shell

[`docs/FINDINGS.md`](docs/FINDINGS.md) — why `reStream`, `rmview` and every
`cat /dev/fb0` guide **cannot** work on this hardware: no framebuffer device,
`xochitl` is exclusive DRM master, and its CMA buffers are unreadable through
`/proc/PID/mem` (`VM_PFNMAP`), `pagemap`, debugfs (not compiled in) or
`/dev/mem` (`STRICT_DEVMEM`). Also documents the stream wire format and the
6528-byte stride that produces a sheared image if you get it wrong.

## Layout

```
setup.sh                       entry point / dispatcher
lib/common.sh                  ssh helpers, rootfs rw/ro, persistent-write trick
splash/apply-splash.sh         apply / revert / status for splash screens
stream/install-stream.sh       download, verify, install service
stream/gomarkablestream.service  unit template
docs/CAVEATS.md                the traps
docs/FINDINGS.md               framebuffer investigation + wire format
```

Override the target with `RM_HOST=root@192.168.1.50 ./setup.sh doctor` if you
are not on USB.

## Safety

Scripts remount `/` read-write only for as long as needed and restore read-only
via an `EXIT`/`INT`/`TERM` trap, so an interrupted run cannot leave the system
partition writable. The downloaded binary is checksum-verified before it is
installed. Nothing here touches the bootloader, the encrypted `/home` volume, or
developer mode.

Not affiliated with reMarkable AS. Third-party components keep their own
licences — goMarkableStream is GPL-3.0.
