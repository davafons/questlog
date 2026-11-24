#!/bin/bash
# One step: build CascLib (MIT, https://github.com/ladislav-zezula/CascLib) and copy the quest UI art, fonts and
# sounds from your own World of Warcraft install into ~/.questlog/theme. Nothing is downloaded from the game.
#   scripts/setup-theme.sh ["/path/to/World of Warcraft"] [product]
# Needs git, a C++ compiler (Xcode command line tools) and uv (https://docs.astral.sh/uv/).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cache="${QUESTLOG_HOME:-$HOME/.questlog}/cache"
src="$cache/CascLib"
lib="$src/build/casc.framework/casc"

command -v uv >/dev/null || { echo "Install uv first: https://docs.astral.sh/uv/" >&2; exit 1; }
if [ ! -f "$lib" ]; then
  mkdir -p "$cache"
  [ -d "$src" ] || git clone --depth 1 https://github.com/ladislav-zezula/CascLib "$src"
  cmake=(cmake); command -v cmake >/dev/null || cmake=(uvx cmake)
  "${cmake[@]}" -S "$src" -B "$src/build" -DCASC_BUILD_SHARED_LIB=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 >/dev/null
  "${cmake[@]}" --build "$src/build" -j 8 >/dev/null
fi
uv run -q --with pillow "$here/extract-wow-theme.py" "$lib" "$@"
echo "Done. In Quest Log's menu bar menu, choose Reload Theme."
