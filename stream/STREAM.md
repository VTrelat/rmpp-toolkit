# Live screen

Mirrors the Paper Pro display to a browser on your Mac — the feature otherwise
gated behind the Connect subscription. Installs
[goMarkableStream](https://github.com/owulveryck/goMarkableStream) as a
persistent systemd service.

```bash
./setup.sh stream
```

The installer downloads the `RMPRO` binary, **verifies it against the release's
published SHA-256** before installing anything, generates a 20-character
password, and registers a unit that survives reboots. It prints the URL and
credentials at the end — save them, the password is not stored on your Mac.

Then open `https://10.11.99.1:2001`. The TLS certificate is self-signed, so your
browser warns once. That is expected.

## Flags

| Flag | Effect |
|---|---|
| `--password 'x'` | Use your own instead of a generated one. |
| `--username 'x'` | Defaults to `admin`. |
| `--bind 0.0.0.0:2001` | Expose on all interfaces (**read Security below**). |
| `--version latest` | Track upstream instead of the pinned release. |
| `--status` | Report unit state, bind address, and whether it survives reboot. |
| `--uninstall` | Remove service, binary, credentials, JWT key, certificate. |
| `--uninstall --keep-config` | Keep the JWT key and certificate so browser sessions survive a reinstall. |

## What goes where

| Path | Contents |
|---|---|
| `/home/root/goMarkableStream` | The binary. On encrypted `/home`, which survives firmware updates. |
| `/home/root/.gms.env` | Bind address and credentials, mode `600`. |
| `/home/root/.config/goMarkableStream/` | JWT signing key and TLS certificate. |
| `/etc/systemd/system/gomarkablestream.service` | The unit, written to the *real* rootfs — see [CAVEATS](../docs/CAVEATS.md). |

The unit is deliberately not stored with the password inside it: the rootfs is
unencrypted, `/home` is not.

## Security

The default bind is `10.11.99.1:2001` — the USB address only — so the stream is
unreachable over wifi. Confirm with:

```bash
./setup.sh stream --status
```

Binding to `0.0.0.0` puts a live view of your screen on the network behind a
single password. If you genuinely need remote access, use a long password and
prefer Tailscale over exposing the port directly.

## Troubleshooting

### `Reconnecting (attempt N/10)` forever

The page loads, but the stream never starts. Almost always a stale session: a
reinstall without `--keep-config` generates a new JWT signing key, and the token
your browser cached is signed with a key that no longer exists. The app gives no
hint that this is the cause.

Fix it in the browser, not on the device:

```javascript
localStorage.clear(); location.reload()
```

Then log in again. Avoid it next time with
`./setup.sh stream --uninstall --keep-config`.

### Browser says "Not Secure" / certificate warning

Expected — the certificate is self-signed and generated on the device. Click
through once. It is regenerated on a destructive uninstall, so the warning
returns after one of those.

### `Too Many Requests`

The server allows a limited number of concurrent stream clients. If a browser
tab already holds the stream, a second client gets this. Close the other tab, or
treat it as confirmation that the stream is working.

### Page will not load at all

The server is TLS-only; `http://10.11.99.1:2001` returns `400`. Use `https://`.

If it still fails, the tablet is probably deep-asleep — that tears down USB
ethernet entirely and looks exactly like a crash. Wake it and check:

```bash
./setup.sh doctor
```

## Technical notes

The Paper Pro has no `/dev/fb0`, and `xochitl` holds `/dev/dri/card0` as
exclusive DRM master. Its scanout buffers cannot be read from any other process.
goMarkableStream works by locating the CPU-side copy inside xochitl's own heap.

Why every `cat /dev/fb0` guide fails here, plus the stream wire format and the
6528-byte stride, are documented in [FINDINGS](../docs/FINDINGS.md).
