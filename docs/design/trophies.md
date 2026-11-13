# Trophies: goal rungs and clears

Answers [Dungeon and raid clears as Crew trophies](https://github.com/Shtian/bff-wow/issues/120), on top of the trophy cabinet from [#119](https://github.com/Shtian/bff-wow/issues/119) (`docs/design/goals.md`). Domain vocabulary from `CONTEXT.md` (**Trophy**, **Clear**). Record format: `docs/adr/0005-clears-kept-in-each-members-own-record.md`. What the game gives: `docs/research/boss-kills.md`.

## The idea in one line

A Crew trophy is either a Crew goal rung reached or an instance the Crew has cleared. Every Member in a clearing party records the clear in their own record; every client works out the Crew's first clear of each instance from the records it holds, and shows it like a goal rung: a medal, a Feed entry, a toast and a While you were away line.

## Recording a clear

`ENCOUNTER_END` → `Snapshot.encounter(...)` (secret values read as nil, the instance type from `GetInstanceInfo()`, the group's `{ guid, name }`) → `core:encounterEnded(encounter)`. Core records a clear when all of these hold:

- the payload is readable: `encounterId` a number, `success` a boolean, `party` a table (else `"unreadable"`, and nothing happens: no error);
- the boss died (`"wipe"` otherwise);
- you're in a party or raid instance (`"notInstance"`);
- the encounter is a known final boss (`"unknown"`): `finals` in the dungeon table (`Core/Together.lua`), collected as `Core.FINAL_BOSSES`. Attunements have none;
- you're in a Crew (`"noCrew"`).

The clear goes into the own record's `clears[instance]`: `t`, the first clear's time, and `m`, the Member ids of every clearing party: you, and each held Member (not Left) owning a party member's Character, matched by GUID, else by name. Strangers aren't named. A repeat clear changes the record only if someone new was in the party. The record goes out with the next DATA ("now" urgency), which waits while the link is down (encounters are in messaging lockdown).

## The Crew's clears

`Goals` keeps the Crew's clears beside the reached rungs, in `db.goals.clears[instance]`: `time`, `members` (a set) and `quiet`. On every check (a record changed: own or merged) it collects the clears over the counted records (`Clears.collect`: per instance the earliest time and every Member id credited):

- An instance not yet kept is a **new Crew trophy**: one Crew-wide `goal` Feed entry, "The Crew cleared The Deadmines!", announced like a goal's (toast, chat line, While you were away under Crew goals).
- One already kept only moves its time back to an earlier clear, if a record brings one, and adds who's credited. No news.
- **Quiet**, as for goals: clears passed at the silent baseline, or first seen in a Member's record when you first see that Member (first sight), are kept without news and are never fresh.

Each client keeps its own; nothing about the Crew's trophies is synced beyond the records.

## On the Trophies tab

`trophies()` gains clears (`docs/design/code-structure.md` has the fields):

- **Shelf and latest win:** clear trophies join the goal rungs, newest first by the first clear's time. A clear can be the gold latest-win plate, worded like its Feed entry. `sinceSeen` counts them too.
- **Medal:** a clear's icon by kind (`Skin.CLEAR_ICONS`), its tier epic for a dungeon, legendary for a raid (Core decides; DESIGN.md, Trophy Colours Rule), its label the instance without "The ", and its date. Gold value while fresh, as for rungs, counted from when the clear first reached this client (a clear can sync days late), while its date is the clear's own. Hover: the instance, "Cleared 3 Nov", and the party's names ("You" first).
- **Cabinet:** "DUNGEONS CLEARED n / N" and "RAIDS CLEARED n / N" (attunements left out) above "GOALS REACHED", each a grid with a slot per instance in the dungeon table's level order: the clear's medal once cleared, otherwise a greyed icon with its name and level range ("17–26"). Hover an empty slot for its name, levels and "Not cleared yet". `trophies().dungeons` and `.raids` are the grids: `{ cleared, total, slots }`.
- **See all** always shows once there's a trophy, since the cabinet holds the empty slots too: "+N" when the shelf hides some, "…" otherwise.

## Dev

- **Encounter logger:** in a dev checkout every `ENCOUNTER_END` is printed and saved in `BFF_DB.devEncounters`; `/bffdev encounters` shows it (`docs/research/boss-kills.md`).
- **Simulated clear:** the console's **Dungeon** button, or `/bffdev clear [raid]`, makes the simulated Members online clear the first dungeon (or raid) the Crew hasn't, in one party, through their own `encounterEnded()`. The sim's Cores know a made-up final boss for every instance (`finalBosses`, a `Core.new` option for tests and the sim). `/bffdev toast` includes a sample clear toast.

## Not in this

Per-boss progress for instances started but not cleared ("Halfway through"); whether kills from different runs add up is undecided. Difficulty levels, clear times, and naming strangers.
