# Feed and While you were away

Answers [How are the Feed and "While you were away" stored and shown?](https://github.com/Shtian/bff-wow/issues/14). Builds on sync in #8 (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`), code structure in #9 (`docs/design/code-structure.md`) and joining a Crew in #10 (`docs/design/joining-a-crew.md`). Domain vocabulary from `CONTEXT.md`.

## The idea in one line

Feed entries are worked out by comparing the copy of a record you held with the newer one you just received. Each entry has a **seen** flag, and **While you were away** is simply the unseen entries from other Members, shown once the first sync after login has settled.

## Entries

### Kinds

| Kind | Made when | Text (example) |
|---|---|---|
| **ding** | A Character's level went up, but not to max level | "Ana dinged 24" |
| **death** | A Character's death count went up | "Ana died 3 times" |
| **new Character** | A known Member's record has a Character GUID it didn't have before | "Ana has a new Character: Jaina (Mage)" |
| **max level** | A Character's level reached `maxLevel` | "Ana reached max level!" |
| **joined the Crew** | A Member appears whose `joinedAt` is after yours, or a known Member's left flag goes from set to cleared | "Bob joined the Crew" |
| **left the Crew** | A known Member's left flag goes from cleared to set (#10) | "Bob left the Crew" |

Zone changes and Main changes make no entries: zones change too often and the panel already shows them, and a new Main is shown by the panel too.

### Working them out

Ledger hands Feed a before/after pair whenever a received copy wins (and when your own record changes). Feed compares them field by field:

- **Skipped versions collapse.** A client that missed some versions only sees before and after, so each kind becomes at most one entry per Character: level 22 » 24 is one "dinged 24" entry that remembers it started at 22, and deaths 3 » 5 is one "died 2 times" entry.
- **Max level replaces the ding.** A jump that reaches max level makes only the max level entry.
- **Odd jumps make nothing.** A death count that goes down (a crash lost that session's count, see #9) makes no entry, and a level above your own `maxLevel` (you're behind on a patch) makes no ding or max level entry.
- **Time** is the after record's version, which is the owner's `GetServerTime()` at the write. It's close to when the event happened, and every client orders entries the same way. For collapsed jumps the time is approximate.

### First sight of a Member

When you join a Crew or reinstall, every record arrives as new. Counting that as "nothing » level 40" would flood the Feed, so **the first sight of a Member is a silent baseline**: their record is stored and no entries are made.

The one exception is a Member who joined after you. The Member record gets one new field, **`joinedAt`**: the server time when that Member started or joined the Crew, rewritten on rejoin. On first sight, if their `joinedAt` is after your own, Feed makes one "joined the Crew" entry. A Member who was in the Crew before you and was just offline for weeks has an earlier `joinedAt`, so they stay a silent baseline.

New Characters on a Member you already know always make a "new Character" entry.

### Your own events

Your own Characters' events go into the log too, so the Feed tab reads as the Crew's whole history ("You dinged 24", "Your Alt Jaina dinged 12"). They are marked as seen when they are made, so they never appear in While you were away or as a chat line.

### Text

Core (Feed) builds each entry's text, so the popup, the Feed tab and the chat line all show the same string. Entries name the Member by Display name and add the Character's name when it's an Alt: "Ana dinged 24", "Ana's Alt Jaina dinged 12". Each entry also carries its kind, so UI can pick an icon or a highlight.

## Storage

- One log in `db`, account-wide, so switching to an Alt shows the same log and the same seen flags.
- Each entry: kind, time, Member id, Character GUID (if any), text, any extra numbers (e.g. the "from" level), and **seen**.
- Kept for **30 days**, and at most **200 entries**, whichever limit is reached first. Pruning runs from `tick()` with the rest of Ledger's pruning.
- **Remove** a Member drops their entries along with their record. **Leaving** the Crew wipes the whole log (#10).

## While you were away

### What goes in

The unseen entries from other Members. "Away" is not a time window: an entry is unseen until it has been shown to you by the chat line, the popup or the Feed tab. So events that happened while you were online but reached you late (lockdown, or a Member who logged in after you) are neither missed nor shown twice.

### When it appears

Only on an **initial login**. A `/reload` creates a new Core but is not a login, so it never shows the popup; unseen entries wait for the next login or the Feed tab.

1. Settling starts once the link is up and your first DIGEST has gone out.
2. The summary is ready after **10 s with no new DATA**, or at most **30 s** after that first DIGEST.
3. If the link never comes up (you logged in inside an instance and stayed there), it keeps waiting. A half-synced summary is never shown.
4. If there's nothing unseen from other Members, nothing is shown.
5. App waits until you're out of combat before showing the frame.

Entries that arrive while settling go into the summary and print no chat line.

### How it looks

A small frame in the panel's style (#7):

- One block per Member, ordered by most recent activity. Each Member's events are condensed onto one line, e.g. "**Ana** (Main Thrall): 18 » 24, died 3×, new Character Jaina (12)". The level range goes from the lowest "before" to the highest "after" across that Member's unseen entries, per Character.
- Max level, joined and left get their own highlighted line.
- **Open Feed** and **Close** buttons.

The summary is marked as seen once Core has fired it.

## Live chat line

After the summary has settled, every new entry from another Member prints one chat line, e.g. "BFF: Ana dinged 24.", and is marked as seen. Toasts (`docs/design/toasts.md`) show the same entries on screen. If chat lines and toasts are both turned off, those entries stay unseen and show up in the next login's popup and on the Feed tab.

## Feed tab

A **Feed** tab in the panel's sidebar, below the Roster: a timeline, newest first, of all kept entries (up to 200), grouped by day, with an icon per kind. Entries that were unseen when you opened it are tagged "new" until you leave it. Opening it marks everything as seen. `/bff feed` opens the panel on it.

## Settings

Two toggles, both stored in `db` and read by Core:

- **Chat message for live events** (on by default).
- **Show While you were away on login** (on by default). When it's off, the minimap button's tooltip shows "N new in Feed" instead.

## Changes to Core's interface

Kept deep: Core decides what is seen and what the settings allow, so UI and App only render and print.

- **Creation options:**
  - `initialLogin`: `isInitialLogin` from `PLAYER_ENTERING_WORLD`. A reload already creates a new Core, so no input method is needed.
  - `maxLevel`: from `GetMaxLevelForPlayerExpansion()`.
- **Listener events:**
  - `feedEntry(entry)`: fires only when the chat-line setting is on, and Core marks the entry as seen as it fires. App prints `entry.text`.
  - `awaySummary(summary)`: fires once per initial login when the summary has settled, only when the popup setting is on and the summary isn't empty. Core marks those entries as seen as it fires. App waits for combat to end and then shows it.
  - `rowsChanged` is renamed to **`changed`**: "re-read whatever you show". The panel, the Feed tab and the minimap badge all redraw from it, so the Feed needs no redraw event of its own.
- **Read:** `feed()` returns the Feed tab's entries grouped by day, plus the unseen count.
- **Command:** `feedSeen()`, called when the Feed tab is opened.
- **Member record:** gains `joinedAt`, written on starting or joining a Crew.

## Scenarios to add to the FakeNet tests

- C misses A's dings from 22 to 24 and two deaths; at C's next login the summary shows "22 » 24, died 2×" once, and nothing prints in chat.
- A reaches max level from 59 in one jump: one max level entry, no ding.
- D joins a Crew that already has A, B and C at various levels: D's Feed stays empty, and A, B and C each get one "D joined the Crew".
- B returns after 200 days offline, so C pruned B's record at 180 days: C makes no "joined" entry.
- A dings while C is in lockdown; C gets one chat line when the DATA arrives after lockdown clears, and the entry isn't in C's next summary.
- With chat lines off, A's ding stays unseen and shows in C's next summary.
- `/reload` after login shows no second summary.
- A Removed Member's entries disappear from `feed()`.
- A crash lowers A's death count: no entry on any client.

## Not decided here

- The exact layout of the popup and the Feed tab; they follow the panel style from #7.
- The rest of the settings panel (still fog on the map).
