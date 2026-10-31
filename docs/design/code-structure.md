# Code structure and testing

Answers [How is the code split into modules and tested?](https://github.com/Shtian/bff-wow/issues/9). Builds on the sync resolution in #8 and `docs/adr/0001-owner-written-records-gossiped-by-server-time.md`. Domain vocabulary from `CONTEXT.md`; architecture vocabulary (module, interface, seam, adapter, depth) as in the `codebase-design` skill.

## The idea in one line

Almost all behaviour lives in one deep, pure-Lua module, **Core**, behind a small interface. The WoW-facing code is thin. Offline tests and `/bff sim` drive real Cores against each other through a fake link.

## Modules

| Module | Pure? | Owns |
|---|---|---|
| **Core** (`Core/`) | yes | Everything BFF knows and decides: Member records, sync, Feed, panel rows, saved-data layout. Details below. |
| **Snapshot** (`Game/Snapshot.lua`) | no | Reads level, XP, zone, class and GUID, counts deaths, and calls `core:updateOwn(character)`. |
| **Channel link** (`Game/ChannelLink.lua`) | no | The production link adapter: joins and hides the Crew channel, AceComm with ChatThrottleLib, decides when the link is up or down, and has an echo mode. |
| **UI** (`UI/Panel.lua`, `UI/Minimap.lua`, `UI/Settings.lua`) | no | Renders Core's rows and summaries and sends user commands to Core. Shows no state it worked out itself. |
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

Inputs:

- `updateOwn(character)`: the current state of the Character being played, from Snapshot.
- `tick()`: once a second. Core decides what is due (reply delays, debounced sends, heartbeat, online timeouts, pruning).
- `received(string)`, `up()` and `down()`: the incoming half of the link port.
- Commands: Set as Main, Remove and re-add a Member, Pause sharing, and settings.

Outputs:

- `link.send(string)`: best-effort (see the link port below).
- Listener events:
  - `rowsChanged`: redraw from `core:rows()`. Also fires when a Member passes the 12-minute online timeout, even though no record changed.
  - `feedEntry(entry)`: a live Feed event. App prints the one-line chat message if that is turned on.
  - `notice(kind)`: one-off messages ("BFF is out of date", "receive-only on trial accounts", "you left the Crew").
- Ready-to-render reads for UI: `rows()`, the While you were away summary, and recent Feed entries. UI never sees a Member record.

When the While you were away popup appears is still open (Feed storage is still fog on the map), so it has no event yet.

### Inside Core

These are internal seams: separate files for locality, tested only through Core's interface, with nothing swappable behind them.

- **Ledger** (`Core/Ledger.lua`): what we know. Holds the own record and copies of everyone else's, the merge rule (a higher version wins), the Remove list, the "left" flag, last-heard times, and 180-day pruning. Removing a Member deletes their record and drops future copies. Re-adding takes them off the list and sends a DIGEST, and peers reply with DATA.
- **Gossip** (`Core/Gossip.lua`): when to talk. Owns the DIGEST and DATA rules, 1–4 s reply delays and suppression, send timing (immediate, 10 s zone debounce, XP piggyback, 5-minute heartbeat, logout), the "record changed" and "reply owed" flags, Pause, and receive-only.
- **Feed** (`Core/Feed.lua`): turns a before/after record pair from Ledger into Feed entries, including skipped versions such as 22 → 24. Also owns the capped log and While you were away.
- **Roster** (`Core/Roster.lua`): builds panel rows from Ledger. Covers Main resolution, "on alt", online (heard within 12 min), Last seen, "can play with you" (±3 levels), the 30-day hide and sorting.
- **Codec** (`Core/Codec.lua`): a plain-text protocol version header, then the LibSerialize + LibDeflate body (`1|<payload>`). A newer version is detected before anything is decoded.

## The link port

This is the only real seam in v1. Its adapters are the channel link, the fake link, and later perhaps the whisper mesh if **Spike: do two clients see each other over the Crew channel?** fails.

- Core → link: `send(string)`. **Best-effort**: a message can be lost silently, including messages ChatThrottleLib had queued when lockdown began.
- Link → Core: `received(string)`, `up()` and `down()`. The sender's name is never passed; identity travels inside the payload.
- Each adapter decides what "down" means. For the channel link it is `C_ChatInfo.InChatMessagingLockdown()`, or not yet in the Crew channel, or having left it.
- On every `up()`, Core sends a fresh DIGEST, plus its own DATA if its record changed while the link was down. This one rule covers first join, rejoin, lockdown clearing, and lost sends.
- Lockdown, Pause and receive-only never appear in the port. Lockdown is the adapter's reason for being down. Pause and receive-only are Core policy.

## Loading pure code in game and in tests

Every file starts with `local _, ns = ...` and attaches itself to `ns`, the addon's private table. Files in `Core/` only touch `ns`, Lua builtins and the pure libraries (LibSerialize, LibDeflate). The test loader mimics the `.toc` with `loadfile("Core/Ledger.lua")("BFF", ns)`. A luacheck rule bans WoW globals in `Core/`.

## Tests

- **Runner:** busted under LuaJIT, linted with luacheck.
- **The interface is the test surface.** Tests create Cores and check `rows()`, the While you were away summary, Feed entries, and the recorded listener events and sent messages. They never look inside `db`, Ledger or Gossip.
- **Fake network** (`Dev/FakeNet.lua`):
  - One shared virtual clock and scheduler, so every run plays out the same way.
  - Each simulated client is a real Core with a fake link and its own `db`.
  - Per client: online or offline (link up or down), lockdown (link down while still online), Pause, reload (a new Core over the same `db`), and crash (a new Core over a copy of `db` taken at the last logout or reload).
  - Delivery is a broadcast to every client whose link is up, after a small delay, with optional drops to test the best-effort contract.
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
- **In game:** `/bff sim` reuses FakeNet to attach a few simulated Members to your real Core, so the panel and Feed can be tested without a friend online. Echo mode on the channel link loops your own messages back to you.
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

**Fetched, not committed**, as most addons do: libraries are declared as externals in `.pkgmeta`, which the BigWigs packager fetches at release time, and `Libs/` is in `.gitignore`. `scripts/fetch-libs.sh` checks out the same externals into `Libs/` for the dev loop (run once on the Windows PC from Git Bash, and again after a library bump) and in CI. `.pkgmeta` also leaves `tests/`, `Dev/` and `scripts/` out of releases.

## Layout

```
BFF.toc
BFF.lua
Core/  Core.lua  Ledger.lua  Gossip.lua  Feed.lua  Roster.lua  Codec.lua
Game/  Snapshot.lua  ChannelLink.lua
UI/    Panel.lua  Minimap.lua  Settings.lua
Dev/   FakeNet.lua  Sim.lua          -- left out of releases
Libs/                                -- fetched, gitignored
scripts/ fetch-libs.sh
tests/ load.lua  wow_stubs.lua  *_spec.lua
.busted  .luacheckrc  .pkgmeta
.github/workflows/ test.yml  release.yml
```

## Not decided here

- Snapshot keeps counting deaths, so a client crash loses that session's deaths, and peers see the count go down. Moving the count into Core was considered and not taken for now.
- Feed storage and when the While you were away popup appears (fog on the map).
- Release packaging details beyond the externals and ignores above (fog on the map).
