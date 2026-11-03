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
4. What does `UnitName` return for a Forever Character with a last name?
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

Names match `Core/Together.lua`'s dungeon table. "Classic final boss" is classic's last boss (**expected**); Forever's new instances have no expectation. The encounter IDs in `finals` today are only the three classic raids', taken from classic and **to confirm**.

| Instance | Kind | Classic final boss | Encounter ID |
|---|---|---|---|
| Ragefire Chasm | dungeon | Taragaman the Hungerer or Bazzalan (no fixed order) | unknown |
| Hall of Thanes | dungeon (Forever) | unknown | unknown |
| Ruins of Lordaeron | dungeon (Forever) | unknown | unknown |
| Wailing Caverns | dungeon | Mutanus the Devourer | unknown |
| The Deadmines | dungeon | Edwin VanCleef | unknown |
| Shadowfang Keep | dungeon | Archmage Arugal | unknown |
| Blackfathom Deeps | dungeon | Aku'mai | unknown |
| The Stockade | dungeon | Bazil Thredd (no fixed order) | unknown |
| Excavation Site | dungeon (Forever) | unknown | unknown |
| SM Graveyard | dungeon | Bloodmage Thalnos | unknown |
| City of Dalaran | dungeon (Forever) | unknown | unknown |
| Gnomeregan | dungeon | Mekgineer Thermaplugg | unknown |
| SM Library | dungeon | Arcanist Doan | unknown |
| Razorfen Kraul | dungeon | Charlga Razorflank | unknown |
| SM Armory | dungeon | Herod | unknown |
| SM Cathedral | dungeon | High Inquisitor Whitemane | unknown |
| The Drowned City | dungeon (Forever) | unknown | unknown |
| Razorfen Downs | dungeon | Amnennar the Coldbringer | unknown |
| Krol'dok Stronghold | dungeon (Forever) | unknown | unknown |
| Uldaman | dungeon | Archaedas | unknown |
| Zul'Farrak | dungeon | Chief Ukorz Sandscalp | unknown |
| Maraudon | dungeon | Princess Theradras | unknown |
| Alcaz Prison | dungeon (Forever) | unknown | unknown |
| Sunken Temple | dungeon | Shade of Eranikus | unknown |
| Blackrock Depths | dungeon | Emperor Dagran Thaurissan | unknown |
| Lower Blackrock Spire | dungeon | Overlord Wyrmthalak | unknown |
| Blackmaw Hold | dungeon (Forever) | unknown | unknown |
| Dire Maul | dungeon | three wings: Alzzin the Wildshaper (East), Prince Tortheldrin (West), King Gordok (North) | unknown |
| Scholomance | dungeon | Darkmaster Gandling | unknown |
| Stratholme | dungeon | two sides: Balnazzar (Live), Baron Rivendare (Undead) | unknown |
| Upper Blackrock Spire | dungeon | General Drakkisath | unknown |
| Shaper's Terrace | dungeon (Forever) | unknown | unknown |
| Molten Core | raid | Ragnaros | 672 (classic's, to confirm) |
| Onyxia's Lair | raid | Onyxia | 1084 (classic's, to confirm) |
| Zul'Gurub | raid | Hakkar | 793 (classic's, to confirm) |
| The Barrow Deeps | raid (Forever) | unknown | unknown |
| Hyjal Summit | raid (Forever) | unknown | unknown |

`finals` takes a list, so Dire Maul and Stratholme can count any wing's or side's last boss as their clear; whether they should, or should be split into separate instances, is still open.

## Every boss

To fill from runs, one table per instance, for a later "Halfway through" ticket (per-boss progress). Instances not yet run stay out.

| Order met | Boss | Encounter ID | Final |
|---|---|---|---|
| | | | |
