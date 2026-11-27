# Crews per ruleset and faction

How ADR 0009 is built. The decision and why are in the ADR, and the words come from `CONTEXT.md`. This file covers the saved layout, the pieces of code, the order to build them in, and the tests.

## Saved layout

```lua
BFF_DB = {
  -- the account: settings (SETTINGS/savedIn), panelPlace, pocketCamp*, minimap,
  -- together, catches, changesSeen, changesTold, newerBffTold
  crews = {
    [slotId] = {
      ruleset = "mode:15:Alliance" | nil,   -- nil while unplaced
      provisional = true | nil,             -- placed by server ID, no other Member heard yet
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
  - `Slots.open(db, facts, random, now)` returns the active slot and its ruleset entry. In order, it:
    1. migrates once (`migrated`): when the old top level has a `crew`, its slot-level keys are copied into one unplaced slot whose id is the old Member id. A `keptCrew` (a Crew left before the update) isn't brought over: rejoining it gets a new Member id. The old keys stay where they are;
    2. builds the key;
    3. repairs a changed key. A missing key takes the entry of the same faction whose server IDs hold the current one, else the one with the current name. A key that's found but whose entry doesn't hold the current server ID swaps with the entry of the same faction that does (a patch renumbered the record IDs), so the server ID isn't added to the wrong entry. Each repair goes to the sync log and `/bff report`;
    4. places an unplaced slot when the entry's active slot has no Crew and the other Members' (or, when alone, the Main's) server IDs include the current one, marking it `provisional`. With no server ID and the `default` key (the game gives no facts), it places it without `provisional`, as one Crew for the account;
    5. makes an empty entry and slot if needed.
  - After placing it by server ID, Core drops your own Characters whose server ID is neither the current one nor any other Member's (`Ledger:keepCharacters`, which bumps the version and clears a dropped Main).
  - The current Character's GUID isn't in the facts, so `Core:updateOwn` drops it from every other slot's own record (left and unplaced slots too), once per Character per session.
  - `Core:elsewhere()` gives the no-Crew card's finished lines, from `Slots.elsewhere`. The panel's card and the login chat line both show them:
    - `hint`: "BFF keeps a separate Crew for each Ruleset and faction. Yours is on Normal (Alliance): log in a Character there to see it." Where the game has realms (retail) it says "realm" instead of "Ruleset". It names every other ruleset where you have a Crew, by its saved name (the Ruleset name, else the realm name), else "Ann's Ruleset" after the Character you last played there. A Crew from before Rulesets that BFF can place but that this login doesn't match is named too, with no faction: by the Character of yours last played on one of its server IDs ("Ann's Ruleset"), else "another Ruleset". (A saved entry holding one of its server IDs can't exist while it waits, since that login would have placed it.) Nil with nothing to name;
    - `ask`: "BFF keeps a separate Crew for each Ruleset and faction. It can't tell which one your Crew from before belongs to. Is this where your Crew is?", only when an unplaced slot with a Crew waits, no login of yours can place it (none of your own Characters shares a server ID with the other Members' Characters, or with your visible Main when alone), and this ruleset hasn't answered (`declined` on its entry);
    - `offer`: "Your Crew on Normal (Horde) hasn't heard from anyone yet. If your friends play this faction, bring it here.", for the other faction's provisional slot on this ruleset.
  - The card's answers, each refusing with `inCrew` in a Crew and `notWaiting` with nothing to answer:
    - `placeCrewHere()` (`Slots.placeHere`) makes the slot that's asked about this entry's active one, not `provisional`, since you chose it;
    - `startFresh()` (`Slots.decline`) marks the entry `declined`, so it stops asking here. Other rulesets still ask;
    - `bringCrewHere()` (`Slots.bringHere`) moves the offered slot into this entry, not `provisional`, and gives the other faction's entry a fresh slot.

    Placing and bringing rebind through `switchSlot`, drop your Characters that don't belong here (`Slots.belongsHere`), raise the generation and fire `crewChanged`. Starting fresh fires `crewChanged` too. Each answer goes to the sync log.
  - `rulesetNamed` fires `changed` when the name changes, so the views redraw.
- **`Core.new`** takes `db` (still the whole `BFF_DB`), plus `ruleset` (the facts). It keeps `self.account` for settings, What's new and `fresh` (the first-install check), and `self.db` for the active slot. A new `bindSlot(slot)` builds the modules that hold a slot:
  - Ledger, Feed, Spares, Goals, Stray, PlayTimes;
  - Gossip, which holds the Ledger;
  - Pocket, which holds Ledger, Feed, Goals and Spares.

  `Core.new` calls it once; starting, joining and leaving call it again.
- **Leave and rejoin.** `putAway`/`bringBack` and `keptCrew` go away:
  - Leaving marks the slot's `crew` left (`crew.left = true`). It moves to the entry's `left`, and a fresh slot with no Crew becomes `active`. Its own record starts as a copy of the left one's display name, Characters, Main and look (`Ledger:carryOwn`), and `joinFailure` moves with it.
  - Joining the left slot's code makes it active again and deletes the fresh slot.
  - Starting or joining any other code deletes the left slot.
  - The `Slots` helpers are `left`, `leave`, `rejoin` and `dropLeft`. Core rebinds through `bindSlot`, replays the last Character into the new Ledger, and fires `crewChanged`.
- **Confirmation.** The first DATA or DIGEST from another Member while `provisional` clears the flag.
- **`/bff report`** shows the key, the realm name, the record ID, the faction and the name, the current server ID and those seen, whether the slot is provisional, and any repair this session.

## Build order

Each step passes `scripts/check.sh` on its own.

1. **`Slots` with no migration.** It covers the key, new entries, the repair, and the account/slot split in `Core.new` and `bindSlot`. Settings, What's new and `fresh` read `self.account`. FakeNet passes facts, with a default of `default`, so the existing specs keep a single slot. Fix `Dev/Sim.lua:1245` (`BFF_DB.goals.seen`) and the specs that reach into `db.goals`, `db.feed`, `db.records` and so on.
2. **Leave and rejoin on slots.** Replaces `keptCrew`; the leave and rejoin specs in `joining-a-crew.md` must still pass.
3. **Migration, placing, provisional and pruning.** Drop the current Character from other slots.
4. **`Game/Ruleset.lua` and the `richPresence` name.** Add the `/bff report` lines.
5. **The no-Crew card**:
   - "BFF keeps a separate Crew for each Ruleset and faction. Yours is on Normal (Alliance)", or the name of a Character when no ruleset or realm name is saved;
   - the ask-once card for an unplaced slot BFF can't place;
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
  - swapped record IDs swap the entries, by server ID, and neither gains the other's server ID;
  - a found key with a server ID no other entry holds keeps its entry and adds the ID;
  - with nothing matching, a new entry is made and the old one is left alone.
- **Migration:** the saved Crew is made by a real BFF 2.18.0 client (`tests/before_rulesets.lua` loads that release's `Core/` and `Link/` files from the `bff@2.18.0` tag into their own namespace, and FakeNet's `Core` option runs a client on them), then the same client updates.
  - The old Crew shows up where it's placed, and the old keys still work for BFF 2.18.0 after a downgrade.
  - It runs only once.
- **Placing:**
  - a match with a friend's server ID places it, as `provisional`;
  - a match with only your RP alt doesn't, and the card says where the Crew is instead of asking;
  - alone in the Crew, the Main's server ID places it;
  - with no server ID to go by (alone, and every Character unplayed for over 30 days), the card asks once, and both answers work;
  - so it does when your friends play only on a server where you have no Characters.
- **Pruning:**
  - Placing it drops your other-ruleset Characters from your own record, and a friend on BFF 2.18.0 drops them too.
  - Playing a Character removes it from another slot's own record.
- **Provisional:**
  - a heard Member confirms it;
  - "bring it here" on the other faction moves the slot;
  - a confirmed slot no longer offers it.
- **Leave and rejoin:**
  - rejoining the same code brings back the slot and the Member id;
  - a different code deletes the left slot and gets a new Member id.
- **FakeNet with mixed versions:** a client on BFF 2.18.0 and a moved client in one Crew still sync, with the same Member ids.
