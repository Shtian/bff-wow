#!/usr/bin/env bash
# Writes the newest releases of CHANGELOG.md into ChangelogText.lua as a Lua
# long string, for What's new (docs/design/whats-new.md). scripts/package.sh
# runs it before the packager builds the zip, and puts the checkout's copy
# back afterwards, so ChangelogText.lua is never committed with text in it.
#
#   scripts/changelog-text.sh        the newest 8 releases
#   scripts/changelog-text.sh 12     the newest 12
set -euo pipefail

releases="${1:-8}"
[[ "$releases" =~ ^[1-9][0-9]*$ ]] || { echo "usage: scripts/changelog-text.sh [releases]" >&2; exit 2; }

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Everything from the first release heading up to the one after the last
# release kept.
text="$(awk -v keep="$releases" '/^## / { seen++ } seen > keep { exit } seen > 0 { print }' CHANGELOG.md)"
[[ -n "$text" ]] || { echo "No releases in CHANGELOG.md" >&2; exit 1; }
if [[ "$text" == *"]==]"* ]]; then
  echo "CHANGELOG.md contains ]==], which would end the Lua string early" >&2
  exit 1
fi

cat >ChangelogText.lua <<LUA
-- The newest releases of CHANGELOG.md, for What's new. Written by
-- scripts/changelog-text.sh for the release build; don't commit it.

local _, ns = ...

ns.CHANGELOG_TEXT = [==[
$text
]==]
LUA
