#!/usr/bin/env bash
# Build the Flutter desktop GUI (gui/) and bundle the tbproxy binary next to
# it, so the app folder is self-contained.
set -euo pipefail

# gui/scripts/ -> repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER="${FLUTTER:-flutter}"

# flutter lives outside PATH on some setups.
if ! command -v "$FLUTTER" >/dev/null 2>&1; then
  for c in "$HOME/develop/flutter/bin/flutter" "$HOME/flutter/bin/flutter"; do
    [[ -x "$c" ]] && FLUTTER="$c" && break
  done
fi
command -v "$FLUTTER" >/dev/null 2>&1 || {
  echo "[build-gui] flutter not found — install Flutter or set FLUTTER=/path/to/flutter" >&2
  exit 1
}

log() { printf '[build-gui] %s\n' "$*"; }

# 1) keep the CLI in sync (the GUI runs it as a subprocess)
if command -v go >/dev/null 2>&1; then
  log "Building tbproxy CLI ..."
  (cd "$REPO_ROOT/cli" && go build -o tbproxy .)
else
  log "go not found — using the existing ./cli/tbproxy"
fi

# 2) the Flutter app
log "Building GUI ..."
cd "$REPO_ROOT/gui"
"$FLUTTER" build linux --release

BUNDLE="$REPO_ROOT/gui/build/linux/x64/release/bundle"
[[ -x "$BUNDLE/tbgui" ]] || { echo "[build-gui] no binary produced" >&2; exit 1; }

# 3) make the bundle self-contained: tbproxy CLI + openvpn binary
# The GUI spawns ./tbproxy, which in turn spawns ./openvpn — both must sit
# next to tbgui so the release/AppImage works without system packages.
cp "$REPO_ROOT/cli/tbproxy" "$BUNDLE/tbproxy"
if [[ -x "$REPO_ROOT/openvpn" ]]; then
  cp "$REPO_ROOT/openvpn" "$BUNDLE/openvpn"
  log "Bundled openvpn: $BUNDLE/openvpn ($(du -h "$BUNDLE/openvpn" | cut -f1))"
else
  log "WARNING: $REPO_ROOT/openvpn not found — bundle will use system openvpn"
  log "  (build it or keep the prebuilt binary at the repo root)"
fi

log "Built: $BUNDLE/tbgui ($(du -h "$BUNDLE/tbgui" | cut -f1))"
log "Bundle contents: $(ls "$BUNDLE" | tr '\n' ' ')"
log "Run it with: ./gui/scripts/run-gui.sh   (root is needed for the tun device)"
