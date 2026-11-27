# Joining a Crew

Answers [How does joining a Crew work?](https://github.com/Shtian/bff-wow/issues/10). Builds on the channel research in #2, sync in #8 (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`) and code structure in #9 (`docs/design/code-structure.md`). Domain vocabulary from `CONTEXT.md`.

## The idea in one line

A Crew is nothing more than its **Crew code**: whoever has the code is in. The code is turned into a hidden channel name and password, a Member is in at most one Crew at a time, and leaving is a flag in your own record plus leaving the channel.

## Crew code

- **Format:** 8 characters from Crockford's base32 alphabet (`0-9 A-Z` without `I L O U`), shown as two groups of four: `K3F9-A2QX`.
  - The first 7 characters are random (35 bits, from Core's `random()`).
  - The last is a **check character**: the sum of each character's value times an odd weight (1, 3, 5, … 13), mod 32. It catches every single mistyped character and nearly all swapped pairs, so a typo fails at `/bff join` instead of silently creating an empty Crew.
- **Typing it is forgiving:** case doesn't matter, spaces and dashes are ignored, `O` is read as `0`, and `I`/`L` as `1`. The normalised code is what gets stored and shared.
- **Codes are always generated**, never chosen. A chosen name like `sundaycrew` is easy to guess, and anyone who guesses it is in.
- **No Crew name** in v1. The panel title stays "BFF". A name would be one more record with no single owner, which the sync model avoids.
- **Sharing:** you send the code to the other Members outside the game (Discord, text). In game, `/bff code` prints it, and the panel shows it in a read-only edit box with the text selected, since addons can't write to the clipboard.

### Threat model

The code keeps strangers from stumbling into the Crew; it is not meant to stop a determined friend-of-a-friend who was given it, or someone set on attacking a 35-bit code. Anyone who has the code can join, read everyone's records and publish their own. BFF has no owner, no kick and no ban; a Member who doesn't want to see someone uses **Remove** (local only, per ADR 0001). A Crew that wants to shut someone out starts a new Crew and shares the new code with everyone else.

The game itself is different: the first Character to join a custom channel becomes its channel owner and could change the password or kick someone with chat commands. BFF never does this, and any Member could, which is accepted for a Crew of friends.

## Hidden channel name and password

Both are derived from the normalised code, never the code itself:

- **Channel name:** `BFF` followed by a 32-bit hash of `"name:" .. code` written as 7 base32 characters, e.g. `BFF2Q7MK9T`.
- **Password:** a 32-bit hash of `"pass:" .. code`, also as 7 base32 characters.
- **Hash:** a small pure-Lua string hash (FNV-1a, 32-bit, using the `bit` library that both WoW and LuaJIT provide). It only has to spread names out, not resist attack.

Why hash instead of using the code directly:

- The channel name shows in the Channels UI and `/chatlist`, and in screenshots and streams. The code and password can't be read off it at a glance. (Someone who reads the source could brute-force a 35-bit code from the name offline; see the threat model.)
- A fixed `BFF` prefix keeps names from starting with a digit, makes BFF's channel easy to spot when debugging, and stays well under the channel name length limit.
- Two Crews colliding on a 32-bit name hash is not a concern at our scale. If it ever happened, the second Crew would be locked out by the first one's password, and the wrong-password notice below would tell them to start a new Crew.

Joining follows #2: `JoinTemporaryChannel(name, password)` from the channel link once the channel list has settled (or after a 10 s fallback), never during lockdown. The channel counts as joined only once the game confirms it with a `YOU_CHANGED` notice, the member list arrives, or BFF is already in it after a `/reload`. A channel number from `GetChannelName` alone isn't proof: the client hands one out even when the server refused the join. The channel is then removed from every chat frame. A temporary channel is left automatically on logout. A join failure keeps the channel link down: the channel link tells Core (`joinFailed(kind)`), Core saves the kind and time until the link next comes up, and shows a `notice`:

- Too many channels (the game's error, or no channel 10 s after asking): "BFF couldn't join its channel: leave a chat channel and /reload."
- Wrong password: "BFF couldn't join its channel: leave the Crew and start a new one."

The link doesn't try again until the Crew changes or the next `/reload`. `/bff report` gives the failure as the link's down reason ("wrong password" or "too many channels") and the saved last failure with its time, so it is still there after a `/reload` or relog until a join succeeds. The sync log has each join attempt and how it ended (joined, already in the channel, wrong password, too many channels, timed out) and every notice for the Crew channel with its kind and both names the game gives (arg 2 and arg 5), readable or not. Which kinds Forever sends, and which name is who, isn't checked in game: retail's `PASSWORD_CHANGED` and `OWNER_CHANGED` name who did it, so a Member still in the channel can see who locked it.

### Channel generations

WoW: Forever can break a custom channel on the server: the join gets `INVALID_NAME` and no member list, or a channel that worked turns grey (#298). So the channel above is **generation 0** of a sequence, and the Crew moves up one when the game breaks the current one (ADR 0008):

- **Generation N > 0** is named from `code .. "#" .. N` the same way (`"name:" .. code .. "#" .. N`), with the generation 0 password.
- **`INVALID_NAME` for the Crew channel**, as the answer to a join or at any time later, makes the client step to N+1: it leaves the broken channel (`leaveStale` already leaves any Crew-shaped channel that isn't the current one) and joins the next.
- **The generation is saved and written into your own record.** A client joins the highest of its saved generation and the generations in current Members' records, skipping left and Removed Members. It joins at that generation at login and moves as soon as a record with a higher one arrives. It never goes down.
- **At most 5 steps per session**, counted again from the next login. At the cap the link stays down. The Roster shows "The game won't let BFF into any channel for your Crew. Try again later." in place of "Waiting for the Crew", with a **Report a bug** button that opens the Contact window. A chat line says it once per session.
- **Moving is silent.** `/bff report` shows the generation, where it came from (saved, or a Member's record) and the steps this session. The sync log has each step and its reason.

A partial break, where some Members can use the channel and some can't, heals through vouching: a Member who can still see you whispers you, you vouch for them as a known Member, and your record with the higher generation reaches them. That's why leaving keeps the Crew's data (below).

## One Crew at a time

A player is in **at most one Crew per Ruleset and faction** (ADR 0009). A Character on another Ruleset or faction has a Crew of its own, or none. Joining another Crew on the same Ruleset and faction means leaving the current one first: the panel asks to confirm, and `/bff join` refuses with "Leave your Crew first (/bff leave)". Joining the Crew you are already in does nothing.

Why:

- Every Character is already capped at about 10 custom channels, and other addons (Total RP 3, Musician) use them too.
- The panel, Feed, While you were away and "can play with you" all assume one roster. More Crews would need a Crew picker in each of them.
- The intended use is one circle of real-life friends (the Crew).

Each Crew has its own Member id (ADR 0009). Leaving and rejoining the same Crew keeps it; starting or joining a different Crew gives a new one.

## First run

1. **On first login** with BFF installed and no Crew, BFF prints one chat line: "BFF: type /bff to start or join a Crew." Nothing is sent and no channel is joined.
2. **Opening the panel** (`/bff`, key binding or minimap button) without a Crew shows a setup view instead of the roster:
   - **Display name:** prefilled with the current Character's first name (Forever Characters can also have a last name), which the Member can change. 2–16 characters, counted as UTF-8 characters rather than bytes. Display names don't have to be unique; Members are told apart by id. (The BattleTag was considered as the default and not taken: it would be published without the Member choosing it.)
   - **Start a Crew:** generates a code and joins it.
   - **Join a Crew:** a code box and a Join button. An invalid code shows "That code doesn't look right" under the box.
3. **Right after joining** the panel switches to the roster. It shows your own row, the Crew code to share, and while no one else is known: "Waiting for your Crew. Members show up when they or someone who has seen them is online."
4. The channel link joins the channel, and the usual `up()` sends a DIGEST (code structure, link port), so any online Member replies with what they know.

Slash commands do the same without the panel:

| Command | Does |
|---|---|
| `/bff` | Opens the panel (setup view if not in a Crew) |
| `/bff start` | Starts a Crew with the default display name and prints the code |
| `/bff join <code>` | Joins a Crew with the default display name |
| `/bff code` | Prints the current Crew code |
| `/bff name <name>` | Changes your display name |
| `/bff leave` | Leaves the Crew (asks to confirm) |
| `/bff report` | Opens a copyable diagnostics report with the sync log (`docs/design/code-structure.md`) |
| `/bff debug sync` | Turns printing the sync trace on or off for the session (`docs/design/code-structure.md`) |

The default display name for slash commands is the current Character's name, as in the setup view. It can also be changed in Settings. Changing it writes your own record, so it spreads like any other change.

**Trial accounts** start and join like any other. Since Forever 1.60.1 (2026-11-04) Trial and Veteran accounts can't send addon messages (per the wiki's patch history; not checked in game), so they only receive: their failed sends never take the link down for anyone, and cost at most a DIGEST a minute per friend (`docs/design/code-structure.md`, the link port). (#8 first made them receive-only on purpose; the channel spike's Trial account sent fine before 1.60.1.)

## Leaving

`/bff leave`, or the Leave button in Settings, after a confirm:

1. Core sets the **left** flag in your own record, bumps its version and enters a saved **leaving** state. While leaving, `crew()` still returns the channel and Gossip keeps running.
2. Your record goes out as DATA right away if the link is up (already a send trigger in #8), or on the next `up()` if it is down (lockdown, not yet in the channel). If you log out first, the leaving state survives in saved data and the next login rejoins the channel to finish.
3. Once the DATA has been handed to the link, Core puts the Crew away: you show as not in a Crew and the link leaves the channel, but the Crew's data stays in saved data, out of sight. That's every other Member's record, the Remove list, the Feed log, While you were away, reactions, reached goal rungs and the channel generation. Your own Spares and Claims are still withdrawn. Then it fires `crewChanged`.
   - **Rejoining the same code** brings all of it back, as if you hadn't left.
   - **Starting or joining a different code** on the same Ruleset and faction wipes it, so Crews stay apart.

   The put-away Crew keeps your own record too (Member id, Characters, Main). Keeping the rest means a Member who leaves and rejoins still knows the others, so their whispers are vouched for even when the member list is broken (ADR 0008).
4. The channel link leaves the channel a few seconds later, after ChatThrottleLib has drained.

**After a failed join** (wrong password, too many channels) the link will never come up, so leaving doesn't wait for it: step 3 happens straight away and nothing is sent, not even the tombstone. The others see you go offline as usual. This covers a leave started after the failure, one already waiting when it happens, and one pending at login whose join then fails (the failure finishes it, with "You left the Crew." and no failure notice). You can then start or join another Crew. Joining the same code while a leave is still waiting cancels it, as before.

On the other side:

- A left record is a **tombstone**: Member id, version, display name and the left flag, with no Characters. Your client publishes only that while left. Peers keep it (it still wins by version and is still relayed, so the flag spreads to Members who were offline), don't show it in the panel, and prune it after 180 days like any other record.
- Feed gets one new entry type, **left the Crew**, created when a known Member's record goes from not left to left.
- Rejoining the same Crew writes a new version with the flag cleared, which wins everywhere.
- Leaving is best-effort, like every send. If nobody hears it, you simply go quiet: offline after 12 minutes, hidden after 30 days, pruned after 180.

Leaving is not the same as **Remove**: leaving is what you do to yourself, and everyone sees it; Remove hides someone else from your own view only.

## Changes to Core's interface

Additions to `docs/design/code-structure.md`:

- **Commands:** `startCrew(displayName)`, `joinCrew(code, displayName)` (returns an error for an invalid code or when already in another Crew), `leaveCrew()`, `setDisplayName(name)`.
- **Read:** `crew()` returns the code, channel name and password, or nil when not in a Crew.
- **Listener event:** `crewChanged`, fired on joining and when leaving has finished. App routes it to the channel link so it joins or leaves the channel.
- **New internal file:** `Core/CrewCode.lua` generates, normalises and checks codes and derives the channel name and password.
- Gossip sends nothing while not in a Crew (leaving still counts as in); the channel link is down then anyway.

Scenarios to add to the FakeNet tests:

- A mistyped code is rejected and nothing is joined.
- B joins A's Crew while A is online and both see each other within one DIGEST round.
- C leaves while D is offline; D later learns it from A and gets one "left the Crew" Feed entry.
- C leaves during lockdown and logs out before it clears; after the next login the left record still goes out.
- C rejoins and shows up again, with their Characters.

## Not decided here

- Whether custom channels reach connected realms on retail. On Forever a Crew lives on one Ruleset and faction (ADR 0009).
- The exact setup view layout; it follows the panel style from #7.
