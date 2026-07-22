# Caveats

Things that will bite you on the reMarkable Paper Pro. Most cost real debugging
time to find, and several fail *silently* — which is worse than failing loudly.

## Enabling developer mode erases the tablet

SSH requires developer mode. Turning it on wipes the device. Back your notebooks
up first. If SSH already works, developer mode is already on — **do not** toggle
it again "to be sure".

This toolkit never enables developer mode. It assumes SSH already works.

## `/etc` writes silently vanish on reboot

`/etc`, `/var/lib`, `/var/cache`, `/var/spool` and `/srv` are overlayfs mounts
whose upper layer lives on `/var/volatile`, which is **tmpfs**:

```
overlay on /etc type overlay (rw,lowerdir=/etc,upperdir=/var/volatile/etc,...)
tmpfs on /var/volatile type tmpfs (rw,relatime)
```

So `cp unit.service /etc/systemd/system/` appears to work, the service starts
fine, and it is gone after a reboot with no error anywhere. `systemctl enable`
has the same problem: its symlink goes to the volatile copy.

The fix, used by `push_persistent`/`symlink_persistent` in `lib/common.sh`: a
plain (non-recursive) bind mount of `/` exposes the underlying filesystem
*without* its submounts, so `/mnt/rootfs/etc` is the real on-disk `/etc`.

```bash
mount -o remount,rw /
mkdir -p /mnt/rootfs && mount --bind / /mnt/rootfs
cp unit.service /mnt/rootfs/etc/systemd/system/
umount /mnt/rootfs
mount -o remount,ro /
```

Check with `./setup.sh stream --status`, which reports `VOLATILE ONLY` if a unit
exists solely in the overlay.

## The rootfs is read-only and nearly full

`/` is `ext4 (ro)` with roughly 46 MB free out of 514 MB. Remount with
`mount -o remount,rw /` and always put it back. Scripts here wrap that in an
`EXIT`/`INT`/`TERM` trap so an interrupted run cannot leave the system partition
writable.

`/home` is a separate 46 GB encrypted volume with plenty of space — put binaries
and anything large there, not on `/`.

## Firmware updates wipe everything

Updates replace the whole rootfs. Splash screens revert to stock and the systemd
unit disappears. `/home` survives, so the binary stays, but the service does not.
Re-run `./setup.sh stream` and `./setup.sh splash --image ...` after each update.

## Deep sleep tears down USB ethernet

When the tablet deep-sleeps, the USB gadget disappears: SSH drops, `en11`
vanishes from the Mac, pings fail. This looks exactly like a crash. It is not —
check `uptime` after reconnecting and you will see the device never rebooted.

Wake the tablet and the link comes back. Services keep running throughout.

## BusyBox is not GNU coreutils

The device shell is BusyBox. These all fail:

| Fails | Use instead |
|---|---|
| `head -3`, `head -n3` | `head -n 3` (space required) |
| `od -A`, `od -tx1` | pull the file to the host and inspect there |
| `strings` | not present at all |
| `awk` `strtonum()` | not present |
| `scp host:'{a,b,c}'` | no brace expansion; copy individually or use `tar` |

## Never `pkill -f` over SSH

```bash
ssh root@10.11.99.1 'pkill -f goMarkableStream'   # kills its own shell
```

The SSH command line *contains* the pattern, so `pkill -f` matches the shell
running it. Match by explicit PID instead — see `kill_remote` in
`lib/common.sh`.

## A stale process makes the service fail to start

If you started something by hand it still holds the port, and systemd reports
`bind: address already in use` while the old instance keeps serving — so it
looks like it worked, with stale settings. `install-stream.sh` kills strays
before starting the unit.

## The clock drifts with no network

With no wifi, chronyd never syncs and the clock can be badly wrong. This matters
because the TLS certificate is generated using the device clock: a tablet that
thinks it is 2025 mints a certificate that your browser considers *already
expired*. Fix before installing:

```bash
ssh root@10.11.99.1 "date -u -s '$(date -u '+%Y-%m-%d %H:%M:%S')'"
```

## Reinstalling logs every browser out, silently

`/home/root/.config/goMarkableStream` holds the JWT signing key and the TLS
certificate. A plain `--uninstall` deletes it, and the next install generates a
new key. Any browser still holding a token from before is then rejected — but
the app does not say so. It shows:

```
Reconnecting (attempt 6/10)...
```

which looks exactly like a network or server problem. The server is fine; the
cached token is signed with a key that no longer exists.

Fix it in the browser, not on the device:

```javascript
localStorage.clear(); location.reload()
```

Then log in again. In Safari the same thing is reachable via
`Réglages` → `Confidentialité` → `Gérer les données de sites web` → remove
`10.11.99.1`.

To avoid it entirely, keep the key across a reinstall:

```bash
./setup.sh stream --uninstall --keep-config
```

`install-stream.sh` warns when it has generated a new key, so you know a
re-login is required rather than guessing.

The certificate is regenerated at the same time, so expect the browser's
self-signed-certificate interstitial once more too.

## Do not expose the stream on wifi

The default bind is `10.11.99.1:2001` — the USB address only. Binding to
`0.0.0.0` puts a live view of your screen on the network behind one password.
If you genuinely need it, use a long password and prefer Tailscale over exposing
the port directly.

## Colour splash screens

Stock `starting.png` and `suspended.png` are 8-bit greyscale, but `factory.png`
in the same directory is 8-bit **colormap** and renders in colour — verified on
the boot splash. `apply-splash.sh` therefore emits `PNG8:` colormap output. If a
future firmware regresses this, fall back to greyscale:

```bash
magick in.png -colorspace Gray -depth 8 -type Grayscale out.png
```
