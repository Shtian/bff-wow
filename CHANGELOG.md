# Changelog


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
