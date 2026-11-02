#!/usr/bin/env bash
# Lint and tests: luacheck, then busted. CI (test.yml) runs this too, so a
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
busted "$@"
