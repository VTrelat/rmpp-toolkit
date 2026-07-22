# Why the classic reMarkable screen hacks fail on Paper Pro

Every widely-circulated guide for streaming a reMarkable screen — `reStream`,
`rmview`, "just `cat /dev/fb0`" — was written for the reMarkable 1 and 2. None of
it works on the Paper Pro, and the failure modes are confusing enough that it is
worth writing down exactly which door is closed and why.

Measured on a Paper Pro (`imx8mm-ferrari`), Codex Linux 5.0.57, image 3.20.0.92,
aarch64.

## There is no framebuffer device

```
# ls /dev/fb*
(none)
# ls /dev/dri/
card0
```

The Paper Pro is DRM/KMS. There is no legacy `/dev/fb0` to read, so anything
built on `cat /dev/fb0` cannot work — not "needs porting", cannot work.

`xochitl` holds `/dev/dri/card0` and is the exclusive DRM master, with 16 mapped
buffers of `0x1AD000` (1,757,184) bytes each:

```
ffffa4090000-ffffa423d000 rw-s /dev/dri/card0
...  (16 of them)
```

16 × 1.716 MB ≈ 27.5 MB, which matches the ~28 MB of CMA in use
(`CmaTotal: 655360 kB`, `CmaFree: 627104 kB`). It is a CMA-backed swapchain.

## Every route into those buffers is closed

| Route | Result |
|---|---|
| `/proc/PID/mem` | `EIO` |
| `/proc/PID/pagemap` | returns `present=0 pfn=0` |
| debugfs (`/sys/kernel/debug/dri/0/`) | `unknown filesystem type 'debugfs'` — not compiled in |
| `/dev/mem` | `Operation not permitted` — `CONFIG_STRICT_DEVMEM` |

The `/proc/PID/mem` failure is the interesting one. Reading the *stack* of the
same process works fine, so it is not a permissions problem:

```
VmFlags: rd wr sh mr mw me ms pf io de dd
Rss:     0 kB
```

`pf` is `VM_PFNMAP` and `io` is `VM_IO`. The kernel refuses `get_user_pages` on
such VMAs — there are no `struct page`s behind them at all, which `Rss: 0`
confirms. That is a structural refusal, not a policy one; no privilege escalation
changes it.

`pagemap` excludes `PFNMAP` VMAs for the same reason. `/dev/mem` would work if
`STRICT_DEVMEM` were off, since CMA base is known from dmesg
(`CMA memory pool at 0x0000000092c00000, size 640 MiB`), but it is on.

**Conclusion: the scanout buffers are unreadable from outside `xochitl`.** The
only way in is from inside the process — which is what XOVI-based tooling does,
and what goMarkableStream does by locating the CPU-side copy in the heap.

## The wire format, if you ever decode it by hand

goMarkableStream serves:

- `POST /login` with `{"username","password"}` → `{"token"}`, then
  `Authorization: Bearer <token>`
- `GET /stream?rate=N` → the pixel stream
- `GET /funnel` → **Tailscale funnel status, not video** (easy to mistake for
  the stream endpoint)

The stream is a 4-byte prefix followed by **one continuous zstd stream** — not
one zstd frame per video frame. There is exactly one `28 b5 2f fd` magic in the
whole capture, so splitting on the magic finds a single frame no matter how long
you record.

Pixels are **BGRA, 1620×2160, stride 6528 bytes**. The stride is the trap: 6528
bytes is 1632 pixels × 4, and 1632 is 1620 padded up to 32-pixel DRM alignment.
Decoding at `1620 × 4 = 6480` produces a recognizable but progressively sheared
image — the diagonal-smear signature of a wrong stride.

```python
W, H, STRIDE = 1620, 2160, 6528
rows = len(raw) // STRIDE
buf = b"".join(raw[y*STRIDE : y*STRIDE + W*4] for y in range(rows))
img = Image.frombytes("RGBA", (W, rows), buf)
r, g, b, a = img.split()
Image.merge("RGB", (b, g, r)).save("screen.png")   # BGRA -> RGB
```

## Toltec is a dead end here

Toltec supports OS builds 2.6.1.71 – 3.3.2.1666 and the rM1/rM2 CPU
architecture. The Paper Pro is aarch64 on a much newer OS. The current community
stack is XOVI + AppLoad. This toolkit does not require either — goMarkableStream
is a standalone static binary.
