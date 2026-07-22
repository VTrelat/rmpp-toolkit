# Splash screens

Replaces the Paper Pro's boot, sleep, deep-sleep and shutdown screens with an
image of your choice — **in color**, on the Gallery 3 panel.

```bash
./setup.sh splash --image ~/cat.png
./setup.sh splash --status
./setup.sh splash --revert
```

Requires ImageMagick on the Mac: `brew install imagemagick`.

## Targets

Targets default to `boot,sleep,deep-sleep`. Choose your own with a comma-separated
`--targets` list:

```bash
./setup.sh splash --image ~/cat.png --targets sleep,battery-empty
```

| Name | File | Shown |
|---|---|---|
| `boot` | `starting.png` | While booting (a few seconds). |
| `first-boot` | `starting_first.png` | First boot after a reset. |
| `sleep` | `suspended.png` | **Whenever the tablet sleeps — the one you actually look at.** |
| `deep-sleep` | `hibernate.png` | Deep sleep. |
| `poweroff` | `poweroff.png` | Shutting down. |
| `reboot` | `rebooting.png` | Rebooting. |
| `battery-empty` | `batteryempty.png` | Flat battery. |

If you only change one thing, make it `sleep`. The boot splash flashes past in
about three seconds; the sleep screen is on the glass whenever the tablet is
idle.

## How the image is prepared

Any image works. It is flattened onto white (transparency becomes white, not
black), fitted to 1620×2160 preserving aspect ratio, padded to exactly panel
size, and written as an **8-bit colormap PNG**.

The colormap part matters. Stock `starting.png` and `suspended.png` are 8-bit
grayscale, which suggests the panel only takes gray — but `factory.png` in the
same directory is 8-bit colormap, and colormap output renders in full color.
That was verified on the boot splash, not assumed.

A portrait image close to 3:4 fills the screen best. Anything else gets white
bars rather than being cropped.

## Backups and reverting

Originals are backed up twice:

- On the device, as `<name>.png.orig`. Written with `cp -n`, so re-running never
  clobbers a previously saved original.
- On your Mac, into `.backups/` at the repo root (gitignored), in case the
  rootfs is ever reflashed.

```bash
./setup.sh splash --revert
```

restores from the device copy, falling back to the local one. `--revert` honors
`--targets`, so you can revert a subset.

Check what is currently installed:

```bash
./setup.sh splash --status
```

Matching MD5s across targets mean the same image is applied to each. Note that
the hash depends on the exact ImageMagick quantization pass, so re-composing the
same source image can produce a slightly different palette and hash while
looking identical.

## Caveats

**Firmware updates wipe this.** Updates replace the entire rootfs, so splash
screens revert to stock. Re-run after each update.

**The rootfs is small.** Roughly 46 MB free. The script refuses to write if less
than 4 MB remains, and verifies each file's checksum on the device after
writing.

**Color regressions.** If a future firmware stops rendering colormap PNGs, fall
back to grayscale:

```bash
magick in.png -colorspace Gray -depth 8 -type Grayscale out.png
```

More traps in [CAVEATS](../docs/CAVEATS.md).
