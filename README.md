# BFF – Best Friends in Forever

A World of Warcraft: Forever addon for friend groups who don't always play at the same time. It shows everyone's characters, levels and whereabouts, and tells you what your friends did while you were away.

Work in progress. Design notes: [`docs/design/architecture.html`](docs/design/architecture.html).

## Install

- **WowUp:** Get Addons → Install from URL, and paste `https://github.com/Shtian/bff-wow`. WowUp picks up new releases from there.
- **By hand:** download `BFF-vX.Y.Z.zip` from the [latest release](https://github.com/Shtian/bff-wow/releases/latest) and unzip it into the game's `Interface\AddOns` folder, so you get `AddOns\BFF\BFF.toc`.

## Development

Libraries aren't committed. Fetch the ones `.pkgmeta` declares into `Libs/` once, and again after a library bump:

```sh
scripts/fetch-libs.sh
```

Tests run under LuaJIT, like WoW's Lua 5.1:

```sh
brew install luajit luarocks
luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" --local install busted
luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" --local install luacheck
export PATH="$HOME/.luarocks/bin:$PATH"

luacheck .
busted
```

## Releasing

Releases are cut with [bumpy](https://github.com/dmno-dev/bumpy) (see `docs/design/settings-and-release.md`). A PR that changes shipped files (`changedFilePatterns` in `.bumpy/_config.json`) needs a bump file:

```sh
npm install
npx bumpy add --packages "bff:patch" --message "What changed, for the changelog."
```

Merging to `main` opens or updates the "Versioned release" PR. Merging that publishes the GitHub release `bff@X.Y.Z` with the zip and `release.json`, and uploads the zip to CurseForge once the `CF_API_KEY` secret and `CURSEFORGE_PROJECT_ID` variable are set.

## License

MIT, see [`LICENSE`](LICENSE). The libraries in `Libs/` keep their own licenses.
