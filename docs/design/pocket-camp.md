# The Pocket Camp

Answers [Pocket Camp: an optional on-screen Camp](https://github.com/Shtian/bff-wow/issues/161). Builds on the Camp (`docs/design/camp.md`), whose art, art unit and rendering rules it shares. Domain words (**Pocket Camp**, **Camp**) are in `CONTEXT.md`.

The Pocket Camp is a small, movable Camp you can keep on screen while playing: the fire and the Members who are online, you included, each shown doing what they're doing. A Member who comes online walks in and says hi, and one who goes offline sleeps in a bedroll by the fire for 10 minutes ([#205](https://github.com/Shtian/bff-wow/issues/205)). Members in your party or raid sit next to you, and Members in the same instance stand together in one doorway ([#206](https://github.com/Shtian/bff-wow/issues/206)). Most of that is what the Roster and Feed already know; what a Member is doing right now (fighting, at a vendor or the auction house, away, resting, flying) and the shapeshift form they're in ([#217](https://github.com/Shtian/bff-wow/pull/217)) come in a small live message, a DOING, that is no part of a record. It's on by default, and can be turned off in Settings. No record field is new.

## Core decides, UI renders

`Core:pocketCamp()` is the ready-to-render read, built by `Camp.pocket` (`Core/Camp.lua`) from Roster's rows, Feed's entries of the last 24 hours, who Pocket (`Core/Pocket.lua`) holds as fishing or at a profession, what Doing says each Member is doing, and your party or raid as the game last read it (`core:group()`). It's nil outside a Crew and while the `pocketCamp` or the `camp` setting is off.

```lua
pocketCamp() -> nil, or {
  columns, rows, -- as wide as who's online needs (below), by pocketRows (34)
  maxColumns = 112, -- how wide it can grow: the pocketCampColumns setting
  actors = { -- the online Members, you first, as many as fit; then bedrolls in the room left
    { memberId, label = "You" | displayName, classFilename, x, width, labelWidth,
      pose = "seated" | "adventuring" | "fishing" | "crafting" | "gathering" | "fighting"
        | "vendor" | "auction" | "afk" | "resting" | "flying"
        | "asleep", -- a bedroll: went offline in the last 10 minutes
      instance = "The Deadmines" | nil, raid = true | nil, -- the instance is a raid
      group = true | nil, -- their shown Character is in your party or raid
      onAlt = true | nil, -- the Character shown isn't their Main (the Roster row's onAlt)
      form = "wolf" | "bear" | "cat" | "travel" | "seal" | "moonkin" | nil, -- drawn in the figure's place, seated or fighting
      trots = true | nil, -- the form trots to and fro (wolf, travel)
      doorway = 1 | nil, -- adventuring: the doorway (below) they stand in
      status = "by the fire" | "in The Deadmines · 25m" | "fishing" | "fighting · 3m" | "in bear form" | "asleep · 4m" | ..., -- the pose in words, or by the fire the form's; with how long from a minute on (below)
      since = 180 | nil, -- seconds in this pose, set only when status shows a time
      spark = true | nil, you = true | nil,
      row = { ... }, -- the Member's Roster row, for the tooltip over the figure
      menu = { fullName, mapId = 1429 | nil } | nil }, -- another Member's figure's right-click menu (below)
  },
  doorways = { -- one per adventuring figure, or per run of them side by side in the same instance
    { x, width, instance = "The Deadmines", raid = true | nil },
  },
  more = 2, moreText = "+2", -- online Members that didn't fit; nil when all did
  lanternSeats, saved, walkIn, -- one lantern seat while you're alone, and the first friend's walk-in (docs/design/camp.md, Lantern seats)
  season = "winter" | "autumn" | "lunar" | "midsummer" | nil, decor = { { key = "tree" | "pumpkin" | "pole", x } } | nil, -- a season's decorations, its piece only in spare width (docs/design/camp.md, Seasons)
  phase = "day" | "night" | nil, -- the game's day or night; nil with Day and night or the Camp off (docs/design/camp.md, Day and night)
  tooltip = { title = "Pocket Camp", lines = { "You: by the fire", "Bob (on alt): in The Deadmines · 25m", "Cy: asleep · 4m" }, hint },
  opacity = 0.6, -- the backdrop's, 0 to 1
  locked = false,
  inCombat = "stay" | "fade" | "hide", -- what it does in combat
  combatFade = 0.25, -- the opacity, 0 to 1, the whole frame fades to in combat while inCombat is "fade"
  position = { x, y } | nil, -- its bottom left corner from the screen's; nil where it starts
  scale = 1, -- how big it is; 1 is its usual size
  spares = 2 | nil, -- unseen Spare notices (unseenSpares()); nil at none or with pocketCampSpares off: the crate
  sparesTooltip = { title = "2 Spare notices", hint = "Click to see them in Spares." } | nil,
  trophies = { { name = "Crew deaths: 25", ago = "12m ago" }, ... } | nil, -- this session's, under an hour old, newest first: the trophy cup
  trophiesTooltip = { title = "2 Trophies reached", lines = { "Crew deaths: 50 · just now", "Crew deaths: 25 · 12m ago" },
    hint = "Click to see them in Trophies." } | nil,
}
```

It takes no width: Core decides it, so Core can also tell whether a Member is by its fire when it decides on an animation. Positions are art pixels from the fire's centre, in the Camp's geometry.

**Width.** It's one of a few widths, from `pocketColumns` (112, its usual width: six figures, three each side) in steps of `pocketStep` (32: one more figure each side) up to `pocketMaxColumns` (304: eighteen), all in `Core.CAMP_LAYOUT`. `Camp.pocket` takes the narrowest that fits every online Member, but never wider than `maxColumns`, the player's `pocketCampColumns` setting (default 112, so it doesn't grow until the player gives it room). Past that, "+N" counts the rest. The one exception is a set sharing a doorway (below): it grows past `maxColumns`, up to `pocketMaxColumns`, until they fit on one side (at most 9), since a dungeon group of five is what the doorway is for. A flying figure takes two seats, and a shapeshift form more than one, so either can need the next step.

UI never reads a setting or a Member record. `UI/PocketCamp.lua` creates its frame the first time the read isn't nil, so with the setting off (the default) there is no frame at all.

## Rules

- **Who:** the Members whose Roster row is online, you first, then your group, then the rest (see Together, below), then the bedrolls (below). No other sleepers, no Graves or tent. Online Members that don't fit are counted in `more` ("+2").
- **Bedrolls:** a Member whose row goes from online to offline (a logout, or timing out) sleeps in a bedroll, the Camp's sleeper art, for 10 minutes from when this client saw it (`BEDROLL_FOR` in `Core/Pocket.lua`), then is gone. Pose `asleep`, status "asleep · 4m" ("asleep" under a minute), and the same line in the whole-Camp tooltip, after the online figures.
  - Bedrolls take the seats after every online Member, most recent Last seen first, in the room the online Members leave at the width they need. They're the first left out, never counted in "+N", and never make it wider.
  - Coming back online within the 10 minutes swaps the bedroll for the usual figure, which walks in.
  - A Member who leaves the Crew or is removed gets none, and loses one they had.
  - None once your own link has been down 10 minutes (a long lockdown; `DEAF_AFTER`): Members who never left start timing out then for want of being heard. A fight's short lockdown changes nothing.
  - Kept in memory only (Pocket's `bedrolls`), so a `/reload` forgets them.
- **Seated:** online, in the open world.
- **How long** ([#212](https://github.com/Shtian/bff-wow/issues/212)): Pocket keeps, per online Member (you included), when their current pose began as this client saw it (its `poseSince`, from `Camp.poseKeys`). A pose begins on a different key: the pose, with the instance for one adventuring ("adventuring:The Deadmines"). So a DOING with a different state, a change of the row's instance, the start of a fishing or profession spell, or your own state changing starts it over; the same DOING said again, a catch during a spell of fishing, a refresh or a redraw doesn't, and a form doesn't count. It's brought up to date every second in `tick` (with the Pocket Camp on; off, it's forgotten and counts afresh once on) and on each read, and a Member who goes offline is forgotten. From a minute on the status gains the time in Last seen's words ("fighting · 3m", "in The Deadmines · 25m") and the actor `since` (those seconds); under a minute, and by the fire, neither. It's a lower bound: what was already going when you logged in, first saw them or reloaded counts from then. Kept in memory only; nothing is sent or saved, and DOINGs carry no start time.
- **Adventuring:** the Character being played is inside an instance (the row's `instance`). The figure stands in a stone doorway with a torch raised, and `instance` and `status` name the instance for the tooltip. `raid` marks an instance the dungeon table lists as a raid: its doorway is red, with a skull for a keystone.
- **Together** ([#206](https://github.com/Shtian/bff-wow/issues/206)):
  - **Your group.** Members whose shown Character is in your party or raid sit right after you, before everyone else, marked `group`; the tooltip over the figure adds "In your group". Snapshot reads the group (`Snapshot.party`: each unit's GUID and `UnitName`'s first and last name, any of them nil when secret) at start and on `GROUP_ROSTER_UPDATE`, and hands it to `core:group(party)`, which fires `changed` when it differs (the Pocket Camp on). `Camp.grouped` matches a unit to a row's shown Character by GUID, else by full name ("First Last", or the first name where there's no last name) ignoring case, as the channel link compares names. Kept in memory only (Pocket's `party`); nothing is sent or saved.
  - **Order.** You, then your group, then the rest. Within your group, and within the rest: those sharing your instance (or, with you outside one, your group outside one) first, then each set of two or more in the same instance, together, in the order of its first, then the others, each in Roster's order. So a group member outside your instance still sits before a Member who only shares it.
  - **Your side.** With you outside an instance, you and your group outside one sit together on your side of the fire, outward from you. When they don't all fit there, it fills your side first and the rest sit across the fire; it doesn't grow for that. With you in a doorway, your group outside it sits round the fire as anyone else does.
  - **One doorway.** Adventuring Members next to each other in that order and in the same instance (equal `instance` names), you included, are placed all on one side, the roomier or else the other, `doorwayGap` (3) apart rather than the usual `gap` (4). If they don't fit on either side, it grows a step at a time, past `maxColumns` if need be (Width, above), as long as one side of `pocketMaxColumns` can hold them (9). A bigger set, a raid, doesn't grow it: it fills the roomier side and places the rest one by one. Side by side in the same instance, they share a doorway: `doorways` has one per run of such figures, reaching `doorway` (2, in `Core.CAMP_LAYOUT`) past the first and last, so one figure's doorway is 16 wide as the arch has always been. It's red with the skull for a raid. Others in an instance on their own get one each.
  - **Fishing wins.** A figure fishing or at a profession inside the instance isn't adventuring, so it stands in no doorway and isn't pulled up.
  - We can't see others' groups, so Members in the same instance are taken to be together. Not in a group, with nobody sharing an instance, it's exactly as before.
- **Fishing:** for 60 s after Core sees a Member's catches grow. When a Member's record is merged and its total catch count (`Catches.total`: every type's `n`) is higher than in the copy held before, they fish from then; another increase starts the 60 s over, and several catches in one update make one spell. Your own figure fishes for 60 s after `caught()` changes your record. Fishing replaces seated or adventuring while it lasts. Core fires `changed` when a spell ends, so the Pocket Camp redraws.
  - Silent on the first sight of a Member (no copy held before) and until sync has settled after a login (as for Live events), so what's caught up at login isn't "fishing now".
  - Kept in memory only (Pocket's `fishing`), never saved or sent, so a `/reload` forgets it.
  - It's an approximation. The record doesn't say when the latest catch was, and catches ride the next send (within a minute), so the rod comes out when the news arrives.
- **Crafting and gathering:** for 60 s after Core sees a profession's skill grow, exactly as fishing works: a record merged with a higher skill than the copy held (herbalism, mining or skinning is gathering, any other crafting; fishing skill doesn't count), or your own. Status "crafting" or "gathering". The same silences as fishing, and in memory only (Pocket's `working`).
- **Doing** (below): `fighting` ("fighting"), `vendor` ("at a vendor"), `auction` ("at the auction house"), `afk` ("away"), `resting` ("resting") and `flying` ("flying").
- **Which pose wins:** in an instance, the instance, unless a spell of fishing or of a profession is on; what a DOING said is left out there, since the record is newer than anything said before going in. Elsewhere flying, the auction house and a vendor come first (the Member chose them), then fishing, a profession, fighting, away, resting, and by the fire.
- **Spark:** a `maxLevel` Feed entry in the last 24 hours, as in the Camp.
- **On an Alt** ([#207](https://github.com/Shtian/bff-wow/issues/207)): an actor whose Roster row has `onAlt` (the Character shown isn't the Member's Main) has `onAlt = true`, and its whole-Camp tooltip line says so: "Bob (on alt): by the fire". The figure (or bedroll) has "ALT" over its head (below). Which Alt isn't said; the tooltip over the figure names the Character. It's the Roster's own read, so nothing new is sent, and it follows the next record that arrives when a Member switches Character. With the `pocketCampAlts` setting off (Settings, below) there's neither: `onAlt` is nil and the line is the usual one. Core passes it to `Camp.pocket` as `shown.alts`.
- **Spares crate** ([#208](https://github.com/Shtian/bff-wow/issues/208)): while `unseenSpares()` is above 0 (new Spares, Claims and Gives not yet told by a chat line or toast, nor shown in the Spares tab), `spares` is that count and a crate stands by the fire. It takes no seat and doesn't change the width. `sparesTooltip` words it: "1 Spare notice" or "2 Spare notices", and the hint "Click to see it in Spares." (or "them"). With the `pocketCampSpares` setting off (Settings, below) there's no crate: both are nil, and the notices stay unseen for the sidebar and the Spares tab. Opening the Spares tab marks them seen (`sparesSeen()`), which fires `changed`, so it redraws without the crate. A notice that arrives fires `changed` with the record it came in. Which item, or who, isn't shown. Nothing new is sent: the notices are the ones Spares already keeps.
- **Trophy cup** ([#209](https://github.com/Shtian/bff-wow/issues/209)): while at least one of this session's Trophies is up, `trophies` lists them and a gold cup floats over the fire, sparkling. It takes no seat and doesn't change the width. A Trophy counts when it isn't quiet, was reached under an hour ago (`TROPHY_CUP_FOR` in `Core/Pocket.lua`), and was reached at or after `trophiesSince`: when this session's Feed settled after a login, or the session's start after a `/reload` (which catches nothing up). So one caught up at login (reached while you were away) doesn't show, even a goal rung, whose time is when your client recorded it. The cost: one reached in the 10 to 30 s before the Feed settles, a clear or Rare kill made then, or your own, doesn't show either. It's a best effort, since records hold no time for a goal rung: a catch-up still arriving after the Feed settled (it settles at most 30 s after the link comes up), or a friend whose record nobody online held at your login logging in later, can show a rung that was really reached while you were away. Clears, Rare kills and goal rungs all count: it's the Trophies tab's shelf (`Goals:trophies()`), and a clear or a kill counts from the time it was made, not when it reached you.
  - Several make one cup. Each is `{ name, ago }`, newest first: `name` is the Trophies tab's title and label ("Crew deaths: 25", "Dungeons cleared: Deadmines", "Rares slain: Rak'shiri"), and `ago` is "just now" under a minute, else "12m ago". `trophiesTooltip` has a line per Trophy ("Crew deaths: 25 · 12m ago"), the title "A Trophy reached" or "2 Trophies reached", and the hint "Click to see it in Trophies." (or "them").
  - It goes at the hour: the read is derived each time, and the Pocket Camp's 30 s redraw picks that up. A `/reload` forgets the session's (`trophiesSince` is in memory only). The goal flare plays as before.
  - Nothing new is sent: the Trophies are the ones the Trophies tab already shows. No setting of its own.
- **Hop:** a Cheer, as in the Camp (`Panel.cheered` passes it on).
- **Lag:** records update on the 5-minute heartbeat and within about 10 s of a zone change, and nothing arrives from a friend in a boss encounter's lockdown. The Pocket Camp shows what's known and claims no more.

## Doing

What a Member is doing right now isn't in their record: it changes too often and is worth nothing a minute later. `Core/Doing.lua` handles it the way Where handles live map spots.

- **Read.** App calls `core:doing(Snapshot.doing())` every second: `{ combat, vendor, auction, afk, resting, flying, form }`. Combat is `InCombatLockdown()`, the vendor's and auction house's windows are kept from their show and close events, afk is `UnitIsAFK("player")` (the game's own away flag: `/afk`, or idle for a while), resting is `IsResting()` (an inn or a city), and flying is `UnitOnTaxi("player")` or, where the client has it, `IsFlying()`. form is from `GetShapeshiftFormID()`: cat (1), travel (3), aquatic (4, `seal`), bear (5, and dire bear's 8), moonkin (31, 35) and Ghost Wolf (16), or Ghost Wolf's aura (spell 2645) where the form reads as none. Other forms (tree of life, flight) are none. A read that's secret or errors gives the last form read outside combat.
- **One state.** Core shows the first that's true of flying, the auction house, a vendor, fighting, away and resting. Fighting lasts 20 s past the end of combat, so pull after pull is one spell of it and not a message each.
- **Your own figure** shows it at once, with or without anyone online.
- **Sent** as `{ type = "DOING", doing, quest, at }` to everyone when the state changes, under WHERE's conditions (link up, in a Crew, not paused, someone else online), at most every `max(15, 5 × others online)` seconds; what's sent then is the state at that moment, so a quick visit in between is never told. The first DOING of a session goes out even when there's nothing to say, so a `/reload` or a quick relog clears what the Crew held from before. While something is being done it's said again every 2 minutes, and right after a Member comes online.
- **Form.** The shapeshift form is the one exception to "no new traffic for UI": it rides in the same DOING, as `form` (`wolf`, `bear`, `cat`, `travel`, `seal`, `moonkin`, or nil), and adds DOINGs of its own only when it's worth it. Ghost Wolf and the combat forms (bear, cat, moonkin) are due as soon as you shift, within the same `max(15, 5 × others online)`. A travel form (travel, aquatic) is due only once it's been held for 30 s, so mounting up and getting off again sends nothing. The end of a form is never due: a DOING that goes out for another reason says there's none, and otherwise what's heard runs out (below). A form begun since the last DOING is due again, even the same one. While you're in a form it's said again every 2 minutes, as a state is. Your own figure shows the form at once, travel forms too.
- **Heard** DOINGs are held in memory per Member. One runs out 5 minutes after it was heard, since the DOING that ends it can be lost, and goes when the Member goes offline or is removed. An older `at` than the one held is ignored. A state this version doesn't know shows as by the fire. A form heard runs out sooner, 2.5 minutes after it was heard (separate from the 5 minutes), so a druid who has shifted back isn't left a bear for long; a form this version doesn't know is none, and so is a DOING with no `form`, as an older BFF's.
- **Quest handed in.** `core:questHandedIn()` (on `QUEST_TURNED_IN`) plays the `quest` animation on your own figure and marks the next DOING `quest = true`, which plays it on the Crew's. Several in a row are one DOING, and one that can't go out within 90 s isn't told.
- **Not in the record,** so nothing is saved, DIGESTs never ask for it, and older BFFs ignore the unknown type and keep showing the figure by the fire. The protocol version is unchanged: an older BFF that knows DOING ignores `form`.
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
| arrive (not a Feed kind) | that Member walks in from the band's nearer edge to their place (2.5 s), then stands there waving with a "hi!" speech bubble over their head; 6 s in all |

A mark over a raised figure (flying) is kept inside the band, so it sits over the head and not above it.

The lengths are CampScene's (`ANIMATION_FOR` in `UI/CampScene.lua`). A second animation of the same kind for the same Member starts it over. They're kept in UI only, so a `/reload` drops one that's playing.

Reactions that reach you live play here too, through their own event, `campReaction`: a Cheer's hop with its burst, and a Welcome's wave with "hi!" (4 s). See docs/design/camp.md, Reactions, live.

No other kind animates. Core decides, in `animate()`:

- Only while `pocketCamp()` isn't nil.
- A Member's animation only when they're an actor of the Pocket Camp at that moment. Sleepers and Members counted in "+N" get none.
- Others' entries only once sync has settled, so first sight and login catch-up (While you were away) animate nothing. Your own entries always count.
- **Arrive** fires when a Member held before (not first sight) goes from offline to online in Roster's eyes (`onlineChanged`), once sync has settled and only once your link has been up for 2 minutes (`HEAR_ALL_WITHIN`): everyone online sends a DIGEST about once a minute, so by then anyone online when your link came up (a login, a `/reload`, the end of a long lockdown) has been heard, and one first heard sooner may have been online all along. The 2 minutes count from before a break shorter than `DEAF_AFTER` (10 minutes, a fight's lockdown), which can't have let anyone time out, so a friend logging in right after a fight still walks in. Never for your own figure, and a bedroll's Member gets no other animation.
- **Independent of the chat-line and toast settings.** `feedEntry` is only fired while one of those is on, so the animation has its own event. It marks nothing seen: with both off the entry still waits for While you were away.

For these nothing new is sent: the entries are the ones Feed already makes, and arrivals and bedrolls come from who Roster already shows online.

## Settings

In a section of their own on the Settings page, Pocket Camp, after Toasts (`docs/design/settings-and-release.md` has how each is saved):

| Key | Label | Default |
|---|---|---|
| `pocketCamp` | Show the Pocket Camp | off |
| `pocketCampOpacity` | Backdrop opacity (0 to 100, a slider) | 60 |
| `pocketCampLocked` | Lock its position and size | off |
| `pocketCampCombat` | In combat: Stay, Fade or Hide (a segmented control) | Stay |
| `pocketCampCombatFade` | Fade to (0 to 100, a slider), on the page only while In combat is Fade | 25 |
| `pocketCampAlts` | ALT over a friend playing an alt | on |
| `pocketCampSpares` | A crate by the fire for unseen Spare notices | on |
| `pocketCampPosition` | not on the page: where it was dragged to | nil |
| `pocketCampScale` | not on the page: how big it was scaled to, a whole percent from 50 to 300 (`Core.POCKET_CAMP_MIN_SCALE`, `POCKET_CAMP_MAX_SCALE`) | 100 |
| `pocketCampColumns` | not on the page: how wide it can grow, in art pixels, one of the widths above (other numbers snap to the nearest) | 112 |

All account-wide. With `camp` off the Pocket Camp never shows, whatever its own setting says.

`pocketCampAlts` and `pocketCampSpares` are **Shown in the Pocket Camp**, a section of its own after Pocket Camp: what the figures are marked with and what stands by the fire, each on by default so a player can opt out. Both are greyed out while the Pocket Camp is off (`needs = "pocketCamp"`). The next mark worth a choice is one more entry there, read in Pocket's `pocketView` into `shown` (a figure's) or in `Pocket:view()` (the fire's, as the crate is).

## UI

- **Frame.** `UI/PocketCamp.lua`: a button on `UIParent`, strata LOW, clamped to the screen, with a CampScene band filling it (`CampScene.new(frame, { target = FIGURE_TARGET, shadow = true, names = false })`). Its art pixel aims for 2 UI units, as on rows and toasts, so at its usual width it's about 224 by 68 UI units; `band:Fit(columns, rows)` gives the exact size. "+N" has a shadow, since the game world is behind it.
- **No names.** With a figure every 16 art pixels there's room for about four letters each, so the Pocket Camp shows none; the tooltip says who a figure is.
- **Backdrop.** Its own art, `Media/CampPocketBackdrop.tga` (`CampSheet.pocketBackdrop`, passed as CampScene's `backdrop` option): the bottom 34 rows of the Camp's backdrop round the fire, cut to a rounded shape that's solid in the middle and dithered away at the rim, so it doesn't sit on the game world as a hard rectangle. The file holds one band per width, top to bottom (36 texels each, the art at the bottom); a wider band is the narrowest's rounded ends with more solid middle between them, so the rim looks the same at every width. CampScene picks the band for `view.columns` with `SetTexCoord`. `scripts/camp-art.mjs` generates it (`pocketBackdrop`: the roundness, the fade's width and how solid the ground stays are constants there), and its widths must match `pocketColumns`, `pocketStep`, `pocketMaxColumns` and `pocketRows`. No sky is filled in behind it. It's drawn at `opacity` (`band:SetBackdropAlpha`). At 0 only the fire, the figures and "+N" show.
- **Click** toggles the panel, as the minimap button does. A click on the crate opens the panel on the Spares tab instead (`Panel.show("spares")`, not a toggle), and a click on the cup on the Trophies tab (`Panel.show("goals")`). In combat (`InCombatLockdown()`) it does nothing.
- **Right-click** on another Member's figure opens a context menu (`MenuUtil.CreateContextMenu`, as the Roster's rows do) titled with the Character's full name ([#210](https://github.com/Shtian/bff-wow/issues/210)). Core puts what it needs on the actor as `menu`: `fullName` (the Character's "First Last", its title: on Forever the first name alone reaches no one) and `mapId`, the map the Member's map pin is on, their live WHERE spot if one was heard since the record, else the record's, whatever the `mapPins` setting (inside an instance that's the last spot outside it, as the pin shows). Its entries:
  - **Whisper** and **Invite**: the Roster's own (`Actions.whisper` and `Actions.invite` in `Game/Actions.lua`, shared, not copied), on `fullName`. Ordinary game actions you take: BFF sends nothing new.
  - **Show on map**: opens the world map on `mapId` (`Actions.openMap`: `OpenWorldMap`, or `WorldMapFrame:SetMapID` where it's missing). Greyed out when `mapId` is nil (no spot ever known).
  - **Open in panel**: opens the panel on the Roster (`Panel.show("roster")`).

  There's no Remove, Cheer or When here; those stay in the panel. Your own figure, a bedroll, the fire, the crate, the cup and empty space have no `menu`, and a right-click there does nothing. In combat no menu opens, and an entry picked after combat began does nothing. A right-click never starts a drag (only the left button drags), and the tooltip hides while the menu is up.
- **Crate.** The `crate` sprite (8 by 7: a wooden crate, its lid lifted on something gold, outlined) stands in front of the fire's right half, its left edge one column left of the fire's centre and its bottom 1 row up (`CRATE_X` and `ROW.crate` in `UI/CampScene.lua`), over the logs and the fire's base. That keeps it clear of the first seat on the right and of a doorway there. `band:CrateAt(x, y)` says whether the mouse is over it, and over it the tooltip is `sparesTooltip`'s title and hint.
- **Trophy cup.** The `trophyCup` sprite (13 by 9: a gold cup with handles on a stepped foot, outlined) floats over the fire, in front of the flames and embers (texture layer ARTWORK 3), its left edge 6 columns left of the fire's centre and its bottom 19 rows up, bobbing up a row and back every 4 ticks (`CUP_X`, `ROW.cup` and `CUP_BOB` in `UI/CampScene.lua`). For 4 ticks in every 18, `cupSparkle1`/`cupSparkle2` twinkle at two spots beside it (`CUP_SPARKLES`), clear of the first seat each side. It's over the fire's centre, so it stays clear of the seats, a doorway and the crate, but it hides the embers' rise. `band:CupAt(x, y)` says whether the mouse is over it (the row it bobs up to included), and over it the tooltip is `trophiesTooltip`'s title, a white line per Trophy and the hint. Chosen from seven prototypes (a pennant, a medal, a cup on a plinth, bunting, a mounted dragon head, a dragon head on a pike), since it ties the Trophy to the fire, as the goal flare does, and stands nothing new on the ground.
- **Drag** moves it unless `locked`. Where it's dropped is saved with `core:setPocketCampPosition(left, bottom)`: the bottom left corner it would have at its usual width, so it's anchored on the fire's centre and grows out both ways as the Crew comes online (saved positions from before widths are the same thing). Until it's dropped it sits under the screen's centre. Locked, a click still works.
- **Scale and width.** Unless `locked`, a grip (the chat window's size grabber) shows in its bottom right corner while the mouse is over it, its tooltip saying what dragging does. A press on the grip draws it at once at its max width (`maxColumns`), so the room it has shows, and dragging resizes it live with its top and the fire kept where they were at the press: it grows and shrinks both ways from the fire. Up and down scales it, in whole percents between 50% and 300%: its height grows or shrinks by as much as the mouse moves. Sideways raises or lowers the max width from what it was at the press, a step at a time (`Core.pocketCampWidth`); since it grows both ways, the width changes by twice what the mouse moves, keeping its right edge under the mouse. The tooltip says "Room for 10" (`Core.pocketCampSeats`, seated figures, from the layout) and the size. A redraw during the drag (the 30 s one, combat, a setting) keeps the dragged size. The band's target becomes `FIGURE_TARGET × scale` (`band:SetTarget`), and the band is made with `crisp = false`, so its art pixel is exactly that many UI units rather than a whole number of screen pixels: it scales smoothly, but some art pixels come out a screen pixel wider than others. Chosen over crisp steps after trying both in game: the steps were too coarse to scale with. On release `core:setPocketCampPosition`, `core:setPocketCampScale(scale)` and `core:setPocketCampColumns(columns)` save where it is and what changed, and it fits who's online again round the same fire, so it can come back narrower than it was dragged to. A press that changes neither saves nothing. A double-click on the grip goes back to scale 1 and the usual width, keeping its top and the fire where they are.
- **Why both.** The width follows the Crew so a small group doesn't get an empty stretch of screen, and a cap the player sets so a big group can't push it into the action bars it was placed next to (player feedback: "make it longer, not just larger").
- **In combat** ([#211](https://github.com/Shtian/bff-wow/issues/211)). `inCombat` says what the frame does between `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`:
  - **Stay** (the default): nothing changes.
  - **Fade**: the whole frame (backdrop, figures, sprites, "+N", grip) drops to `combatFade` (`frame:SetAlpha`), and goes back to full when combat ends. The backdrop's own `opacity` still applies under it, so the backdrop shows at `combatFade × opacity`. Faded, it works as usual: it keeps drawing and animating, the tooltip shows, and a click or right-click does nothing, as in any combat. At 0 it can't be seen but stays where it is.
  - **Hide**: the frame hides. Hidden, its `OnUpdate` doesn't run.

  A save from before the choice, Hide in combat on (`pocketCampCombatHide = true`), reads as Hide, and off as Stay, so nobody's choice changes. The Settings page shows Fade to only while Fade is picked: Core's `settings()` marks it `hidden` otherwise.
- **Tooltip.** Over the crate, `sparesTooltip`. Over the cup, `trophiesTooltip`. Over a figure, its status as a line first when it has a time (`since` set: "fighting · 3m"), then that Member's tooltip exactly as the Roster shows it (`CharacterTooltip.add(actor.row, actor.row)`: the Character being shown, level, zone, professions and so on), then the hint. Over a bedroll, "Bob: asleep · 4m", then the hint. Anywhere else, Core's `tooltip`: the title, a line per figure, "+N" and the hint. `band:ActorAt(x)` says which figure the mouse is over (half the gap each side counts), and the tooltip follows the mouse from one to the next.
- **Poses.** CampScene's `POSE` table says how each is drawn: whether the figure stands (the hop figure, no seat) or sits, a sprite in its raised hand, one behind it and one over it. Sprites that face the fire are mirrored on its right.

  | Pose | Figure | Sprites |
  |---|---|---|
  | adventuring | standing | `torch` in hand, and its doorway (below) behind |
  | fighting | standing | `blade` in hand |
  | crafting | standing | `hammer` in hand, `anvil` at its feet |
  | gathering | standing | `pick` in hand |
  | fishing | seated | `rod` out towards the fire |
  | vendor | seated | `bag` at its feet |
  | auction | seated | `coins` at its feet |
  | resting | seated | `innSign` behind, its board over the head |
  | afk | seated | `afk`, the word AFK in pixel letters, over its head, bobbing a row once a second; it's the head mark's last case, so a one-off mark takes its place while it plays |
  | flying | seated, raised 9 rows | `griffin` under it, `griffinWing` over its legs, lifting to `griffinWingUp` for 3 ticks in 9 |

  A doorway (`view.doorways`) is drawn behind its figures from slices of `arch` (`archRaid` for a raid), so it can be as wide as Core says: the sprite's 4 columns at each edge, its middle 8 (the keystone, or the skull) at the doorway's centre, and the column next to each rim stretched over the rest (`drawDoorway`, `DOORWAY` in `UI/CampScene.lua`). One figure's doorway is the sprite as drawn.

  **On an Alt.** A figure with `onAlt` has the `alt` sprite over its head: the word ALT in AFK's pixel letters, in pale blue so it reads as a label and not an alert (`ALT` and `drawAlt` in `UI/CampScene.lua`). It's a row over the head, or over what the pose holds up there (a torch, blade, hammer or pick, or the inn sign), kept inside the band as other marks are, so over the inn sign it sits on the sign's beam. A bedroll has it over the z's, where the Camp puts a sleeper's name. A head mark (the star, fish, quest mark, smoke or AFK) takes its place while it shows, as do a death's skeleton and an arrival's walk and wave. (A small gem by the face was tried first; it didn't say "alt" without explaining.)

  The griffin reaches 8 art pixels past the figure towards the fire and 6 away from it (`griffinFore` and `griffinAft` in `Core.CAMP_LAYOUT`), and Core keeps that clear when it places the figure. New tools have a dark outline (`outlined()` in the art script) so they read with the game world behind them.
- **Shapeshift forms.** A figure with `form` is drawn as that form instead (`FORM` and `drawForm` in `UI/CampScene.lua`), seated or fighting, with no seat, tool or class colour: the animal says who it is. Its sprite stands on the ground centred on the figure's 12 columns, faces right as drawn and is mirrored on the fire's right to face it, and is kept inside the band. They're alive, take C of the prototype (`prototypes/shapeshift-sprites.html` on [#217](https://github.com/Shtian/bff-wow/pull/217)'s branch), on the band's 6 ticks a second:

  | Form | Sprites | Moves |
  |---|---|---|
  | wolf | `wolfRun1`/`wolfRun2`, with `wolfGlow1`/`wolfGlow2` behind | trots; see-through at alpha 0.6, its glow at 0.15, both a little brighter for 2 ticks in 9 |
  | bear | `bearStand1`/`bearStand2`, `bearRear`, `bearSwipe`, `bearClaws` | breathes (a frame every 9 ticks); every 10 s rears up for 3 ticks, swipes for 2 with claw marks in front of its paw, rears for 2 more |
  | cat | `catElf1`/`catElf2` (an Alliance viewer), `catLion1`/`catLion2` (a Horde one) | the tail swishes for 3 ticks in 24 |
  | travel | `travelRun1`/`travelRun2` | trots |
  | seal | `seal1`/`seal2` | waves a flipper for 3 ticks in 24 |
  | moonkin | `moonkin1`/`moonkin2` | blinks for 3 ticks in 24 |

  A trot goes to and fro over 4 columns from the figure's place, away from the fire, a step every 2 ticks, facing the way it goes. The cat is chosen by the viewer's own `UnitFactionGroup("player")`: faction isn't synced, and a Crew whispers within one faction. Each actor's animation is offset by its place, so they don't move in step. The sprites are 14 to 18 columns wide on a 12-column figure, so Core keeps `formFore` (3) clear towards the fire and `formAft` (3) away from it, plus `formTrot` (4) for one that trots (`Core.CAMP_LAYOUT`), and neighbours never cover each other. Head marks, ALT and an arrival's walk work as on a figure; a death's skeleton takes the form's place. When an actor's form changes between two draws, `leaves1`/`leaves2` puff over it for a second (`spirit1`/`spirit2` to or from Ghost Wolf), fading after 4 ticks; not for a figure that has just come into view. Only the Pocket Camp shows forms: the panel's Camp and While you were away show no Doing.
- **Animations.** `band:Animate(kind, memberId)` keeps each for its length and draws it on the band's 6-per-second tick: an arrival's `walk1`/`walk2` steps in from the edge (mirrored coming from the right, the seat waiting for them), then `wave1`/`wave2` with the `hi` bubble over the head; `star`, `fish`, `quest`, `smoke1`/`smoke2` over the head, `skeleton` in the figure's place (one untinted layer, no tool, whatever the pose), alternate-tick alpha for the flicker, seven sparks flying out for each burst, and `flare1`–`flare3` in the fire's place.
- **Sprites.** The poses' sprites above, `crate`, `trophyCup`, `cupSparkle1`, `cupSparkle2`, `afk`, `alt`, `star`, `quest`, `fish`, `smoke1`, `smoke2`, `skeleton`, `flare1`–`flare3`, the arrival's `walk1`, `walk2`, `wave1`, `wave2` (each with a cloth layer) and `hi`, and the forms' sprites and puffs (each form with its own palette, `FORM_PAL`, copied from the prototype; Ghost Wolf's glow is a ring one pixel out from its outline) are grids in `scripts/camp-art.mjs` (the flare is each fire frame with its upper rows doubled, painted in purples). Run it after changing one.
- **Redraws** on Core's `changed`, `crewChanged` and its settings, on a UI scale or display change, and every 30 s while shown.
- **Silence.** It plays no sound.

## Tests

`tests/pocket_camp_spec.lua` drives real Cores through FakeNet: who is in `pocketCamp()` and when it's nil, "+N", adventuring, the spark, each actor's Roster row, the right-click menu (another Member's figure only, the full name, the pin's map from the record or a live WHERE, kept in an instance, and with the map setting off), how it's shown, fishing (the 60 s, the restart, your own, first sight, login and reload), each animation and when none plays, arrivals and bedrolls (once, first sight, login, reload, lockdown, the 10 minutes, coming back, removed and left, seats and width, and that nothing more is sent), and playing together (your group's seats and mark, the name match, shared and single doorways, fishing in the instance, widening, the read unchanged out of a group, the redraw and that nothing more is sent), what it does in combat (Stay, Fade or Hide, an old saved Hide in combat, and that nothing more is sent), a Member on an Alt (the actor's `onAlt`, the tooltip line, your own, back on the Main, and none with its setting off), and the Spares crate (its count and wording, the redraw when a notice arrives and when the tab marks them seen, none with its setting off, none for notices told in chat or a toast, and that nothing more is sent), how long a Member has been at it (no time under a minute or by the fire, a repeated DOING not resetting it with nobody reading, a new state or instance starting over, fishing through a catch, your own, after a reload, and that nothing more is sent), and the trophy cup (a Trophy reached this session for its hour, the Trophies tab's names, several newest first with the tooltip's wording, a clear by when it was made, none for one caught up at login, from before a `/reload` or quiet, and that nothing more is sent). `tests/doing_spec.lua` covers Doing the same way: your own figure, the one DOING and what it leaves alone, which state wins, the fighting hold, the rate, the refresh and running out, newcomers and going offline, pause, lockdown and being alone, an unknown state, the redraw, a quest handed in, the profession spells, raids and the griffin's room, and a shapeshift form (your own figure, sending a combat form or Ghost Wolf at once and a travel form after 30 s, never the end, running out after 2.5 minutes, the refresh, an older DOING with none, which poses it shows over, and its room). `tests/settings_spec.lua` covers the new settings, In combat's choices, its old saved Hide in combat, and Fade to shown only while Fade is picked. Frames and art aren't tested offline; in game, `/bff sim` and `/bff sim fish` make simulated Members fish, and the dev console's Doing, Form and Quest buttons step one through what it can be doing, through the shapeshift forms, and hand in a quest. Its action bar's **Inst** button steps the selected simulated Member into The Deadmines, then Molten Core (a raid), then back out, and **Group** puts them in or out of your group (their row says "in your group"): the sim tells your Core the real group plus those, every second, so a real `GROUP_ROSTER_UPDATE` doesn't drop them, and stopping the sim leaves the real group alone. Two in one instance share a doorway; your own figure's doorway needs you in a real instance.

## Still to check in game

None of the rendering has run in a client, and the new sprites were authored as grids without being seen at size. On Forever:

- With the setting off, no `BFFPocketCamp` frame exists.
- Pixels stay crisp at a few UI scales and across drags (the frame's corner can land between screen pixels; the art's origin frame rounds to the nearest).
- It's readable over bright and dark scenes at 0%, 60% and 100% opacity, and the backdrop's dithered rim looks right at size.
- Dragging, the lock, and the position after `/reload` and on another Character.
- A click in and out of combat; In combat on Stay, Fade and Hide. Faded: that the whole frame fades (backdrop, figures, sprites, "+N", grip), at 0 too, that it comes back to full when combat ends, that the tooltip still shows, and that Fade to shows on the Settings page only while Fade is picked.
- Each pose and animation reads at size: the rod towards the fire on both sides, the star, fish, smoke, skeleton, bursts and flare, and that 10 s feels right for each.
- The Doing poses on both sides of the fire: the AFK text, the torch and doorway (and the raid's), blade, hammer and anvil, pick, bag, coins, inn sign and the griffin with its wing flapping, and the quest mark.
- That the events and reads behind Doing behave on Forever: `MERCHANT_SHOW`/`MERCHANT_CLOSED`, `AUCTION_HOUSE_SHOW`/`AUCTION_HOUSE_CLOSED`, `QUEST_TURNED_IN`, `IsResting()`, `UnitIsAFK("player")`, `UnitOnTaxi("player")` and whether `IsFlying` exists, and that none of them reads secret in the open world.
- Each shapeshift form at size on both sides of the fire: the trot staying clear of its neighbours at the end seats, the bear's swipe and claws, Ghost Wolf's see-through look and glow over bright and dark scenes, both cats, and the puffs.
- That `GetShapeshiftFormID()` gives the IDs above on Forever (Ghost Wolf 16, moonkin 31), whether it or Ghost Wolf's aura reads secret in combat, and that a travel form's 30 s keeps mounting up from showing in the sync trace.
- That a DOING gets through in ordinary combat (the retail spike found chat unlocked there), and what a levelling session's DOING traffic looks like in the sync trace.
- The tooltip over each figure and over the fire, and that it changes as the mouse moves between them.
- No measurable CPU cost while it's hidden.
- An arrival: the walk frames and speed from each edge at a few widths, the wave and the "hi!" bubble at size, and that 6 s feels right. That a friend logging in shortly after you (within 2 minutes) not walking in doesn't look like a bug.
- A bedroll in the Pocket Camp beside seated figures, its z's inside the band, and its tooltip.
- The Settings slider's thumb, track and fill in the panel's Settings view.
- How the Pocket Camp growing past its max width for a dungeon group of four or five looks next to the action bars it was placed by. A press on the grip draws it at the max width, which can then be narrower than the doorway's set, clipping them until the release.
- A shared doorway for two, three, four and five figures, normal and raid: that the stretched lintel and the centred keystone or skull read well, and the torches inside it.
- That `GROUP_ROSTER_UPDATE` fires on joining, leaving and a raid conversion on Forever, and whether `UnitGUID` or `UnitName` of party and raid units read secret in an instance (the name match is the fallback). That `UnitName` on a party unit gives the last name as its second value, as it does for `"player"`.
- The "In your group" line in a figure's tooltip.
- How long ("fighting · 3m") in the tooltip over the fire and as the first line over a figure, and that it ticks on with the 30 s redraw while the tooltip is up. Over a figure the status line is the GameTooltip's first line, so it takes the title font and the Character's name drops to an ordinary line: check that it reads well, or move it below the name. That a pull-after-pull fight with its 20 s hold reads as one spell, and that a friend's DOING arriving a few seconds late doesn't make the time look wrong.
- The right-click menu on a figure: that `MenuUtil.CreateContextMenu` works on the Pocket Camp's frame on Forever, that Whisper opens a tell to "First Last" and Invite (`C_PartyInfo.InviteUnit`) invites by the full name, that Show on map opens the world map on that map (`OpenWorldMap`, and the `WorldMapFrame:SetMapID` fallback), greyed out with no spot, and that Open in panel opens the Roster. That a right-click in combat, on your own figure, a bedroll or the fire opens nothing, and doesn't start a drag.
- ALT at size in every pose: seated, in a doorway over the raised torch, fighting, crafting, gathering, flying, resting (on the inn sign's beam), and over a bedroll's z's. That the pale blue reads over bright and dark scenes, that ALT over a raised tool still looks like the figure's, and that it goes while a head mark or AFK shows. `/bffdev`'s **Alt** button switches the selected simulated Member to their next Character, which shows ALT for one with a Main set.
- The Shown in the Pocket Camp section on the Settings page, its switch greyed out while the Pocket Camp is off, and ALT going and coming back at once when it's turned off and on.
- The Spares crate going and coming back at once when its setting is turned off and on.
- The Spares crate at size in front of the fire: that it reads as a crate, doesn't hide too much of the fire, and stays clear of the first figure on the right, a form's room and a doorway. That its tooltip shows over it and the usual one beside it, and that a click on it opens the Spares tab while a click on the fire or a figure still toggles the panel. With chat lines and toasts off, the dev console's buttons for a simulated Member offering a test Spare or claiming your newest one should bring it up.
- The trophy cup at size over the fire: that it reads as a cup over the flames and not as part of them, that the bob and the sparkles aren't distracting while you play, and that the sparkles stay clear of the first figures' raised tools, ALT and head marks. That its tooltip shows over it and the usual one beside it, and that a click on it opens the Trophies tab. That it goes about an hour after the Trophy (within the 30 s redraw). A goal rung reached with the dev console (a simulated Member's level or deaths) should bring it up.
