# The Pocket Camp and Tips

Answers [Pocket Camp: an optional on-screen Camp](https://github.com/Shtian/bff-wow/issues/161). Builds on the Camp (`docs/design/camp.md`), whose art, art unit and rendering rules it shares. Domain words (**Pocket Camp**, **Tip**, **Camp**) are in `CONTEXT.md`.

The Pocket Camp is a small, movable Camp you can keep on screen while playing: the fire and the Members who are online, you included, each shown doing what they're doing. Most of that is what the Roster and Feed already know; what a Member is doing right now (fighting, at a vendor or the auction house, away, resting, flying) comes in a small live message, a DOING, that is no part of a record. It's off by default, and the panel offers it once with a **Tip**. No record field is new.

## Core decides, UI renders

`Core:pocketCamp()` is the ready-to-render read, built by `Camp.pocket` (`Core/Camp.lua`) from Roster's rows, Feed's entries of the last 24 hours, who Core holds as fishing or at a profession, and what Doing says each Member is doing. It's nil outside a Crew and while the `pocketCamp` or the `camp` setting is off.

```lua
pocketCamp() -> nil, or {
  columns, rows, -- Core.CAMP_LAYOUT.pocketColumns (112) by pocketRows (34), always
  actors = { -- the online Members, you first, as many as fit
    { memberId, label = "You" | displayName, classFilename, x, width, labelWidth,
      pose = "seated" | "adventuring" | "fishing" | "crafting" | "gathering" | "fighting"
        | "vendor" | "auction" | "afk" | "resting" | "flying",
      instance = "The Deadmines" | nil, raid = true | nil, -- the instance is a raid
      status = "by the fire" | "in The Deadmines" | "fishing" | "at a vendor" | ..., -- the pose in words
      spark = true | nil, you = true | nil,
      row = { ... } }, -- the Member's Roster row, for the tooltip over the figure
  },
  more = 2, moreText = "+2", -- online Members that didn't fit; nil when all did
  tooltip = { title = "Pocket Camp", lines = { "You: by the fire", "Bob: in The Deadmines" }, hint },
  opacity = 0.6, -- the backdrop's, 0 to 1
  locked = false, hideInCombat = false,
  position = { x, y } | nil, -- its bottom left corner from the screen's; nil where it starts
  scale = 1, -- how big it is; 1 is its usual size
}
```

It takes no width: the Pocket Camp is a fixed size, so Core can also tell whether a Member is by its fire when it decides on an animation. Positions are art pixels from the fire's centre, in the Camp's geometry. Six figures fit, three each side; a flying figure takes two seats.

UI never reads a setting or a Member record. `UI/PocketCamp.lua` creates its frame the first time the read isn't nil, so with the setting off (the default) there is no frame at all.

## Rules

- **Who:** only the Members whose Roster row is online, you first, in the Roster's order. No sleepers, Graves or tent. Those that don't fit are counted in `more` ("+2"). A Member who logs out or times out is gone at the next read.
- **Seated:** online, in the open world.
- **Adventuring:** the Character being played is inside an instance (the row's `instance`). The figure stands in a stone doorway with a torch raised, and `instance` and `status` name the instance for the tooltip. `raid` marks an instance the dungeon table lists as a raid: its doorway is red, with a skull for a keystone.
- **Fishing:** for 60 s after Core sees a Member's catches grow. When a Member's record is merged and its total catch count (`Catches.total`: every type's `n`) is higher than in the copy held before, they fish from then; another increase starts the 60 s over, and several catches in one update make one spell. Your own figure fishes for 60 s after `caught()` changes your record. Fishing replaces seated or adventuring while it lasts. Core fires `changed` when a spell ends, so the Pocket Camp redraws.
  - Silent on the first sight of a Member (no copy held before) and until sync has settled after a login (as for Live events), so what's caught up at login isn't "fishing now".
  - Kept in memory only (`Core.fishing`), never saved or sent, so a `/reload` forgets it.
  - It's an approximation. The record doesn't say when the latest catch was, and catches ride the next send (within a minute), so the rod comes out when the news arrives.
- **Crafting and gathering:** for 60 s after Core sees a profession's skill grow, exactly as fishing works: a record merged with a higher skill than the copy held (herbalism, mining or skinning is gathering, any other crafting; fishing skill doesn't count), or your own. Status "crafting" or "gathering". The same silences as fishing, and in memory only (`Core.working`).
- **Doing** (below): `fighting` ("fighting"), `vendor` ("at a vendor"), `auction` ("at the auction house"), `afk` ("away"), `resting` ("resting") and `flying` ("flying").
- **Which pose wins:** in an instance, the instance, unless a spell of fishing or of a profession is on; what a DOING said is left out there, since the record is newer than anything said before going in. Elsewhere flying, the auction house and a vendor come first (the Member chose them), then fishing, a profession, fighting, away, resting, and by the fire.
- **Spark:** a `maxLevel` Feed entry in the last 24 hours, as in the Camp.
- **Hop:** a Cheer, as in the Camp (`Panel.cheered` passes it on).
- **Lag:** records update on the 5-minute heartbeat and within about 10 s of a zone change, and nothing arrives from a friend in a boss encounter's lockdown. The Pocket Camp shows what's known and claims no more.

## Doing

What a Member is doing right now isn't in their record: it changes too often and is worth nothing a minute later. `Core/Doing.lua` handles it the way Where handles live map spots.

- **Read.** App calls `core:doing(Snapshot.doing())` every second: `{ combat, vendor, auction, afk, resting, flying }`. Combat is `InCombatLockdown()`, the vendor's and auction house's windows are kept from their show and close events, afk is `UnitIsAFK("player")` (the game's own away flag: `/afk`, or idle for a while), resting is `IsResting()` (an inn or a city), and flying is `UnitOnTaxi("player")` or, where the client has it, `IsFlying()`.
- **One state.** Core shows the first that's true of flying, the auction house, a vendor, fighting, away and resting. Fighting lasts 20 s past the end of combat, so pull after pull is one spell of it and not a message each.
- **Your own figure** shows it at once, with or without anyone online.
- **Sent** as `{ type = "DOING", doing, quest, at }` to everyone when the state changes, under WHERE's conditions (link up, in a Crew, not paused, someone else online), at most every `max(15, 5 × others online)` seconds; what's sent then is the state at that moment, so a quick visit in between is never told. The first DOING of a session goes out even when there's nothing to say, so a `/reload` or a quick relog clears what the Crew held from before. While something is being done it's said again every 2 minutes, and right after a Member comes online.
- **Heard** DOINGs are held in memory per Member. One runs out 5 minutes after it was heard, since the DOING that ends it can be lost, and goes when the Member goes offline or is removed. An older `at` than the one held is ignored. A state this version doesn't know shows as by the fire.
- **Quest handed in.** `core:questHandedIn()` (on `QUEST_TURNED_IN`) plays the `quest` animation on your own figure and marks the next DOING `quest = true`, which plays it on the Crew's. Several in a row are one DOING, and one that can't go out within 90 s isn't told.
- **Not in the record,** so nothing is saved, DIGESTs never ask for it, and older BFFs ignore the unknown type and keep showing the figure by the fire. The protocol version is unchanged.
- **Privacy.** Appear offline silences it, as it does everything else. There is no setting of its own.

## One-off animations

A new Feed entry made while running fires the listener event `pocketCampAnimation({ kind, memberId })`, and the Pocket Camp plays it once, for 10 s (visual only). A quest handed in fires it too (kind `quest`, 6 s), from a DOING and not from the Feed. Each has a quick opening and a tail, so it's still there when you glance over a few seconds later:

| Feed kind | Animation |
|---|---|
| ding | a small gold star rises over that Member's head (1.2 s) and stays there while the figure bounces, half a second up and half down |
| max level | that Member bounces while bursts of sparks fly out, one every 1.8 s; the 24-hour spark stays |
| death | that Member is a skeleton, with a puff of grey smoke and a flicker for the first 1.6 s |
| rare find | that Member holds up a fish, bobbing (over the rod, if they're fishing) |
| goal (Crew-wide) | the fire flares, taller and purple; no `memberId` |
| quest (not a Feed kind) | a gold question mark over that Member's head, bobbing |

A mark over a raised figure (flying) is kept inside the band, so it sits over the head and not above it.

The lengths are CampScene's (`ANIMATION_FOR` in `UI/CampScene.lua`). A second animation of the same kind for the same Member starts it over. They're kept in UI only, so a `/reload` drops one that's playing.

No other kind animates. Core decides, in `animate()`:

- Only while `pocketCamp()` isn't nil.
- A Member's animation only when they're an actor of the Pocket Camp at that moment. Sleepers and Members counted in "+N" get none.
- Others' entries only once sync has settled, so first sight and login catch-up (While you were away) animate nothing. Your own entries always count.
- **Independent of the chat-line and toast settings.** `feedEntry` is only fired while one of those is on, so the animation has its own event. It marks nothing seen: with both off the entry still waits for While you were away.

For these nothing new is sent: the entries are the ones Feed already makes.

## Settings

In a section of their own on the Settings page, Pocket Camp, after Toasts (`docs/design/settings-and-release.md` has how each is saved):

| Key | Label | Default |
|---|---|---|
| `pocketCamp` | Show the Pocket Camp | off |
| `pocketCampOpacity` | Backdrop opacity (0 to 100, a slider) | 60 |
| `pocketCampLocked` | Lock its position and size | off |
| `pocketCampCombat` | Hide in combat | off |
| `pocketCampPosition` | not on the page: where it was dragged to | nil |
| `pocketCampScale` | not on the page: how big it was scaled to, a whole percent from 50 to 300 (`Core.POCKET_CAMP_MIN_SCALE`, `POCKET_CAMP_MAX_SCALE`) | 100 |

All account-wide. With `camp` off the Pocket Camp never shows, whatever its own setting says.

## UI

- **Frame.** `UI/PocketCamp.lua`: a button on `UIParent`, strata LOW, clamped to the screen, with a CampScene band filling it (`CampScene.new(frame, { target = FIGURE_TARGET, shadow = true, names = false })`). Its art pixel aims for 2 UI units, as on rows and toasts, so it's about 224 by 68 UI units; `band:Fit(columns, rows)` gives the exact size in whole screen pixels. "+N" has a shadow, since the game world is behind it.
- **No names.** With six figures there's room for about four letters each, so the Pocket Camp shows none; the tooltip says who a figure is.
- **Backdrop.** Its own art, `Media/CampPocketBackdrop.tga` (`CampSheet.pocketBackdrop`, passed as CampScene's `backdrop` option): the 112 by 34 art pixels of the Camp's backdrop round the fire, cut to a rounded shape that's solid in the middle and dithered away at the rim, so it doesn't sit on the game world as a hard rectangle. `scripts/camp-art.mjs` generates it (`pocketBackdrop`: the roundness, the fade's width and how solid the ground stays are constants there), and its size must match `pocketColumns` and `pocketRows`. No sky is filled in behind it. It's drawn at `opacity` (`band:SetBackdropAlpha`). At 0 only the fire, the figures and "+N" show.
- **Click** toggles the panel, as the minimap button does. In combat (`InCombatLockdown()`) it does nothing.
- **Drag** moves it unless `locked`. Where it's dropped is saved with `core:setPocketCampPosition(left, bottom)`; until then it sits under the screen's centre. Locked, a click still works.
- **Scale.** Unless `locked`, a grip (the chat window's size grabber) shows in its bottom right corner while the mouse is over it. Dragging the grip scales it live, in whole percents between 50% and 300%: its top left stays where it was at the press, and its width grows or shrinks by as much as the mouse moves sideways. The band's target becomes `FIGURE_TARGET × scale` (`band:SetTarget`), and the band is made with `crisp = false`, so its art pixel is exactly that many UI units rather than a whole number of screen pixels: it scales smoothly, but some art pixels come out a screen pixel wider than others. Chosen over crisp steps after trying both in game: the steps were too coarse to scale with. On release `core:setPocketCampPosition` and `core:setPocketCampScale(scale)` save where its corner is and the scale; a press that doesn't change the scale saves nothing. A double-click on the grip goes back to 1, keeping its top left where it is.
- **Hide in combat.** With `hideInCombat`, the frame hides on `PLAYER_REGEN_DISABLED` and shows on `PLAYER_REGEN_ENABLED`. Hidden, its `OnUpdate` doesn't run.
- **Tooltip.** Over a figure, that Member's tooltip exactly as the Roster shows it (`Panel.characterTooltip(actor.row, actor.row)`: the Character being shown, level, zone, professions and so on), then the hint. Anywhere else, Core's `tooltip`: the title, a line per figure, "+N" and the hint. `band:ActorAt(x)` says which figure the mouse is over (half the gap each side counts), and the tooltip follows the mouse from one to the next.
- **Poses.** CampScene's `POSE` table says how each is drawn: whether the figure stands (the hop figure, no seat) or sits, a sprite in its raised hand, one behind it and one over it. Sprites that face the fire are mirrored on its right.

  | Pose | Figure | Sprites |
  |---|---|---|
  | adventuring | standing | `torch` in hand, `arch` behind (`archRaid` for a raid) |
  | fighting | standing | `blade` in hand |
  | crafting | standing | `hammer` in hand, `anvil` at its feet |
  | gathering | standing | `pick` in hand |
  | fishing | seated | `rod` out towards the fire |
  | vendor | seated | `bag` at its feet |
  | auction | seated | `coins` at its feet |
  | resting | seated | `innSign` behind, its board over the head |
  | afk | seated | `afk`, the word AFK in pixel letters, over its head, bobbing a row once a second; it's the head mark's last case, so a one-off mark takes its place while it plays |
  | flying | seated, raised 9 rows | `griffin` under it, `griffinWing` over its legs, lifting to `griffinWingUp` for 3 ticks in 9 |

  The griffin reaches 8 art pixels past the figure towards the fire and 6 away from it (`griffinFore` and `griffinAft` in `Core.CAMP_LAYOUT`), and Core keeps that clear when it places the figure. New tools have a dark outline (`outlined()` in the art script) so they read with the game world behind them.
- **Animations.** `band:Animate(kind, memberId)` keeps each for its length and draws it on the band's 6-per-second tick: `star`, `fish`, `quest`, `smoke1`/`smoke2` over the head, `skeleton` in the figure's place (one untinted layer, no tool, whatever the pose), alternate-tick alpha for the flicker, seven sparks flying out for each burst, and `flare1`–`flare3` in the fire's place.
- **Sprites.** The poses' sprites above, `afk`, `star`, `quest`, `fish`, `smoke1`, `smoke2`, `skeleton` and `flare1`–`flare3` are grids in `scripts/camp-art.mjs` (the flare is each fire frame with its upper rows doubled, painted in purples). Run it after changing one.
- **Redraws** on Core's `changed`, `crewChanged` and its settings, on a UI scale or display change, and every 30 s while shown.
- **Silence.** It plays no sound.

## Tips

A **Tip** is a one-time offer of a feature that's off by default: a small window the first time, then a card at the top of the panel until it's answered. Core holds an ordered list, `TIPS` in `Core/Core.lua`, each `{ key, title, text, setting, needs }`: `setting` is the on/off setting Turn on turns on, and `needs` (optional) a setting that must be on for the Tip to show. Adding the next opt-in feature is one entry.

- `tip()` returns the first unanswered Tip ready to render, `{ key, title, text, accept = "Turn on", dismiss = "No thanks" }`, or nil when there's none or outside a Crew. Only one shows at a time.
- `acceptTip(key)` answers the Tip and turns its setting on (`settingChanged`, then `changed`). `dismissTip(key)` only answers it (`changed`). Both return false for a key that isn't a Tip.
- Answered keys are saved account-wide in `tipsAnswered`, so the card never comes back after a `/reload` or on another Character.
- A feature turned on in Settings answers its Tip too (in `setSetting`), so it never shows, even if the feature is turned off again later.
- **The window.** On the first `tick()` where `tip()` has a Tip that hasn't been offered, Core fires the listener event `tip(tip)` and saves the key in `tipsOffered`, account-wide. So it fires once per Tip: at the first login or `/reload` after the update, or later, once the player is in a Crew. App shows it with `UI/TipDialog.lua` (after combat, if in combat): a small Skin window near the top of the screen titled "New: the Pocket Camp", with the text and the same two buttons. Closing it with the X or Escape answers nothing, so the card stays in the panel, and the window never comes back. It closes by itself if the Tip is answered elsewhere.
- The Pocket Camp's Tip needs `camp` on, since the Pocket Camp can't show without it. It waits rather than being answered.

The one Tip so far: "Keep your Crew on screen. The Pocket Camp shows the fire and who's by it while you play. You can turn it on or off any time in Settings."

Panel draws it as a card across the window under the Camp band, above the sidebar and every tab (`drawTip` in `UI/Panel.lua`): the text on the left, **Turn on** and **No thanks** on the right, as high as its text. A Tip is not a Toast or a chat line and plays no sound. (#161 asked for the card only; the window was added so players notice the feature without opening the panel.) There is no control to show Tips again.

## Tests

`tests/pocket_camp_spec.lua` drives real Cores through FakeNet: who is in `pocketCamp()` and when it's nil, "+N", adventuring, the spark, each actor's Roster row, how it's shown, fishing (the 60 s, the restart, your own, first sight, login and reload), each animation and when none plays, and Tips. `tests/doing_spec.lua` covers Doing the same way: your own figure, the one DOING and what it leaves alone, which state wins, the fighting hold, the rate, the refresh and running out, newcomers and going offline, pause, lockdown and being alone, an unknown state, the redraw, a quest handed in, the profession spells, raids and the griffin's room. `tests/settings_spec.lua` covers the new settings. Frames and art aren't tested offline; in game, `/bff sim` and `/bff sim fish` make simulated Members fish, and the dev console's Doing and Quest buttons step one through what it can be doing and hand in a quest.

## Still to check in game

None of the rendering has run in a client, and the new sprites were authored as grids without being seen at size. On Forever:

- With the setting off, no `BFFPocketCamp` frame exists.
- Pixels stay crisp at a few UI scales and across drags (the frame's corner can land between screen pixels; the art's origin frame rounds to the nearest).
- It's readable over bright and dark scenes at 0%, 60% and 100% opacity, and the backdrop's dithered rim looks right at size.
- Dragging, the lock, and the position after `/reload` and on another Character.
- A click in and out of combat; Hide in combat on and off.
- Each pose and animation reads at size: the rod towards the fire on both sides, the star, fish, smoke, skeleton, bursts and flare, and that 10 s feels right for each.
- The Doing poses on both sides of the fire: the AFK text, the torch and doorway (and the raid's), blade, hammer and anvil, pick, bag, coins, inn sign and the griffin with its wing flapping, and the quest mark.
- That the events and reads behind Doing behave on Forever: `MERCHANT_SHOW`/`MERCHANT_CLOSED`, `AUCTION_HOUSE_SHOW`/`AUCTION_HOUSE_CLOSED`, `QUEST_TURNED_IN`, `IsResting()`, `UnitIsAFK("player")`, `UnitOnTaxi("player")` and whether `IsFlying` exists, and that none of them reads secret in the open world.
- That a DOING gets through in ordinary combat (the retail spike found chat unlocked there), and what a levelling session's DOING traffic looks like in the sync trace.
- The tooltip over each figure and over the fire, and that it changes as the mouse moves between them.
- No measurable CPU cost while it's hidden.
- The Tip card at the panel's narrowest (460) and with the short Camp band.
- The Tip window at first login: its place next to While you were away, which opens a little later, and that it waits for combat to end.
- The Settings slider's thumb and track on Forever's Settings page.
