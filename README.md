# BFF – Best Friends in Forever

![BFF – Best Friends in Forever](docs/gallery/out/00-banner.png)

A World of Warcraft: Forever addon for friends who don't always play at the same time. It shows everyone's characters, levels and whereabouts, and tells you what your friends did while you were away. No server, no account, and no shared guild needed.

## What it does

<table>
<tr>
<td width="50%"><img src="docs/gallery/out/01-hero.png" alt="While you were away"><br><b>While you were away.</b> On login, every ding, death and new character your friends had since you last played.</td>
<td width="50%"><img src="docs/gallery/out/02-camp.png" alt="Gather round the fire"><br><b>Gather round the fire.</b> Your friends around one campfire at the top of the panel: awake while they play, asleep while they don't, with a grave for each recent death and a flower once someone pays respects.</td>
</tr>
<tr>
<td><img src="docs/gallery/out/03-roster.png" alt="Your whole crew"><br><b>Your whole crew.</b> Every friend's characters, levels and whereabouts, and when each was last seen.</td>
<td><img src="docs/gallery/out/04-feed.png" alt="Cheer every ding"><br><b>Cheer every ding.</b> One click sends a cheer for a ding, respects for a death, or a welcome for someone new.</td>
</tr>
<tr>
<td><img src="docs/gallery/out/05-goals.png" alt="Level up together"><br><b>Level up together.</b> Goals the whole crew works towards, and trophies for what you do together, like clearing a dungeon. Nobody is ranked.</td>
<td><img src="docs/gallery/out/06-spares.png" alt="Pass on spare gear"><br><b>Pass on spare gear.</b> Offer an item to your friends. Whoever claims it first gets it by in-game mail.</td>
</tr>
<tr>
<td><img src="docs/gallery/out/07-when.png" alt="When everyone plays"><br><b>When everyone plays.</b> A heatmap of the hours each friend usually plays, in your own time zone.</td>
<td><img src="docs/gallery/out/08-professions.png" alt="Who crafts what"><br><b>Who crafts what.</b> Every friend's professions and skill in one grid, so you know who to ask for a craft.</td>
</tr>
<tr>
<td><img src="docs/gallery/out/09-together.png" alt="Dungeons together"><br><b>Dungeons together.</b> See which friends are close to your level, and the dungeons you can run together.</td>
<td></td>
</tr>
</table>

## Start a crew

1. Everyone in the group installs BFF.
2. One friend types `/bff start` and shares the crew code.
3. The others type `/bff join <code>`.

## Commands

| Command | What it does |
|---|---|
| `/bff` | Open or close the panel (also a key binding and the minimap button) |
| `/bff feed`, `/bff goals`, `/bff when`, `/bff spares`, `/bff professions`, `/bff together` | Open the panel on that tab |
| `/bff spares add <item>` | Offer an item from your bags: shift-click it in after `add` |
| `/bff start`, `/bff join <code>`, `/bff leave` | Start, join or leave a crew |
| `/bff code` | Show your crew code |
| `/bff name <name>` | Set the name your friends see |
| `/bff settings` | Open Settings |
| `/bff minimap` | Bring back a hidden minimap button |
| `/bff report` | Open a diagnostics report (versions, link state and the recent sync log) to copy into a bug report |
| `/bff debug sync` | Print the sync trace in chat as well: a line for each message sent and received, and for the link going up or down. Off again after a reload. The trace is always kept for `/bff report` |
| `/bff help` | List the commands |

## Install

- **CurseForge:** [BFF – Best Friends in Forever](https://www.curseforge.com/wow/addons/bff-best-friends-in-forever), or search for it in the CurseForge app.
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

scripts/check.sh    # luacheck, then busted; CI runs the same
```

Design notes: [`docs/design/code-structure.md`](docs/design/code-structure.md) and the rest of `docs/design/`. [`docs/design/architecture.html`](docs/design/architecture.html) is the original draft, kept for history.

### Gallery images

The CurseForge gallery and the banner above are rendered from in-game screenshots with `npm run gallery`. See [`docs/gallery/README.md`](docs/gallery/README.md).

## Releasing

Releases are cut with [bumpy](https://github.com/dmno-dev/bumpy) (see `docs/design/settings-and-release.md`). A PR that changes shipped files (`changedFilePatterns` in `.bumpy/_config.json`) needs a bump file:

```sh
npm install
npx bumpy add --packages "bff:patch" --message "What changed, for the changelog."
```

Merging to `main` opens or updates the "Versioned release" PR. Merging that publishes the GitHub release `bff@X.Y.Z` with the zip and `release.json`, and uploads the zip to CurseForge once the `CF_API_KEY` secret and `CURSEFORGE_PROJECT_ID` variable are set.

## Support

If BFF brings your crew together and you'd like to say thanks, you can [buy me a coffee](https://buymeacoffee.com/mltdwymkxn). It's never expected.

## Thanks

Some of BFF came from ideas players left in the comments on CurseForge:

- **kayloohoo** asked for a small campfire to keep on screen, with little animations for what friends are doing. That became the Pocket Camp.
- **absolutezabba12** asked for a setting to turn the map location off, more accurate positions, and the Camp's characters on the map in place of dots. That became the map pin setting, live positions and the Camp figures as map pins.
- **TheDolmenDuke** asked for the Pocket Camp to show a friend at a shop or the auction house, in combat and handing in a quest, and for a dungeon icon of its own. That became the Pocket Camp's poses for what each friend is doing right now.

## License

MIT, see [`LICENSE`](LICENSE). The libraries in `Libs/` keep their own licenses.
