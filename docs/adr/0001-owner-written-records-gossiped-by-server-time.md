# Owner-written records, gossiped and versioned by server time

BFF has no server, and Members often play at different times, so sync is gossip: each Member's client is the only writer of that Member's record, and every other client stores it, relays it to whoever is online, and keeps the newer version. There is one record per Member (all their Characters inside), and its version is `GetServerTime()` at the last write rather than a saved counter, because a client crash loses that session's SavedVariables and a counter would drop behind the copies peers already hold, while server time keeps moving forward.

## Considered Options

- **A version per Character with a saved `seq` counter** (the first architecture draft): smaller sends, but a digest of about 30 entries spread over several 255-byte messages, two kinds of record to keep in step, and the crash problem above.
- **Crew-wide authority** (e.g. anyone can remove a Member for everyone): needs trusted removal markers and rules for who may remove whom. Rejected; removing a Member only hides them from your own view.

## Consequences

- No merge conflicts: a received copy wins only if its version is higher.
- The version doubles as "time of last write", and each Character's "last played" time is written by its owner, so last seen spreads to Members who were never online at the same time.
- Multiple accounts per Member would break the one-writer rule (already out of scope).
