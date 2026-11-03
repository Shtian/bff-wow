# Together

Answers [Together tab: friends and dungeons on a level line](https://github.com/Shtian/bff-wow/issues/111), part of [Overlap finder](https://github.com/Shtian/bff-wow/issues/110), the level-overlap finder #1 left for v2. Domain vocabulary from `CONTEXT.md` (**Together**, **Can play**, **Fits**). The look was picked from the prototype on branch `prototype/overlap-finder` (`prototypes/overlap-finder.html`, variant A, round 2).

## The idea in one line

A **Together** tab answers "who can I play with, and where?": the Crew's Characters and the game's dungeons sit on one 1–60 level line, with an answer line on top that says it in words.

## Rules

- **Can play** stays the Roster's rule: within 3 levels (`Core.CAN_PLAY_LEVELS`) of the Character you play.
- **Fits** is separate: a Character fits a dungeon when its level is inside the dungeon's range. A friend can fit a dungeon you fit and still be too far from you to play together, and tooltips say so ("fits, but 5 levels from you").
- **People, not Characters.** Counts and names are per Member; Alts belong to their person. A Member counts once, through their Character closest to your level, so two Characters of one Member within 3 levels count once, and an Alt is named "Simbad (alt)".
- **Who shows on the line:** every other Member's Main and the Character they're playing, offline friends included; your own Character being played. Other Alts are hidden, and the toolbar says how many ("3 alts hidden"). Characters the Roster hides (Left, Removed, unseen for 30 days) never show.
- **Which Characters count:** every Character the Roster shows, Alts included, so a hidden Alt still makes its Member fit a dungeon or count as able to play.
- **Dungeons shown:** every dungeon and the Onyxia attunement. Raids are hidden. The Show menu (#112) will make these, and the friends filters, choices; until then they are fixed.

## Dungeon table

`Core.DUNGEONS`, in `Core/Together.lua`: a name, `from` and `to` levels, `kind` (`dungeon`, `attunement` or `raid`), `new` (new in WoW: Forever), `where`, and a raid's `size`.

- The classic dungeons with their usual recommended ranges. These are rough and should be checked against Forever's own dungeon finder once it's live.
- The nine new Forever dungeons, from Blizzard's [Explore the New Dungeons of World of Warcraft: Forever](http://worldofwarcraft.blizzard.com/en-us/news/24301455) (Oct 20 2026): Hall of Thanes 13–18, Ruins of Lordaeron 15–20, Excavation Site 24–29, City of Dalaran 28–33 (needs an attunement), The Drowned City 35–40, Krol'dok Stronghold 40–45, Alcaz Prison 48–53, Blackmaw Hold 55–60, Shaper's Terrace 58–60.
- The Onyxia attunement, 55–60.
- Raids at 60: Molten Core, Onyxia's Lair, Zul'Gurub, and the two new Forever raids The Barrow Deeps (10-player) and Hyjal Summit (20-player). Their levels aren't published; 60 is assumed.

## Core's read

`together(measure)` returns the whole tab ready to lay out, or nil before you play a Character (see `Core:together` for every field). Core places everything, so the UI shows no state it worked out itself:

- **Geometry** is `Core.TOGETHER_LAYOUT`: 24px per level, 16px before level 1 and 90px after 60, 4 label rows and 5 dungeon lanes. Positions are pixels from the track's left edge. `measure(text, font)` is the UI's text width in Skin's `small` or `tiny` font; offline tests leave it out and widths are estimated from the length.
- **Groups:** the Characters shown, one group per level. Its Characters are ordered you first, then whoever is online, then Mains, and the first leads the label ("You", or the Member's name, with `alt` when it isn't their Main) with "+N" for the rest.
- **Label rows:** labels are placed you first, then groups with someone online, then nearest your level, each in the first of the 4 rows (row 1 nearest the axis) where it keeps 6px from its neighbours. A label that finds no room has `row` nil: only its dot shows, with a count when merged.
- **Bars:** one per dungeon shown, from its first level, as wide as its range or its content (name, NEW plate, up to 4 Member dots and "+N"), whichever is wider. Each other Member who fits it is listed once, through their Character closest to your level, online first. They're placed most relevant first (ones you fit, then by how many Members fit, then by level) in the first of the 5 lanes with room, 3px apart.
- **Chips:** bars with no room are grouped by level (within 3 levels of a group's first) into "+N here" chips, each placed in the first room at or right of its level, lowest lane first. A chip that finds no room joins the one before.
- **Answer line:** two lines, each a list of `{ text, style }`, style `text`, `muted` or `highlight` (gold, only ever "can play"):
  - Some can play: "Simba and Simbad (alt) **can play** with you" (up to 3 names, online first, then nearest; long names cut to their first word). More than 3: "10 friends **can play** with you · 7 online now".
  - Then "Best together: **Shadowfang Keep** with Simba and Simbad · also Blackfathom Deeps": the dungeon you fit that the most can-play Members fit with a Character within 3 levels of you, then the most of them online, then the lowest.
  - Nobody near: "Nobody is within 3 levels of you." / "Nearest: Simone's alt Simonette, 4 ahead." (a Main is just "Simone").
  - Alone: "You're the only one in the Crew so far." / "Share your Crew code from Settings to bring friends in."
- **Tooltips:** a group lists each Character: Member, Character, level, alt, online, and "can play" or "N ahead" / "N behind". A bar gives its name, kind, range and where it is, "New in WoW: Forever", "You fit", "You need N more levels" or "You've outlevelled it", each Member who fits (with online and "fits, but N levels from you" over 3 levels apart), or "No friend fits it yet", and "Almost: Simone (2 short)" for Members up to 3 levels short of it.

## Showing

`UI/TogetherTab.lua`, a sidebar tab after Professions; `/bff together` opens it. It keeps to the panel's fixed size:

- **Toolbar** (28px): "As Gahzuria 24" in class colour, an "alt" tag when you're on an Alt, and the hidden note at the right.
- **Answer line** (46px): the first line in Body, the second in Small, Smoke Muted with the dungeon in Ash.
- **The line** scrolls sideways (drag or mouse wheel) and opens centred on the Character you play. Ticks every level, numbers every 5, at 1 and at your level. The can-play band has 1px gold edges, a 4% gold fill and a "can play" label.
- **Friends** above the axis: a class-coloured dot per level on a rail, ringed green while someone there is being played and grey otherwise, as the map pins; yours has a light outline. Labels in Ash with the level and "+N", and a stem down to the dot.
- **Dungeons** below the axis: bars at 5% white (12% when you fit, with a 2px Bar Fill underline), NEW on a neutral plate, a dashed edge for the attunement, and a 6px class-coloured dot per Member who fits. A bar's name slides along so it stays readable while the bar is partly scrolled off the left. Chips are a 1px Border box with "+N here".
- **Overview strip** (22px): a tick per group, a gold mark for you and a frame for the visible window. Clicking or dragging it jumps there. "‹ You" or "You ›" shows whenever you've scrolled yourself out of view.

## Not decided here

- Selecting friends to see shared dungeons, and the Show menu's filters and key: #112.
- README, CurseForge description and gallery image: #113.
