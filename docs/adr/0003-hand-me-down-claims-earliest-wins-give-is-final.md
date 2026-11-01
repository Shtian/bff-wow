# The earliest Claim on a Hand-me-down wins, but the owner's Give is final

A Hand-me-down (#54) lives in its owner's record and each Claim lives in the claimer's record (ADR 0001), so no single client decides who gets the item. We considered having the owner pick among claimants, but that needs the owner to act before anyone knows the answer, and the point of the feature is that nobody has to be online at the same time. So every client shows the earliest Claim by server time as the winner, with ties broken by Member id, and the result settles once gossip catches up. When the owner Gives the item, the receiving Member and Character are written into the owner's record, and every client shows that over its own calculation.

## Consequences

- Before the Give, the winner shown is only a display and can differ between clients: briefly while records are still arriving, and for good when a client has Removed a claimer (Remove is local, and Removed Members' records aren't held). The owner may have Removed a claimer who claimed first, so they never see that Claim and Give to the next one. The Give then overrides everyone else's view.
- A claimer who loses gets no notice. Their row just names who claimed first.
- A Claim points at its Hand-me-down by the owner's Member id plus an id the owner's client assigns and never reuses. Unlike Feed entries (ADR 0002), a Hand-me-down is something its owner creates explicitly, so a stable id is safe.
