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
  graves = { { memberId, x, flower = true | nil } },
  tent = { x } | nil, -- only when there's room
  more = 2, moreText = "+2 more", -- Members that didn't fit; nil when all did
}
```

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
- **Hop.** After a Cheer goes through `react(key)` (from the Feed, a toast or the popup), a seated friend swaps to the hop pose, 2 art pixels up, for 0.7 s, in the band and in the Pocket Camp. It's the only state the Camp keeps in UI and changes nothing Core reports. A sleeping friend's Cheer works exactly as before.
- **Roster rows and toasts.** Rows show the seated figure in the class icon's place while there's a Camp. A toast with `figure` shows that Member's figure in the picture's place.
- **Silence.** The Camp plays no sound.

## Tests

`tests/camp_spec.lua` drives real Cores through FakeNet and checks `camp()`, the summary's `camp` and intro, `rows()` and `summary()` wording, the toast's `figure` and the setting. Frames and art aren't tested offline.

## Still to check in game

None of the rendering has run in a client. Before tuning the art, run the research note's [Check in game](../research/pixel-art-rendering.md#check-in-game) list on retail, then on Forever: `NEAREST` on a TGA first, since everything depends on it, then even pixels across UI scales, the origin under drags and resizes, tint with filtering, ElvUI, clipping, client texture settings, the TGA origin, combat, and the CPU cost with the panel closed. The sprites were judged in a browser at 2x, so expect to tune their contrast against the game's gamma. The short band (as few as 22 art rows) crops the top of the tent's roof first; sparks sit on the figures so it never crops them. Check names stay readable there.
