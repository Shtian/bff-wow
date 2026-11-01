# Feed entries are matched across clients by what happened, not by version

A Reaction (#50) lives in the reacting Member's own record and has to point at a Feed entry that every client, the owner's included, can find. The obvious key is the entry's time, which is the record version it was made from (ADR 0001). But the version goes up on every write, including xp, zone and the heartbeat, so a client that only received a later copy has the same ding at a different time, and the owner's own entry has the time of their own write. So an entry is identified by its owner, its Character and what it reached: the level for a ding, the death total for a death, the Character for a new Character or max level, and `joinedAt` for joining.

## Consequences

- A collapsed entry ("dinged 24 (from 22)") covers a range and matches any key inside it: levels 23–24, or death totals 4–5. A Reaction made on it is keyed to the top of the range. The owner never collapses their own entries, so every Reaction finds exactly one entry on their side.
- Death entries store the total they reached, not only how many deaths were added.
- A crash that loses a session's deaths can repeat a death total, so an old Reaction can attach to a newer death within the 30 days Reactions are kept. Accepted as rare and harmless.
