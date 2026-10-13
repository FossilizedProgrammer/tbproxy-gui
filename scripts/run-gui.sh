#!/usr/bin/env bash
# Run the Flutter GUI as root (the tun device needs it) while keeping the
# current user's display and $HOME, so settings are saved in the user's own
# ~/.config/tbproxy-gui instead of root's.
#
# Works both in a monorepo checkout (gui/ next to cli/) and in the
# standalone tbproxy-gui repo.
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
BIN="$GUI_SRC/build/linux/x64/release/bundle/tbgui"
[[ -f "$BIN" ]] || { echo "missing $BIN — run the build script (scripts/build-gui.sh) first" >&2; exit 1; }

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
