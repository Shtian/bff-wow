# Research: boss kills on WoW: Forever

For [#120](https://github.com/Shtian/bff-wow/issues/120), step 1: does `ENCOUNTER_END` fire on Forever for dungeon and raid bosses, are its values readable, and which boss's kill clears each instance. BFF needs the encounter ID of each instance's **final boss** to record a **Clear** (`CONTEXT.md`, `docs/design/trophies.md`).

**Status (2026-11-03): no Forever runs logged yet.** Development happens on retail, and an agent can't run dungeons on Forever. Everything below that says "to confirm" needs a person with a Forever client and the encounter logger. Until a final boss's ID is known, BFF records no clear for that instance. That's safe: an unknown encounter records nothing.

How sure each answer is:

- **Documented:** a source says so.
- **Expected:** classic's answer, which Forever may have changed.
- **To confirm:** needs a run on Forever with the logger.

## What's known

- `ENCOUNTER_END` gives `encounterID` (a DungeonEncounterID, not the Encounter Journal's ID), `encounterName`, `difficultyID`, `groupSize` and `success` (1 or 0) ([Warcraft Wiki](https://warcraft.wiki.gg/wiki/ENCOUNTER_END)). **Documented.**
- A [Forever API cheat sheet](https://wowforeverguides.com/addons/api-cheatsheet) says to use `ENCOUNTER_START`/`ENCOUNTER_END` "if the encounter fires them". The combat log is unavailable to addons, and secret values are active on Forever. **Documented**, by a third party.
- Forever has no native Encounter Journal for its own content; third-party journals are being filled in from player runs. So the IDs can only come from runs.
- Addon messages are blocked during encounters (`Enum.AddOnRestrictionType` has Encounter; see `docs/research/bag-items.md`). BFF doesn't need to send then: a clear goes into the own record, and the record goes out once the channel link is back up.

## Questions for the first runs

1. Does `ENCOUNTER_END` fire for **dungeon** bosses? For **raid** bosses? For every boss, or only some?
2. Are its values readable, or secret (`issecretvalue`)? `encounterID` and `success` are the ones BFF needs. Are `GetInstanceInfo()`'s instance type and ID readable at that moment?
3. Can the party's `UnitGUID` and `UnitName` be read then? BFF matches party members to Members by GUID, then by name.
4. What does `UnitName` return for a Forever Character with a last name? **Answered 2026-11-08** for `"player"`: two values, `"Moorwyn", "Stormgaard"`, with the last name where retail puts the realm (`docs/research/addon-message-reliability.md`, Findings in game). BFF stores and compares the first value. Party units are not checked yet.
5. The encounter ID, name and order of every boss in each instance, with the final one marked.
6. Dire Maul's three wings and Stratholme's two sides: one instance in BFF's dungeon table each. Which kill should count as the clear (see below)?

## How to log

In a dev checkout (`Dev/` is loaded), every `ENCOUNTER_END` is printed in chat and saved in `BFF_DB.devEncounters` (the newest 200): the five payload values, which of them were secret, `GetInstanceInfo()` (name, instance type, difficulty, instance ID and the rest), the group's GUIDs and names, and what BFF made of it ("clears The Deadmines", or why not: `unknown`, `wipe`, `notInstance`, `unreadable`). `/bffdev encounters` shows the last five; `/bffdev encounters clear` empties the log. The log is written to `WTF/Account/<account>/SavedVariables/BFF.lua` on `/reload` or logout.

After a run, fill in the tables below from the saved log, and add each final boss's ID to `finals` in `Core/Together.lua`'s dungeon table.

## Findings

| Question | Answer |
|---|---|
| Fires for dungeon bosses | to confirm |
| Fires for raid bosses | to confirm |
| `encounterID` readable | to confirm |
| `success` readable | to confirm |
| Instance type and ID readable | to confirm |
| Party GUIDs and names readable | to confirm |

## Final bosses

Names match `Core/Together.lua`'s dungeon table. "Classic final boss" is classic's last boss (**expected**); Forever's new instances have no expectation. The encounter IDs in `finals` today are **datamined** from Forever's `DungeonEncounter` table ([wago.tools](https://wago.tools/db2/DungeonEncounter), build 1.60.1.70755, the `wowf` product), the three classic raids' matching classic's. Where there are several (one per difficulty or season, a wing, a side, or two bosses in no fixed order), `finals` lists all of them and any one clears the instance; a run narrows that down. Not in the table yet, so still unknown: Excavation Site (probably Relic Guardian, 3482), City of Dalaran (probably Shade of the Archmage, 3303), Blackmaw Hold, The Drowned City, Krol'dok Stronghold, Alcaz Prison, Shaper's Terrace, The Barrow Deeps and Hyjal Summit.

| Instance | Kind | Classic final boss | Encounter ID |
|---|---|---|---|
| Ragefire Chasm | dungeon | Taragaman the Hungerer or Bazzalan (no fixed order) | 2733 or 2735 (datamined, to confirm) |
| Hall of Thanes | dungeon (Forever) | unknown | 3496 (datamined, to confirm) |
| Ruins of Lordaeron | dungeon (Forever) | unknown | 3354 (datamined, to confirm) |
| Wailing Caverns | dungeon | Mutanus the Devourer | 592 (datamined, to confirm) |
| The Deadmines | dungeon | Edwin VanCleef | 2747 (datamined, to confirm) |
| Shadowfang Keep | dungeon | Archmage Arugal | 2755 (datamined, to confirm) |
| Blackfathom Deeps | dungeon | Aku'mai | 2910, 2891 or 2767 (one per difficulty) (datamined, to confirm) |
| The Stockade | dungeon | Bazil Thredd (no fixed order) | 2760 (datamined, to confirm) |
| Excavation Site | dungeon (Forever) | unknown | unknown |
| SM Graveyard | dungeon | Bloodmage Thalnos | 2779 (datamined, to confirm) |
| City of Dalaran | dungeon (Forever) | unknown | unknown |
| Gnomeregan | dungeon | Mekgineer Thermaplugg | 2772 or 2940 (one per difficulty) (datamined, to confirm) |
| SM Library | dungeon | Arcanist Doan | 447 (datamined, to confirm) |
| Razorfen Kraul | dungeon | Charlga Razorflank | 2778 (datamined, to confirm) |
| SM Armory | dungeon | Herod | 448 (datamined, to confirm) |
| SM Cathedral | dungeon | High Inquisitor Whitemane | 450 (datamined, to confirm) |
| The Drowned City | dungeon (Forever) | unknown | unknown |
| Razorfen Downs | dungeon | Amnennar the Coldbringer | 2785 (datamined, to confirm) |
| Krol'dok Stronghold | dungeon (Forever) | unknown | unknown |
| Uldaman | dungeon | Archaedas | 554 (datamined, to confirm) |
| Zul'Farrak | dungeon | Chief Ukorz Sandscalp | 600 (datamined, to confirm) |
| Maraudon | dungeon | Princess Theradras | 429 (datamined, to confirm) |
| Alcaz Prison | dungeon (Forever) | unknown | unknown |
| Sunken Temple | dungeon | Shade of Eranikus | 3584, 2959 or 493 (one per difficulty) (datamined, to confirm) |
| Blackrock Depths | dungeon | Emperor Dagran Thaurissan | 2790 (datamined, to confirm) |
| Lower Blackrock Spire | dungeon | Overlord Wyrmthalak | 275 (datamined, to confirm) |
| Blackmaw Hold | dungeon (Forever) | unknown | unknown |
| Dire Maul | dungeon | three wings: Alzzin the Wildshaper (East), Prince Tortheldrin (West), King Gordok (North) | 346, 361 or 368 (one per wing) (datamined, to confirm) |
| Scholomance | dungeon | Darkmaster Gandling | 2801 (datamined, to confirm) |
| Stratholme | dungeon | two sides: Balnazzar (Live), Baron Rivendare (Undead) | 478 or 484 (one per side) (datamined, to confirm) |
| Upper Blackrock Spire | dungeon | General Drakkisath | 3069 (datamined, to confirm) |
| Shaper's Terrace | dungeon (Forever) | unknown | unknown |
| Molten Core | raid | Ragnaros | 672 (datamined, matches classic, to confirm) |
| Onyxia's Lair | raid | Onyxia | 1084 (datamined, matches classic, to confirm) |
| Zul'Gurub | raid | Hakkar | 793 (datamined, matches classic, to confirm) |
| The Barrow Deeps | raid (Forever) | unknown | unknown |
| Hyjal Summit | raid (Forever) | unknown | unknown |

`finals` takes a list, so Dire Maul and Stratholme can count any wing's or side's last boss as their clear; whether they should, or should be split into separate instances, is still open.

## Every boss

To fill from runs, one table per instance, for a later "Halfway through" ticket (per-boss progress). Instances not yet run stay out.

| Order met | Boss | Encounter ID | Final |
|---|---|---|---|
| | | | |
