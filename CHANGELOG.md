# Changelog



















































## 2.20.0
<sub>2026-11-28</sub>

- *(minor)*
  Gathering in the Pocket Camp is animated

  A friend whose mining, herbalism or skinning goes up now shows which one: a miner swings a pick at a rock, chips flying and now and then a piece of ore; a herbalist kneels and picks flowers into a basket until the patch grows back; a skinner kneels over a boar with a knife. The status says "mining", "picking herbs" or "skinning" instead of "gathering".
- *(minor)*
  Crafting in the Pocket Camp is animated

  A friend whose alchemy, blacksmithing, enchanting, engineering, leatherworking, tailoring, cooking or first aid goes up now shows which one: an alchemist kneels at a bubbling flask that puffs and changes colour, a smith swings a hammer at a hot bar on an anvil, an enchanter points a rod at a glowing gem over a rune, an engineer works a gadget with a wrench until it bangs, a leatherworker scrapes a hide on a frame, a tailor sits at a spinning wheel, a cook stirs a pot over a little fire, and a first aider winds up a bandage. The status names it ("brewing potions", "smithing", "tinkering" and so on) instead of "crafting". Crafters take a little more room by the fire, so with several at once one friend may wait in "+1" until they're done.

## 2.19.2
<sub>2026-11-27</sub>

- *(patch)*
  Fishing in the Pocket Camp is easier to see

  A friend who's fishing now sits by a little pond: their rod arcs out over the water, the line hangs down to a bobber with ripples round it, and now and then a fish leaps. The old dark rod was hard to spot, and its line landed on the fire.

## 2.19.1
<sub>2026-11-27</sub>

- *(patch)*
  Internal: the link now goes down once chat messaging lockdown is in effect, even when the game turns it on after the restriction event, and sends nothing until it ends.
- *(patch)*
  Appear offline now shows you offline at once

  Turning on Appear offline used to leave you showing online to your friends for up to 12 minutes. Now BFF steps out of the Crew's channel, so they see you offline straight away. While it's on you don't get their updates either; you catch up as soon as you turn it off.
- *(patch)*
  Friends in a battleground no longer show as offline

  A friend in a battleground or other PvP match used to drop to offline after 12 minutes, because the game keeps BFF from sending anything there. Now they stay online for as long as they're in the Crew's channel, shown as "online · quiet" (or "by the fire · quiet" in the Camp) until you hear from them again. They still go offline when they log out.

## 2.19.0
<sub>2026-11-27</sub>

- *(minor)*
  Each Ruleset and faction now has its own Crew

  Play a Character on another Ruleset or faction and BFF shows the Crew you have there, or lets you start or join one. Your Crew stays on the Ruleset where your friends are, and on the others BFF tells you where it is. If BFF can't tell where your Crew belongs, it asks you once. If it lands on the wrong faction, you can bring it over from the other one until a friend is heard. Settings are shared by all your Crews, apart from Appear offline, which each Crew keeps. /bff report now shows which Ruleset you're on.
- *(patch)*
  Internal: Saved data now keeps each Crew in its own slot, with a Ruleset entry per Ruleset and faction that points at its active and left slot, and a changed Ruleset key is repaired by server ID or name. The first login after updating moves the existing Crew into a slot once and leaves the old saved keys in place.

## 2.18.0
<sub>2026-11-25</sub>

- *(minor)*
  Camp names now sit on pixel name tags you can read by day

  Each name in the Camp sits on a small dark tag with a pointer down to its figure, in the Tiny5 pixel font, class-coloured as before. Names used to be hard to read against the day sky; now they read the same by day, at night and in winter. The lunar lanterns step aside only when a tall hat or a flying friend lifts a name into them.

## 2.17.0
<sub>2026-11-24</sub>

- *(minor)*
  When the game breaks your Crew's hidden chat channel, BFF now moves the whole Crew to a new one by itself: no new code, nothing lost. If the game keeps refusing, the Roster says so and offers Report a bug.
- *(minor)*
  Leaving a Crew no longer forgets it: join again with the same code and your Crew, Feed, While you were away, reactions, goals and Removed list are all back. Starting or joining a different Crew still starts fresh.

## 2.16.7
<sub>2026-11-24</sub>

