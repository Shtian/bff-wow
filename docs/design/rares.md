# Rares

Answers [Rare kills: a Trophy for each Rare the Crew slays, and a Rares slain track](https://github.com/Shtian/bff-wow/issues/190). Builds on Clears (`docs/design/trophies.md`), Catches (`docs/design/catches.md`) and owner-written records (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`, `docs/adr/0005-clears-kept-in-each-members-own-record.md`). Domain vocabulary from `CONTEXT.md` (**Rare**, **Rare kill**, **Unlisted rare**, **Trophy**). The list and the API findings come from `docs/research/rare-mobs.md`.

## The idea in one line

Each Member's own client records their first Rare kill of each Rare in their record. Every client works out the Crew's Rare kills from the records it holds, the earliest per Rare, and keeps each as a Trophy, like a Clear.

## The list (data)

`Core/Rares.lua` ships the list as data, keyed by NPC ID: `Rares.LIST`, each `{ id, name, zone, level, elite }`, in level order (`index` is the place in it). A new Rare is one row.

- The research note's shortlist: 30 rows, from Snapbeak the Quick (Zephras Isle, 9) to Pexmit (Mount Hyjal, 60). The note calls it 29 picks, but its table has 30; all 30 ship.
- Only mobs the game classifies as rare (`rare` or `rareelite`). Famous elites aren't on it: Mor'Ladim, Gazz'uz, and Mother Fang, who is Elite on Forever.
- `elite` marks a rare elite. Levels and classifications are Wowhead Forever's, read 2026-11-13; the in-game check will correct the list (research section 5).

## Detecting a kill (own client only)

`Rares.watch(api)` tells a kill from three signals. Snapshot hands it the game's reads (`UnitGUID`, `UnitName`, `UnitClassification`, `UnitIsDead`, `UnitIsTapDenied`, `GetNumLootItems`, `GetLootSourceInfo`, the zone, subzone and map, and `issecretvalue`); offline tests hand it a fake. Every read is guarded: a value that reads secret, or a read that errors, finds nothing. It costs that kill, never an error.

The NPC ID comes from the GUID (`Creature-0-[server]-[instance]-[zone]-[npc]-[spawn]`). Forever obfuscates the server and spawn parts per client, so GUIDs are never compared across Members.

1. **Loot (main).** On `LOOT_READY`, once per loot window (until `LOOT_CLOSED`), each slot's sources from `GetLootSourceInfo`. A listed Rare among them is a kill. Looting a corpse means your group had the tag.
2. **Target died.** The watch remembers units it sees while their identity can be read (`PLAYER_TARGET_CHANGED` for the target, `UPDATE_MOUSEOVER_UNIT`, `NAME_PLATE_UNIT_ADDED`): listed Rares and anything the game calls rare, by GUID (up to 100, then it starts over). The target is remembered apart, until the next target change. On `PLAYER_TARGET_DIED`, and again on `PLAYER_REGEN_ENABLED`, the target is read again; if its GUID reads secret (in combat), the remembered target stands in. It's a kill when it's dead and `UnitIsTapDenied` is false: nobody outside the group tagged it. Either reading secret is no kill.
3. **`PARTY_KILL`.** A kill when its target GUID can be read. The research expects it to be secret for an NPC; it costs nothing to listen.

**Unlisted rares:** a creature not on the list counts as one when the game classifies it as rare: read off a dead target, or from a unit seen while readable (for loot and `PARTY_KILL`, which don't say). Its name goes with it.

## Saving

`core:rareKilled(kill)` writes the kill into the own record, inside a Crew or not (a Character must have been reported), as catches are:

- A Member-level field `rares`: `{ [npcId] = { t, z, s, m, c, n } }`. `t` is the first kill's time, `z`, `s` and `m` its zone, subzone and map ID, `c` the GUID of the Character who made it, and `n` an unlisted rare's name. Only the first kill of each is kept. No party list: only the Member whose client saw the kill is credited.
- **Unlisted rares** are kept the same way, under their NPC ID, so the list can grow: once a later release lists the Rare, the same entry counts. At most `Rares.UNLISTED_CAP` (50); a new one past it is dropped, while listed Rares still go in.
- A listed Rare's kill goes out **now**, as a Clear does (it waits while the link is down). An unlisted one rides the next send.

## Sharing and the shape check

The field travels with the rest of the record; the record itself isn't checked for it, so a malformed field costs only the Rare kills, and older clients relay it unchanged. When the Crew's Rare kills are worked out, a field that isn't a table, or has more than 200 entries, is ignored, and so is each entry whose key isn't a whole NPC ID or that isn't `{ t (number), z, s, c, n (text, optional), m (whole number, optional) }`. Past `UNLISTED_CAP` unlisted rares in one record, the later ones are skipped.

## The Crew's Rare kills

`Rares.collect(records)` over every Member held who hasn't left, you included: per listed Rare, the earliest kill (ties to the lower Member id), with its Member and Character. Never matched by GUID.

`Goals` keeps them beside the clears, in `db.goals.rareKills[npcId]`: `time`, `memberId`, `character`, `quiet` and `seen`. On every check:

- A Rare not yet kept is a **new Crew trophy**: one Crew-wide `goal` Feed entry naming whose kill it was, "Ana slew Rak'shiri!" ("You slew Rak'shiri!" for your own), announced like a goal's (toast, chat line, While you were away under Crew goals).
- One already kept only moves to an earlier kill, if a record brings one, and credits its Member. No news.
- **Quiet**, as for clears: kills passed at the silent baseline, or first seen in a Member's record when you first see that Member, are kept without news and are never fresh.

## Rares slain, a Crew goal track

The listed Rares anyone in the Crew has slain. Steps at 5, 10, 20 and every Rare (`Rares.STEPS`), then it's complete. Several steps crossed at once make one entry for the highest ("The Crew has slain 10 Rares!", "The Crew has slain every Rare!"). Its medals read "5 Rares" and "Every Rare". A client whose baseline predates the track passes the rungs already reached quietly (the late baseline, `docs/design/goals.md`). Unlisted rares never count.

## On the Trophies tab

No new sidebar tab. `trophies()` gains Rare kills:

- **Shelf and latest win:** they join the other trophies, newest first by the kill's time, worded like the Feed entry.
- **Medal:** a claw icon (`Skin.RARE_ICON`), its tier rare for a rare and epic for a rare elite (DESIGN.md, Trophy Colours Rule), its label the Rare's name. Gold while fresh, counted from when it reached this client. Hover: the name, "Level 57 Rare · Winterspring", "Slain 3 Nov" and "By Ana (Anabelle)".
- **Cabinet:** "RARES SLAIN n / N" after the dungeons and raids, a slot per Rare in level order: its medal once slain, otherwise greyed with its name and level. Hover an empty slot for its name, level and zone and "Not slain yet". `trophies().rares` is the grid: `{ slain, total, slots }`.
- **Working on:** a Rares slain tile, as for every track.

## Dev

- **Rare logger:** in a dev checkout, every read that could tell a Rare kill (loot, the target dying, `PARTY_KILL`, and a unit seen when it's rare, or the target when its identity reads secret) is printed, shown in the console's log and saved in `BFF_DB.devRares` (the newest 300): the values read, which were secret, what the watch made of them and what Core did with each kill. `/bffdev rares` shows the last few; `/bffdev rares clear` empties it. It answers the research note's section 5, starting with whether the loot source GUID is readable.
- **Simulated kill:** the console's **Rare** button, or `/bffdev rare`, makes an online simulated Member slay the first Rare the Crew hasn't, through their own `rareKilled()`. `/bffdev toast` includes a sample.

## Not in this

How many times a Rare was killed, who else was in the party, and respawn timers.
