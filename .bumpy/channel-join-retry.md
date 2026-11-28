---
bff: patch
---

BFF no longer calls a half-joined channel "too many channels"

Sometimes the game holds on to BFF's channel without really letting it in (an empty row in your Channels settings), and joining again only makes it worse until you log out. BFF used to call this "too many channels" and tell you to /reload, which didn't help. It now leaves the channel and tries again, and if that doesn't work, it tells you to log out and back in.
