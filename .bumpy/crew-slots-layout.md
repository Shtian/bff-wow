---
bff: patch
---

Internal: Saved data now keeps each Crew in its own slot, with a Ruleset entry per Ruleset and faction that points at its active and left slot, and a changed Ruleset key is repaired by server ID or name. The first login after updating moves the existing Crew into a slot once and leaves the old saved keys in place.
