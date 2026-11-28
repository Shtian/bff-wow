# Several Crews per ruleset and faction, one active at a time, chosen per Character

ADR 0009 gave each ruleset and faction its own Crew. A player asked to keep two separate friend groups on the *same* ruleset and faction (#317). So a ruleset and faction can now hold any number of Crews:

- **One Crew is active at a time.** Only its channel is joined, so there's no new traffic, and the protocol doesn't change.
- **A Character can be in several Crews.** Switching never writes a record in the Crew you leave. In the Crew you switch to, the current Character is updated as it would be at login (its level, zone and last played), and nothing else changes: no Character is added to or removed from either Crew's record, and neither marks you as left. The Character stays in each Crew's own record it was played in, and to the other Crews you look offline, the same as logging out.
- **Each Character remembers its last used Crew** (`lastUsed[guid]`). A login picks it. With one Crew and no choice made, that Crew is used, as before. With two or more, the no-Crew card asks "Who is <Character> playing with?".
- **Leaving keeps the Crew** in the ruleset's left list until it is deleted. Characters whose last used Crew was the one left are marked to be asked next time (`lastUsed[guid] = false`), so they are never moved silently into another Crew, even when only one is left.
- **A Crew label is local.** It defaults to the other Members' display names and is never sent.
- **Switching is refused during messaging lockdown** (combat, instances), since leaving and joining channels and sending the first messages wouldn't work there, and while a leave is still pending, so the leave isn't stranded in a Crew you no longer play with.
- **Starting or joining another Crew** starts from a blank slot that carries only your display name, so the new Crew sees only the Characters you play with it.

## Saved layout

`BFF_DB.rulesets[key]` keeps `crews` (the active slot ids), `left` (the left slot ids, newest first), `lastUsed` (`guid` → slot id, or `false` to ask) and `blank`: the slot with no Crew that Core binds while the player picks, starts or joins one. `BFF_DB.crews[slotId]` gains `label`, `leftAt` and `syncedAt` (when another Member was last heard). The #318 layout (`active`, `left` as single ids) moves over at login: a Crew in `active` becomes `crews[1]`, `left` becomes `left[1]`, and every Character in the active Crew's own record gets `lastUsed`. An `active` slot with no Crew becomes `blank`.

## Considered Options

- **A Character belongs to only one Crew:** moving a Character between Crews would remove it from one Crew's record and add it to the other's, so switching a few times a session would show churn to both.
- **Several Crews joined at once:** a channel and a whisper mesh per Crew, so more traffic and more of the roughly 10 custom channels the game allows.
- **A shared Crew name:** new protocol data and more traffic. A local label covers telling Crews apart.

## Consequences

- **A player in two Crews on one ruleset is two Members**, as in ADR 0009.
- **Each Crew sees the Character's state as of the last time it was played with that Crew**, the same as a Character that logged out.
- **An older BFF doesn't read the new layout.** It sees no `active` slot and starts empty, but the data stays in `BFF_DB.crews`.
