# Code structure and testing

Answers [How is the code split into modules and tested?](https://github.com/Shtian/bff-wow/issues/9). Builds on the sync resolution in #8 and `docs/adr/0001-owner-written-records-gossiped-by-server-time.md`. Domain vocabulary from `CONTEXT.md`; architecture vocabulary (module, interface, seam, adapter, depth) as in the `codebase-design` skill.

## The idea in one line

Almost all behaviour lives in one deep, pure-Lua module, **Core**, behind a small interface. The WoW-facing code is thin. Offline tests and `/bff sim` drive real Cores against each other through a fake link.

## Modules

| Module | Pure? | Owns |
|---|---|---|
| **Core** (`Core/`) | yes | Everything BFF knows and decides: Member records, sync, Feed, panel rows, saved-data layout. Details below. |
| **Snapshot** (`Game/Snapshot.lua`) | no | Reads level, XP, zone, class and GUID, counts deaths (kept per Character in `BFF_CharacterDB`), and calls `core:updateOwn(character)`. |
| **Channel link** (`Game/ChannelLink.lua`) | no | The production link adapter: joins and hides the Crew channel (including filtering its system notices out of chat), AceComm with ChatThrottleLib, decides when the link is up or down, reports Members leaving the channel, and has an echo mode. See `docs/research/channel-spike.md`. |
| **UI** (`UI/Panel.lua`, `UI/Minimap.lua`, `UI/Away.lua`, `UI/Settings.lua`) | no | Renders Core's rows and summaries and sends user commands to Core. Shows no state it worked out itself. |
| **App** (`BFF.lua`) | no | Wiring only: creates Core, routes WoW events, runs a 1 s `C_Timer` ticker that calls `core:tick()`, and handles slash commands. |

The first draft's Zones module is dropped from v1, because only the overlap finder needed it.

## Core

### Interface

Core is created with:

- `db`: the whole `BFF_DB` table. Core owns its layout, defaults and migrations, settings included.
- `now()` and `random()`: the clock (`GetServerTime` in game) and randomness, so tests are deterministic.
- `link`: the outgoing half of the link port (`send(string)`).
- `listener`: receives Core's events.
- `receiveOnly`: true on Trial and Veteran accounts.
- `initialLogin`: `isInitialLogin` from `PLAYER_ENTERING_WORLD`, so Core can tell a login from a reload (see `docs/design/feed.md`).
- `maxLevel`: from `GetMaxLevelForPlayerExpansion()`, for max level Feed entries.
- `utcOffset`: how many seconds local time is ahead of server time, so `feed()` starts each day at local midnight (default 0).

Inputs:

- `updateOwn(character)`: the current state of the Character being played, from Snapshot.
- `tick()`: once a second. Core decides what is due (reply delays, debounced sends, heartbeat, online timeouts, pruning).
- `received(string)`, `up()`, `down()` and `gone(name)`: the incoming half of the link port.
- Commands: start, join and leave a Crew, change the display name, Set as Main, Remove and re-add a Member, Pause sharing, and settings (see `docs/design/joining-a-crew.md`).

Outputs:

- `link.send(string)`: best-effort (see the link port below).
- Listener events:
  - `changed`: re-read whatever you show (`rows()`, `feed()`, settings such as Pause sharing and Show minimap button). Also fires when a Member passes the 12-minute online timeout, even though no record changed.
  - `feedEntry(entry)`: a live Feed event, fired only when the chat-line setting is on. App prints `entry.text`.
  - `awaySummary(summary)`: While you were away has settled after an initial login. Fired only when the popup setting is on and it isn't empty. App shows it once out of combat.
  - `notice(kind)`: one-off messages ("BFF is out of date", "receive-only on trial accounts", "you left the Crew").
  - `crewChanged`: the Crew was joined or left. App tells the channel link to join or leave the channel from `crew()`.
- Reads: `crew()` (code, channel name and password, a `leaving` flag while a leave is pending, or nil), `displayName()`, `isReceiveOnly()`, `isPaused()`, `isMinimapShown()`, `isChatLinesOn()` and `isAwayPopupOn()`, plus `minimapIcon()`, the saved table LibDBIcon keeps the button's position and hidden flag in.
- Ready-to-render reads for UI: `rows()`, and `feed()` (the Feed tab's entries grouped by day, plus the unseen count). UI never sees a Member record.
- `feedSeen()` is the command for opening the Feed tab. Core marks entries seen itself when it fires `feedEntry` or `awaySummary`.

### Inside Core

These are internal seams: separate files for locality, tested only through Core's interface, with nothing swappable behind them.

- **Ledger** (`Core/Ledger.lua`): what we know. Holds the own record and copies of everyone else's, the merge rule (a higher version wins), the Remove list, the "left" flag, last-heard times, and 180-day pruning. Removing a Member deletes their record and drops future copies. Re-adding takes them off the list and sends a DIGEST, and peers reply with DATA.
- **Gossip** (`Core/Gossip.lua`): when to talk. Owns the DIGEST and DATA rules, 1–4 s reply delays and suppression, send timing (immediate, 10 s zone debounce, XP piggyback, 5-minute heartbeat), the "record changed" and "reply owed" flags, Pause, and receive-only.
- **Feed** (`Core/Feed.lua`): turns a before/after record pair from Ledger into Feed entries, including skipped versions such as 22 → 24. Also owns the capped log, seen flags, and when While you were away is ready. See `docs/design/feed.md`.
- **Roster** (`Core/Roster.lua`): builds panel rows from Ledger. Covers Main resolution, "on alt", online (heard within 12 min, and not seen leaving the channel since), Last seen, "can play with you" (±3 levels), the 30-day hide and sorting.
- **CrewCode** (`Core/CrewCode.lua`): generates, normalises and checks Crew codes, and derives the channel name and password from them.
- **Codec** (`Core/Codec.lua`): a plain-text protocol version header, then the LibSerialize + LibDeflate body (`1|<payload>`). A newer version is detected before anything is decoded.

## The link port

This is the only real seam in v1. Its adapters are the channel link, the fake link, and the whisper mesh is not needed: **Spike: do two clients see each other over the Crew channel?** showed the channel works (`docs/research/channel-spike.md`).

- Core → link: `send(string)`. **Best-effort**: a message can be lost silently, including messages ChatThrottleLib had queued when lockdown began.
- Link → Core: `received(string)`, `up()`, `down()` and `gone(name)`. The sender's name is never passed with a message; identity travels inside the payload. Core drops messages carrying its own Member id, since the channel echoes your own messages back.
- `gone(name)`: a Character left the channel, i.e. logged out (a real logout leaves the channel before any goodbye could be sent, so there is none). The name is bare (`Ambiguate(sender, "none")`). Core marks the Member owning a Character of that name offline right away; the 12-minute timeout stays as the fallback. It is only a presence hint, never used to identify data.
- A send the game refuses (`AddonMessageThrottle`, `GeneralError`) makes the channel link call `down()`, and `up()` again 5 s later, so the rule below recovers it. The pause keeps a refusal that repeats (such as sends during a logout) from becoming a send loop.
- Each adapter decides what "down" means. For the channel link it is `C_ChatInfo.InChatMessagingLockdown()`, or not yet in the Crew channel, or having left it.
- On every `up()`, Core sends a fresh DIGEST, plus its own DATA if its record changed while the link was down. This one rule covers first join, rejoin, lockdown clearing, and lost sends.
- Lockdown, Pause and receive-only never appear in the port. Lockdown is the adapter's reason for being down. Pause and receive-only are Core policy; receive-only comes from `IsTrialAccount()` / `IsVeteranTrialAccount()` only, never `AreOutgoingAddonChatMessagesRestricted()`, which the spike saw return true on a full account.

## Loading pure code in game and in tests

Every file starts with `local _, ns = ...` and attaches itself to `ns`, the addon's private table. Files in `Core/` only touch `ns`, Lua builtins, the `bit` library (WoW and LuaJIT both have it) and the pure libraries (LibSerialize, LibDeflate). The test loader mimics the `.toc` with `loadfile("Core/Ledger.lua")("BFF", ns)`. A luacheck rule bans WoW globals in `Core/`.

## Tests

- **Runner:** busted under LuaJIT, linted with luacheck.
- **The interface is the test surface.** Tests create Cores and check `rows()`, the While you were away summary, Feed entries, and the recorded listener events and sent messages. They never look inside `db`, Ledger or Gossip.
- **Fake network** (`Dev/FakeNet.lua`):
  - One shared virtual clock and scheduler, so every run plays out the same way.
  - Each simulated client is a real Core with a fake link and its own `db`.
  - Per client: online or offline (link up or down), lockdown (link down while still online), Pause, reload (a new Core over the same `db`), and crash (a new Core over a copy of `db` taken at the last logout or reload).
  - Delivery is a broadcast to every client whose link is up, after a small delay, with optional drops to test the best-effort contract.
  Delivery includes the sender itself, as the real channel does. A client going offline fires `gone(name)` on the others; a crash can skip it.
  - Messages go through the real Codec.
- **Scenarios** include:
  - C logs in after missing A's ding, learns it from B, and D stays quiet.
  - A crashes and its next version still wins.
  - Changes made during lockdown go out after one DIGEST when it clears.
  - A lost message is recovered at the next `up()`.
  - A removed Member is never shown or relayed.
  - Someone going quiet flips to offline after 12 minutes.
  - Ten Members with three Characters each: the DIGEST fits one message.
- **WoW stand-ins** (`tests/wow_stubs.lua`): only for Snapshot and the channel link. UI frames aren't tested offline.
- **In game:** `/bff sim` reuses FakeNet to attach a few simulated Members to your real Core, so the panel and Feed can be tested without a friend online. Their records are kept and relayed like real ones, so it only runs in a Crew where no one else is known yet. `/bff sim ding` makes one ding, `/bff sim stop` logs them out. The `.toc` lists `Dev/` inside `#@do-not-package@`, so releases don't load it. Echo mode on the channel link loops your own messages back to you.
- **GitHub Actions** (`test.yml`) on every push and PR: `leafo/gh-actions-lua` (LuaJIT) and `leafo/gh-actions-luarocks`, `luarocks install busted luacheck`, fetch libraries, `luacheck .`, `busted`.

## Libraries

| Library | Why |
|---|---|
| LibStub, CallbackHandler-1.0 | required by the rest |
| AceComm-3.0 | splits messages over 255 bytes |
| ChatThrottleLib | send limits (used by AceComm) |
| LibSerialize, LibDeflate | compact payloads; pure Lua, so tests use them too |
| LibDataBroker-1.1, LibDBIcon-1.0 | minimap button |

Not embedded: AceDB (Core owns plain SavedVariables), AceConsole and AceEvent (a few lines with `SlashCmdList` and an event frame), and AceConfig (the native Settings API).

**Fetched, not committed**, as most addons do: libraries are declared as externals in `.pkgmeta`, which the BigWigs packager fetches at release time, and `Libs/` is in `.gitignore`. `scripts/fetch-libs.sh` checks out the same externals into `Libs/` for the dev loop (run once on the Windows PC from Git Bash, and again after a library bump) and in CI. `.pkgmeta` also leaves `tests/`, `Dev/`, `scripts/` and the bumpy files out of releases. Releases are cut with bumpy and built by `scripts/package.sh`; see `docs/design/settings-and-release.md`.

## Layout

```
BFF.toc
BFF.lua
Bindings.xml                         -- key binding to open the panel
Core/  Core.lua  Ledger.lua  Gossip.lua  Feed.lua  Roster.lua  CrewCode.lua  Codec.lua
Game/  Snapshot.lua  ChannelLink.lua
UI/    Panel.lua  Minimap.lua  Away.lua  Settings.lua
Dev/   FakeNet.lua  Sim.lua          -- left out of releases
Libs/                                -- fetched, gitignored
scripts/ fetch-libs.sh  package.sh   -- package.sh builds the release zip
tests/ load.lua  wow_stubs.lua  *_spec.lua
.busted  .luacheckrc  .pkgmeta
package.json  .bumpy/  CHANGELOG.md  -- release tooling (bumpy), left out of releases
.github/workflows/ test.yml  release.yml
```

## Not decided here

- Snapshot keeps counting deaths, so a client crash loses that session's deaths, and peers see the count go down. Moving the count into Core was considered and not taken for now.
