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
- **Which PRs need one:** `changedFilePatterns` covers only shipped files (`*.toc`, `*.lua`, `*.xml`), excluding `tests/`, `Dev/` and `scripts/`, plus `.pkgmeta`, since it pins the libraries that ship. Docs, tests and tooling PRs need none. The patterns can't use `!` exclusions (any one matching pattern counts), so the folders are left out with an extglob.
- **Repo files:** a minimal root `package.json` (`"name": "bff"`, `"version": "0.0.0"`, `"private": true`, bumpy pinned as a dev dependency) and `.bumpy/_config.json` with the package's `managed`, `publishCommand`, `skipNpmPublish` and `changedFilePatterns`. `"private": true` keeps npm out of it; bumpy skips private packages unless they're marked `managed`, and then runs their custom `publishCommand`.
- **Versions:** semver, staying `0.x` until v1 is complete. No prerelease channels. `package.json` starts at `0.0.0`, which bumpy treats as never released, and the first bump file is a `minor`, so the first Versioned release PR makes it `0.1.0`.
- **Changelog:** bumpy writes `CHANGELOG.md` from the bump files. It also ships in the zip (`.pkgmeta`: `manual-changelog` with `filename: CHANGELOG.md`, `markup-type: markdown`); the packager's generated changelog isn't used.

### Flow

```text
PR with a bump file        -> test.yml (luacheck, busted) + bumpy-check.yml (comments the release plan)
merge to main              -> bumpy ci release opens/updates the "Versioned release" PR
                              (bumps package.json, writes CHANGELOG.md)
merge the Versioned release PR
  -> release.yml: test.yml (luacheck, busted), then bumpy ci release publishes:
       draft GitHub release for tag bff@X.Y.Z (notes from the bump files)
       publishCommand: scripts/package.sh X.Y.Z
       tag pushed, release finalised
```

Bumpy's tags are always `<name>@<version>` (`bff@0.1.0`); that isn't configurable.

`release.yml` follows bumpy's split-job layout: a `plan` job decides between `version-pr` and `publish`, and only the publish path runs the tests and the packager. The tests run in their own job because bumpy won't publish from a working tree with untracked files, and the Lua setup leaves some.

An optional `BUMPY_GH_TOKEN` secret (a fine-grained token with contents and pull-request write access on this repo) makes the Versioned release PR trigger the test and bumpy check workflows. Without it, that PR gets no checks, which is fine since `release.yml` runs the tests before publishing anyway.

No `BUMPY_GH_TOKEN` is set today, so Settings → Actions → General → **Allow GitHub Actions to create and approve pull requests** must be on. Otherwise `version-pr` fails with "GitHub Actions is not permitted to create or approve pull requests".

`.bumpy/_config.json` names `versionPr.branch` (`bumpy/version-packages`) explicitly: bumpy (as of 1.19.0) replaces the whole `versionPr` object instead of merging it with its defaults, so setting only the title left the branch `undefined`. The default preamble (bumpy's logo and blurb) is dropped the same way, which is fine.

### Building the zip: `scripts/package.sh <version>`

Bumpy owns the tag, the GitHub release and its notes. The BigWigs packager only builds:

1. Create a local tag `v<version>`, so the packager's `@project-version@` (used in `## Version:`) becomes `v0.1.0` rather than `bff@0.1.0`. It's never pushed.
2. Run the packager (pinned to a release tag) in build-only mode (`-d`): fetch the `.pkgmeta` externals and write `BFF-v<version>.zip`, leaving out `tests/`, `Dev/`, `scripts/`, `.bumpy/`, `package.json`, `package-lock.json` and `node_modules/`.
3. Write `release.json` with `jq` in the packager's format: one entry for the zip, with a metadata row per interface in the `.toc` (`forever` for `16001`, `mainline` for `120105`). The packager only writes it in its own upload step, which `-d` skips.
4. `gh release upload bff@<version>` with the zip and `release.json`.

Bumpy creates the draft release, runs the `publishCommand`, then finalises the release and pushes the tag, so the upload goes to a **draft** release whose tag doesn't exist on the remote yet. A dry run on 2026-10-31 proved that works: `gh release upload` found a draft by its pending tag name and attached both files, and no tag was created.

`scripts/package.sh <version> --no-upload` builds into `.release/` without uploading. The packager needs bash 4, so on the Mac run it in a Linux container.

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

- The settings page layout beyond the sections above. It's a canvas page (`Settings.RegisterCanvasLayoutCategory`) with standard-looking controls, since the vertical layout has no text box for the display name. The Defaults button leaves BFF's settings alone.
- Forever's launch interface number and game type (map: "Forever launch day").
