# BFF frames its own chunks

A message over 255 bytes has to be split into several addon whispers. AceComm did that for BFF, with one control byte per chunk and nothing to say which message a chunk belongs to or where in it. ADR 0006 left replacing it "for later, if the sync trace shows it's needed". The trace showed it (#163): chunks of a whisper arriving out of order (Ace3 PR #21), and between one pair of Characters every multi-chunk DATA arriving with whole chunks missing, in both directions, for minutes. AceComm glues what it got together, so the message decoded as invalid, the receiver knew nothing more, and the two kept sending the same DATA and DIGESTs.

BFF now splits and reassembles messages itself, in a pure module under the link port (`Link/Framing.lua`). Each chunk carries a message id, its index and the total. Chunks are kept per sender and message id and the message is delivered only when all are in, so reordering and two messages close together are both safe (as Chomp does). A message with no new chunk for 30 s is reported lost, and Core sends that peer a DIGEST of its own, as after a failed send. The channel link sends the chunks through ChatThrottleLib directly, one chunk of a long message at a time from an outbox per peer. The protocol goes to 2.

**New still reads old.** This version sends only the new format. It keeps AceComm's receiving side and accepts protocol 1, so friends who haven't updated are still seen. Every chunk starts with `2|`, which an older BFF reads as a newer protocol: it shows its out-of-date notice and stops seeing updated friends until it updates.

## Considered Options

- **A hard break** (no reading of protocol 1): a mixed Crew looks half offline until everyone updates.
- **Full mixed mode** (sending the old format to friends on an older BFF): needs the version tracked per friend, and keeps the out-of-order bug towards them.
- **A check on the last chunk:** left out. Every chunk is accounted for by index and total, and the Codec rejects a body that doesn't inflate.

## Consequences

- A lost or reordered chunk no longer produces a corrupt message. A message with a chunk missing is known lost within 30 s if any other chunk of it arrived, and that peer is asked again then, not at the next minute's DIGEST. A message none of whose chunks arrive is still found only by a DIGEST. No ACKs: ADR 0006 stands.
- The sync trace keeps the game's result code for a failed chunk, which AceComm reduced to true or false. Which code Forever returns for a whisper to a logged-out friend is still to be read from it.
- A peer who leaves has their unsent chunks dropped, since ChatThrottleLib holds only one chunk of a long message at a time. That closes what #178 left open. A chunk already handed over still goes.
- A chunk holds 247 bytes of a message, not 254, so a message of 248 to 255 bytes now takes two whispers. A DIGEST of 10 entries still fits one.
- One-chunk messages still go at `ALERT`. The rule that every longer message keeps one priority, so chunks never interleave, is no longer needed for correctness.
- When to stop reading protocol 1 is decided later.
