#!/usr/bin/env bash
# Prints a CHANGELOG.md section for a beta: the heading <version>, today's
# date and the pending bump files' entries in bumpy's format, as bumpy reads
# them (`bumpy status --json`). Leaves out "none" entries, and "Internal:"
# entries unless they're major, as What's new does. scripts/package.sh puts it
# at the top of CHANGELOG.md for a beta's zip, so CurseForge shows what the
# beta brings.
#
#   scripts/pending-changelog.sh 2.17.0-beta-a1b2c3d
set -euo pipefail

version="${1:-}"
[[ -n "$version" ]] || { echo "usage: scripts/pending-changelog.sh <version>" >&2; exit 2; }

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

bumpy_version="$(jq -r '.devDependencies["@varlock/bumpy"]' package.json)"
# bumpy status exits 1 when nothing is pending, still printing the plan.
plan="$(npx -y "@varlock/bumpy@$bumpy_version" status --json)" || jq -e '.bumpFiles == []' <<<"$plan" >/dev/null

echo "## $version"
echo "<sub>$(date -u +%Y-%m-%d)</sub>"
echo
echo "Beta: what the next release will bring, for testing before it's out."
jq -r '
  .bumpFiles[]
  | (.releases[] | select(.name == "bff") | .type) as $level
  | select($level != "none")
  | select((.summary | startswith("Internal:") | not) or $level == "major")
  | "\n- *(\($level))*\n" + (.summary | split("\n") | map(if . == "" then . else "  " + . end) | join("\n"))
' <<<"$plan"
