#!/usr/bin/env bash
# Build the Flutter desktop GUI and bundle the tbproxy + openvpn binaries
# next to it, so the app folder is self-contained.
#
# Works both in a monorepo checkout (gui/ next to cli/) and in the
# standalone tbproxy-gui repo (where the CLI release is downloaded).
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
CLI_VERSION="${CLI_VERSION:-v1.0.0}"
CLI_REPO="${CLI_REPO:-https://github.com/FossilizedProgrammer/tbproxy-cli}"
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

# 1) tbproxy CLI (the GUI runs it as a subprocess).
TBPROXY_BIN=""
if [[ -f "$REPO_ROOT/cli/go.mod" ]]; then
  # monorepo checkout: build the sibling CLI from source.
  if command -v go >/dev/null 2>&1; then
    log "Building tbproxy CLI from source ..."
    (cd "$REPO_ROOT/cli" && go build -o tbproxy .)
  else
    log "go not found — using the existing ./cli/tbproxy"
  fi
  TBPROXY_BIN="$REPO_ROOT/cli/tbproxy"
elif [[ -n "${TBPROXY_BIN:-}" ]]; then
  log "Using TBPROXY_BIN=$TBPROXY_BIN"
else
  # standalone repo: fetch the matching CLI release tarball (it contains
  # both tbproxy and the linux openvpn binary).
  mkdir -p "$REPO_ROOT/.vendor"
  TARBALL="$REPO_ROOT/.vendor/tbproxy-${CLI_VERSION}-linux-amd64.tar.gz"
  if [[ ! -f "$TARBALL" ]]; then
    log "Downloading tbproxy ${CLI_VERSION} ..."
    curl -fL -o "$TARBALL" \
      "$CLI_REPO/releases/download/${CLI_VERSION}/tbproxy-${CLI_VERSION}-linux-amd64.tar.gz"
  fi
  tar -xzf "$TARBALL" -C "$REPO_ROOT/.vendor"
  TBPROXY_BIN="$REPO_ROOT/.vendor/tbproxy"
  if [[ -f "$REPO_ROOT/.vendor/openvpn" && ! -f "$REPO_ROOT/openvpn" ]]; then
    cp "$REPO_ROOT/.vendor/openvpn" "$REPO_ROOT/openvpn"
  fi
fi
[[ -x "$TBPROXY_BIN" ]] || { echo "[build-gui] tbproxy binary missing: $TBPROXY_BIN" >&2; exit 1; }

# 2) the Flutter app
log "Building GUI ..."
cd "$GUI_SRC"
"$FLUTTER" build linux --release

BUNDLE="$GUI_SRC/build/linux/x64/release/bundle"
[[ -x "$BUNDLE/tbgui" ]] || { echo "[build-gui] no binary produced" >&2; exit 1; }

# 3) make the bundle self-contained: tbproxy CLI + openvpn binary.
# The GUI spawns ./tbproxy, which in turn spawns ./openvpn — both must sit
# next to tbgui so the release/AppImage works without system packages.
cp "$TBPROXY_BIN" "$BUNDLE/tbproxy"
if [[ -x "$REPO_ROOT/openvpn" ]]; then
  cp "$REPO_ROOT/openvpn" "$BUNDLE/openvpn"
  log "Bundled openvpn: $BUNDLE/openvpn ($(du -h "$BUNDLE/openvpn" | cut -f1))"
else
  log "WARNING: $REPO_ROOT/openvpn not found — bundle will use system openvpn"
  log "  (put a prebuilt openvpn binary at the repo root and rebuild)"
fi

log "Built: $BUNDLE/tbgui ($(du -h "$BUNDLE/tbgui" | cut -f1))"
log "Bundle contents: $(ls "$BUNDLE" | tr '\n' ' ')"
if [[ "$GUI_SRC" == "$REPO_ROOT" ]]; then
  log "Run it with: ./scripts/run-gui.sh   (root is needed for the tun device)"
else
  log "Run it with: ./gui/scripts/run-gui.sh   (root is needed for the tun device)"
fi
