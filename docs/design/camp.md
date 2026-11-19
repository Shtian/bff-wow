# The Camp

Answers [The Camp: a living pixel campsite for the Crew](https://github.com/Shtian/bff-wow/issues/127). The rendering choices come from `docs/research/pixel-art-rendering.md`. Domain words (**Camp**, **Grave**) are in `CONTEXT.md`.

The **Pocket Camp**, the cut-down Camp kept on screen while playing, has its own doc: `docs/design/pocket-camp.md`.

The Camp is a small pixel campsite at the top of the panel, on every tab, and at the top of While you were away. Every Member the Roster shows is in it: online Members sit by the fire, offline ones sleep in bedrolls, a recent death leaves a Grave, Respects put a flower on it, and a fresh max level has a spark. It's another way of showing what Core already knows. It has no saved data of its own, sends nothing, and keeps working in lockdown, showing what's known.

## Core decides, UI renders

`Core:camp(columns)` is the ready-to-render read, built by `Core/Camp.lua` from Roster's rows and Feed's entries of the last 24 hours (`Feed:since`). It takes the band's width in **art columns**: only UI knows how big an art pixel is, so UI passes the whole number of columns that fit, and Core stays free of scale. It returns nil while the `camp` setting is off.

```lua
camp(columns) -> nil, or {
  columns,
  actors = { -- you first, then as placed
    { memberId, pose = "seated" | "asleep", label = "You" | displayName,
      classFilename, x, width, labelWidth, spark = true | nil, you = true | nil },
  },
  graves = { { memberId, x, flower = true | nil, key } },
  tent = { x } | nil, -- only when there's room
  more = 2, moreText = "+2 more", -- Members that didn't fit; nil when all did
}
```

A grave's `key` is the death's Reaction key as a string (`Reactions.id` of the entry's key, docs/design/reactions.md), so the band can find the Grave that Respects bloom. Every Grave of a collapsed "died 3 times" entry shares it, as they share the flower. It's nil for an entry saved before it had a death total.

Positions are art pixels from the fire's centre, negative to the left; `x` is a sprite's left edge. The geometry is `Core.CAMP_LAYOUT`: the fire keeps 9 columns clear each side, a seated figure is 12 wide and a sleeper 18, a grave 8 with a 2-column gap, neighbours 4 apart, 2 columns clear inside each edge, the tent 36. The panel's band runs 128 to 375 columns; the popup's is 120.

## Rules

- **Who:** exactly the Members the Roster shows, you included. Left, Removed and fully hidden (30-day) Members are never in it. One actor per Member, with the class of the Character their row shows (the one being played while online, else the Main), so Alts never crowd it.
- **Pose:** seated while the row is online, else asleep. You are always seated. A logout (`gone`) or the 12-minute timeout puts a Member to sleep at the next read.
- **Label:** "You", else the Display name (the Character's name without one). `labelWidth` is the room for it: twice the distance from the figure's centre to the midpoint with its neighbour on the nearer side (the fire and the band's edges count as neighbours), less the gap. UI cuts names to it, so names never run into each other.
- **Placement:** seated Members nearest the fire, you first, alternating sides by taking whichever side has more room (ties go left). Sleepers carry on outward, most recent Last seen first. A Member's Graves sit beside them, on the side away from the fire. Nothing overlaps, and nothing touches the fire or leaves the band, at any width from 128 to 375 columns (`camp_spec`).
- **When Members don't fit:** online Members first, then sleepers by most recent Last seen. A slot that won't fit with its Graves is tried without them. The rest are counted in `more`. In a Crew so large that even the online Members don't fit, the extra ones are counted too.
- **Graves:** one per death in the Member's `death` Feed entries from the last 24 hours, newest first, at most 2 per Member and 4 in the Camp. A collapsed "died 3 times" entry counts as its deaths. Your own deaths count.
- **Flower:** on a Grave whose Feed entry has any Member's Respects, not only yours. So it's asynchronous: a friend's Respects gossiped while you were offline shows when you log in, and your own Graves get flowers even though you can't react to your own entries. A Removed Member's Respects don't count, as in the Feed.
- **Spark:** a Member with a `maxLevel` Feed entry from the last 24 hours. Dings get none.
- **Tent:** after everyone, on the side with more room, only when it fits. Never in the popup. It's a pavilion, its canvas lit on the side facing the fire, so it's mirrored on the fire's right.

## While you were away

`awaySummary` gains `camp`: the same shape at `Core.CAMP_LAYOUT.awayColumns`, without the tent, plus each actor's `gained` (its Main's, as the scoreboard words it: "+3" or "new") and `highlight` (it reached max level). Actors whose Main gained nothing have no `gained`. With the setting on, `intro` reads "The fire kept burning. 7 things happened in camp." The scoreboard under the Camp stays as it is. The popup widens from 400 to 440 for it.

## Setting and wording

One on/off setting, `camp`, "Show the Camp", on by default, in Notifications and display, saved as `campOff = true` while off. Off, `camp()` and the summary's `camp` are nil and every bit of wording below goes back to what it was; Panel redraws on its `settingChanged`. UI never reads the setting: no Camp from Core means no band, no figures on rows and no figure on toasts.

| Where | Camp on | Camp off |
|---|---|---|
| Header (`summary().header`) | "2 of 5 by the fire" (you counted) | "1 of 4 online" (others only) |
| Roster row (`rows()[i].status`) | "by the fire", "asleep · 7m ago" | "online", "7m ago" |
| Roster sections (`rows()[i].section`), sorted Online first | BY THE FIRE, ASLEEP IN CAMP | CREW |
| Roster sections, other sorts | CREW | CREW |
| Popup intro | "The fire kept burning. 7 things happened in camp." | "7 things happened while you were away." |
| Toast (`feedEntry`'s `figure`) | the Member's shown class | nil |

Alt lines keep plain Last seen. Feed day titles stay TODAY and YESTERDAY, Feed reactor lines and the solid timeline stay, and the Roster keeps its Sort control and online dot.

## UI

- **Band.** `UI/CampScene.lua`, across the full panel width under the header, above the sidebar and content, on every tab. About 120 UI units high, or 78 in a panel under 460 high, each rounded down to whole art pixels; bottom-aligned, so the short band crops the sky. Every tab's height is what's left below it.
- **Art unit.** One art pixel is a whole number of screen pixels nearest 3 UI units in the band (2 on rows and toasts), from `PixelUtil.GetPixelToUIUnitFactor()` and the frame's effective scale. Worked out on every draw, so `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED` (App redraws the panel) and a panel resize all pick it up. Every size and offset is art pixels times the unit. Names stay in UI units, and the Camp is never `SetScale`d.
- **Textures.** Every Camp texture is set once with `"CLAMP", "CLAMP", "NEAREST"`. The art's origin frame has `SetRoundLayoutToNearestPixel(true)` where the client has it, since ElvUI turns default texture snapping off. The band clips its children.
- **Backdrop.** `Media/CampBackdrop.tga`, 512×64, the 384×52 backdrop art at the bottom with the fire on column 256. A fixed-size texture anchored on a whole art pixel; no texture-coordinate crop. The band's sky colour fills above it.
- **Sprites.** `Media/CampSprites.tga`, 32-bit uncompressed, bottom-left origin, with a 1-pixel transparent gutter round each cell. `UI/CampSheet.lua` holds every rectangle. Both are generated by `scripts/camp-art.mjs` from the prototype's grids; run it after changing a grid. Figures are two textures on one rectangle: cloth tinted by `RAID_CLASS_COLORS` (authored white and `#9E9E9E`; sleepers' at 55%), under untinted skin and outline.
- **Animation.** One `OnUpdate` on the band, which only runs while it's shown. It returns early unless a new tick (6 per second) is due, then steps the fire's 3 frames by `SetTexCoord`, moves 3 embers in whole art pixels, and builds each sleeper's three staggered z's (small to normal) one at a time. Sparks stay lit. No FlipBook, no Translation.
- **Firelight.** `UI/Firelight.lua` lights the panel under the band (DESIGN.md, the Firelit Window Rule): the fire's glow (`Media/CampLight.tga`, from `scripts/camp-art.mjs`, the fire's orange fading out in a half ellipse) hung from the fire's middle (`band:FireX()`) and drawn added at 16% with a 30% lip, a shade settling from the window's foot, and up to six embers that leave the fire every few seconds and drift down into the window, gold then red, on the Camp's `ember`, `emberWarm` and `emberCool` sprites at the band's art pixel (`band:Unit()`). Everything is on the panel's own background and artwork layers, under every child frame, so rows and text sit over it. Its own `OnUpdate`, on a frame shown only while the band is, steps the glow's flicker (every 0.3 s) and moves the embers every frame, so it stops with the band and the panel. `Panel` places it after each layout, with the room under the band; no Camp, no light. The popup's Camp isn't lit.
- **Hop.** After a Cheer goes through `react(key)` (from the Feed, a toast or the popup), a seated friend swaps to the hop pose, 2 art pixels up, for 0.7 s, with a burst of gold over their head (below), in the band and in the Pocket Camp. A sleeping friend's Cheer works exactly as before.
- **Reactions.** Every Reaction that reaches you live plays too (Reactions, live, below): the hop for a Cheer, a bloom on the Grave for Respects, a wave for a Welcome. The hops, blooms and waves playing are the only state the Camp keeps in UI, and they change nothing Core reports.
- **Roster rows and toasts.** Rows show the seated figure in the class icon's place while there's a Camp. A toast with `figure` shows that Member's figure in the picture's place.
- **Silence.** The Camp plays no sound.
- **Head pieces** ([#241](https://github.com/Shtian/bff-wow/issues/241)). See Head pieces, below.
- **Empty states' vignettes.** `Media/EmptyStates.tga` (256×128, from `scripts/camp-art.mjs`, `CampSheet.vignettes`) holds the seven vignettes `UI/EmptyState.lua` shows in empty views (DESIGN.md, Empty state): the Feed's fire burned down, Trophies' stand with the cup's outline, Play Times' hourglass under the moon, Spare Items' emptied crate, Professions' anvil, Catches' rod over a pond, and the alone state's log by the fire. Each is 40×22 art pixels at the band's art unit, its frames held for `hold` ticks of the band's 6 a second (the fires every tick, the hourglass and the water every other), stepped by its own `OnUpdate` while shown and only while the Camp is on; with it off they show their first frame. Chosen in [#239](https://github.com/Shtian/bff-wow/issues/239) over a minimal set (the bare subjects, outlined, about 16 to 28 columns), because the ground and light make them read as pieces of the Camp rather than icons. A first detailed set was critiqued and redrawn before the choice: its empty plinth, sundial and anvil were one grey silhouette (the stand, hourglass and anvil now differ in shape and material), the crate's straw read as a face, Catches' water was a hard blue strip, and the vignettes didn't share a size or a light. The stacked layout won over the vignette beside the text, which dropped back to stacked at the smallest panel anyway; the plain code box over a big gold plate, which would be a second gold accent (the One Ember Rule).

## Head pieces

A Member chooses a head piece for their figure (the Look), and every Member sees it in the panel's Camp, While you were away, the Pocket Camp, roster rows and toasts. The class colour stays on the cloth.

- **Data.** The own record's optional `look` is `{ hat = "<key>" }`, with room for more later (a pet). `Core:setLook({ hat = key })` writes it through `Ledger:writeOwn` and sends it at once, as `setDisplayName` does, and fires `changed`; `"none"` clears it, an unknown key returns `nil, "unknownHat"`, and the same piece again does nothing. `Core:look()` reads yours. It's lenient: `look` isn't in `RECORD_SHAPE`, and `Look.hat` (`Core/Look.lua`) reads a malformed `look`, or a key this client doesn't know, as no hat while keeping the record. Older clients keep and relay the field unchanged (records travel whole), so there's no protocol bump. Roster rows, `camp()` and `pocketCamp()` actors and live entries (for toasts) carry `hat`, a known key or nil. Leaving keeps your piece.
- **The pieces.** `Core.HATS` (`Look.HATS`): none, templar helm, centurion helmet, dwarven helm, wolfskin helmet, coonskin cap, cowboy hat, straw hat, fez, beret, circlet, bandana, feathered cap, wizard hat, horned helm and top hat.
- **Art.** Grids in `scripts/camp-art.mjs` (`HATS`), fill only and outlined like the tools, in `PAL` plus `HAT_PAL`, untinted. Each has a `brow`, the fill row whose underside sits on the seated figure's forehead (its row 2), carried to `CampSheet.hats`. Pieces are 10 to 12 fill columns wide and rise up to 4 rows above the head; the helmets (templar, centurion, dwarven, wolfskin) come down over the face.
- **Drawing.** `CampScene` draws the piece over the skin (ARTWORK 3), centred on the figure's 12 columns, on every pose whose head is the seated sprite's: seated, the hop, standing (a Doing), flying (raised with the rider), and the arrival's walk (mirrored with it) and wave. None while asleep, as a skeleton, or in a shapeshift form. Head marks (star, fish, quest, AFK, ALT, smoke and the "hi!" bubble) sit one row higher while a piece shows, still kept inside the band, so on tall pieces they overlap the piece's top. The name label sits a row above the piece. `CampScene.figure` (roster rows and toasts) takes the piece as `SetClass(class, hat)`: the frame grows to include it, so a row's figure keeps its feet and a toast's stays centred. Map pins and the Dungeons tab's heads show none.
- **Choosing.** Settings › You › Look: a grid of the pieces (the piece alone in each cell, the chosen one on a cream chip), its name under it, and your seated figure in your shown class colour as a preview. A click saves at once, in lockdown too, going out when the link is back.
- **Chosen** in [#241](https://github.com/Shtian/bff-wow/issues/241) from a prototype (`prototypes/look-hats.html` on the `prototype/241-head-pieces` branch): the detailed style (outlined, 2 or 3 shades) over a flat silhouette with one highlight, because it matches the Camp's tools; no piece while asleep, rather than one beside the pillow; marks one row up rather than clear of the piece, which ran into the short band's top; a grid in Settings rather than ‹ › arrows, so every piece shows at once. Three rounds of pieces: the hood, crown of flowers and pumpkin beanie didn't read and went; the knight's helmet became the templar and centurion helmets after references; the samurai kabuto, dragon helm and great helm were tried and dropped.

## Reactions, live

Answers [Camp: Reactions animate live](https://github.com/Shtian/bff-wow/issues/238). Builds on Reactions (docs/design/reactions.md) and the Pocket Camp's animations (docs/design/pocket-camp.md).

Every Reaction this client attaches while running plays in the Camp, not only your own Cheer. Core fires the listener event

```lua
campReaction({ kind = "cheer" | "respects" | "welcome", memberId, grave })
```

`memberId` is whose entry it is (B, maybe you). `grave` is for Respects only: the key of the Grave to bloom (`camp()`'s `key`). The panel's Camp, While you were away's and the Pocket Camp each pass it to their band while they show (`band:React`).

| Reaction | Plays | Where |
|---|---|---|
| **Cheer** | B hops (`HOP_FOR`, 0.7 s), with a burst of gold over the head | the panel's Camp, the popup's and the Pocket Camp |
| **Respects** | B's Grave's flower blooms: it grows in from the stem up, then 3 petals drift up and fade (1.6 s) | the panel's Camp and the popup's: the Pocket Camp has no Graves |
| **Welcome** | B stands from their seat and waves in place with the "hi!" bubble, the arrival's wave without the walk (4 s) | the panel's Camp, the popup's and the Pocket Camp |

**Rules.** Core decides in `playReactions` and `Feed:campReaction`:

- Any Member's Reaction on any Member's entry, as Feed first attaches it (`Feed:recordChanged`), from a DATA, a merge or gossip.
- Only once sync has settled, so login catch-up plays nothing. Never on the first sight of the reacting Member, and so never for a joiner's backlog.
- Never for a Removed Member's Reaction, nor on a Removed or Left Member's entry.
- Respects only when they're the first on that death (the flower appears). Later Respects on a Grave that already has its flower play nothing.
- Your own Reactions: the Cheer keeps its direct path (UI calls `Hop` after `react(key)`), so Core plays none for it, and nothing plays twice. Respects you pay, and a Welcome you give, play through `react(key)` (`campReaction`), under the same rules.
- Independent of the chat-line and toast settings, like `pocketCampAnimation`. Marks nothing seen. Nothing with the `camp` setting off.
- The band plays one only when B is drawn there and not asleep (a Grave blooms even for a sleeper). Several arriving together each play. A second one for the same figure or Grave starts it over.

**Drawing.** All on the band's 6-per-second tick (`UI/CampScene.lua`):

- **Cheer burst** (`CHEER_BURST`): seven single pixels fly out from 2 rows over the hopping head, out and up, a step a tick: `glint` (white), `glintPale`, `ember` (gold), then `emberWarm` (orange) at 60%. Four ticks, so it's over with the hop. Only a Cheer's hop bursts: a ding's or max level's bounce doesn't.
- **Bloom** (`BLOOM`, `drawBloom`): the `flower` sprite revealed from its bottom row up, a row every 1.5 ticks (stem, bud, petals, top), then a `petal` pixel at each of 3 spots drifts up a row a tick, a tick apart, swaying out a column every other tick and fading to 50% after 3 ticks, until 1.6 s. Keyed by the Grave's `key` (`scene.blooms`). After it, the Grave shows its flower as `camp()` says, which by then is the next redraw's.
- **Welcome** (`ANIMATION_FOR.welcome`): `drawArrival` with no walk: `wave1`/`wave2`, a wave every 2 ticks, mirrored on the fire's right, with `hi` over the head and the seat waiting.
- **Marks stay inside the band** (`markRow`): the panel's short band too, not only the Pocket Camp, so the "hi!" bubble, 11 rows tall over a standing head, is pulled down onto the head rather than cut off at the top.
- **Sprites.** `glint` (white), `glintPale` (pale gold) and `petal` (pink), single pixels, are new in `scripts/camp-art.mjs`.

**Chosen** from a prototype of each (`prototypes/camp-reactions.html` on [#247](https://github.com/Shtian/bff-wow/pull/247)'s branch), judged on the panel's band, the short band and the Pocket Camp at 1x and 2x:

- **Cheer: the hop with a gold burst**, over the hop alone, so a friend's Cheer reads as a celebration and not only a twitch. The prototype's burst had a fifth step; it's four here so it ends with the hop.
- **Respects: grows row by row, then petals drift**, over popping in with a petal puff or fading in with drifting petals. It reads as growing even at 4 rows, and it's the gentlest for a death.
- **Welcome: the wave with "hi!"**, over a heart or a star instead of the bubble. It's the arrival's own greeting, so a Welcome looks like what it says. The bubble covers the name while it shows, as an arrival's already does, and the short band needs the clamp above.

**Traffic.** None. Reactions already travel in records; this only reads what this client attaches.

## Tests

`tests/reactions_spec.lua` (Reactions in the Camp) checks `campReaction` through FakeNet: a friend's Cheer on a third Member's entry plays for the owner and the third Member, and your own Cheer plays none; Respects play with the Grave's key, once, for your own too, and later Respects play nothing; a Welcome plays, your own too; chat lines and toasts off change nothing, the Camp off plays nothing; nothing at login or on first sight; nothing for a Removed Member's Reaction or on a Removed or Left Member; and nothing more is sent.

`tests/camp_spec.lua` drives real Cores through FakeNet and checks `camp()`, the summary's `camp` and intro, `rows()` and `summary()` wording, the toast's `figure` and `hat`, the setting, and head pieces (the list, `setLook` writing and sending, another Member's piece in your Camp, none and an unknown key, sending nothing when unchanged, an unknown or malformed `look` read as none with the record kept, a relayed record keeping its `look`, and your piece kept after leaving). `tests/pocket_camp_spec.lua` checks a piece on Pocket Camp actors, and `tests/settings_spec.lua` the `look()` read and its redraw. Frames and art aren't tested offline.

## Still to check in game

None of the rendering has run in a client. Before tuning the art, run the research note's [Check in game](../research/pixel-art-rendering.md#check-in-game) list on retail, then on Forever: `NEAREST` on a TGA first, since everything depends on it, then even pixels across UI scales, the origin under drags and resizes, tint with filtering, ElvUI, clipping, client texture settings, the TGA origin, combat, and the CPU cost with the panel closed. The sprites were judged in a browser at 2x, so expect to tune their contrast against the game's gamma. The short band (as few as 22 art rows) crops the top of the tent's roof first; sparks sit on the figures so it never crops them. Check names stay readable there. For live Reactions, with `/bff sim` and the dev console's **Cheer**, **Resp** and **Welc** (the selected simulated Member gives that Reaction to the newest entry that takes it, yours or a friend's; **Die** gives them a death to pay Respects to): the hop and its burst, the bloom (its timing, and that it reads as growing at size), and the wave, in the panel's Camp, the short band (the bubble pulled down onto the head) and the Pocket Camp. Head pieces: each piece on each pose, in both Camps at a few widths and UI scales; tall pieces against the short band's top, and their names above them; a head mark over a piece; roster rows (the piece inside the row) and toasts; the Settings grid and its preview.
