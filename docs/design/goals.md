# Crew goals

Answers [Crew goals: built-in goal tracks, a Goals tab and a Feed entry when reached](https://github.com/Shtian/bff-wow/issues/51), with the profession tracks from [#100](https://github.com/Shtian/bff-wow/issues/100). Builds on the Feed (`docs/design/feed.md`) and toasts (`docs/design/toasts.md`). Domain vocabulary from `CONTEXT.md` (**Crew goal**, **Crew levels**).

## The idea in one line

Each client works out six built-in goal tracks from the Member records it already holds, remembers which rungs it has seen reached, and adds one Crew-wide Feed entry when a new rung is reached. No record fields, no sync change.

## Tracks and rungs

| Track | Progress | Rungs |
|---|---|---|
| **Crew levels** | Each Member's highest Character level, summed. Alts don't add to it. | 50, 100, 150, … for ever |
| **Everyone at level N** | Reached when every Member has a Character at N or above (the lowest of the Members' highest levels). | 10, 20, 30, … then max level itself, and the track is complete |
| **Crew deaths** | Deaths over every Character of every Member, summed. | 25, 50, 100, 250, 500, 1000, 2500, … |
| **Every profession in the Crew** | Which of the twelve professions (the nine main ones, cooking, fishing, first aid) at least one Character has, by skill line. | each profession, complete when all twelve are reached |
| **Crew skill** | Base skill over every profession of every Character, summed. | 500, 1000, 2500, 5000, 10000, … for ever |
| **Everyone a Journeyman** | Like Everyone at level N: the lowest, over Members, of each Member's best base skill in any profession on any Character. | 75 Apprentice, 150 Journeyman, 225 Expert, then 300 Artisan, and the track is complete |

The profession tracks count Alts and every profession. A Character whose professions are unknown (its client never shared them) adds nothing, so a Member none of whose professions are known has a best of 0: Everyone a Journeyman waits for them rather than being reached by whoever shared first.

**Who counts:** every Member your Roster could show: you, and everyone held who hasn't Left. Removed Members aren't held, so they don't count; Remove is local, so progress is per client. A Member with no Characters yet doesn't count. All-time, from the records as they are.

**No ranking.** Nothing names or credits a Member: no per-Member numbers, no top contributor.

## Reaching a rung

- Core checks the tracks whenever a record changes: your own Character, DATA from others, and Remove.
- Reached rungs are kept in `db.goals` (account-wide) with when they were reached. A reached rung **stays reached** even if progress drops (a level-1 Member joins, someone is Removed); the track just moves on to the rung above the highest reached.
- A newly reached rung makes **one Crew-wide Feed entry**, kind `goal`, with no Member: "The Crew reached 300 Crew levels!", "Everyone in the Crew has a Character at 20!" ("… at max level!" for the last rung), "The Crew has died 100 times together!", "The Crew has an Engineer now!" ("… has every profession!" for the twelfth), "The Crew has 2,500 profession skill together!", "Everyone in the Crew is a Journeyman at something!". It's highlighted in gold like max level and joined, has no Reaction, and goes the usual ways: chat line, toast (same sound and settings), or While you were away when it arrives while settling or with both off.
- Several rungs crossed at once (after being away) are each recorded, but make **one entry per track**, for the highest. For Every profession, the entry names each profession newly had: "The Crew has an Engineer, a Cook and a First Aider now!".
- **Only progress is news.** A rung reached because *who counts* changed (a Member first seen after the baseline, one Leaving or coming back, one you Remove, or a Character's professions first known: a first share or a new Character) is recorded quietly, with no entry. Like the Feed's first sight of a Member, a new Member's levels aren't something the Crew did together, and a toast celebrating someone leaving would read wrong.

### Silent baseline

The first time a client has goals in a Crew (this feature's first run, or after joining a Crew), the rungs already passed are recorded as reached, with no Feed entry or toast. Like the first sight of a Member in the Feed.

The baseline is taken once, **when the first sync has settled** (the Feed's rule: 10 s with no new DATA, or 30 s after the link came up; `Core/Settle.lua`). Until then nothing is recorded: right after joining, only part of the Crew's records may have arrived, and Everyone at level N would look reached when it isn't. The Goals tab shows nothing reached until then.

**Leaving the Crew**, or starting or joining one, clears `db.goals`, so a new Crew gets its own baseline.

## Goals tab

A third tab in the panel's sidebar, under Roster and Feed, drawn by `UI/GoalsTab.lua`. It scrolls within the panel's fixed height. `/bff goals` opens it. A **trophy cabinet** ([#119](https://github.com/Shtian/bff-wow/issues/119)): every rung reached stays visible, as a medal. Top to bottom:

- **Latest win:** the newest trophy in an Ember Gold framed plate, worded like its Feed entry ("The Crew reached 150 Crew levels!"), its date, and how many other rungs were reached since you last opened the tab: "3 Nov · 2 more since you last looked". Nothing is counted the first time.
- **Trophy shelf:** every reached rung as a medal, newest first: the track's icon (the profession's own for Every profession in the Crew), its value ("150", "Journeyman", "Engineering") and date. The newest 7 show, then a **See all** tile with how many more. Medals wrap to a second line in a narrow panel rather than scroll sideways. Hover shows the track, the value and the date.
- **Working on:** a tile per track, in the order below: its icon, name, big progress numbers ("212 / 250", "3 / 5 Members" for the Everyone tracks: a count, so no Member's own level shows), a bar towards the next rung, and "2 reached · last 3 Nov" or "Not reached yet". Two columns, one below 400px of content (the panel's minimum, 460×380). Everyone at level N once max level is reached, Everyone a Journeyman at 300 and Every profession with all twelve show "Complete" and a full gold bar. Every profession's tile names the professions nobody has yet on hover.
- **Trophy cabinet**, opened from See all in the same tab, with a Back button: "Goals reached N", then each track that has reached rungs, its medals oldest first, so a track reads as a progression. Leaving the tab closes it.

Track names: "Crew levels", "Everyone at level 30" (the next rung; "Everyone at a level" in the cabinet), "Crew deaths", "Every profession in the Crew", "Crew skill", "Everyone a Journeyman" (the next rank; "Everyone at a rank" in the cabinet).

**Empty state.** Before the silent baseline has settled, the tab shows "Counting up the Crew" where the latest win and shelf would be; with it settled and nothing reached, "No trophies yet". Working on shows either way.

**Colour** (DESIGN.md, the Trophy Colours Rule): track hues reuse the Feed kinds (green for Crew levels and Everyone at level N, red for Crew deaths, violet for the profession tracks) on the track icon's edge and the bar. A medal's tier is WoW's item quality by how many rungs its track has reached: 1st–2nd uncommon, 3rd–4th rare, 5th–6th epic, 7th on legendary; Every profession's are all rare. Gold stays news: the latest-win plate, and the value of a rung reached in the last 3 days (**fresh**).

## In Core

- **Goals** (`Core/Goals.lua`): the ladders, progress from a list of records, the saved reached rungs, the baseline and the tab's rows. Pure; tested through Core and directly for the ladders.
- **Feed** turns reached rungs into `goal` entries (`Feed:goalsReached`), and While you were away lists them on their own as `summary.goals` (`{ text, time }`, newest first), shown under "Crew goals" in gold.
- **Core:** `goals()` for the Working on tiles: a row per track, with `reached` (how many rungs it has) and `last.date` ("3 Nov"). `trophies()` for the rest: `{ settled, count, shelf (newest first), cabinet ({ track, title, trophies } per track with any, oldest first), latest, sinceSeen }`, a trophy being `{ track, title, rung, label, text (its Feed entry's), time, date, quality, fresh, icon }`. Core decides each trophy's quality and whether it's fresh; Skin maps them to colours. `openGoals()` on every draw of the tab and `leaveGoals()` when it's left make a **Goals visit**, like the Feed's: `sinceSeen` counts from the tab's previous opening through the visit. When the tab was last opened is kept in `db.goals.seen`, so a new Crew starts again. `feedEntry` and `awaySummary` carry goal entries as they do others.

## Dev

The `/bffdev` console's **Goal** button makes the first simulated Member online die as often as the Crew needs to reach the next Crew deaths rung. `/bffdev toast` includes a sample goal toast.

## Not in this

Custom or Member-proposed goals, deadlines, Competitions or any ranking, a goal strip on the Roster, and tracks needing data not in records (gold, zones, play time).
