# The earliest Claim wins on each client, until the owner's Give settles it

A Hand-me-down (#54) lives in its owner's record and each Claim in its claimer's (ADR 0001), so no client sees every Claim at the same moment, and nobody can lock a Hand-me-down for everyone. Each client therefore shows as winner the earliest Claim by server time among the Claims it holds, ties broken by Member id, and when that Claim is withdrawn the next-earliest wins. The owner's **Give** is final: it writes the receiving Member and Character into the Hand-me-down, and from then on every client shows that recipient instead of its own calculation.

## Considered Options

- **The owner accepts a Claim** before anyone is told they won: one source of truth, but a Claim then waits for the owner to log in, and the claimer can't see where they stand.
- **First Claim to reach the owner wins**: depends on message order, which differs per client and can't be shown the same way elsewhere.
- **Earliest by server time, settled by the Give** (chosen): every client holding the same Claims agrees without talking, the owner sees who to mail as soon as the Claims reach them, and the Give removes any disagreement left.

## Consequences

- Before the Give, two clients can briefly show different winners when one hasn't received an earlier Claim yet. Accepted: it resolves as records spread, and the Give overrides it.
- A Claim that arrives after the Give, even an earlier one, changes nothing.
- A Removed Member's Hand-me-downs are hidden and their Claims ignored on your client only, like everything else about Remove.
- Server time is the claimer's own `GetServerTime()`, trusted the same way record versions are.