- *(patch)* Dying with a pet out no longer counts as two deaths.

## 2.16.6
<sub>2026-11-24</sub>

- *(patch)*
  Internal: Log each Crew channel join attempt and its outcome, and every Crew channel notice, in the sync log, and show the last join failure in /bff report
- *(patch)*
  Fixed being stuck on "Leaving the Crew" when BFF can't join its channel (wrong password or too many channels): leaving now finishes straight away, so you can start or join another Crew. The wrong-password message now says to leave the Crew and start a new one

## 2.16.5
<sub>2026-11-23</sub>

- *(patch)* Internal: Read shapeshift forms on the DOING tick again instead of after form events

## 2.16.4
<sub>2026-11-23</sub>

- *(patch)* Internal: Gate form and Ghost Wolf aura reads by class, events, and combat

## 2.16.3
<sub>2026-11-22</sub>

- *(patch)*
  Map pins no longer get stuck in the middle of the screen.

  With OpenMap installed, a Member's map pin could stay on screen after a fight with the map open, until the map was opened again.

## 2.16.2
<sub>2026-11-22</sub>

- *(patch)*
  While you were away is tidier after an update. When the update is all there is to show, its gold button opens What's new. With Crew news too, the update sits on its own band under the Camp, its What's new button at the band's foot. The change wraps instead of being cut off, the line above the scoreboard reads as a heading, and the buttons have more room.

## 2.16.1
<sub>2026-11-21</sub>

- *(patch)*
  More of Forever's new dungeons now count as Clears.

  Clearing Excavation Site, City of Dalaran, The Drowned City, Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold or Shaper's Terrace now adds a trophy to your Crew's cabinet.

## 2.16.0
<sub>2026-11-21</sub>

- *(minor)*
  While you're alone in your Crew, the Camp saves lantern seats for your friends. Hover one for your Crew code, click it to put an invite in chat, or right-click it for the code box. Your pet naps on a seat, and the first friend you hear from walks in to take one.
- *(minor)*
  While you're alone in your Crew, your pet reacts to your news: it hops at a ding, holds up a fish or a star for a rare find or kill, and curls up by your grave after a death. In the Pocket Camp it watches the trophy cup and your fishing.
- *(minor)*
  While you're alone in your Crew with no pet, a stray may wander into the Camp and nap on a lantern seat. Click it to keep it as your pet, or right-click for "not now".

## 2.15.2
<sub>2026-11-21</sub>

- *(patch)* Fixed an error on an empty Trophies or Play times tab.

## 2.15.1
<sub>2026-11-21</sub>

- *(patch)*
  Deaths in battlegrounds and arenas no longer count.

  They no longer show up in the Feed, the Camp or the Crew deaths goal.

## 2.15.0
<sub>2026-11-20</sub>

- *(minor)*
  The Pocket Camp is now on by default.

  Your Crew's campfire shows on screen while you play. If you'd rather not have it, turn it off with Settings › Show the Pocket Camp. The one-time "New: the Pocket Camp" offer is gone.

## 2.14.0
<sub>2026-11-20</sub>

- *(minor)*
  The Camp now follows the game's day and night. By day the panel's Camp and While you were away show a blue sky, a sunny backdrop and the sun, and the Pocket Camp shows a daylit backdrop. By night you get the familiar night scene, now with a moon and a few twinkling stars. Fireflies, the firework and bats come out only at night. Turn it off with "Day and night" in Settings.
- *(minor)*
  When someone in your Crew runs a newer BFF, a chat line names the version and who has it, once per release, so you know to update on CurseForge.
- *(patch)*
  Internal: the Pocket Camp's live state (fishing and working, bedrolls, how long a pose is held, the trophy cup, the Spares crate and the figure menus) moved out of Core into its own module. Nothing you see changes.
