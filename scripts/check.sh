#!/usr/bin/env bash
# Lint and tests: luacheck, the comment check, then busted. CI (test.yml) runs this too, so a
# local pass means CI's checks pass. Extra arguments go to busted, e.g.
#   scripts/check.sh tests/settings_spec.lua
# Fetches Libs/ first if it's missing. Finds tools installed with
# `luarocks --local` (README) without PATH setup.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export PATH="$HOME/.luarocks/bin:$PATH"

[ -d Libs ] || scripts/fetch-libs.sh

luacheck -q .
git ls-files --cached --others --exclude-standard '*.lua' \
  | grep -vE '^(Libs|\.luarocks|lua_modules|\.install|\.lua)/' \
  | "$(command -v luajit || command -v lua)" scripts/check-comments.lua
busted "$@"
