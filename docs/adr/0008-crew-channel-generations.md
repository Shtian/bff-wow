# The Crew moves to the next channel generation when the game breaks its channel

WoW: Forever has had a server bug since at least 2026-11-06 that leaves some custom channels unusable ([forum thread](https://us.forums.blizzard.com/en/wow/t/wow-forever-custom-chat-channels-with-passwords-cant-be-rejoined-if-everyone-leaves/2403383), #298). The game answers a join with `INVALID_NAME`, or a channel that worked turns grey. The client still gives the channel a number, but there is no member list and no `YOU_CHANGED`. Logging out, deleting `chat-cache.txt` and switching Character don't help, and it hits World, Trade and channels without a password too. The one trigger named is everyone leaving the channel, which a Crew that never plays at the same time does all the time. A Crew whose channel breaks sits at "Waiting for the Crew" for good, and starting a new Crew loses its Feed, While you were away and open Spares.

So BFF derives a sequence of channels from the Crew code, its **channel generations**, and the Crew moves up one when the game breaks the current one:

- **Generation 0 is today's channel:** the same name and password as before. Generation N > 0 is named the same way from `code .. "#" .. N`, with the same password.
- **`INVALID_NAME` for the Crew channel**, as the answer to a join or at any time later, makes the client step to N+1, leave the broken channel and join the new one.
- **The generation is saved and written into the Member's own record**, so gossip carries it (ADR 0001). A client joins the highest generation among its saved one and the records of current Members, skipping left and Removed Members. It never goes down: a channel the game broke isn't worth going back to.
- **A partial break is bridged by vouched whispers.** When only some Members can't use the channel, the others still whisper them, the whisper is vouched for because the sender is a known Member, and the higher generation reaches them in a record. That's why leaving no longer forgets the Crew's data (`docs/design/joining-a-crew.md`).
- **At most 5 steps per session.** After that the Roster says the game won't let BFF into any channel for the Crew, with a Report a bug button. The count starts again at the next login.

The same bug made "joined" unreliable: the client hands out a channel number even when the server refused the join. A channel now counts as joined only once `YOU_CHANGED` confirms it, the member list arrives, or BFF is already in it after a `/reload`.

MeetingHorn, a widely used group-finder addon, does the same on a smaller scale: on `INVALID_NAME` for its join it tries `name1`, `name2` and so on (`Core/Channel.lua`). It keeps no generation and doesn't bring other users along.

## Considered Options

- **Tell the player to start a new Crew:** loses the Feed, While you were away, open Spares and the dates of goal rungs, and someone has to hand a new code round. Kept only as the last resort, at the cap.
- **Stay in the broken channel and also join the next:** the logs show a client in a broken channel isn't in it (no `YOU_CHANGED`), so staying only costs a channel slot.
- **Each client steps on its own error only:** splits the Crew whenever only some Members are affected, as in #298.
- **The generation in every message header:** reaches peers sooner but changes the wire format. Own records already reach every Member.
- **Drop the password:** the bug hits channels without one, and it would be a protocol change.
- **Whisper known Characters directly, without the channel:** adds traffic to Characters who may be offline, and still needs a way to know who's online.

## Consequences

- Crews whose channel never breaks see no change, and the record grows by one small field. Older clients relay it untouched and stay on generation 0: once a Crew moves, a Member who hasn't updated is cut off and can't be reached with the out-of-date notice. Accepted; it's a minor bump, not a protocol major.
- The generation only grows. Every number gives a valid channel name, so there's no limit to reach.
- A bug or bad record could move a Crew needlessly; that costs a few seconds and a channel slot until `leaveStale` frees it. Removed Members can't move you.
- Moving is silent: the player sees nothing when it works. `/bff report` shows the generation, where it came from (saved, or a Member's record) and the steps this session. The sync log has each step with its reason.
- Which notice kinds Forever sends for a broken channel is read from the sync log. Only `INVALID_NAME` counts until a log shows another.
