# BFF – Best Friends in Forever

A WoW: Forever addon that keeps a small circle of real-life friends aware of each other's progress, even when they don't play at the same time.

## Language

### People and characters

**Member**:
A real person taking part in BFF, identified the same way across all their Characters.
_Avoid_: Friend, player, user

**Crew**:
The set of Members who share BFF data with each other.
_Avoid_: Group, guild, party, friends

**Crew code**:
The generated code that names a Crew and is the only key to it. Whoever has it can join; a Member is in at most one Crew at a time.
_Avoid_: Invite code, password, Crew name

**Leave (the Crew)**:
What a Member does to themselves: their record is marked as left, so every other Member stops showing them. Unlike Remove, everyone sees it.
_Avoid_: Quit, unsubscribe

**Display name**:
The name a Member chooses to be shown as, independent of their Characters' names.
_Avoid_: Nickname, username

**Character**:
One in-game character owned by a Member.
_Avoid_: Toon, player, alt (when meaning any character)

**Main**:
The Character a Member has chosen to represent them.
_Avoid_: Primary

**Alt**:
Any of a Member's Characters other than their Main.

**Profession**:
A trade skill a Character has learned, with its skill and max skill, as that Character's own client reports it: a main profession (two at most, such as Alchemy) or a secondary one (cooking, fishing, first aid). Its rank (Apprentice, Journeyman, Expert, Artisan) comes from the max skill. A profession **milestone** is a base skill of 75, 150, 225 or 300 (maxed), each Feed news; it has nothing to do with Crew goals.
_Avoid_: Trade, skill (when meaning the profession), craft

**Remove (a Member)**:
To hide a Member from your own view of the Crew. It never affects what other Members see; nobody removes a Member for the whole Crew.
_Avoid_: Kick, ban

### What the Crew sees

**Feed**:
The log of noteworthy things that happened to the Crew's Characters, such as dings, deaths and new Characters.
_Avoid_: News, timeline, activity log

**New (Feed entry)**:
A Feed entry, or a Reaction to your own, that was unseen when you opened the Feed, or that arrived while it was open and was still unseen when it redrew. It stays New until you leave the Feed (the end of that **Feed visit**), though opening the Feed is what makes it seen. One a Live event already showed is never New.
_Avoid_: Fresh, unread

**While you were away**:
The summary of Feed entries, and Reactions to their own entries, that a Member missed since their last logout, shown on login.
_Avoid_: Digest, recap

**Reaction**:
A Member's one-click acknowledgement of another Member's Feed entry. Each kind of entry has exactly one: a **Cheer** for dings, max level, new Characters and profession news, **Respects** for deaths, and a **Welcome** for joining the Crew. A Reaction is permanent, and it is news to the entry's owner.
_Avoid_: Like, emote, kudos

**Live event**:
A new Feed entry from another Member, a Reaction to one of your entries, or a Spare notice, announced as it happens by a chat line, a Toast or both.
_Avoid_: Notification, alert, live news

**Camp**:
The scene of the Crew shown at the top of the panel and in While you were away: every Member the Roster shows around a campfire, seated by it while online and asleep in a bedroll while not, with a Grave for each recent death and a spark over a fresh max level. Another way of showing what the Roster and the Feed already say; it has no data of its own. Respects show in it as a flower on the Grave.
_Avoid_: Scene (when meaning the Camp), campsite, diorama

**Pocket Camp**:
A small, movable on-screen Camp you can keep up while playing: the fire and the Members by it (online), with what they are doing: what the Roster and Feed know (in an instance, fishing, at a profession), and what each Member's game says they're doing right now (fighting, at a vendor or the auction house, resting, flying). It opens the panel on click.
_Avoid_: mini Camp, overlay, widget, transparent fire

**Grave**:
The mark a death in the last 24 hours leaves in the Camp, beside its Member: one per death, at most 2 per Member and 4 in the Camp. It gets a flower once any Member has paid Respects to that death.
_Avoid_: Tombstone, death marker

**Toast**:
A small on-screen notice for a Live event, with an optional sound. Shows the same things as the chat line.
_Avoid_: Popup, alert, notification (when meaning a toast)

**Map pin**:
A Member's mark on the world map where their shown Character was last seen: their Camp figure (or class icon with the Camp off), with a small green dot while online. While a Member moves in the open world, their client sends a small **WHERE** so the pin follows them between their record's updates; the record still carries the last spot for anyone who missed it.
_Avoid_: Dot, blip, marker

**Tip**:
A one-time offer of a feature that's off by default, with a button to turn it on and one to dismiss it: a small window the first time, and a card at the top of the panel until it's answered. Once answered, it never shows again on any Character of the account.
_Avoid_: Toast (for a Tip), notice, announcement, what's new

**Play times**:
The hours of the week a Member usually plays, from the last 4 weeks of their own client's counting, across all their Characters. A Member **usually plays** an hour they played at least 10 minutes in, in at least 2 of those weeks.
_Avoid_: Schedule, availability, activity

