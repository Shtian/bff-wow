# What's new

What changed in BFF itself, shown in the game: a view in the panel, opened from the version under the sidebar, and a line in While you were away after an update. Settled with an HTML prototype and a design critique (the prototype is on the `prototype/whats-new` branch).

## The idea in one line

The version label carries the Unread dot while there are changes you haven't seen; clicking it opens a page of the newest releases, each change a short title with its detail under it.

## Where the text comes from

- **Bump files** are written for players: a short title (one sentence, at most about 70 characters), a blank line, then a paragraph of detail (`docs/design/settings-and-release.md`). Bumpy keeps the paragraphs in `CHANGELOG.md`, its first line indented under `- *(kind)*` and the rest with it.
- **The release build** writes the newest 8 releases of `CHANGELOG.md` into `ChangelogText.lua` as a Lua string (`scripts/changelog-text.sh`, run by `scripts/package.sh` before the packager copies the working tree). The checkout's copy is empty and is put back after the build, so it's never committed with text. A checkout has no What's new: its version is only a label.
- **Changelog** (`Core/Changelog.lua`) parses it: a release per `## X.Y.Z` heading with its `<sub>` date ("13 Nov"), an entry per bullet with its kind (major, minor, patch). The first paragraph is the title and the rest the detail. An older entry written as one paragraph splits after its first sentence. Code spans and bold lose their marks.

## What's seen

- `db.changesSeen` is the version last seen, account-wide. A change is new while its release is newer than it and no newer than the version running.
- **A fresh install** (empty saved data) starts with the version installed seen: there's nothing to catch up on.
- **Saved data from before What's new** starts with the release before the one installed seen, so only that release is new.
- **A visit:** opening What's new marks every change seen at once. The releases that were new stay marked until the view is left, as the Feed's New entries do, so you can read them.
- **While you were away** says it once per update (`db.changesTold`), after a login once sync has settled. An update with no other news still opens the popup, with only that section. With the popup turned off, only the dot says it, and the update counts as told: turning the popup back on doesn't bring up an old one.

## The view

From top to bottom, in the panel's content area (no window of its own, so the panel keeps its size):

1. **A Heading and a Small line.** With changes new: "Updated to 2.3.0" and "5 changes since 2.1.0". When the newest 5 releases don't hold all of them: "… · the last 5 updates are below". With nothing new: "What's new in BFF" and "You're on 2.3.0, from 15 Nov".
2. **Make sure your friends update too**, when a major release is new on this visit: a Raised Plate with a 1px gold edge (the Flat Ledger Rule's way to stand out) saying friends on an older BFF see the out-of-date notice and stop seeing you. It names the Members known to run a version older than that release, in their class colour with their version ("Still on an older BFF: Mirelle (1.6.2)"), or says everyone is on it or later when there are friends and every one's version is known. A Member whose version isn't known (from before BFF told it) is neither named nor vouched for.
3. **The newest 5 releases**, each under a section label ("2.3.0 · 15 NOV") with 10px of room above it, a row per change: an 18px Feed picture for its kind, its title in Body and its detail in Small Smoke Muted, cut to two lines. A click shows the detail whole, until the view is left. A release new on this visit has the Unread dot left of each picture, as on the Feed; a release already seen shows titles only, in Smoke Muted, and a click shows its detail. Rows have no Hairlines: they read like the releases' rules, so releases and changes looked alike; the pictures mark where each change starts.
4. **A Small Dusk Dim line about older updates**, when the changelog holds more than 5: how many you missed aren't shown here, and that older ones are on BFF's CurseForge page.

**Kinds** show as the picture, not as tags (bumpy's major, minor and patch are the release tool's words): a big change is a battle shout on a gold edge, since it asks something of you; a new feature a gift on green, something gained; a small change or fix a wrench on grey (`Skin.CHANGE_PICTURES`, `Skin.CHANGE_EDGES`). Hovering a change names its kind ("Big change", "New feature", "Small change or fix", from Core). Otherwise gold appears only as the Unread dots and the plate's edge (the One Ember Rule).

## Friends' versions

Each Member's record carries `bff`, the BFF version they run (a release version; a checkout sends none). It's written whenever the own record is, so a friend's update reaches the Crew on their next login. Older BFFs ignore the field, so it needs no protocol bump.

## Not decided here

- Showing the out-of-date friends anywhere else (the Roster), or before a major release is seen.
- A slash command to open the view.
