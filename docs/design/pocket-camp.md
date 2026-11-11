# The Pocket Camp and Tips

Answers [Pocket Camp: an optional on-screen Camp](https://github.com/Shtian/bff-wow/issues/161). Builds on the Camp (`docs/design/camp.md`), whose art, art unit and rendering rules it shares. Domain words (**Pocket Camp**, **Tip**, **Camp**) are in `CONTEXT.md`.

The Pocket Camp is a small, movable Camp you can keep on screen while playing: the fire and the Members who are online, you included, each shown doing what the Roster and Feed already know. It's off by default, and the panel offers it once with a **Tip**. Like the Camp it has no data of its own: no record field is new and nothing new is sent.

## Core decides, UI renders

`Core:pocketCamp()` is the ready-to-render read, built by `Camp.pocket` (`Core/Camp.lua`) from Roster's rows, Feed's entries of the last 24 hours and who Core holds as fishing. It's nil outside a Crew and while the `pocketCamp` or the `camp` setting is off.

```lua
pocketCamp() -> nil, or {
  columns, rows, -- Core.CAMP_LAYOUT.pocketColumns (112) by pocketRows (34), always
  actors = { -- the online Members, you first, as many as fit
    { memberId, label = "You" | displayName, classFilename, x, width, labelWidth,
      pose = "seated" | "adventuring" | "fishing",
      instance = "The Deadmines" | nil, status = "by the fire" | "in The Deadmines" | "fishing",
      spark = true | nil, you = true | nil,
      row = { ... } }, -- the Member's Roster row, for the tooltip over the figure
  },
  more = 2, moreText = "+2", -- online Members that didn't fit; nil when all did
  tooltip = { title = "Pocket Camp", lines = { "You: by the fire", "Bob: in The Deadmines" }, hint },
  opacity = 0.6, -- the backdrop's, 0 to 1
  locked = false, hideInCombat = false,
  position = { x, y } | nil, -- its bottom left corner from the screen's; nil where it starts
}
```

It takes no width: the Pocket Camp is a fixed size, so Core can also tell whether a Member is by its fire when it decides on an animation. Positions are art pixels from the fire's centre, in the Camp's geometry. Six figures fit, three each side.

UI never reads a setting or a Member record. `UI/PocketCamp.lua` creates its frame the first time the read isn't nil, so with the setting off (the default) there is no frame at all.

## Rules

- **Who:** only the Members whose Roster row is online, you first, in the Roster's order. No sleepers, Graves or tent. Those that don't fit are counted in `more` ("+2"). A Member who logs out or times out is gone at the next read.
- **Seated:** online, in the open world.
- **Adventuring:** the Character being played is inside an instance (the row's `instance`). The figure stands with a sword raised, and `instance` and `status` name the instance for the tooltip.
- **Fishing:** for 60 s after Core sees a Member's catches grow. When a Member's record is merged and its total catch count (`Catches.total`: every type's `n`) is higher than in the copy held before, they fish from then; another increase starts the 60 s over, and several catches in one update make one spell. Your own figure fishes for 60 s after `caught()` changes your record. Fishing replaces seated or adventuring while it lasts. Core fires `changed` when a spell ends, so the Pocket Camp redraws.
  - Silent on the first sight of a Member (no copy held before) and until sync has settled after a login (as for Live events), so what's caught up at login isn't "fishing now".
  - Kept in memory only (`Core.fishing`), never saved or sent, so a `/reload` forgets it.
  - It's an approximation. The record doesn't say when the latest catch was, and catches ride the next send (within a minute), so the rod comes out when the news arrives.
- **Spark:** a `maxLevel` Feed entry in the last 24 hours, as in the Camp.
- **Hop:** a Cheer, as in the Camp (`Panel.cheered` passes it on).
- **Lag:** records update on the 5-minute heartbeat and within about 10 s of a zone change, and nothing arrives from a friend in an instance or combat lockdown. The Pocket Camp shows what's known and claims no more.

## One-off animations

A new Feed entry made while running fires the listener event `pocketCampAnimation({ kind, memberId })`, and the Pocket Camp plays it once, for 10 s (visual only). Each has a quick opening and a tail, so it's still there when you glance over a few seconds later:

| Feed kind | Animation |
|---|---|
| ding | a small gold star rises over that Member's head (1.2 s) and stays there while the figure bounces, half a second up and half down |
| max level | that Member bounces while bursts of sparks fly out, one every 1.8 s; the 24-hour spark stays |
| death | that Member is a skeleton, with a puff of grey smoke and a flicker for the first 1.6 s |
| rare find | that Member holds up a fish, bobbing (over the rod, if they're fishing) |
| goal (Crew-wide) | the fire flares; no `memberId` |

The lengths are CampScene's (`ANIMATION_FOR` in `UI/CampScene.lua`). A second animation of the same kind for the same Member starts it over. They're kept in UI only, so a `/reload` drops one that's playing.

No other kind animates. Core decides, in `animate()`:

- Only while `pocketCamp()` isn't nil.
- A Member's animation only when they're an actor of the Pocket Camp at that moment. Sleepers and Members counted in "+N" get none.
- Others' entries only once sync has settled, so first sight and login catch-up (While you were away) animate nothing. Your own entries always count.
- **Independent of the chat-line and toast settings.** `feedEntry` is only fired while one of those is on, so the animation has its own event. It marks nothing seen: with both off the entry still waits for While you were away.

Nothing new is sent: the entries are the ones Feed already makes.

## Settings

In Notifications and display, under Show the Camp (`docs/design/settings-and-release.md` has how each is saved):

| Key | Label | Default |
|---|---|---|
| `pocketCamp` | Show the Pocket Camp | off |
| `pocketCampOpacity` | Pocket Camp backdrop opacity (0 to 100, a slider) | 60 |
| `pocketCampLocked` | Lock the Pocket Camp's position | off |
| `pocketCampCombat` | Hide the Pocket Camp in combat | off |
| `pocketCampPosition` | not on the page: where it was dragged to | nil |

All account-wide. With `camp` off the Pocket Camp never shows, whatever its own setting says.

## UI

- **Frame.** `UI/PocketCamp.lua`: a button on `UIParent`, strata LOW, clamped to the screen, with a CampScene band filling it (`CampScene.new(frame, { target = FIGURE_TARGET, shadow = true, names = false })`). Its art pixel aims for 2 UI units, as on rows and toasts, so it's about 224 by 68 UI units; `band:Fit(columns, rows)` gives the exact size in whole screen pixels. "+N" has a shadow, since the game world is behind it.
- **No names.** With six figures there's room for about four letters each, so the Pocket Camp shows none; the tooltip says who a figure is.
- **Backdrop.** The band's sky and backdrop art at `opacity` (`band:SetBackdropAlpha`). At 0 only the fire, the figures and "+N" show.
- **Click** toggles the panel, as the minimap button does. In combat (`InCombatLockdown()`) it does nothing.
- **Drag** moves it unless `locked`. Where it's dropped is saved with `core:setPocketCampPosition(left, bottom)`; until then it sits under the screen's centre. Locked, a click still works.
- **Hide in combat.** With `hideInCombat`, the frame hides on `PLAYER_REGEN_DISABLED` and shows on `PLAYER_REGEN_ENABLED`. Hidden, its `OnUpdate` doesn't run.
- **Tooltip.** Over a figure, that Member's tooltip exactly as the Roster shows it (`Panel.characterTooltip(actor.row, actor.row)`: the Character being shown, level, zone, professions and so on), then the hint. Anywhere else, Core's `tooltip`: the title, a line per figure, "+N" and the hint. `band:ActorAt(x)` says which figure the mouse is over (half the gap each side counts), and the tooltip follows the mouse from one to the next.
- **Poses.** CampScene draws `adventuring` as the standing (hop) figure with the `sword` sprite over its raised hand and no seat, and `fishing` as the seated figure with the `rod` sprite out towards the fire (mirrored on the fire's right).
- **Animations.** `band:Animate(kind, memberId)` keeps each for its length and draws it on the band's 6-per-second tick: `star`, `fish`, `smoke1`/`smoke2` over the head, `skeleton` in the figure's place (one untinted layer, no tool, whatever the pose), alternate-tick alpha for the flicker, seven sparks flying out for each burst, and `flare1`–`flare3` in the fire's place.
- **Sprites.** `rod`, `sword`, `star`, `fish`, `smoke1`, `smoke2`, `skeleton` and `flare1`–`flare3` are grids in `scripts/camp-art.mjs` (the flare is each fire frame with its upper rows doubled). Run it after changing one.
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

`tests/pocket_camp_spec.lua` drives real Cores through FakeNet: who is in `pocketCamp()` and when it's nil, "+N", adventuring, the spark, each actor's Roster row, how it's shown, fishing (the 60 s, the restart, your own, first sight, login and reload), each animation and when none plays, and Tips. `tests/settings_spec.lua` covers the new settings. Frames and art aren't tested offline; in game, `/bff sim` and `/bff sim fish` make simulated Members fish.

## Still to check in game

None of the rendering has run in a client, and the new sprites were authored as grids without being seen at size. On Forever:

- With the setting off, no `BFFPocketCamp` frame exists.
- Pixels stay crisp at a few UI scales and across drags (the frame's corner can land between screen pixels; the art's origin frame rounds to the nearest).
- It's readable over bright and dark scenes at 0%, 60% and 100% opacity.
- Dragging, the lock, and the position after `/reload` and on another Character.
- A click in and out of combat; Hide in combat on and off.
- Each pose and animation reads at size: the rod towards the fire on both sides, the sword, star, fish, smoke, skeleton, bursts and flare, and that 10 s feels right for each.
- The tooltip over each figure and over the fire, and that it changes as the mouse moves between them.
- No measurable CPU cost while it's hidden.
- The Tip card at the panel's narrowest (460) and with the short Camp band.
- The Tip window at first login: its place next to While you were away, which opens a little later, and that it waits for combat to end.
- The Settings slider's thumb and track on Forever's Settings page.
