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

Joining follows #2: `JoinTemporaryChannel(name, password)` from the channel link once the channel list has settled (or after a 10 s fallback), never during lockdown. The channel is then removed from every chat frame. A temporary channel is left automatically on logout. Join failures keep the channel link down and show a `notice`:

- Too many channels: "BFF couldn't join its channel: leave a chat channel and /reload."
- Wrong password: "BFF couldn't join its channel: start a new Crew."

## One Crew at a time

A Member is in **at most one Crew**. Joining another Crew means leaving the current one first: the panel asks to confirm, and `/bff join` refuses with "Leave your Crew first (/bff leave)". Joining the Crew you are already in does nothing.

Why:

- Every Character is already capped at about 10 custom channels, and other addons (Total RP 3, Musician) use them too.
- The panel, Feed, While you were away and "can play with you" all assume one roster. More Crews would need a Crew picker in each of them.
- The intended use is one circle of real-life friends (the Crew).

The Member id stays the same across Crews, so leaving and rejoining keeps the same identity.

## First run

1. **On first login** with BFF installed and no Crew, BFF prints one chat line: "BFF: type /bff to start or join a Crew." Nothing is sent and no channel is joined.
2. **Opening the panel** (`/bff`, key binding or minimap button) without a Crew shows a setup view instead of the roster:
   - **Display name:** prefilled with the current Character's first name (Forever Characters can also have a last name), which the Member can change. 2–16 characters, counted as UTF-8 characters rather than bytes. Display names don't have to be unique; Members are told apart by id. (The BattleTag was considered as the default and not taken: it would be published without the Member choosing it.)
   - **Start a Crew:** generates a code and joins it. Not offered on Trial and Veteran accounts, which can't send.
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

The default display name for slash commands is the current Character's name, as in the setup view. It can also be changed in Settings. Changing it writes your own record, so it spreads like any other change.

**Trial and Veteran accounts** can join and see the Crew, but stay receive-only (#8), so others never see them. The setup view says so up front.

## Leaving

`/bff leave`, or the Leave button in Settings, after a confirm:

1. Core sets the **left** flag in your own record, bumps its version and enters a saved **leaving** state. While leaving, `crew()` still returns the channel and Gossip keeps running.
2. Your record goes out as DATA right away if the link is up (already a send trigger in #8), or on the next `up()` if it is down (lockdown, not yet in the channel). If you log out first, the leaving state survives in saved data and the next login rejoins the channel to finish.
3. Once the DATA has been handed to the link, Core forgets the Crew: the code, every other Member's record, the Remove list, the Feed log and While you were away. Then it fires `crewChanged`. Your own record (Member id, Characters, Main) is kept locally, so rejoining resumes where you left off.
4. The channel link leaves the channel a few seconds later, after ChatThrottleLib has drained.

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

- Whether custom channels reach connected realms, and how Forever's rulesets change "same realm" (still open on the map; the spike in #6 checks the channel itself).
- The exact setup view layout; it follows the panel style from #7.
