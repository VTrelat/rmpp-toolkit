# rmpp-toolkit

Scripts for customizing a **reMarkable Paper Pro** over SSH from macOS.

Paper Pro only. reMarkable 1/2 have a different CPU architecture and a real
`/dev/fb0`; use [Toltec](https://toltec-dev.org/) for those.

## Tools

| Command | Tool | What it does |
|---|---|---|
| `./setup.sh doctor` | **Diagnostics** | Checks the connection and reports firmware, storage, mount state, and which components are installed. Run this first. |
| `./setup.sh stream` | **Live screen** | Mirrors the tablet display to your browser — the feature otherwise gated behind the Connect subscription. Installs as a persistent systemd service. |
| `./setup.sh splash` | **Splash screens** | Replaces the boot, sleep, deep-sleep and shutdown screens with any image, in color. |
| `./setup.sh all` | — | Runs `splash` then `stream`. |

More tools may be added over time; each gets its own subcommand and its own
directory at the top level.

## Requirements

- Paper Pro with **developer mode already enabled** and working SSH key access.
  Enabling developer mode **erases the tablet**, so this toolkit will not do it
  for you. Check with `ssh root@10.11.99.1 true`.
- Tablet connected over USB (`10.11.99.1`).
- macOS with `imagemagick` (splash only): `brew install imagemagick`.

## Quick start

```bash
git clone https://github.com/VTrelat/rmpp-toolkit.git
cd rmpp-toolkit
./setup.sh doctor
```

Then pick what you want:

```bash
./setup.sh stream                     # live screen -> https://10.11.99.1:2001
./setup.sh splash --image ~/cat.png   # boot + sleep + deep-sleep screens
./setup.sh all --image ~/cat.png      # both
```

Point it somewhere else with `RM_HOST=root@192.168.1.50 ./setup.sh doctor` if
you are not on USB.

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
| `--password 'x'` | Use your own instead of a generated one. |
| `--bind 0.0.0.0:2001` | Expose on all interfaces (**read the warning**). |
| `--version latest` | Track upstream instead of the pinned release. |
| `--status` | Report unit state, bind address, and whether it survives reboot. |
| `--uninstall` | Remove service, binary, credentials, certificates. |
| `--uninstall --keep-config` | Keep the JWT key and TLS certificate so browser sessions survive a reinstall. |

By default it binds to `10.11.99.1:2001` — the USB address only — so it is not
reachable over wifi.

If you reinstall without `--keep-config`, a new JWT signing key is generated and
every browser holding a saved session starts showing
`Reconnecting (attempt N/10)`. That looks like a network fault but is only a
stale token: run `localStorage.clear(); location.reload()` in the browser
console and log in again. The installer warns you when this applies.

## Splash screens

```bash
./setup.sh splash --image ~/cat.png
./setup.sh splash --status
./setup.sh splash --revert
```

Any image works. It is flattened onto white, fitted to 1620×2160, and written as
an 8-bit colormap PNG, which renders **in color** on the Gallery 3 panel.

Targets default to `boot,sleep,deep-sleep`. Choose your own with `--targets`:

| Name | File | Shown |
|---|---|---|
| `boot` | `starting.png` | While booting (a few seconds). |
| `first-boot` | `starting_first.png` | First boot after a reset. |
| `sleep` | `suspended.png` | **Whenever the tablet sleeps — the one you actually look at.** |
| `deep-sleep` | `hibernate.png` | Deep sleep. |
| `poweroff` | `poweroff.png` | Shutting down. |
| `reboot` | `rebooting.png` | Rebooting. |
| `battery-empty` | `batteryempty.png` | Flat battery. |

Originals are backed up twice: on the device as `*.orig`, and into `.backups/`
here (gitignored). `--revert` restores from either.

## Read this before debugging anything

[`docs/CAVEATS.md`](docs/CAVEATS.md) — the traps, several of which fail
*silently*:

- `/etc` is a **tmpfs overlay**, so unit files written normally vanish on reboot
  with no error.
- Firmware updates wipe the rootfs; re-run after each one.
- Deep sleep drops USB ethernet and looks exactly like a crash.
- Reinstalling invalidates browser sessions, which surfaces as an endless
  `Reconnecting` banner.
- BusyBox is not coreutils (`head -3` fails, no `strings`, no brace expansion).
- `pkill -f` over SSH kills its own shell.

[`docs/FINDINGS.md`](docs/FINDINGS.md) — why `reStream`, `rmview`, and every
`cat /dev/fb0` guide **cannot** work on this hardware: there is no framebuffer
device, `xochitl` is the exclusive DRM master, and its CMA buffers are
unreachable through `/proc/PID/mem` (`VM_PFNMAP`), `pagemap`, debugfs (not
compiled in), or `/dev/mem` (`STRICT_DEVMEM`). Also documents the stream wire
format and the 6528-byte stride that yields a sheared image if you get it wrong.

## Safety

Scripts remount `/` read-write only for as long as needed and restore read-only
through an `EXIT`/`INT`/`TERM` trap, so an interrupted run cannot leave the
system partition writable. The downloaded binary is checksum-verified before it
is installed. Nothing here touches the bootloader, the encrypted `/home` volume,
or developer mode.
