# Settings and releases

Answers [What's in the settings panel, and how are releases cut?](https://github.com/Shtian/bff-wow/issues/16). Builds on the panel in #7, sync in #8, code structure in #9 (`docs/design/code-structure.md`), joining a Crew in #10 (`docs/design/joining-a-crew.md`) and the Feed in #14 (`docs/design/feed.md`). The `.toc` and packager facts come from #3 and #5. Domain vocabulary from `CONTEXT.md`.

## Settings

### Where they live

One page in the game's native Settings panel (Esc → Options → AddOns → **BFF**), built with the Settings API (no AceConfig, per #9). It opens from:

- the gear button on the panel,
- **Settings** in the minimap button's right-click menu (#7),
- `/bff settings`.

### What's on it

| Section | Setting | Default | From |
|---|---|---|---|
| **You** | Display name (2–16 characters) | Character name at setup | #10 |
| | Crew code, read-only, text selected for copying | | #10 |
| **Sharing** | Pause sharing | off | #8 |
| | Leave Crew button (asks to confirm) | | #10 |
| **Notifications and display** | Chat message for live events | on | #14 |
| | Show While you were away on login | on | #14 |
| | Show minimap button | on | #7 |

Not in a Crew: the Crew code and Leave Crew are hidden, and the panel's setup view handles joining.

The **key binding** to open the panel goes in the game's own Key Bindings screen under a "BFF" header (`Bindings.xml`), not on this page.

### Fixed in v1

No other options: the "can play with you" range (±3), the 30-day hide, a chat line when a Member comes online, and Feed sounds all stay fixed or out. Revisit after playtesting; "Member came online" would be a new notification, so v2.

### Storage

Everything is **account-wide** in `BFF_DB`, including the minimap button position (LibDBIcon's table lives inside it). Core owns the layout and defaults (#9); UI reads and writes settings only through Core's commands.

## Releases

### Versioning and changelog: bumpy

Releases and the changelog are managed by [`@varlock/bumpy`](https://github.com/dmno-dev/bumpy/).

- **Bump files:** a PR that changes shipped files carries `.bumpy/<name>.md`, naming `bff` with `patch`, `minor` or `major` and one changelog line. Agents create them with `bumpy add` (non-interactive); the repo gets bumpy's `add-change` agent skill.
- **Which PRs need one:** `changedFilePatterns` covers only shipped files (`*.toc`, `*.lua`, `*.xml`), excluding `tests/`, `Dev/` and `scripts/`. Docs, tests and tooling PRs need none.
- **Repo files:** a minimal root `package.json` (`"name": "bff"`, `"version": "0.1.0"`, `"private": true`, bumpy as a dev dependency) and `.bumpy/_config.json` with the package's `publishCommand`, `skipNpmPublish` and `changedFilePatterns`. `"private": true` keeps npm out of it; bumpy still runs a custom `publishCommand` for private packages.
- **Versions:** semver, starting at `0.1.0` and staying `0.x` until v1 is complete. No prerelease channels.
- **Changelog:** bumpy writes `CHANGELOG.md` from the bump files. It also ships in the zip (`.pkgmeta`: `manual-changelog` with `filename: CHANGELOG.md`, `markup-type: markdown`); the packager's generated changelog isn't used.

### Flow

```text
PR with a bump file        -> test.yml (luacheck, busted) + bumpy ci check (comments the release plan)
merge to main              -> bumpy ci release opens/updates the "Versioned release" PR
                              (bumps package.json, writes CHANGELOG.md)
merge the Versioned release PR
  -> release.yml: luacheck + busted, then bumpy ci release publishes:
       draft GitHub release for tag bff@X.Y.Z (notes from the bump files)
       publishCommand: scripts/package.sh X.Y.Z
       tag pushed, release finalised
```

Bumpy's tags are always `<name>@<version>` (`bff@0.1.0`); that isn't configurable.

### Building the zip: `scripts/package.sh <version>`

Bumpy owns the tag, the GitHub release and its notes. The BigWigs packager only builds:

1. Create a local tag `v<version>`, so the packager's `@project-version@` (used in `## Version:`) becomes `v0.1.0` rather than `bff@0.1.0`. It's never pushed.
2. Run the packager in build-only mode (`-d`): fetch the `.pkgmeta` externals and write `BFF-v<version>.zip`, leaving out `tests/`, `Dev/`, `scripts/`, `.bumpy/`, `package.json` and `node_modules/`.
3. Write `release.json` with `jq` in the packager's format (one entry for the zip, with metadata for interfaces `16001` and `120105`). The packager only writes it in its own upload step, which `-d` skips.
4. `gh release upload bff@<version>` with the zip and `release.json`.

**To prove when this is built:** that `gh release upload` attaches to bumpy's **draft** release by tag. Do a dry run before the first real release. If it can't, the script waits until bumpy has finalised the release and uploads then.

### The `.toc`

The released `.toc` keeps `## Interface: 16001, 120105` and has no `AllowLoadGameType` (#5): it costs nothing on Forever, and the retail dev loop and the released zip stay the same file. Bump the retail number when retail patches. "Forever launch day" on the map revisits it: add Forever's launch interface number, and drop the retail one once testing has moved to Forever.

### Installing

- **WowUp:** add the GitHub repo URL; WowUp reads `release.json` from the latest release.
- **By hand:** download the zip from GitHub releases and unzip it into `Interface\AddOns`.

The README gets a short install section with both.

## Changes to `docs/design/code-structure.md`

- Layout gains `Bindings.xml`, `package.json`, `.bumpy/`, `CHANGELOG.md` and `scripts/package.sh`.
- `release.yml` runs bumpy, not the packager directly.

## Not decided here

- The settings page layout beyond the sections above; it follows the Settings API's standard controls.
- Forever's launch interface number and game type (map: "Forever launch day").
