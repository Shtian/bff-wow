# BFF – Best Friends in Forever

**Keep up with your friends in WoW: Forever, even when you play at different times.**

BFF is for a small group of friends who don't always play at the same time. It shows everyone's characters, levels and whereabouts, and tells you what your friends did while you were away. No server, no account, and no shared guild needed.

## What it does

- **While you were away:** when you log in, see every ding, death and new character your friends had since you last played.
- **Gather round the fire:** the Camp, a small pixel campsite at the top of the panel and in While you were away. Friends who are online sit by the fire and the rest sleep in bedrolls. A recent death leaves a grave, respects put a flower on it, and a fresh max level gets a spark. You can switch it off in Settings.
- **Keep the fire on screen:** the Pocket Camp, an optional small Camp you can keep up while you play.
  - Shows the fire and every friend who's online, you included.
  - Each friend is shown doing what they're doing: sitting by the fire, fighting with a sword raised, holding a torch in a dungeon or raid doorway, at a vendor or the auction house, with AFK over their head while away, resting under an inn's sign, flying on a griffin, crafting, gathering, or holding a fishing rod after a catch.
  - Reacts to news for about 10 seconds: a ding gets a gold star and a bounce, a max level bursts into sparks, a death turns the figure into a skeleton, a rare find is held up, a handed-in quest pops a gold question mark, and a crew goal makes the fire flare purple.
  - Hover a friend to see their character, level, zone and professions. Hover the fire to see who's doing what.
  - Click it to open BFF. Drag it anywhere on screen.
  - Its own Settings section: backdrop opacity from see-through to solid, lock its position, and hide it in combat.
  - Off by default. BFF offers it once when you log in, and you can turn it on or off any time in Settings.
- **Your whole crew:** every friend's characters, levels and whereabouts, and when each was last seen. Alts are grouped under the person who plays them.
- **Cheer every ding:** one click sends a cheer for a ding, respects for a death, or a welcome for someone new. Toasts can play an optional sound.
- **Level up together:** goals the whole crew works towards, like everyone reaching level 60, and trophies for what you do together, like clearing a dungeon or a raid, or catching every type of fish. Nobody is ranked.
- **Who crafts what:** every friend's professions and skill in one grid, so you know who to ask for a craft. Hover a tile to see which characters have that profession. You also get feed entries when friends pick up a profession, reach a new rank or max it.
- **Fish together:** a field guide of the crew's fishing catches. Every type of fish and fishing find is filled in by whoever caught it first, with when and where. Group it by where to fish or by type, and see what the crew still hasn't caught. Rare finds, like Nat Pagle's fish, are news you can cheer.
- **Pass on spare gear:** offer an item to your friends. Whoever claims it first gets it by in-game mail.
- **When everyone plays:** a heatmap of the hours each friend usually plays, in your own time zone.
- **Dungeons together:** see which friends are close to your level, and the dungeons you can run together. Click a friend to see the dungeons that fit you both.
- **Map pins** show where your friends' characters are.

## Start a crew

1. Everyone in the group installs BFF.
2. One friend types `/bff start` and shares the crew code (on Discord, by text, however you like).
3. The others type `/bff join <code>`.

## Commands

| Command | What it does |
|---|---|
| `/bff` | Open or close the panel (also a key binding and the minimap button) |
| `/bff feed`, `/bff goals`, `/bff when`, `/bff spares`, `/bff professions`, `/bff catches`, `/bff together` | Open the panel on that tab: Feed, Trophies, Play Times, Spare Items, Professions, Catches or Dungeons |
| `/bff spares add <item>` | Offer an item from your bags: shift-click it in after `add` |
| `/bff start`, `/bff join <code>`, `/bff leave` | Start, join or leave a crew |
| `/bff code` | Show your crew code |
| `/bff name <name>` | Set the name your friends see |
| `/bff settings` | Open Settings |
| `/bff minimap` | Bring back a hidden minimap button |
| `/bff report` | Open a report to copy into a bug report: versions, link state and the recent sync log. It includes your crew's character names |
| `/bff debug sync` | Print the sync trace in chat: a line for each message sent and received. Off again after a reload |
| `/bff help` | List the commands |

## How it works, and its limits

BFF has no server. Each player's addon keeps their own data and passes it to the other crew members' addons in game: they find each other in a hidden chat channel and whisper updates directly. That keeps it simple and private, but it comes with limits:

- **Someone has to be online to pass news on.** Updates travel only between players who are online at the same time. When anyone who has your news is online alongside a friend, that friend gets it, even if you are offline. A crew whose members are never online at the same time won't see each other's news.
- **Same realm and same faction.** WoW's chat channels and whispers don't cross factions or reach other realms. Whether connected realms work hasn't been tested.
- **Paused in combat and instances.** WoW blocks addon messages there. Your news goes out as soon as you leave, and nothing is lost.
- **Delivery is best effort.** A message can occasionally get lost. The next sync fills in the gap, so data catches up but isn't instant.
- **One crew at a time.** BFF uses one of your character's custom chat channels, and there's a cap of about 10. If you're at the cap, leave a channel and `/reload`.
- **The crew code is the only key.** Anyone with the code can join and see the crew's data. There's no owner, kick or ban. You can hide someone just for yourself with Remove. To shut someone out, start a new crew and share the new code with the others.
- **History is short.** The feed keeps 30 days or 200 entries, whichever runs out first. Friends unseen for 30 days are hidden from the panel.
- **Settings has an "Appear offline" option** if you want to stop sharing for a while.

## Feedback

Bugs and ideas are welcome on [GitHub](https://github.com/Shtian/bff-wow/issues).

## Support

If BFF brings your crew together and you'd like to say thanks, you can [buy me a coffee](https://buymeacoffee.com/mltdwymkxn). It's never expected.

## Thanks

Some of BFF came from ideas players left in the comments on CurseForge:

- **kayloohoo** asked for a small campfire to keep on screen, with little animations for what friends are doing. That became the Pocket Camp.
- **absolutezabba12** asked for a setting to turn the map location off, more accurate positions, and the Camp's characters on the map in place of dots. That became the map pin setting, live positions and the Camp figures as map pins.
- **TheDolmenDuke** asked for the Pocket Camp to show a friend at a shop or the auction house, in combat and handing in a quest, and for a dungeon icon of its own. That became the Pocket Camp's poses for what each friend is doing right now.
