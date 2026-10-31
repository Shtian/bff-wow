#!/usr/bin/env bash
# Checks out the libraries declared as externals in .pkgmeta into Libs/, the
# same ones the BigWigs packager fetches for a release. Run it from anywhere
# (Git Bash on Windows too) once, and again after a library bump.
# Needs git and curl; CurseForge svn externals are read over plain HTTP.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Downloads a directory of a CurseForge svn repository, recursively, from its
# HTTP listing.
fetch_svn_dir() {
  local url="${1%/}" dest="$2" entry
  mkdir -p "$dest"
  for entry in $(curl -fsSL "$url/" | sed -n 's/.*<li><a href="\([^"]*\)".*/\1/p'); do
    case "$entry" in
      ../) ;;
      */) fetch_svn_dir "$url/${entry%/}" "$dest/${entry%/}" ;;
      *) curl -fsSL -o "$dest/$entry" "$url/$entry" ;;
    esac
  done
}

fetch_git() {
  local dir="$1" url="$2" tag="$3" path="$4"
  local checkout="$work/$(printf '%s@%s' "$url" "$tag" | tr -c 'A-Za-z0-9._-' '_')"
  if [ ! -d "$checkout" ]; then
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$url" "$checkout"
  fi
  mkdir -p "$(dirname "$dir")"
  cp -R "$checkout/${path:-.}" "$dir"
  rm -rf "$dir/.git"
}

fetch() {
  local dir="$1" url="$2" tag="$3" path="$4"
  [ -n "$dir" ] || return 0
  echo "Fetching $dir"
  case "$url" in
    https://repos.curseforge.com/wow/*/tags/*) fetch_svn_dir "$url" "$dir" ;;
    *)
      if [ -z "$tag" ]; then
        echo "  $dir has no tag; pin every external in .pkgmeta" >&2
        exit 1
      fi
      fetch_git "$dir" "$url" "$tag" "$path"
      ;;
  esac
}

rm -rf Libs

dir= url= tag= path= inExternals=
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in
    externals:*) inExternals=1; continue ;;
    "" | "#"*) continue ;;
    [!\ ]*) inExternals= ; continue ;;
  esac
  [ -n "$inExternals" ] || continue
  key="$(echo "$line" | sed 's/^ *\([^:]*\):.*/\1/')"
  value="$(echo "$line" | sed 's/^ *[^:]*: *//')"
  case "$line" in
    "    "*)
      case "$key" in
        url) url="$value" ;;
        tag) tag="$value" ;;
        path) path="$value" ;;
        *) echo "Unsupported key in .pkgmeta external $dir: $key" >&2; exit 1 ;;
      esac
      ;;
    *)
      fetch "$dir" "$url" "$tag" "$path"
      dir="$key" url="$value" tag= path=
      ;;
  esac
done < .pkgmeta
fetch "$dir" "$url" "$tag" "$path"
