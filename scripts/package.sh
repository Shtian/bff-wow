#!/usr/bin/env bash
# Builds the release zip and release.json for BFF <version> and uploads both to
# the GitHub release bff@<version>. Bumpy runs this as the package's
# publishCommand, after it has created that release as a draft and before it
# finalises it.
#
#   scripts/package.sh 0.1.0              build and upload
#   scripts/package.sh 0.1.0 --no-upload  build only, into .release/
#
# Needs bash 4+ (the packager's), git, curl, jq and svn (CurseForge
# externals); gh for the upload. On macOS, run it in a Linux container.
set -euo pipefail

PACKAGER_VERSION="v2.6.1"

usage() {
  echo "usage: scripts/package.sh <version> [--no-upload]" >&2
  exit 2
}

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
upload=true
case "${2:-}" in
  "") ;;
  --no-upload) upload=false ;;
  *) usage ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

tag="v$version"
release_dir="$root/.release"
zip="BFF-$tag.zip"

# The packager takes the version from a tag on HEAD. Bumpy's tag (bff@X.Y.Z)
# would put "bff@0.1.0" in the .toc, so tag v<version> for the build only. It's
# never pushed. On a retry bumpy's lightweight tag can sit on HEAD too; the
# packager prefers the highest name, so v<version> still wins.
work="$(mktemp -d)"
trap 'git tag -d "$tag" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
git tag -f "$tag" >/dev/null

# Build only (-d): the packager fetches the .pkgmeta externals, leaves out the
# ignored paths and writes .release/BFF-v<version>.zip. Bumpy owns the release.
curl -fsSL -o "$work/release.sh" \
  "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_VERSION/release.sh"
bash "$work/release.sh" -d -r "$release_dir"
[[ -f "$release_dir/$zip" ]] || { echo "The packager didn't write $zip" >&2; exit 1; }

# The packager only writes release.json (read by WowUp) in its upload step,
# which -d skips, so write it here in the same format: one entry for the zip,
# one metadata row per interface in the .toc, with the packager's flavour
# names. BFF only ships for Forever and retail.
interface_flavor() {
  case "$1" in
    16???) echo forever ;;
    1[0-9][0-9][0-9][0-9][0-9]) echo mainline ;;
    *) echo "No flavour for interface $1 in BFF.toc" >&2; exit 1 ;;
  esac
}
metadata="[]"
for interface in $(sed -n 's/^## Interface:[[:space:]]*//p' BFF.toc | tr -d '\r' | tr ',' ' '); do
  flavor="$(interface_flavor "$interface")"
  metadata="$(jq -c --arg flavor "$flavor" --argjson interface "$interface" \
    '. + [{flavor: $flavor, interface: $interface}]' <<<"$metadata")"
done
[[ "$metadata" != "[]" ]] || { echo "No ## Interface: line in BFF.toc" >&2; exit 1; }
jq -n --arg version "$tag" --arg filename "$zip" --argjson metadata "$metadata" \
  '{releases: [{name: "BFF", version: $version, filename: $filename, nolib: false, metadata: $metadata}]}' \
  >"$release_dir/release.json"

if $upload; then
  # gh finds a draft release by its pending tag name too.
  gh release upload "bff@$version" "$release_dir/$zip" "$release_dir/release.json" --clobber
else
  echo "Built $release_dir/$zip and $release_dir/release.json"
fi