- *(patch)*
  Internal: every panel tab (Roster, Feed, Trophies, Play Times, Spares, Professions, Dungeons, Catches, Settings and What's new) now has its own module behind one shared interface, and the panel only hosts them. Nothing you see changes.
- *(patch)*
  The Dungeons tab glides to your Character the first time you open it.

  Before, it only did so when you came back to the tab.
- *(patch)* What's new leaves out internal changes that don't affect what you see.

## 2.13.0
<sub>2026-11-20</sub>

- *(minor)*
  Choose a pet for your Camp figure in Settings › You › Look: a cat, dog, owl, frog, rabbit or fox. It sits beside you in the Camp, the Pocket Camp and While you were away, idles now and then, curls up asleep beside your bedroll and hops when you're cheered. Your whole Crew sees it. When the band is narrow, pets are left out first, so nobody loses their seat. Members on an older BFF don't see pets yet.
- *(minor)*
  The Camp dresses up for winter from 1 December to 2 January: snow on the ground, the tent and the bedrolls, a few falling flakes, a small decorated pine and twinkling lights on the tent, in the Camp, the Pocket Camp and While you were away. Turn it off with Settings › Seasonal decorations.
- *(minor)*
  The Camp dresses up three more times a year, in the Camp, the Pocket Camp and While you were away. Autumn (18 October to 1 November): a carved pumpkin by the fire, bats crossing the sky now and then, and a more orange fire. The lunar new year (22 January to 12 February): red and gold paper lanterns strung over the panel's Camp, and now and then a firework over the fire. Midsummer (20 June to 5 July): a bonfire, a Midsummer pole and fireflies. Turn them off with Settings › Seasonal decorations.
- *(patch)*
  The sidebar says Spares instead of Spare Items. The Dungeons tab, What's new, Settings and the empty Roster now talk about Members and the Crew instead of friends.
- *(patch)*
  The Camp keeps its full height at every panel size.

  The panel can no longer be made shorter than 460, and a smaller saved panel grows to fit. The Camp is the same height on every screen and UI scale.

## 2.12.0
<sub>2026-11-19</sub>

- *(minor)*
  Every empty tab now shows a small Camp scene with a headline and a line on what will fill it. While you're the only one in your Crew, the Roster shows the Crew code to hand out under your Characters, or, if you joined with someone's code, that you're waiting for the Crew.
- *(minor)*
  `/bff help` is a short grouped list, and `/bff help <command>` says more about one. Every tab has a command named after it: `/bff roster`, `/bff trophies`, `/bff playtimes`, `/bff dungeons` and `/bff whatsnew` are new, and the old `/bff goals`, `/bff when` and `/bff together` still work. A mistyped command suggests the one you probably meant instead of listing them all.
- *(minor)*
  Choose a head piece for your Camp figure in Settings › You › Look: a templar or centurion helmet, a dwarven or wolfskin helm, a cowboy, straw, top or wizard hat, a fez, beret, circlet, bandana, feathered cap, coonskin cap or horned helm. Your whole Crew sees it in the Camp, the Pocket Camp, While you were away, roster rows and toasts. Members on an older BFF don't see head pieces yet.

## 2.11.0
<sub>2026-11-18</sub>

- *(minor)*
  The Camp plays your Crew's Reactions as they arrive.

  A Cheered friend hops with a burst of gold, the first Respects grow a flower on the Grave, and a Welcomed Member stands and waves "hi!".

## 2.10.0
<sub>2026-11-17</sub>

- *(minor)*
  When you open the Trophies tab, it unveils Trophies you haven't seen yet: the latest win's medal stamps in with a gold sweep and a sound, and the other new medals on the shelf shine.

## 2.9.0
<sub>2026-11-16</sub>

- *(minor)* The Pocket Camp's tooltips now say how long a friend has been at it: "fighting · 3m", "in The Deadmines · 25m".
- *(patch)*
  Your Crew's member list no longer shows up in chat after a boss pull.

  BFF asked for it just as the pull locked chat down, and the answer came back unreadable, as a line like "[5. BFF…] *You". It now waits until the lockdown lifts.

## 2.8.1
<sub>2026-11-16</sub>

- *(patch)*
  The sync log in `/bff report` now notes the Crew channel's member list: the first one after joining, and every one BFF ignores and why. This helps track down friends who can't see each other.
- *(patch)*
  A friend in your Crew can reach you even when your game doesn't give BFF the Crew channel's member list. Before, BFF dropped their messages and you couldn't see each other online. Now a message from a Member BFF already knows makes them count as in the channel. It can take up to 5 minutes to see each other again. Messages from Characters BFF doesn't know are still dropped.

## 2.8.0
<sub>2026-11-16</sub>

- *(minor)*
  A crate by the Pocket Camp's fire says Spare notices are waiting.

  While there are Spare notices you haven't seen (new Spares, Claims and Gives, with chat lines and toasts off), a small crate sits by the Pocket Camp's fire. Its tooltip says how many, and a click on it opens the Spares tab, which clears it. Turn it off under Shown in the Pocket Camp in Settings.
- *(minor)*
  A gold cup over the Pocket Camp's fire marks a Trophy reached while you play.

  For an hour after the Crew reaches a Trophy during your session (a Crew goal, a dungeon or raid cleared, or a Rare slain), a small gold cup floats and sparkles over the Pocket Camp's fire. Its tooltip lists each one and how long ago, newest first, and a click on it opens the Trophies tab. Trophies reached while you were away don't raise it.
- *(minor)*
  Right-click a friend in the Pocket Camp to whisper, invite or find them.

  A right-click on another Member's figure opens a menu with their Character's full name: Whisper and Invite (the same as in the Roster), Show on map, which opens the world map where their map pin is (greyed out when BFF doesn't know where they are), and Open in panel. Your own figure, bedrolls and the fire have no menu, and it doesn't open in combat.
- *(minor)*
  The Pocket Camp can now fade in combat instead of hiding. In Settings, "Hide in combat" is now "In combat": Stay, Fade or Hide. With Fade, the whole Pocket Camp drops to the "Fade to" opacity (25% unless you change it) while you fight and comes back when combat ends. If you had Hide in combat on, it's still set to Hide.

## 2.7.0
<sub>2026-11-15</sub>

- *(minor)*
  Settings now open inside the BFF window, with switches.

  Settings is a page in the BFF window now, not in the game's Options, and opens from the sidebar, the minimap button's menu or /bff settings. Every on/off setting is a switch that glows like an ember while on, in the same sections as before.
- *(minor)*
  Shapeshifted friends show as their form in the Pocket Camp.

  A druid in bear, cat, travel, aquatic or moonkin form, or a shaman in Ghost Wolf, is drawn as that animal by the fire: the bear rears up and swipes, the wolf and the cheetah trot, and shifting puffs leaves or spirit wisps. Travel forms are only told to the Crew once held for half a minute.
- *(patch)* The knob of an on switch in Settings is dark and a bit bigger now, so it stands out on the ember.

## 2.6.0
<sub>2026-11-15</sub>

- *(minor)*
  Friends walk into the Pocket Camp and say hi.

  When someone in your Crew comes online, they walk in from the edge and wave. When someone logs off, they sleep in a bedroll by the fire for 10 minutes. Hover over the bedroll to see who it is and how long ago they left.
- *(minor)*
  The Pocket Camp shows who's playing together.

  Friends in your party or raid sit right next to you, and their tooltip says "In your group". Friends in the same dungeon or raid stand side by side in one shared doorway.
- *(minor)*
  The Pocket Camp shows who's playing an alt.

  A friend playing a character other than their main has "ALT" over their head. Hover over the Pocket Camp and their line says "on alt" too. Don't want it? Turn it off under Settings → Shown in the Pocket Camp.

## 2.5.0
<sub>2026-11-14</sub>

- *(minor)*
  The Pocket Camp can grow to fit more of your Crew.

  Drag its corner grip sideways to give it room for up to 18. It widens round the fire as people come online, and up or down still scales it.

## 2.4.0
<sub>2026-11-14</sub>

- *(minor)*
  The Dungeons tab is easier to read at a glance.

  A dungeon's bar now covers exactly its levels, with its name running on past it when it's longer. Bars are drawn in the Camp's pixel dither: solid where you fit, a checker ahead of you, and a faint dither once you've outlevelled them. A line runs down from your level through the dungeons, every other ten levels is shaded, and hovering the line says how many dungeons fit that level. Hovering a dungeon picks out the friends who fit it, and hovering a friend picks out their dungeons. With the Camp on, your friends stand on the line as their Camp heads, and the ones playing hop now and then. Opening the tab glides the line to you, and the overview at the bottom shows where the dungeons are and where your friends stand.
- *(patch)*
  Catches counts Whimsyfin and Raw Plated Armorfish as fish (48 types), and shows 14 chests, crates and trunks fished on Forever as Extras, in the waters where they are fished.

## 2.3.0
<sub>2026-11-14</sub>

- *(minor)*
  The Pocket Camp can be scaled.

  Drag the grip in its bottom right corner to make it bigger or smaller, and double-click the grip to go back to the usual size. "Lock its position" now locks its size too.
- *(minor)*
  The panel is lit by the Camp's fire.

  Its glow spills under the band and flickers with the flames, the night settles at the window's foot, and now and then an ember drifts down from the fire. Hairlines and washes are warmer, section labels open with a small spark, and your own row and the latest win catch the light.
- *(minor)*
  See what's new in BFF from the version under the panel's sidebar.

  A gold dot marks it while there are changes you haven't seen; click it for the newest updates, each change in a line with more under it. While you were away says once that BFF updated, and when an update needs your friends to update too, BFF names who's still on an older version.
- *(patch)*
  The Camp's tent is now a pavilion: a laced cone roof over canvas walls, its flaps tied back round the pole and its canvas lit on the side facing the fire.

## 2.2.0
<sub>2026-11-13</sub>

- *(minor)*
  Friends who are away (AFK) sit by the fire in the Pocket Camp.

  The Pocket Camp now shows when a friend is away: they sit by the fire with AFK over their head.

## 2.1.0
<sub>2026-11-13</sub>

- *(minor)*
  Rares: the Crew earns a Trophy for each of 30 rare mobs.

  The first time anyone in the Crew slays one of 30 noteworthy rare mobs, the Crew earns its Trophy (with a Feed entry, a toast and a While you were away line), shown in a new "Rares slain" grid in the trophy cabinet, plus a "Rares slain" Crew goal track.

## 2.0.0
<sub>2026-11-12</sub>

- *(major)*
  Updates from friends no longer arrive garbled or go missing.

  BFF now splits long messages into chunks itself, so one that arrives out of order or with a piece missing no longer shows up as unreadable, and a friend whose update got lost is asked for it again within about half a minute. Friends on an older BFF are still seen, but they see an "out of date" notice and stop seeing you until they update.
- *(patch)*
  BFF stops whispering friends it can't reach.

  A friend who logged out but still shows in the channel list is no longer whispered again every minute, and a friend who hasn't answered for 3 minutes (in a dungeon, say) is left alone until BFF hears from them again.
- *(patch)*
  Fewer messages: a friend who's behind gets caught up directly.

  A friend who is behind is now sent what they missed directly, instead of everyone in the Crew getting it again.

## 1.6.2
<sub>2026-11-12</sub>

- *(patch)*
  No more "No player named ... is currently playing" in chat when a friend logs out.

  It showed when a friend logged out while BFF still had messages queued for them.
- *(patch)*
  Members you removed stay removed.

  Friends no longer send you a Member you removed again after every sync. You still don't see them, and re-adding them brings them back as before.

## 1.6.1
<sub>2026-11-12</sub>

- *(patch)*
  The bug report records when friends join and leave the channel.

  The sync log (`/bff report`) now records every channel join and leave notice, to find out whether WoW: Forever tells BFF when a friend logs out.

## 1.6.0
<sub>2026-11-12</sub>

- *(minor)*
  Report a bug and Get in touch, from the panel's header.

  The panel's header has a bug button that opens the bug report (`/bff report`) and a message button that opens Get in touch, with links to GitHub issues and CurseForge to copy. The bug report window now says where to paste the report and what to add to it.
- *(minor)*
  The Pocket Camp shows what each friend is doing right now.

  Fighting, at a vendor or the auction house, resting at an inn, flying on a griffin, crafting or gathering, with a gold question mark when they hand in a quest. Dungeons and raids get their own doorway, and the fire flares purple for a Crew goal.
- *(patch)* Clicking a link in Get in touch no longer causes a Lua error.

## 1.5.0
<sub>2026-11-11</sub>

- *(minor)*
  The Pocket Camp: a small Camp to keep on screen while you play.

  An optional small Camp you can move anywhere: who's by the fire, in a dungeon or fishing, with animations for dings, deaths, rare finds and Crew goals. It's off by default, and BFF offers it once with a Tip: a small window the first time you log in, and a card in the panel until you answer.
- *(minor)*
  World map pins show friends' avatars and follow them as they move.

  Pins show each friend's Camp figure (or class icon with the Camp off) instead of a dot. While you travel, BFF shares your spot every 10 seconds or so (less often the more friends are online) instead of every 5 minutes. New settings: "Show your Crew on the world map" turns the pins off, and "Map pin size" (Small, Medium or Large) sets how big they are.

## 1.4.0
<sub>2026-11-11</sub>

- *(minor)*
  Type /bff report when syncing with your Crew goes wrong.

  Copy what it shows into your bug report. It holds your BFF and game versions, the state of BFF's link to your Crew, whether you're in a dungeon, and the recent sync log, which BFF now keeps all the time (and across reloads) instead of only while `/bff debug sync` is on. The report includes your Crew's Character names.

## 1.3.0
<sub>2026-11-10</sub>

- *(minor)*
  Character tooltips (Roster, Professions, Dungeons and the world map) now show the full name ("Moorwyn Stormgaard"), the Dungeons tooltips no longer run a friend's and their Character's names together, and Whisper and Invite now reach the Character on Forever. A friend's last name is known once they run this version.

## 1.2.2
<sub>2026-11-08</sub>

- *(patch)*
  Fixed fished herbs, rum and quest items showing under New on Forever in Catches: Spotted Sunfish, Stranglekelp and Rumsey Rum are now Extras, and items not on the list yet get their own section.

## 1.2.1
<sub>2026-11-08</sub>

- *(patch)*
  Fixed two problems with Forever's first and last names: BFF no longer whispers every message to your own Character (which doubled the Crew traffic), and a friend who logs out shows offline straight away instead of up to 12 minutes later.

## 1.2.0
<sub>2026-11-08</sub>

- *(minor)*
  Added `/bff debug sync`, a sync trace in chat: a timestamped line for each message sent and received (with its size, chunks and how late it arrived), the link going up or down and why, and Characters joining and leaving the Crew channel. Off by default, and off again after a reload. `/bff help` lists the commands.
- *(minor)*
  Fixed Crew updates lost on the way arriving up to 5 minutes late: a lost ding now comes back within about a minute, XP and gold reach friends within a minute, a failed send to one friend no longer stalls sync for everyone, and Crews of more than 10 Members compare every record over time.

## 1.1.0
<sub>2026-11-07</sub>

- *(minor)*
  BFF now records your **fishing catches** and shares them with your Crew: the first time you catch each type of fish or fishing find (when and where), and how many you've caught.
- *(minor)*
  A new **Catches** tab in the panel (or `/bff catches`) shows the Crew's fishing catches as a field guide: every type of fish and fishing find, filled in by whoever caught it first. Group it by where to fish or by type, pick what to show, and hover a fish to see who caught it first, when and where, and how many the Crew has caught. The bar on top counts the types caught towards the next trophy step, and the newest first catches show at the bottom.
- *(minor)*
  Catches are now news. A new **Types caught** track on the Goals tab has steps at 10, 20, 30, 40 and every type, each a trophy, a gold Feed entry and a toast. The Crew's first catch of a Nat Pagle fish or a Sunday contest fish is a Feed entry you can Cheer, named in the item's colour. While you were away gets a Catches section: "4 new types caught (Tor 3, Mira 1)", and a line for any rare find you missed. Everyday first catches stay in the Catches tab.
- *(patch)*
  Renamed four tabs in the panel sidebar: Goals is now **Trophies**, When is now **Play Times**, Spares is now **Spare Items** and Together is now **Dungeons**.
- *(patch)*
  Reworded the popup for a claimed Spare whose item is gone. It used to ask "Did you mail it to …?", which the Give, Not now and Withdraw buttons didn't answer. It now asks what happened to the item, with **Sent it**, **Ask me later** and **Got rid of it**.

## 1.0.1
<sub>2026-11-05</sub>

- *(patch)*
  Fixed Crews not syncing on WoW: Forever, which drops addon messages sent to custom channels: BFF now whispers each message to every other Character online in the Crew.

## 1.0.0
<sub>2026-11-05</sub>

- *(major)*
  BFF 1.0: the Camp joins the Roster, Feed, While you were away, Reactions, Crew goals and trophies, Spares, Play times, Professions and Together. Nothing breaks for an existing Crew; this marks the addon as complete for its first full release.
- *(minor)*
  Added the Camp: a pixel campsite of the Crew at the top of the panel and in While you were away, with graves, flowers and sparks for recent news, and a setting to turn it off.
- *(patch)*
  New Feed entries now show a small gold unread dot instead of a NEW tag on every row, and dungeons and raids new in WoW: Forever show an infinity mark.

## 0.5.0
<sub>2026-11-03</sub>

- *(minor)*
  The Goals tab is now a trophy cabinet: your latest win in gold, every Crew goal reached kept as a coloured medal on a shelf, a progress tile per goal, and See all for the whole cabinet.
- *(minor)*
  Dungeon and raid clears are Crew trophies: when your party kills an instance's final boss, the Crew gets a medal for its first clear, with a Feed entry, a toast and the party's names. The trophy cabinet now has a slot for every dungeon and raid. Only bosses BFF knows yet count: most of the classic dungeons and raids, Ruins of Lordaeron and Hall of Thanes, with the rest to follow.
- *(patch)* The When tab's grid now grows with the panel, filling the larger default size and any size you resize it to.

## 0.4.0
<sub>2026-11-03</sub>

- *(minor)*
  New Together tab (and `/bff together`): your Crew and the game's dungeons on one level line. See who can play with you, which dungeons fit you together, and who's a few levels short, with the nine new Forever dungeons marked NEW.
- *(minor)*
  Together tab: click a friend to see the dungeons you share (shift-click adds more, Escape or Clear to stop), and a Show menu to hide offline friends, show Alts, keep only dungeons near your level, hide attunements or show raids. Your choices are kept across reloads.
- *(minor)*
  The BFF panel opens bigger (640×520) and can be resized: drag the grip in its bottom right corner, down to the old 460×380 or up to 900×800. Every tab uses the extra room, and the panel reopens at the size and place you left it, on every Character. Double-click the grip, or use Reset BFF window in Settings, to put it back.
- *(patch)* Moved the panel's and While you were away's wording into Core, so it's tested offline. Nothing looks different in game.
- *(patch)* Kept a development file (`skills-lock.json`) out of the release zip. Nothing changes in game.
- *(patch)*
  Together tab: larger text, every dungeon on the line (no more "+N here"), a green dot on online friends' names, and Clear moved up next to Show. The answer line above the level line is gone, since the line and overview already show who you can play with and where. The Show buttons on Together and When get a filter icon, and the Roster's sort button an up and down arrow.

## 0.3.0
<sub>2026-11-02</sub>

- *(minor)*
  Each Character's professions and skill are now shared with your Crew. A new Professions tab (`/bff professions`) shows a grid of all twelve professions, a row per Member with their best skill in each, sortable by profession, and the Character tooltip lists each profession with its rank and skill. Characters not played since the Crew upgraded show no professions until they are.
- *(minor)*
  Profession progress is now Feed news with a Cheer: picking up a profession, reaching 75, 150 and 225 skill, and maxing it at 300, shown as a chat line, a toast and in While you were away.
- *(minor)*
  Added three Crew goals for professions on the Goals tab: Every profession in the Crew, Crew skill, and Everyone a Journeyman (each Member has a profession at the next rank). The Goals tab now scrolls.
- *(patch)*
  Refactored the settings into one list in Core, and Core now decides whether each live event becomes a chat line or a toast.
- *(patch)* The version number now shows at the bottom of the panel's sidebar and in the minimap button's tooltip.

## 0.2.1
<sub>2026-11-02</sub>

- *(patch)* Fixed CurseForge failing to process the release file: the zip no longer includes LibDeflate's documentation.

## 0.2.0
<sub>2026-11-01</sub>

- *(minor)*
  Restyled the panel and the While you were away popup with a flatter, modern look: a sidebar for Roster, Feed and Settings, a sort menu, a fixed-height window that scrolls, and the Feed as a timeline with an icon per event. Pause sharing is now called Appear offline and lives in Settings and the minimap menu.
- *(minor)*
  Added toasts for live Feed events, with a sound you pick and a position you drag, set in a new Toasts section in Settings.
- *(minor)*
  While you were away is now a scoreboard: a row per Character with their level, a bar for the levels they gained and their deaths, instead of everything joined onto one line.
- *(minor)*
  Added Reactions: cheer a Crew member's ding, pay respects for a death or welcome a new member with one click from the Feed, While you were away or a toast, and see who reacted to yours.
- *(minor)*
  Added Crew goals: a Goals tab with Crew levels, Everyone at level N and Crew deaths to reach together, and a Feed entry, chat line and toast when the Crew reaches one.
- *(minor)*
  Added a When tab: a heatmap of the hours your Crew usually plays, in your local time, from the last 4 weeks. Pick a Member to see their week, or right-click their row and choose "When does … play?".
- *(minor)*
  Added Crew pins on the world map: a dot where each Member was last seen, in their class colour, faded while they're offline. Hover a pin to see their Character, zone (or the instance they're in) and when they were last seen. Your spot is shared when BFF next sends your record, not on every step.
- *(minor)*
  Each Character's gold is now shared with your Crew and shown, in whole gold, in the panel's Character tooltip. Characters not played since the Crew upgraded show no gold line until they are.
- *(minor)*
  A Spare whose item has left your bags and bank (sold, mailed, traded, destroyed or equipped) is now noted on your Spares tab. If it's still gone at your next login, BFF withdraws it, or, if someone has claimed it, asks whether you mailed it to them so you can Give or withdraw it.
- *(minor)*
  Added Spares: offer items to the Crew with /bff spares add, Claim others' from a new Spares tab, and Give them to the earliest Claim, with notices and a Feed entry for each Give.
- *(minor)*
  Offer a Spare by dropping an item from your bags on the new drop slot in the Spares tab. BFF now refuses bound, quest and account-bound items, and /bff spares add only offers items you're carrying.
- *(patch)* Fixed the level arrow in While you were away showing as a box; it now reads "18 » 24".
- *(patch)* Reworded the Give confirmation and the Spares tab's hint: mail the item first, then Give it.
- *(patch)* BFF has its own icon: two linked rings, on the minimap button and in the AddOns list.
- *(patch)*
  New Reaction icons: fireworks for Cheer and a flower for Pay respects. The Reaction button on Feed entries is always shown, as on toasts, instead of appearing only on hover.
- *(patch)*
  Feed and toast icons are now easier to see: a square, full-colour picture for each kind of entry, with a faded edge in its colour. Dings show a plus.
- *(patch)* Fixed the Roster footer's Hidden and Removed counts sitting higher than the Crew code.
- *(patch)*
  Toasts lose their border and gold side bar: a thin line along the bottom shows the time each has left. The selected panel tab is a light chip instead of a gold bar.
- *(patch)* The toast sound in Settings is now a dropdown showing the chosen sound, like the game's own settings.
- *(patch)* Toasts stay on screen for 10 seconds instead of 6.
- *(patch)*
  Gold is kept for news: progress bars, toast timer lines, "You", given Reactions, "new" and max level in While you were away, and "left" are no longer gold, and a disabled Give is grey instead of faded gold.
- *(patch)* Section, day and column labels and Crew goal names are set in Friz Quadrata, and the smallest text is a size larger.
- *(patch)*
  The empty Feed shows a faint stretch of its timeline with "Nothing yet", and the panel before joining a Crew is centred, with Start and Join side by side.
- *(patch)*
  Tighter spacing at the top of While you were away, roomier Goals rows and Play times cells, and windows a touch more opaque.
- *(patch)*
  The panel's parts match: every bar is a neutral fill on a faint track, small buttons share one height, day labels look like section labels, the sidebar is plain text, and the roster tooltip opens beside its row. Map pins get a dark edge, and the minimap count sits on a small plate.
- *(patch)* A Skin button that becomes clickable again while the mouse is over it shows its hover straight away.

## 0.1.0
<sub>2026-10-31</sub>

- *(minor)*
  First release: the Crew panel with Mains and Alts, online status, sync between Members, the Feed, While you were away and the settings page.
- *(patch)*
  Fixed Trial accounts being invisible to the rest of the Crew: they now send like any other account, and can start a Crew.
