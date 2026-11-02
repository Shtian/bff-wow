# Professions

Answers [Professions: records, Professions tab and tooltip](https://github.com/Shtian/bff-wow/issues/98), part of [#97](https://github.com/Shtian/bff-wow/issues/97). Builds on owner-written records (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`) and Gossip's send timing (`docs/design/code-structure.md`). Domain vocabulary from `CONTEXT.md` (**Profession**). The placement was picked from the prototype on branch `prototype/professions` (`prototypes/professions.html`): variant B's grid as a tab, variant A's tooltip lines.

## The idea in one line

Each Character's own client shares its professions and skill in its record, like gold, and the panel shows them in a Professions tab and the Character tooltip.

## Reading (own client only)

- Snapshot reads them with `GetProfessions()` (five slots: two main professions, then first aid, fishing and cooking) and `GetProfessionInfo(index)`, on `PLAYER_ENTERING_WORLD` and `SKILL_LINES_CHANGED`. Other Snapshot events send the last list read.
- The reading itself is `Professions.read(api, last)` in Core, handed the two functions and `issecretvalue`, so offline tests can fake the game. A value that reads secret, a value a record couldn't store (such as a max skill of 0), or a read that errors (pcall, as `Snapshot.locate` does), keeps the last good list: it costs the professions, never the send. Before the first good read of a session Snapshot reports none (nil), and the Ledger keeps the list the record already has, so a /reload into a secret read doesn't wipe them.
- Each profession: skill line ID, name (as the owner's client words it, so other locales don't need the profession themselves), icon file ID, the base skill (the API's `rank`) and max skill, and whether it's a secondary profession (slots 3 to 5). `rankModifier`, the bonus from gear and racials, isn't sent or shown.

## Sharing

- A per-Character field `professions` in the record: a list of up to 5 `{ id, n, i, k, m, s }` (skill line ID, name, icon, skill, max skill, `s = true` for a secondary). Short names, since it rides every DATA. An empty list means the Character has none; no field means its client never shared them.
- **"Later" urgency**, like gold and XP: a professions-only change waits for the next send or the 5-minute heartbeat. Reading the same list again isn't a change.
- **Shape check:** a malformed list (not a list, more than 5 entries, or any entry with a missing or wrong field) is ignored for that Character, which then shows as unknown. The record itself isn't checked for it, so the rest is kept, and the list is relayed unchanged, as older clients relay a field they don't know.
- A professions-only change that crosses a milestone, or picks up a profession, makes a Feed entry and goes out right away instead (#99, see Feed entries below).

## Reads

- `rows()`: each Character carries `professions`, nil when unknown, else a list of `{ skillLine, name, icon, skill, max, secondary, rank, full, capped }`, main professions first (in the owner's order), then cooking, fishing, first aid. `rank` comes from the max skill: 75 Apprentice, 150 Journeyman, 225 Expert, 300 Artisan (Forever caps professions at 300, #97). `full` is skill at the max skill; `capped` is skill at 300.
- `professions(order?, sortBy?)`: the Professions tab. `professions` is all twelve, main ones by name, then cooking, fishing and first aid, plus any other a shown Character has, after its kind; `had` says whether any shown Character has it. `members` is a row per Member the Roster shows (so not Left, Removed or unseen for 30 days): yours first, then the others in the Roster's `order`, or by best skill in the profession with skill line `sortBy` (yours still first, ties in the Roster's order). Each has `cells`, one per profession: false for none, or the best skill among the Member's Characters (skill, max, rank, full, capped) and `characters`, each Character who has it, best first. `known` is false for a Member none of whose clients ever shared professions.

## Showing

**Professions tab:** a sidebar tab after Spares, `/bff professions` opens it, within the panel's fixed height. A grid: column headers are the twelve profession icons, always all twelve (cooking, fishing and first aid after a hairline), desaturated at 55% when nobody has one; the rows below scroll, one per Member (people, not Characters), labelled with the display name. Each cell is an 18px tile with the Member's best skill in it, shaded by rank in neutral washes (a lighter plate at 300; no gold, which is for news), and a 2px skill/max bar under it; none is a faint empty tile, so the grid reads even where it's sparse. Hovering a tile washes its row and column and lists each of the Member's Characters who have it, in class colour, with rank and skill/max. Clicking an icon sorts the Members by that profession, yours staying first; clicking it again goes back to the Roster's order. A Member whose clients never shared professions shows "Not shared yet". Picked from the prototype on branch `prototype/professions-grid` (`prototypes/professions-grid.html`); a row per Character and a row per profession were tried first and were harder to scan.

**Tooltip:** under the Gold line, one line per profession: icon, name and rank, then "skill/max", gold at 300/300. No lines when unknown.

## Feed entries

From [#99](https://github.com/Shtian/bff-wow/issues/99), following `docs/design/feed.md`: `Professions.news(before, after)` compares a Character's stored lists, and Feed makes, for every profession, main and secondary, on Mains and Alts alike:

- **new profession**, "Simone picked up Tailoring", for a profession the Character didn't have.
- **profession skill**, "Simone reached 225 Alchemy", when the base skill reaches 75, 150 or 225. Skipped versions collapse to the highest milestone crossed, with `from` the skill before.
- **profession maxed**, "Simone maxed Alchemy", in gold, at 300 (it replaces the milestone).

Alts are named the usual way ("Simone's Alt Simmy picked up Tailoring"). An unknown or malformed list on either side makes nothing, so the first share and a new Character are silent; so are drops and unlearning. Own entries are marked seen. Each takes a **Cheer**, keyed by owner, Character, kind, skill line and, for a milestone, the milestone reached (ADR 0002); a collapsed milestone entry matches every milestone in its range. The owner sees "Bob cheered your 225 Alchemy", "cheered you picking up Tailoring", "cheered you maxing Alchemy".

Entries carry the profession's `icon` (file ID), which the Feed tab and toasts draw instead of the kind's picture, edged in amber (gold when maxed). While you were away lists them under **Professions**, a line each with the icon and a Cheer, rather than on the scoreboard.

## Crew goals

Three Crew goal tracks are worked out from the professions in records ([#100](https://github.com/Shtian/bff-wow/issues/100)): Every profession in the Crew, Crew skill and Everyone a Journeyman. See `docs/design/goals.md`.

## Dev

`/bff sim` gives the simulated Members some professions; Simba's client "never shared" any. The console's **Skill** button steps a Member's first profession short of 300 to its next milestone, or picks up Tailoring. `/bffdev toast` includes the three profession kinds.

## Not in this

Recipes (only readable while the profession window is open, and big), specialisations, and the skill bonus from gear and racials.
