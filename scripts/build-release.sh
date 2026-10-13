#!/usr/bin/env bash
# Full GUI release pipeline: bundle + tar.gz + AppImage.
# Usage: ./scripts/build-release.sh [v1.0.0]
# (in a monorepo checkout: ./gui/scripts/build-release.sh [v1.0.0])
# Output in dist/:
#   tbgui-<ver>-linux-x86_64.tar.gz   (tbgui + tbproxy + openvpn folder)
#   tbgui-<ver>-x86_64.AppImage       (single-file, self-contained)
set -euo pipefail

# Layout detection: monorepo (gui/scripts/) vs standalone repo (scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$SCRIPT_DIR" in
  */gui/scripts)
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)" ;;  # monorepo
  *)
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" ;;     # standalone repo
esac
if [[ -d "$REPO_ROOT/gui" ]]; then GUI_SRC="$REPO_ROOT/gui"; else GUI_SRC="$REPO_ROOT"; fi
VERSION="${1:-${VERSION:-v1.0.0}}"
BUNDLE="$GUI_SRC/build/linux/x64/release/bundle"
OUT="$REPO_ROOT/dist"

log() { printf '[gui-release] %s\n' "$*"; }

"$GUI_SRC/scripts/build-gui.sh"
"$GUI_SRC/scripts/build-appimage.sh" "$VERSION"

# tarball: same bundle as a plain folder (for systems without FUSE/AppImage
# support). Top-level dir is tbgui/ with tbgui + tbproxy + openvpn inside.
TARBALL="$OUT/tbgui-${VERSION}-linux-x86_64.tar.gz"
log "Packing $TARBALL ..."
rm -rf "$OUT/tbgui-pkg" && mkdir -p "$OUT/tbgui-pkg/tbgui"
cp -a "$BUNDLE/." "$OUT/tbgui-pkg/tbgui/"
tar -czf "$TARBALL" -C "$OUT/tbgui-pkg" tbgui
rm -rf "$OUT/tbgui-pkg"

log "Release files in $OUT:"
ls -lh "$OUT"/tbgui-"${VERSION}"-* | sed 's/^/[gui-release] /'
log "Verify: tar tzf <tarball> must list tbgui/ with tbgui, tbproxy and openvpn inside"
log "Run the tarball build as root, keeping your display:"
log "  sudo -E --preserve-env=DISPLAY,XAUTHORITY ./tbgui/tbgui"
