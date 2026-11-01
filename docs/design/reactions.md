# Reactions

Answers [Reactions on Feed entries](https://github.com/Shtian/bff-wow/issues/50). Builds on sync in #8 (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`), the Feed in #14 (`docs/design/feed.md`) and toasts (`docs/design/toasts.md`). How entries are matched across clients is `docs/adr/0002-feed-entries-keyed-by-content-not-version.md`. Domain vocabulary from `CONTEXT.md`.

## The idea in one line

A Member reacts to another Member's Feed entry with one click. The Reaction is written into the reacting Member's own record and gossiped like everything else, and the entry's owner hears about it in While you were away, a chat line or a Toast.

## Reactions

One per entry kind, so there's never a picker:

| Entry kind | Reaction | Text the owner sees |
|---|---|---|
| ding | **Cheer** | "Bob cheered your ding to 30" |
| max level | **Cheer** | "Bob cheered you reaching max level" |
| new Character | **Cheer** | "Bob cheered your new Character Jaina" |
| death | **Respects** | "Bob paid respects (Jaina died)" |
| joined the Crew | **Welcome** | "Bob welcomed you" |
| left the Crew | none | |

- You can only react to other Members' entries, never your own.
- A Reaction is permanent. Clicking one you've already given does nothing.
- Entries of a Removed Member can't be reacted to, and a Removed Member's Reactions are hidden.
- Alt entries name the Character the same way the Feed does ("your Alt Jaina's ding to 12").

## Which entry a Reaction points at

The entry's time can't be used, because the version it comes from differs between clients (ADR 0002). A Reaction's key is:

| Kind | Key |
|---|---|
| ding | owner Member id + Character GUID + level reached |
| max level | owner Member id + Character GUID |
| death | owner Member id + Character GUID + death total reached |
| new Character | owner Member id + Character GUID |
| joined | owner Member id + `joinedAt` |

A collapsed entry matches every key in its range: "dinged 24 (from 22)" shows Reactions keyed to 23 or 24, and "died 2 times" going from 3 to 5 shows those keyed to 4 or 5. A Reaction made on a collapsed entry, or on a While you were away row, is keyed to the top of the range. The owner's own entries never collapse, so each Reaction lands on exactly one of them.

Death entries gain the death total they reached (`to`) next to `count`.

## Storage

### In the reacting Member's record

The record gains an optional `reactions` list. Each item holds the key (owner id, GUID, kind, number) and the server time it was made, with short field names to keep DATA small.

- Kept for **30 days**, and at most the **50 most recent**. Pruned when the record is next written, so pruning alone never sends a DATA.
- Clients that don't know the field keep and relay it unchanged, since `wellFormed` only checks the fields it knows.
- A malformed item is ignored. It doesn't get the whole record rejected.
- **Leaving** the Crew clears the list.

### On Feed entries

The record is only how a Reaction travels. Every client attaches the Reactions it learns of to the matching entries in its own Feed log, so a Reaction outlives the sender's 50-item cap:

- When a record wins, Feed compares its old and new `reactions` and attaches the new ones.
- When an entry is made, Feed attaches the matching Reactions already in held records, so it doesn't matter which record arrives first.
- Each entry keeps who reacted and when. On your own entries each Reaction also has a **seen** flag.
- A Reaction whose entry isn't in the log (pruned, wiped, or never made) is ignored. Reactions go when their entry is pruned or Removed.

### Silent baseline

The first sight of a Member (joining, reinstalling) attaches their Reactions as already seen, the same rule as Feed entries.

## Telling the owner

A Reaction to one of your entries is news. It isn't a Feed entry of its own: it's marked seen the same way and shown alongside entries.

### While you were away

Unseen Reactions to you can bring up the popup by themselves. They show in a section at the top, **Your Crew noticed**, with one line per entry, newest first: "Bob and Cleo cheered your ding to 30", "Bob, Cleo, Dan and 2 others welcomed you". After 3 names it says "and N others". With no Crew news, the popup shows only this section. Reactions that arrive while settling go into the summary.

### Live

After settling, a new Reaction to you goes through the same settings as entries: a chat line ("BFF: Bob cheered your ding to 30.") if chat lines are on, a Toast if toasts are on, and it's marked seen as it fires. With both off it stays unseen. Chat lines are never merged. A Reaction for an entry whose Reaction toast is still on screen merges into it ("Bob and Cleo cheered your ding to 30") and gives it its full time again. Reaction toasts use the kind's Reaction icon and play the toast sound like any other toast.

### Unseen count

Unseen Reactions count in the minimap's "N new in Feed", and their entries are tagged "new" in the Feed tab. Opening the Feed tab marks them seen.

## Reacting

Your own Reaction goes into your record right away, and is attached to the entry locally as "You". It's a local write, so it works in combat, in instances and while offline. Others get it with your next DATA once lockdown has cleared.

### Feed tab

An entry you can react to shows its Reaction icon and who reacted ("🎉 Bob, Cleo"). Click it to react. Your own shows as "You" and is highlighted. Entries with no Reactions show a faint icon on hover only. Entries of yours show who reacted, with no button.

### While you were away

Each scoreboard row gets a button per Reaction that applies to it: a Cheer for the row's ding, max level or new Character (keyed to the highest level), and Respects for its deaths (keyed to the highest death total). A Welcome sits next to the gold "joined" tag. Buttons you've already used show as done.

### Toasts

An entry toast you can react to gets a small Reaction button at its right edge. Clicking it reacts, shows it as done, and leaves the toast up. Left-click elsewhere and right-click keep doing what they do today. Reaction toasts and the "+N more in the Feed" toast have no button.

## Changes to Core's interface

- **Command:** `react(key)`, with a key from `feed()` or the summary. Ignores your own entries, Removed Members, entries that can't be reacted to, and keys you've already reacted to. Fires `changed`.
- **Listener events:**
  - `reaction(news)`: like `feedEntry`, fires when either chat lines or toasts are on, and Core marks the Reaction seen as it fires. `news` carries the text, the Reaction and the entry key, so ToastQueue can merge.
  - `awaySummary(summary)`: the summary gains `noticed`, the lines for Your Crew noticed. It fires when there are unseen entries or unseen Reactions.
- **Reads:** each entry from `feed()` and each summary row carries its key(s), which Reaction applies, who reacted, and whether you have. `unseen()` counts Reactions too.
- **Member record:** gains `reactions`.

## Scenarios to add to the FakeNet tests

- B cheers A's ding to 24. At A's next login, Your Crew noticed shows "B cheered your ding to 24", and C's Feed tab shows B on that entry.
- C collapsed A's 22 » 24. B cheered 23 and C cheers the collapsed entry: C's entry shows both, and A sees B on her 23 entry and C on her 24 entry.
- A dings at v2 and changes zone at v3. B got v2 and C only v3. B's and C's Cheers both land on A's single ding entry.
- B's record with a Cheer reaches C before A's record with the ding: the Cheer shows once the entry is made.
- B and C both cheer while A is online with toasts on: one toast that ends up naming both, and two chat lines.
- D joins and is welcomed by A and B: D's popup shows "A and B welcomed you" with no scoreboard.
- B gives 51 Reactions within 30 days: B's record keeps 50, and A still shows the oldest on her entry.
- D joins a Crew where B has Reactions in their record: D gets no news, and Reactions to entries D doesn't have are ignored.
- B reacts in combat: it reaches A after B's lockdown clears.
- A Removed Member's Reactions don't show, and nothing of theirs can be reacted to.
- A record from an older client with no `reactions`, and one with a malformed item, are both kept.

## Not decided here

- The Reaction icons and the exact layout of the buttons; they follow the Skin.
- Reacting to Reactions, or showing Reactions to other Members' entries as notifications.
