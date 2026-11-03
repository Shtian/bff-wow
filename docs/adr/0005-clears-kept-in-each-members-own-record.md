# Clears are kept in each Member's own record, and the Crew's trophy is worked out by every client

A dungeon or raid clear has to reach Members who weren't there and weren't online. BFF already has one way to do that: each Member's own record, written only by them and gossiped by version (ADR 0001). So every Member in the clearing party records the clear in their own record (`clears`: per instance name, the first clear's time and the Member ids of every clearing party), and each client works out the Crew's clears from all the records it holds: per instance, the earliest time and everyone credited. The **trophy** is that first clear; later clears only add who's credited. Each client keeps the trophies it has seen in `db.goals.clears`, the way it keeps reached goal rungs, so one appears once, makes one Feed entry, and stays even if the records that brought it go.

## Considered Options

- **A Crew-wide "first clear" record** written by whoever cleared first: needs agreement on who was first, and a writer other than the owner. Rejected for the same reasons as Crew-wide authority in ADR 0001.
- **Recording each boss kill, not clears:** more data in every record for a feature not decided yet (whether kills from different runs add up to a clear). Only the final boss is recorded; the full boss list is in `docs/research/boss-kills.md` for later.
- **Only the party leader records it:** the leader may not run BFF, and every party member's client sees the kill anyway. Each records it; the Crew's view merges them.

## Consequences

- The record format grows by `clears`, keyed by the dungeon table's instance names (`Core/Together.lua`). Renaming an instance in the table orphans its clears, so names there are now stable keys. Older clients relay the field untouched, since a record is kept as received.
- A clear is bounded: one entry per instance, with at most the Crew's Members in it.
- Strangers in the party aren't recorded; a Member is matched by Character GUID, else by name.
- A clear recorded while the link is down (encounters lock addon messages) goes out with the next DATA once it's back up, like any own change.
- Which kill is a clear is a table of final-boss encounter IDs. Until Forever's IDs are known, most instances record nothing.
