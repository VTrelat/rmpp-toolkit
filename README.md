# rmpp-toolkit

Scripts for customizing a **reMarkable Paper Pro** over SSH from macOS.

Paper Pro only. reMarkable 1/2 have a different CPU architecture and a real
`/dev/fb0`; use [Toltec](https://toltec-dev.org/) for those.

## Tools

| Command | Tool | What it does | Docs |
|---|---|---|---|
| `./setup.sh doctor` | **Diagnostics** | Checks the connection and reports firmware, storage, mount state, and which components are installed. Run this first. | — |
| `./setup.sh stream` | **Live screen** | Mirrors the tablet display to your browser — the feature otherwise gated behind the Connect subscription. Installs as a persistent systemd service. | [STREAM.md](stream/STREAM.md) |
| `./setup.sh splash` | **Splash screens** | Replaces the boot, sleep, deep-sleep and shutdown screens with any image, in color. | [SPLASH.md](splash/SPLASH.md) |
| `./setup.sh all` | — | Runs `splash` then `stream`. | — |

More tools may be added over time. Each gets its own subcommand, its own
top-level directory, and its own docs page linked from this table.

## Requirements

- Paper Pro with **developer mode already enabled** and working SSH key access.
  Enabling developer mode **erases the tablet**, so this toolkit will not do it
  for you. Check with `ssh root@10.11.99.1 true`.
- Tablet connected over USB (`10.11.99.1`).
- macOS with `imagemagick` (splash only): `brew install imagemagick`.

## Quick start

```bash
git clone git@github.com:VTrelat/rmpp-toolkit.git
cd rmpp-toolkit
./setup.sh doctor
```

No GitHub SSH key? Use `git clone https://github.com/VTrelat/rmpp-toolkit.git`
instead.

`doctor` verifies the connection and prints device state without changing
anything. Then pick what you want:

```bash
./setup.sh stream                     # live screen -> https://10.11.99.1:2001
./setup.sh splash --image ~/cat.png   # boot + sleep + deep-sleep screens
./setup.sh all --image ~/cat.png      # both
```

Point it elsewhere with `RM_HOST=root@192.168.1.50 ./setup.sh doctor` if you are
not on USB.

## Documentation

| Page | Contents |
|---|---|
| [stream/STREAM.md](stream/STREAM.md) | Live screen: flags, where files land, security, troubleshooting. |
| [splash/SPLASH.md](splash/SPLASH.md) | Splash screens: targets, image preparation, backups, reverting. |
| [docs/CAVEATS.md](docs/CAVEATS.md) | **Read before debugging anything.** The traps, several of which fail silently. |
| [docs/FINDINGS.md](docs/FINDINGS.md) | Why `reStream`, `rmview` and every `cat /dev/fb0` guide cannot work on this hardware. Plus the stream wire format. |

The caveats are worth skimming even if nothing is broken yet. The short version:
`/etc` is a tmpfs overlay so unit files written normally vanish on reboot with no
error; firmware updates wipe the rootfs; deep sleep drops USB ethernet and looks
exactly like a crash; and BusyBox is not coreutils.

## Safety

Scripts remount `/` read-write only for as long as needed and restore read-only
through an `EXIT`/`INT`/`TERM` trap, so an interrupted run cannot leave the
system partition writable. The downloaded binary is checksum-verified before it
is installed. Nothing here touches the bootloader, the encrypted `/home` volume,
or developer mode.
