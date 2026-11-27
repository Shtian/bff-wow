# A Crew per ruleset and faction, each in its own slot

A player asked to use BFF with one group of friends on PvP and another on RP, without mixing them. Until now `BFF_DB` held one Crew for the whole account. But a Crew's channel only reaches Characters on the same ruleset and faction: Forever has one world per ruleset in each region, and the channel spike (#6) showed custom channels don't cross factions. So logging in a Character on another ruleset joined an empty channel, and that Character still showed up in the Crew's roster.

So each **ruleset and faction** now has its own Crew:

- **Each Crew's data lives in its own slot.** That's `BFF_DB.crews[slotId]`, which holds the code, the Member id, the records, Feed, goals, Spares, catches, channel moves, Appear offline, play times and the stray. A ruleset and faction points to its active slot from `BFF_DB.rulesets[key]`. Settings, panel and Pocket Camp positions, the minimap button and What's new state stay at the top level, because they belong to the player, not a Crew. Core gets the account table and the active slot.
- **A Member id belongs to a Crew.** Two Crews never see each other, so a shared id would give them nothing. A new id also keeps two Crews from sharing one record, and with it one set of Characters, looks and Spares. Rejoining a Crew you left brings back its slot, and so its id.
- **A Crew you left is an inactive slot.** It replaces `keptCrew`. Starting or joining a different Crew on the same ruleset and faction still deletes it, so only one left Crew is kept, as before.
- **How the key is built:**
  - On Forever, `GetRealmName()` and `GetNormalizedRealmName()` return `""`. `C_GameRules.GetCurrentGameModeRecordID()` names the ruleset: 14 is PvP, 15 Normal, 16 Roleplay, 18 Roleplay PvP. Each ruleset also has its own GUID server ID: 6856, 6939, 6944 and 6943, the same for two Characters on Normal. All of this was checked in game on 2026-11-27.
  - The key is the first of these that's available: `realm:<GetNormalizedRealmName()>:<faction>` if the name isn't empty (that's retail), otherwise `mode:<record id>:<faction>`, otherwise `default`.
  - The faction comes from `UnitFactionGroup("player")`.
  - The code checks what the game provides, never which game it is.
- **When an ID changes, BFF repairs the key.** A game-data row ID can be renumbered by a patch, and server IDs can change in a merge. So each ruleset entry also saves its record ID, its server IDs, and its name, read from your own Battle.net `richPresence` ("Forever - Normal - Stormwind City" gives "Normal"). A login whose key isn't found looks for an entry with the current server ID, then one with the current name, and moves it to the new key. The sync log notes the move. Only when nothing matches does it start a new entry.

## Moving the old data

This is BFF's first migration of saved data:

1. **Today's Crew data becomes one unplaced slot.** Placing it on whichever ruleset you log into first would be wrong whenever your first Character after the update isn't on the Crew's ruleset.
2. **A login places it** when its server ID is among those of the other Members' Characters, since your friends are where the Crew is. If you're alone in the Crew, your Main's server ID is used instead.
3. **Old records have no faction**, so placing it by server ID is **provisional** until BFF hears another Member through it. While it's provisional, the no-Crew card on the other faction of that ruleset offers "Bring your Crew here". When this login's server ID doesn't match, the no-Crew card says where the Crew is. Only when BFF can't place it for you does it ask once whether this is where the Crew is: when it has no server ID to go by (no other Member's Characters and no Main), or when none of your own Characters is on any of them (your friends moved, or a merge changed the server ID).
4. **When it's placed, your Characters from other rulesets are dropped** from your own record, by server ID. At every login, the current Character is removed from any other slot's own record. That's how Characters of the other faction leave it: playing a Character shows where it belongs.
5. **The old top-level keys stay for a few releases**, so a player who goes back to an older BFF still finds their Crew. A later release deletes them.

## Considered Options

- **Key by realm name:** returns `""` on Forever.
- **Key only by server ID or only by the ruleset name:** a merge can change a server ID, and the name is in the client's language, so each one alone is fragile. Both are kept, but only for repairing the key.
- **Our own table of record IDs to ruleset names:** has to be updated for Hardcore and any new ruleset. The name read from `richPresence` works for rulesets we haven't seen.
- **Split all of `BFF_DB` per ruleset:** least code, but settings, positions and What's new would reset on each ruleset.
- **One table per ruleset instead of per Crew:** fixes "one Crew per ruleset" in place, so allowing several Crews (#317) would take a second migration. With slots, #317 only needs to change how the active slot is chosen.
- **Place the old data by your own Characters' server IDs:** a player whose Crew is on PvP and who logs an RP alt first would give it to RP.

## Consequences

- **The protocol doesn't change.** The channel, messages and records are as before. Mixed versions in one Crew work: an existing Crew keeps its Member ids, and a record that drops Characters wins by version on older clients too. Older clients just don't split by ruleset.
- **A player in two Crews is two Members**, each with its own display name and id.
- **Retail realms work the same way**, but connected realms haven't been tested.
- **A faction change through the paid service, or a Hardcore Character moving to another ruleset**, lands in a different key, the same as playing on another ruleset.
- **Until the old top-level keys are deleted**, the saved file holds two copies of the Crew data.
