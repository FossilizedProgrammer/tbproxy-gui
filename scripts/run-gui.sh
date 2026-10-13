#!/usr/bin/env bash
# Run the Flutter GUI as root (the tun device needs it) while keeping the
# current user's display and $HOME, so settings are saved in the user's own
# ~/.config/tbproxy-gui instead of root's.
set -euo pipefail

# gui/scripts/ -> repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$REPO_ROOT/gui/build/linux/x64/release/bundle/tbgui"
[[ -f "$BIN" ]] || { echo "missing $BIN — run ./gui/scripts/build-gui.sh first" >&2; exit 1; }

# Plain `sudo ./tbgui` loses DISPLAY/XAUTHORITY (sudoers env_reset), so the
# window never appears. Restore them explicitly.
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$HOME/.Xauthority}"
# Allow root to talk to the user's X server (no-op on most setups).
xhost +si:localuser:root >/dev/null 2>&1 || true

# `sudo env VAR=...` sets the vars *after* sudo, so env_reset can't strip them.
exec sudo env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" HOME="$HOME" \
  ${WAYLAND_DISPLAY:+WAYLAND_DISPLAY="$WAYLAND_DISPLAY"} \
  "$BIN" "$@"
