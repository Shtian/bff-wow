---
target: the Catches prototype
total_score: 23
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:/Users/shtian/.t3/worktrees/bff-wow/t3-72679e79/prototypes/catches.html"
target_fingerprint: "sha256:3585281e0cf8a6abd2b7611c52df802a1296937d79e3482702767cf3528da458"
target_path: /Users/shtian/.t3/worktrees/bff-wow/t3-72679e79/prototypes/catches.html
timestamp: 2026-11-07T08-48-06Z
slug: prototypes-catches-html
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Count, bar and next trophy are clear; "+8 new types since you left" really means "last 3 days" and includes your own catches |
| 2 | Match System / Real World | 2 | "30–45" reads as "I can fish here", but fishing is gated by skill; "Cold and deep", "Far coasts" aren't names players know |
| 3 | User Control and Freedom | 3 | Pickers undo easily, Esc closes, checkbox keeps menu open like the game's |
| 4 | Consistency and Standards | 2 | Every first catch is gold (a ding isn't); quality colours outside Goals; "You" in class colour |
| 5 | Error Prevention | 2 | "All types" counts seasonal, Sunday-only and unconfirmed types; rungs [10,25,50,total] break when total changes (50 then 52) |
| 6 | Recognition Rather Than Recall | 2 | With names off, every uncaught tile is an identical "?"; hover is the only way to tell them apart |
| 7 | Flexibility and Efficiency | 2 | No "missing in waters I can fish", no "my catches" |
| 8 | Aesthetic and Minimalist Design | 2 | Bright green edges on uncaught bloated tiles are the loudest thing in the grid; one fish fills up to 3 tiles |
| 9 | Error Recovery | 2 | Empty filter always says "The Crew has caught every type", wrong for Show: Treasure with unconfirmed hidden |
| 10 | Help and Documentation | 3 | Tooltip notes ("Summer only", "Needs lockpicking", "Try: …") and the names hint are good |
| **Total** | | **23/40** | **Acceptable** |

## Design Specificity Verdict
LLM: authored for BFF. Where-to-fish bands with zone lines turn the collection into a plan; "First caught by Mira" ties it to people; Feed, toast, Goals track and While you were away reuse existing patterns. Drift: the grid itself shows only items (people appear on hover only), and two colour systems (Ember Gold, item quality) are used beyond the scope DESIGN.md gives them.
Deterministic scan: file scan 25 findings (2 cramped-padding, 2 design-system-font, 21 design-system value advisories); URL scan 37 (36 low-contrast, 1 tight-leading). Nearly all false positives: the low-contrast hits are the hidden icon fallback letter; fonts, class colours, 1.25 leading and flush header mirror the game; pill bar and page gradient are prototype chrome. Real but minor: literal colours (#222, #556, menu rgba) DESIGN.md could absorb as tokens.
Overlays: not available (no Playwright/Puppeteer for injection).

## Priority Issues
1. [P1] Every first catch is gold news (One Ember Rule). Fix: catch entries in normal text with a kind-coloured icon edge like dings; gold only for trophy rungs (and maybe Nat Pagle/rare first catches); Fresh strip in normal text; no Feed entries for unlisted junk. Command: quieter.
2. [P1] "All types" can't be reached; denominator too big. Fix: count only confirmed, any-time types (~35–45); seasonal, Sunday and unconfirmed as extras outside the denominator; fixed rungs independent of the total. Command: shape.
3. [P2] Duplicate tiles across waters and level-labelled bands. Fix: each fish once, in its lowest band, other waters in the tooltip; label bands as zone level or derive "you can fish here" from skill. Command: layout.
4. [P2] Quality colours outside Goals (Trophy Colours Rule; raw #0070dd, not DESIGN's #3a9bff); green edges on empty tiles read as selection. Fix: add a scoped rule to DESIGN.md or drop the edges; quality only on caught tiles at the faded feed-picture edge; uncaught tiles uniformly faint. Command: colorize/quieter.
5. [P3] Copy for non-native speakers: "fished up", "what bites here", "Sells by the pound", "not charted", "Special catches", "Extravaganza", "Bloated". "You" should be Ash. Command: clarify.

## Persona Red Flags
Alex: no "missing and fishable at my skill" filter; totals uncheckable with duplicate tiles; per-Member counts only in tooltip.
Sam: fresh mark is a 5px gold square (invisible on yellow icons); unconfirmed is a 12% dashed outline; "?" at 18% white; hover-only details; 28px tiles 4px apart.
Casual Member (twice a week): own catches shown as news; "since you left" is really 3 days; first view is a wall of "?"; friends' story is three lines at the bottom.

## Minor Observations
Title "Catches" repeats the tab; summary + pickers ~95px, at min size only ~145px of grid and Fresh truncates. Two trophy lines in the same dim style say different things. Group picker uses the Sort icon. Context medals coloured by position, not by rungs reached. Cheer is a text button, not the icon Reaction. No true zero state; no celebration when everything is caught; New on Forever hides under Not caught yet. Show menu has 7 items, and "Not caught yet" sits next to "Show names of fish not caught yet".

## Questions to Consider
- Should Catches be a Goals track with a field-guide view instead of a 9th tab?
- What if each caught tile showed who caught it (a class-coloured corner), so the grid reads as friends, not inventory?
- Should everyday first catches be news at all, or only rungs and rare finds?