**Together (tab)**:
The panel's view of who a Member can play with, and where: the Crew's Characters and the game's dungeons on one level line.
_Avoid_: Overlap finder (the feature's working name), level line (when meaning the tab)

**Can play**:
A Character is within 3 levels of the Character you play, so you can play together. The Roster and Together share the rule.
_Avoid_: In range, near, fits

**Fits (a dungeon)**:
A Character fits a dungeon when its level is inside the dungeon's recommended range. Separate from Can play: a friend can fit a dungeon you fit and still be too far from you to play together.
_Avoid_: Can do, eligible

**Last seen**:
When a Member or Character was last played, as reported by that Member's own client rather than observed by others.
_Avoid_: Last online, last active

### Together and against each other

**Crew goal**:
A target the whole Crew reaches together, where every Member's progress counts and nobody is ranked or credited. Built in, as a ladder of ever-higher targets.
_Avoid_: Challenge, quest, achievement, milestone

**Trophy**:
A Crew goal rung the Crew has reached, or an instance it has cleared (the Crew's first Clear of it), kept as a medal on the Goals tab with when. It's **fresh** for 3 days, while it's still news. The **trophy cabinet** is every trophy: the dungeons and raids, cleared or not, then the goal rungs by track.
_Avoid_: Achievement, badge, award

**Clear**:
A dungeon or raid run to its final boss's death, recorded by each Member in the party, with the Members who were there. Only a final boss counts; strangers in the party aren't named. The Crew's first Clear of an instance is its Trophy, and everyone in any party that cleared it is credited.
_Avoid_: Kill (when meaning the whole run), completion, run

**Crew levels**:
The sum, over the Crew's Members, of each Member's highest Character level. Alts don't add to it.
_Avoid_: Total levels

**Crew skill**:
The base skill of every Profession of every Character in the Crew, Alts included, summed.
_Avoid_: Total skill

**Catch**:
A fishing find a Member has caught, kept in their own record: per type, their first catch (when, where, on which Character) and how many they've caught. **Catches** is the Crew's collection: each type is filled in the first time any Member catches it, credited to whoever caught it earliest. Only what the loot window says came from fishing counts; what's inside a fished chest or clam doesn't.
_Avoid_: Fish (when meaning any find), loot, collection item

**Type (of Catch)**:
One entry in BFF's shipped list of what can be fished: a fish, a Nat Pagle quest fish, a bloated fish, or a family of fish sold by weight, where every weight ("19 Pound Catfish") counts as the one type ("Catfish (by weight)"). The list is data, keyed by item ID. "23 of 46 types caught" counts types, never Extras.
_Avoid_: Kind, species, entry

**Extra (Catch)**:
A type that's shown but never counted towards the types caught, because not everyone can catch it any time: seasonal fish, the Sunday fishing contest's fish, fish that drop only for a quest outside Nat Pagle's (Spotted Sunfish), what's fished but isn't a fish (Stranglekelp, rum), and anything not yet confirmed on Forever (treasure, Whimsyfin, Raw Plated Armorfish).
_Avoid_: Bonus, optional, rare

**Unlisted catch**:
A fished item that isn't on BFF's list, kept in the record anyway (up to a cap) so the list can grow. Not counted, never an Extra; adding it to the list later is one row of data.
_Avoid_: Unknown catch, other

**Rare find**:
The Crew's first catch of one of Nat Pagle's quest fish or a Sunday fishing contest fish. The one kind of Catch that's a Feed entry, with a Cheer; every other first catch stays in the Catches tab.
_Avoid_: Rare catch (the Catches tab's wider group, which also has bloated fish and families), big catch

**Waters**:
A zone-level band where types are found ("Level 30–45", "New on Forever"), with the zones it covers. Each type lists its waters, lowest first. Kept as data, so a new zone is one row.
_Avoid_: Fishing spot, pool, zone (when meaning the band)

**Competition**:
A contest that ranks Members against each other. Unlike a Crew goal, it names who is ahead.
_Avoid_: Race, leaderboard (when meaning the contest)

### Passing things on

**Spare**:
An item a Member offers free to the Crew, to be sent by in-game mail to whichever Member Claims it. It ends when it is Given, withdrawn by its owner, or after 30 days. If its item has left the owner's bags and bank (sold, mailed, traded, destroyed or equipped) and is still gone at the owner's next login, BFF withdraws it for them. If it has a Claim, BFF asks the owner whether to Give it or withdraw it (ADR 0004).
_Avoid_: Gift, offer, listing, loot

**Claim**:
A Member asking for a Spare, for one of their own Characters to receive it. The earliest Claim gets the Spare; a claimer can withdraw their Claim until it is Given.
_Avoid_: Request, reserve, dibs

**Give**:
What the owner of a Spare does once they have mailed it to the Character named in the winning Claim. It ends the Spare and makes a Feed entry.
_Avoid_: Deliver, trade, send (when meaning the act in BFF)
