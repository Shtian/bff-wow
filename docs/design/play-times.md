# Play times

Answers [When people play: Play times heatmap](https://github.com/Shtian/bff-wow/issues/52). Builds on owner-written records (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`) and Gossip's send timing (`docs/design/code-structure.md`). Domain vocabulary from `CONTEXT.md` (**Play times**, "usually plays").

## The idea in one line

Each client counts when in the week its own Member plays, shares a 168-character summary in their record, and the When tab turns the summaries into a heatmap in the viewer's local time.

## Collecting (own client only)

- `Core:tick()` (once a second) counts the time since the last tick as played, in the UTC hour of the week it falls in: 168 slots, weeks starting Monday 00:00 UTC, from `GetServerTime()`. A tick crossing an hour is split at the boundary, so sessions over an hour, midnight or the week's end land in the right slots.
- **No double counting:** the last time counted up to is saved with the counts. After a /reload the next tick carries on from there. A gap of more than 60 s between ticks (loading screens, logouts, a crash's lost saved data, the clock going backwards) isn't counted.
- Kept in `db.playTimes` (account-wide), so every Character adds to one set: `since` (when collecting started, set the first time BFF runs with this), `last`, and seconds per slot for the last 4 weeks. Older weeks are dropped. Raw seconds never leave the client.
- Collecting runs whenever the game does, in a Crew or not, paused or not.

## Sharing

The own record gains `playTimes = { since, week, slots }`:

- `slots` is 168 hex digits, one per UTC slot. Each digit is a bit per week the slot had at least 10 minutes: 1 for `week` (the week the summary was made in), 2 for the week before, 4 and 8 for the two before that.
- **A mask, not a count.** The brief asked for the number of weeks (0–4). The mask holds the same and lets a viewer **age** a summary: one made 2 weeks ago only has its last 2 weeks left in the viewer's 4-week window, so a Member who stopped playing fades out instead of counting for ever. It costs the same 168 characters.
- Written into the record when it may have changed: at the first Character report after login (a second write right after the Character's, so the same send carries both), when a slot reaches 10 minutes, and when a week begins. That's at most about once an hour of play.
- **Never forces a send:** it's `"later"` urgency, like XP, so it goes out with the next send or the 5-minute heartbeat.
- Shared by default; Pause sharing already silences everything. No setting.
- Validated on merge (a table with numeric `since` and `week` and 168 hex digits); a record with malformed Play times is dropped like any malformed record. Older clients ignore the field, and records from them merge and show "no data".

**Size:** encoded with the real Codec, a DATA message carrying a typical two-Character record grows by about 43 bytes with no hours played yet and about 57 bytes with a regular evening pattern (282 → 339 bytes). A pathological random pattern adds 154. DATA was already over 255 bytes and split by AceComm.

## Showing: the When tab

A fourth tab in the sidebar, under Goals, within the panel's fixed height. `/bff when` opens it. From `Core:playTimes(memberId?)`:

- **The Crew** (default): a 7 × 24 grid, Monday to Sunday, 00 to 23, each cell shaded by how many Members **usually play** then (played in at least 2 of the last 4 weeks), out of every Member your Roster shows: you, and everyone not Left, not Removed and not hidden by the 30-day rule. The count is in each cell's tooltip.
- **One Member:** picked from the "Show:" menu, or with "When does <display name> play?" on their row's right-click menu. Cells shaded by weeks played, 0 to 4.
- **Local time:** the grid is shifted from UTC by the viewer's `utcOffset`, rounded to the hour (half-hour time zones are off by 30 minutes). DST changes take effect on the next login, like the Feed's days.
- **Little data:** a Member who started collecting under a week ago shows "Collecting since <date>"; one whose BFF doesn't share Play times says so; an empty Crew view says nobody usually plays yet rather than showing a blank grid silently.
- No Feed entries, Toasts or chat lines.

## Dev

`/bff sim` gives each simulated Member four weeks of made-up Play times (their own evening hours and some weekend afternoons), so the tab has something to show.

## Not in this

The "On tonight" status, reminders, Toasts or Feed entries about play times, opt-in or opt-out, the level-overlap finder, suggesting a best time, and showing other Members' time zones.
