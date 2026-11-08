# A confirming DIGEST instead of ACKs

A message can be lost on the way and no one knows. AceComm splits DATA into 254-byte chunks with no message id, checksum or resend, so one lost chunk loses the whole message. ChatThrottleLib tells the sender that a chunk failed only if the game refused it, never whether it arrived (`docs/research/addon-message-reliability.md`). Before #146 a lost ding came back only at the 5-minute heartbeat, and a failed chunk to one friend took the link down for everyone.

We recover lost messages with DIGESTs, not per-message ACKs. 20–30 s after own DATA goes out, a **confirming DIGEST** follows it. A friend who missed the DATA sees a newer version in it, replies with their own DIGEST, and the existing anti-entropy rules re-send it. A DIGEST also goes out about every minute while the link is up, and one goes to a single friend shortly after a send to them failed. A DIGEST lists the own record and up to 9 others, **taking turns** in a Crew of more than 10 Members. One that leaves records out says so (`partial`), and those records aren't owed.

## Considered Options

- **Per-message ACKs:** each receiver confirms each DATA, and the sender re-sends what isn't confirmed. That costs one message per friend per DATA in every direction, plus timers and resend state per friend and message. It also duplicates what DIGESTs already do. None of the addons surveyed (BigWigs, DBM, WeakAuras, Chomp, RCLootCouncil, Details!) use ACKs.
- **Our own chunk header** (message id, index, total, as Chomp does), to detect a lost middle chunk and read the game's result code: bypasses AceComm, and doesn't recover anything by itself. Left for later, if the sync trace shows it's needed.
- **A shorter heartbeat:** re-sends whole DATA (2–3 chunks per friend) whether anything was lost or not. A DIGEST is one chunk.

## Consequences

- A lost update arrives within about 40 s while the link stays up, and anything else that differs is found within a minute.
- More traffic when nothing is lost: about one DIGEST per friend per minute, plus one after each own DATA. In a Crew of 6 the busiest Member sends about 25 whispers a minute while grinding, well under the throttle (`docs/design/code-structure.md`, Sync).
- No protocol bump: `partial` and `turns` are new optional fields. Older clients ignore them, and a DIGEST without them means what it did before. Older clients still owe every record a full DIGEST leaves out, so in a Crew of more than 10 each DIGEST costs a burst of DATA from each of them. While one is around, the every-minute DIGEST is skipped.
- A record that just went out to everyone isn't owed to a DIGEST that crossed it, for 2 s. If it really was lost, the next DIGEST catches it.
