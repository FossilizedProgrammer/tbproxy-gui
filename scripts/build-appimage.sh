#!/usr/bin/env bash
# Build a tbgui AppImage that is fully self-contained:
#   tbgui + tbproxy + openvpn in one file.
# Usage: ./gui/scripts/build-appimage.sh [v1.0.0]
# Requirements: flutter, go (run build-gui.sh first or let this call it),
#   appimagetool (auto-downloaded if missing).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:-${VERSION:-v1.0.0}}"
BUNDLE="$REPO_ROOT/gui/build/linux/x64/release/bundle"
APPDIR="$REPO_ROOT/dist/AppDir"
APPIMAGE="$REPO_ROOT/dist/tbgui-${VERSION}-x86_64.AppImage"

log() { printf '[appimage] %s\n' "$*"; }

# 1) make sure the bundle exists (this also bundles tbproxy + openvpn)
if [[ ! -x "$BUNDLE/tbgui" || ! -f "$BUNDLE/tbproxy" ]]; then
  log "Bundle incomplete — running build-gui.sh first ..."
  "$REPO_ROOT/gui/scripts/build-gui.sh"
fi
[[ -x "$BUNDLE/tbgui" ]] || { echo "no tbgui binary" >&2; exit 1; }
[[ -f "$BUNDLE/tbproxy" ]] || { echo "no tbproxy in bundle" >&2; exit 1; }
if [[ ! -f "$BUNDLE/openvpn" ]]; then
  log "WARNING: openvpn NOT in bundle — AppImage will fall back to system openvpn"
else
  log "openvpn bundled: $(du -h "$BUNDLE/openvpn" | cut -f1) ($("$BUNDLE/openvpn" --version 2>/dev/null | head -n1))"
fi

# 2) assemble AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp -a "$BUNDLE/." "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/tbgui" "$APPDIR/usr/bin/tbproxy"
[[ -f "$APPDIR/usr/bin/openvpn" ]] && chmod +x "$APPDIR/usr/bin/openvpn"

# icon (simple bear-ish placeholder SVG; replace with real art anytime)
cat > "$APPDIR/usr/share/icons/hicolor/256x256/apps/tbgui.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<rect width="256" height="256" rx="48" fill="#2b2b2b"/>
<text x="128" y="170" font-size="120" text-anchor="middle">🐻</text>
</svg>
SVG
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/tbgui.svg" "$APPDIR/tbgui.svg"
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/tbgui.svg" "$APPDIR/.DirIcon.svg"

# desktop entry — AppRun launches tbgui; tbproxy/openvpn are found via PATH
# (AppRun prepends $APPDIR/usr/bin) or via the bundle dir lookup.
cat > "$APPDIR/usr/share/applications/tbgui.desktop" <<'DESKTOP'
[Desktop Entry]
Name=tbproxy GUI
Comment=Unofficial TunnelBear client for Linux (personal use, optimized for Iran — needs an upstream proxy in Iran)
Exec=tbgui
Icon=tbgui
Type=Application
Categories=Network;
Terminal=false
DESKTOP
cp "$APPDIR/usr/share/applications/tbgui.desktop" "$APPDIR/tbgui.desktop"

# AppRun: keep XDG paths sane, put our bin dir first so openvpn/tbproxy resolve
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HERE/usr/lib:$LD_LIBRARY_PATH"
exec "$HERE/usr/bin/tbgui" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# 3) get appimagetool
APPIMAGETOOL=""
if command -v appimagetool >/dev/null 2>&1; then
  APPIMAGETOOL="appimagetool"
else
  mkdir -p "$REPO_ROOT/dist"
  if [[ ! -x "$REPO_ROOT/dist/appimagetool-x86_64.AppImage" ]]; then
    log "Downloading appimagetool ..."
    curl -fL -o "$REPO_ROOT/dist/appimagetool-x86_64.AppImage" \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$REPO_ROOT/dist/appimagetool-x86_64.AppImage"
  fi
  APPIMAGETOOL="$REPO_ROOT/dist/appimagetool-x86_64.AppImage"
fi

# 4) build
mkdir -p "$REPO_ROOT/dist"
log "Building $APPIMAGE ..."
ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$APPIMAGE"
chmod +x "$APPIMAGE"
log "Done: $APPIMAGE ($(du -h "$APPIMAGE" | cut -f1))"
log "Contents (bin): $(ls "$APPDIR/usr/bin" | tr '\n' ' ')"
log "Run with: sudo -E --preserve-env=DISPLAY,XAUTHORITY $APPIMAGE  (root needed for tun)"
log "  or via the helper: ./gui/scripts/run-gui.sh (runs the bundle, not the AppImage)"
