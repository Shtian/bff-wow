# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The web surfaces are the CurseForge listing and gallery (`docs/gallery/`), the README and the design pages in `docs/design/`. The product itself is an in-game addon. See Capabilities and Constraints.

## Users

Any small group of real-life friends playing World of Warcraft: Forever who don't always play at the same time. The user's own friend group is the first Crew, but the addon is public and written for any group. A Member opens the panel to see where everyone is, and logs in to learn what happened while they were away.

## Product Purpose

BFF keeps a friend group connected when they play at different times. It gives the group a shared friends panel (the Roster: every Member's Characters, levels, whereabouts and when they were last seen) and a Feed of what happened while you were away. It also lets the group react to each other's news, work towards Crew goals, pass items on, and see when everyone usually plays. It succeeds when friends who rarely overlap still feel they're playing together.

## Positioning

It's built around people, not characters or guilds. A Member is one real person across all their Characters and alts, and friends can be in different guilds. Data reaches you even when the Member who wrote it is offline: each Member's client writes its own record, and the Crew's clients gossip those records to each other. So you catch up on friends you never see online.

## Operating Context

- Used inside WoW: Forever (game type `camelot`, a Midnight-style addon API). The panel, While you were away popup, toasts and map pins are in-game frames.
- People join a Crew with a Crew code. Sync runs over a custom chat channel and stops in combat and instances (`C_ChatInfo.InChatMessagingLockdown()`).
- People find and install it on CurseForge or through WowUp from GitHub releases. The listing and README are a group's first impression, often passed on by the friend who set up the Crew.
- Development and testing happen on retail (Midnight), because Forever has no client on the dev Mac.

## Capabilities and Constraints

- Shipped: Roster, Feed, While you were away, Reactions (Cheer, Respects, Welcome), toasts with optional sound, Crew goals, Spares (Claim and Give), Play times heatmap, map pins, minimap button, settings.
- Planned, not built: Competitions (ranked contests) and a level-overlap finder.
- Terminology lives in `CONTEXT.md` (Crew, Member, Character, Feed, Crew goal, Spare, …). Crew goals deliberately name and rank nobody.
- In-game UI is built from WoW frames, not web tech. Its look is set in `UI/Skin.lua`: dark windows, a gold accent, Friz Quadrata titles and Arial Narrow text, drawn with solid colour textures and long-standing game textures. It runs in Lua 5.1 under Midnight's addon restrictions.
- Character names on Forever can have a first and a last name.

## Brand Commitments

- The name "BFF – Best Friends in Forever".
- The icon: two braided rings, one gold and one teal, linked at a spark, on deep navy (`docs/assets/icon.png`, `Media/BFF.tga`).

## Evidence on Hand

- The icon (`docs/assets/icon.png`).
- Design docs per feature in `docs/design/`, and the architecture page `docs/design/architecture.html`.
- The gallery generator in `docs/gallery/`. The in-game screenshots it renders from are in `docs/gallery/shots/`.
- No user count, reviews, testimonials or press yet. Don't invent any.

## Product Principles

1. People, not characters: everything groups by Member, and alts belong to their person.
2. Asynchronous first: what you missed while you were away matters as much as what's happening live.
3. Each Member owns their own data: it's written by their client and shared with the Crew, and there's no server.
4. Small and personal: a circle of real-life friends, not a guild tool.
