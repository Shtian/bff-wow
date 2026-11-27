# Crews per ruleset and faction

How ADR 0009 is built. The decision and why are in the ADR, and the words come from `CONTEXT.md`. This file covers the saved layout, the pieces of code, the order to build them in, and the tests.

## Saved layout

```lua
BFF_DB = {
  -- the account: settings (SETTINGS/savedIn), panelPlace, pocketCamp*, minimap,
  -- together, catches, changesSeen, changesTold, newerBffTold
  crews = {
    [slotId] = {
      ruleset = "mode:15:Alliance" | nil,   -- nil while unclaimed
      provisional = true | nil,             -- claimed by server ID, no other Member heard yet
      crew, channelMoves, joinFailure,
      memberId, records, via, removed, heard,
      feed, feedJoins, goals,
      spareItems, nextSpare, spareNews, spareWinners, catchTypesTold,
      paused, playTimes, stray,
    },
  },
  rulesets = {
    ["mode:15:Alliance"] = {
      active = slotId, left = slotId | nil,
      recordId = 15, faction = "Alliance", name = "Normal", serverIds = { "6939" },
    },
  },
  migrated = 1,
  -- the old top-level Crew keys, left as they were until a later release deletes them
}
```

A slot id is 8 characters from `[a-z0-9]`: a new slot's id is its new Member id. That keeps the number of `random()` calls per new Crew what it was, so FakeNet's seeded clients behave as before. A repair only moves an entry with the same faction, since both factions of a ruleset share its server IDs and name. A ruleset entry's `active` slot is what Core runs on. The entry is made empty (no `crew`) on the first login with that key.

## Pieces

- **`Game/Ruleset.lua` (the game side)** reads the facts once at `PLAYER_ENTERING_WORLD`, before `Core.new`:
  - `realmName` from `GetNormalizedRealmName()`
  - `recordId` from `C_GameRules.GetCurrentGameModeRecordID()`
  - `faction` from `UnitFactionGroup("player")`
  - `serverId` from `UnitGUID("player")`
  - `name` from `C_BattleNet.GetGameAccountInfoByGUID(guid).richPresence`, taking the text after `Forever - ` up to the next ` - `

  Each value is nil when the API is missing or returns nothing. Battle.net info may not be ready at login, so `name` is read again on `BN_INFO_CHANGED` and handed to `core:rulesetNamed(name)`.
- **`Core/Slots.lua` (pure)** owns the layout:
  - `Slots.open(db, facts, random)` returns the active slot and its ruleset entry. In order, it:
    1. migrates once (`migrated`);
    2. builds the key;
    3. repairs a changed key by server ID, then by name;
    4. drops the current Character from every other slot's own record;
    5. claims an unclaimed slot whose other Members' (or, when alone, Main's) server IDs include the current one, marking it `provisional`, and prunes other-ruleset Characters from its own record;
    6. makes an empty entry and slot if needed.
  - It also returns what the no-Crew card needs:
    - an unclaimed slot to ask about;
    - the other faction's provisional slot to offer;
    - the names of the rulesets where you have a Crew.
- **`Core.new`** takes `db` (still the whole `BFF_DB`), plus `ruleset` (the facts). It keeps `self.account` for settings, What's new and `fresh` (the first-install check), and `self.db` for the active slot. A new `bindSlot(slot)` builds the modules that hold a slot:
  - Ledger, Feed, Spares, Goals, Stray, PlayTimes;
  - Gossip, which holds the Ledger;
  - Pocket, which holds Ledger, Feed, Goals and Spares.

  `Core.new` calls it once; starting, joining and leaving call it again.
- **Leave and rejoin.** `putAway`/`bringBack` and `keptCrew` go away:
  - Leaving marks the slot's `crew` left. It moves to the entry's `left`, and a fresh empty slot becomes `active`.
  - Joining the left slot's code makes it active again.
  - Starting or joining any other code deletes the left slot.
- **Confirmation.** The first DATA or DIGEST from another Member while `provisional` clears the flag.
- **`/bff report`** shows the key, the record ID, server IDs, the name, whether the slot is provisional, and any repair this session.

## Build order

Each step passes `scripts/check.sh` on its own.

1. **`Slots` with no migration.** It covers the key, new entries, the repair, and the account/slot split in `Core.new` and `bindSlot`. Settings, What's new and `fresh` read `self.account`. FakeNet passes facts, with a default of `default`, so the existing specs keep a single slot. Fix `Dev/Sim.lua:1245` (`BFF_DB.goals.seen`) and the specs that reach into `db.goals`, `db.feed`, `db.records` and so on.
2. **Leave and rejoin on slots.** Replaces `keptCrew`; the leave and rejoin specs in `joining-a-crew.md` must still pass.
3. **Migration, claim, provisional and pruning.** Drop the current Character from other slots.
4. **`Game/Ruleset.lua` and the `richPresence` name.** Add the `/bff report` lines.
5. **The no-Crew card**:
   - "Your Crew is on Normal (Alliance)", or the name of a Character when no ruleset name is saved;
   - the ask-once card for an unclaimed slot;
   - "Bring your Crew here" for the other faction's provisional slot.
6. **Bump files**:
   - minor, for players: "BFF keeps a separate Crew for each ruleset and faction";
   - "Internal:", for the slot layout.

   Also update the FAQ in `docs/curseforge-description.md` and `code-structure.md` (Core's deps, `crew()`, the db layout).

## Tests

- **Key:**
  - a realm name wins;
  - otherwise the record ID;
  - otherwise `default`;
  - the faction is part of the key.
- **Repair:**
  - a new record ID with a known server ID moves the entry;
  - so does an unknown server ID with a known name;
  - with nothing matching, a new entry is made and the old one is left alone.
- **Migration:**
  - The old top-level data becomes one unclaimed slot, the settings stay at the top level, and the old keys are still there.
  - It runs only once.
- **Claim:**
  - a match with a friend's server ID claims, as `provisional`;
  - a match with only your RP alt doesn't claim;
  - alone in the Crew, the Main's server ID claims;
  - with no match, the slot stays unclaimed and the card asks.
- **Pruning:**
  - On a claim, your other-ruleset Characters leave your own record, and a merge on an old client drops them too.
  - Playing a Character removes it from another slot's own record.
- **Provisional:**
  - a heard Member confirms it;
  - "bring it here" on the other faction moves the slot;
  - a confirmed slot no longer offers it.
- **Leave and rejoin:**
  - rejoining the same code brings back the slot and the Member id;
  - a different code deletes the left slot and gets a new Member id.
- **FakeNet with mixed versions:** an old client and a new client in one Crew still sync, with the same Member ids.
