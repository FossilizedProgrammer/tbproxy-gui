# tbproxy GUI 🐻

Unofficial TunnelBear client for Linux, as a desktop window (Flutter).

> **Disclaimer — unofficial client, personal use only.**
> This is an independent, community-made client for TunnelBear. It is
> **not affiliated with, endorsed, reviewed, or supervised by TunnelBear /
> McAfee** in any way — the original company has no involvement, approval,
> or oversight here. It is designed for **personal use** by people who
> already own a TunnelBear account. Use at your own risk.
>
> **Optimized for Iran's filtering situation.** **Inside Iran this client
> does NOT work without an upstream proxy** — a direct connection to
> TunnelBear is blocked, so you must keep a local upstream proxy running
> for the whole session (fill in the upstream section of the window, or let
> auto-detect pick up 127.0.0.1:1080/8080). This tool is **not a general
> anti-filter solution**: it is only useful when a website or app has a
> problem with your current IP — then you can use this client (over your
> upstream) to get a cleaner, more suitable IP through TunnelBear.

**Read this in:** [فارسی](README.fa.md) · [Русский](README.ru.md)

---

## What is this?

A small desktop app that drives the same `tbproxy` CLI (see
[tbproxy-cli](https://github.com/FossilizedProgrammer/tbproxy-cli)) — no terminal needed:

- Country dropdown, big **Connect / Disconnect / Check-login** buttons
- Saved email + password (stored in `~/.config/tbproxy-gui/`)
- System-wide and Share-on-LAN switches, an upstream section with its own
  on/off switch (for filtered networks; off = always connect directly), and
  a live log of everything that happens

---

## What you need

1. **Linux with root** (the tunnel device needs it) — or Windows 10/11
   with administrator rights (see [Windows](#windows) below).
2. **Go 1.24+** — to build the `tbproxy` CLI that the GUI runs.
3. **Flutter** with Linux desktop support — to build the window itself.
4. **An `openvpn` binary (2.5+)** — e.g. `sudo apt-get install -y openvpn`,
   or build from source; full instructions in
   [tbproxy-cli](https://github.com/FossilizedProgrammer/tbproxy-cli).

---

## Build

One command gets the `tbproxy` CLI (built from source, or the matching
release downloaded automatically), builds the GUI, and puts `tbproxy` +
`openvpn` next to the app so the folder is self-contained:

```bash
./scripts/build-gui.sh
```

The result is `build/linux/x64/release/bundle/tbgui` (with `tbproxy` and
`openvpn` alongside it). For release files (folder tarball + single-file
AppImage, both containing `tbgui` + `tbproxy` + `openvpn`):

```bash
./scripts/build-release.sh v1.0.0
# dist/tbgui-v1.0.0-linux-x86_64.tar.gz   (plain folder; run ./tbgui/tbgui as root, see below)
# dist/tbgui-v1.0.0-x86_64.AppImage       (single file, needs FUSE)
```

Root is needed for the tunnel device; when launching by hand (tarball or
AppImage, not via `./scripts/run-gui.sh`), keep your display:

```bash
sudo -E --preserve-env=DISPLAY,XAUTHORITY ./tbgui-v1.0.0-x86_64.AppImage
```

Release files (tarball + AppImage + Windows zip, all with openvpn) are
compiled on GitHub itself: pushing a tag like `v1.1.0` builds the Linux
files via the `linux-release` workflow, and the `windows-release`
workflow builds the Windows zip. Nothing is ever uploaded by hand.

---

## Run

```bash
./scripts/run-gui.sh
```

Root is needed for the tunnel device; the script keeps your display and your
own settings (`~/.config/tbproxy-gui/`), so the window appears normally.

---

## Windows

The GUI also runs on Windows (proxy-only mode): extract
`tbgui-<ver>-windows-x86_64.zip` from the release (`tbgui.exe` +
`tbproxy.exe` + `openvpn.exe`) and run `tbgui.exe` **as administrator**
(right-click → Run as administrator) — the tun device needs it, and the
app tells you so if you forget. Windows builds require a Windows machine
with Flutter (desktop builds can't be cross-compiled from Linux): either
run `.\scripts\build-windows.ps1 -Version v1.0.0` there, or press “Run
workflow” on the `windows-release` action — it downloads the matching
tbproxy-cli Windows zip and attaches the GUI zip to the release for you.
First-time note: Windows may need the OpenVPN network-adapter driver
(install the official OpenVPN package once) before the tunnel can come up.

---

## Use it

1. Pick a country (e.g. `de`), enter your TunnelBear email + password.
2. Press **Connect**. Watch the log until you see the tunnel is up.
3. Set your browser to **SOCKS5 127.0.0.1:1081** (or HTTP 127.0.0.1:8081).
4. Browse. **Disconnect** when you're done.

---

## Filtering (Iran & co.)

**Important for Iran: without an upstream proxy, there is no connection.**
Direct connections from Iran to TunnelBear are blocked (the TLS handshake
stalls — the ISP's DPI kills it), so an upstream proxy is **mandatory for
the whole session**. Outside Iran both cases below may occur:

- **Filtering exists, but TunnelBear is reachable**: just press Connect —
  no upstream needed.
- **TunnelBear itself is blocked** (direct connection stalls in the
  middle of the TLS handshake — the ISP's DPI kills it): the **only**
  way to connect is through a local upstream proxy, and you need it for
  the **whole session**, not just the login:

  - Run any proxy client you trust (Psiphon, v2ray, NekoBox, ...) so
    that a SOCKS/HTTP proxy listens on `127.0.0.1:1080` /
    `127.0.0.1:8080`.
  - tbproxy **auto-detects** those ports and routes the whole VPN
    connection through the proxy (or fill in the upstream fields in the
    GUI yourself).
  - Don't want the upstream at all (say, a local proxy on 1080/8080 that
    must not carry the VPN)? Turn the **Use upstream proxy** switch off:
    the fields are ignored, nothing on those ports is picked up and the
    VPN always connects directly.

**Keep the upstream running for as long as you use the VPN** — when
TunnelBear is blocked, the tunnel connection itself rides on the proxy
the entire time, so if the proxy dies the tunnel drops with it. Don't
worry: tbproxy waits for the proxy to come back and reconnects on its
own (in the log: `upstream proxy is down — waiting for it to come back
...`). Browsing traffic goes through the tunnel device (`tun0`); the
ISP may still throttle that path (slow pages) — that's the ISP, not
the proxy.
