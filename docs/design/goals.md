# Crew goals

Answers [Crew goals: built-in goal tracks, a Goals tab and a Feed entry when reached](https://github.com/Shtian/bff-wow/issues/51). Builds on the Feed (`docs/design/feed.md`) and toasts (`docs/design/toasts.md`). Domain vocabulary from `CONTEXT.md` (**Crew goal**, **Crew levels**).

## The idea in one line

Each client works out three built-in goal tracks from the Member records it already holds, remembers which rungs it has seen reached, and adds one Crew-wide Feed entry when a new rung is reached. No record fields, no sync change.

## Tracks and rungs

| Track | Progress | Rungs |
|---|---|---|
| **Crew levels** | Each Member's highest Character level, summed. Alts don't add to it. | 50, 100, 150, … for ever |
| **Everyone at level N** | Reached when every Member has a Character at N or above (the lowest of the Members' highest levels). | 10, 20, 30, … then max level itself, and the track is complete |
| **Crew deaths** | Deaths over every Character of every Member, summed. | 25, 50, 100, 250, 500, 1000, 2500, … |

**Who counts:** every Member your Roster could show: you, and everyone held who hasn't Left. Removed Members aren't held, so they don't count; Remove is local, so progress is per client. A Member with no Characters yet doesn't count. All-time, from the records as they are.

**No ranking.** Nothing names or credits a Member: no per-Member numbers, no top contributor.

## Reaching a rung

- Core checks the tracks whenever a record changes: your own Character, DATA from others, and Remove.
- Reached rungs are kept in `db.goals` (account-wide) with when they were reached. A reached rung **stays reached** even if progress drops (a level-1 Member joins, someone is Removed); the track just moves on to the rung above the highest reached.
- A newly reached rung makes **one Crew-wide Feed entry**, kind `goal`, with no Member: "The Crew reached 300 Crew levels!", "Everyone in the Crew has a Character at 20!" ("… at max level!" for the last rung), "The Crew has died 100 times together!". It's highlighted in gold like max level and joined, has no Reaction, and goes the usual ways: chat line, toast (same sound and settings), or While you were away when it arrives while settling or with both off.
- Several rungs crossed at once (after being away) are each recorded, but make **one entry per track**, for the highest.
- **Only progress is news.** A rung reached because *who counts* changed (a Member first seen after the baseline, one Leaving or coming back, or one you Remove) is recorded quietly, with no entry. Like the Feed's first sight of a Member, a new Member's levels aren't something the Crew did together, and a toast celebrating someone leaving would read wrong.

### Silent baseline

The first time a client has goals in a Crew (this feature's first run, or after joining a Crew), the rungs already passed are recorded as reached, with no Feed entry or toast. Like the first sight of a Member in the Feed.

The baseline is taken once, **when the first sync has settled** (the Feed's rule: 10 s with no new DATA, or 30 s after the link came up; `Core/Settle.lua`). Until then nothing is recorded: right after joining, only part of the Crew's records may have arrived, and Everyone at level N would look reached when it isn't. The Goals tab shows nothing reached until then.

**Leaving the Crew**, or starting or joining one, clears `db.goals`, so a new Crew gets its own baseline.

## Goals tab

A third tab in the panel's sidebar, under Roster and Feed, within the panel's fixed height. `/bff goals` opens it. One row per track, from `Core:goals()`:

- The track's name: "Crew levels", "Everyone at level 30", "Crew deaths".
- Progress numbers and a bar towards the next rung: "212 / 250". Everyone at level N counts Members: "3 / 5 Members" have a Character at the next rung. That count, not the lowest level, so no Member's own level shows.
- The last rung reached and when: "Reached 200 on 14 Oct", or "Not reached yet".
- Everyone at level N, once max level is reached, shows "Complete" and a full gold bar.

## In Core

- **Goals** (`Core/Goals.lua`): the ladders, progress from a list of records, the saved reached rungs, the baseline and the tab's rows. Pure; tested through Core and directly for the ladders.
- **Feed** turns reached rungs into `goal` entries (`Feed:goalsReached`), and While you were away lists them on their own as `summary.goals` (`{ text, time }`, newest first), shown under "Crew goals" in gold.
- **Core:** `goals()` for the tab. `feedEntry` and `awaySummary` carry goal entries as they do others.

## Dev

The `/bffdev` console's **Goal** button makes the first simulated Member online die as often as the Crew needs to reach the next Crew deaths rung. `/bffdev toast` includes a sample goal toast.

## Not in this

Custom or Member-proposed goals, deadlines, Competitions or any ranking, a goal strip on the Roster, and tracks needing data not in records (gold, zones, play time).
