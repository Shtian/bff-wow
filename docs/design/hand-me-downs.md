# Hand-me-downs

Answers [Hand-me-downs: records, Claims, notices and tab](https://github.com/Shtian/bff-wow/issues/66), part of [Hand-me-downs: items free to the Crew](https://github.com/Shtian/bff-wow/issues/54). Builds on sync in #8 (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`), the Feed in #14 (`docs/design/feed.md`) and Reactions (`docs/design/reactions.md`). Who wins a Claim is `docs/adr/0003-hand-me-down-claims-earliest-wins-give-is-final.md`. Domain vocabulary from `CONTEXT.md`.

## The idea in one line

A Member offers an item to the Crew as a Hand-me-down in their own record. Other Members Claim it from their own records, the earliest Claim wins, and the owner mails it with ordinary in-game mail, then Gives it in BFF.

## Hand-me-downs

They live in the owner's record, in an optional `handMeDowns` list. Each one has short field names, as Reactions do:

| Field | What |
|---|---|
| `i` | The id, assigned by the owner's client and never reused (a counter in `BFF_DB`, kept across leaving) |
| `s` | The trimmed item string (below) |
| `l` | The required level, 0 if none |
| `t` | The server time it was posted |
| `r`, `c` | Once Given: the receiving Member id and Character GUID |

- At most **20 open** per owner.
- It ends when the owner **withdraws** it (it's taken out of the list), **Gives** it, or **30 days** after posting.
- A Given one stays in the list until its 30 days run out, so every client sees the Give. Then it's pruned.
- Pruning happens on the next write of the own record, so pruning alone never sends DATA. Other clients treat one past its 30 days as ended without waiting.
- **Leaving** the Crew clears the list.

### Posting one

The Hand-me-downs tab has a **drop slot** above your own list (#74, after the research in #65 and #67, `docs/research/bag-items.md`). Dropping a bag item on it offers that item, and so does clicking it while holding one: on retail a click with an item held arrives as either `OnReceiveDrag` or `OnClick`, so both do the same. BFF reads the item's location from `C_Cursor.GetCursorItem()` and always calls `ClearCursor()`, so the item goes back to its bag slot whether it was taken or refused. It works with any bag addon that puts items on the cursor, and in combat, instances and encounters. While messaging is locked down the post waits and goes out when the lockdown lifts, like any other record change.

`/bff hmd add`, then shift-click the item into the chat box, still works. It offers the first item in the bags with the same trimmed item string, and refuses the item if there isn't one.

Either way Core checks the item can be traded (`HandMeDowns.tradeable`): it's refused if `C_Item.IsBound` says it's bound (soulbound, or account-bound at any scope; heirlooms report `bindType` 1 but are bound), or its `bindType` is Quest (4) or one of the account bindings (7, 8, 9). Conjured items aren't caught; the mail window refuses them. The required level comes from the game's item info.

When an item is posted, its **item GUID** (`C_Item.GetItemGUID`) is kept locally in `BFF_DB.handMeDownItems`, by the posting Character's GUID and the Hand-me-down's id. It's never in the record, so it never goes out. It's dropped once the Hand-me-down is withdrawn, Given or ends, and when you leave the Crew. The follow-up (ADR 0004) uses it to notice the item has gone.

### The trimmed item string

Not the whole link, to keep DATA small: the item ID, then the enchant, suffix ID and unique ID, each only if set, separated by colons with unset fields left off the end (`5191`, `5191:1897`, `15210::-19:1238425`). The unique ID is only kept for a negative suffix ID, where it carries the factor a scaling random suffix's stats depend on. #65 is to confirm the link layout under the Forever API.

To show it, the item string `item:15210::::::-19:1238425` is rebuilt with every field where an item link has it, and the game resolves its name, quality and tooltip from that. So a random-suffix item keeps its "of the Monkey". Until the game has the item cached, the tab shows "Loading..." and texts say "an item"; the panel redraws once item info arrives.

## Claims

They live in the claimer's record, in an optional `claims` list:

| Field | What |
|---|---|
| `m` | The owner's Member id |
| `i` | The Hand-me-down's id |
| `c` | The GUID of the Character it's for: one of the claimer's own, by default the one logged in |
| `t` | The server time it was made |

- One Claim per Member per Hand-me-down, and never on your own.
- At most **20 open** Claims.
- A Claim can be withdrawn until the Hand-me-down is Given.
- Pruned when its Hand-me-down has ended (withdrawn, Given or expired, as the held copy of the owner's record says, or the owner is no longer held) or after 30 days.
- **Leaving** the Crew clears the list.

## Who gets it

From ADR 0003:

- Each client shows as winner the **earliest Claim by server time** among the Claims it holds, ties broken by Member id. When the winner withdraws, the next-earliest wins.
- Once **Given**, every client shows the Give's recipient instead of its own calculation. A Claim that arrives later, even an earlier one, changes nothing.
- A **Removed** Member's Hand-me-downs are hidden and can't be Claimed, and their Claims are ignored. A Member who left the Crew has no Hand-me-downs or Claims.

## Notices

Hand-me-down notices go through the same settings and seen-marking as Reactions: a chat line if chat lines are on, a Toast if toasts are on, marked seen as they fire after settling, and While you were away otherwise.

| Who | When | Text |
|---|---|---|
| Owner | A Claim becomes the winning one: the first Claim, an earlier one arriving, or the next one moving up after a withdrawal | "Bob claimed [Cruel Barb] for Jaina" |
| Winning claimer | It's Given to them | "Ana sent you [Cruel Barb]. Check Jaina's mailbox." |

- Claims that don't win, expiry and withdrawal are silent. So is a winner moving up because the owner Removed the one ahead, or a Claim expiring.
- The first sight of a Member (joining, reinstalling) is a silent baseline, the same rule as Feed entries.
- In While you were away they show in a **Hand-me-downs** section, with the Gives that were made meanwhile.
- With chat lines and toasts both off, they stay unseen. Opening the Hand-me-downs tab marks them seen, and its sidebar button shows how many are unseen.
- Clicking a notice's toast opens the Hand-me-downs tab.

The owner's client remembers the winner it last told of per Hand-me-down, so a reload doesn't tell it again.

## The Feed

A Give makes a **gave** Feed entry for the owner: "Ana gave Bob [Cruel Barb]", "You gave Bob ..." on the owner's client and "Ana gave you ..." on the recipient's.

- It has **no** Reaction.
- It's matched across clients by content, the owner's Member id and the Hand-me-down's id (ADR 0002), so skipped versions or a record that arrives twice still make one entry.
- On the recipient's client it's seen when made, since their notice already tells them.
- Its text is worked out when it's shown, so the item's name appears once the game has it.

## The panel

### Hand-me-downs tab

A sidebar tab under When, opened by `/bff hmd`, within the panel's fixed height and scrolling:

- **From the Crew:** other Members' open Hand-me-downs, newest first. Each row has the item's icon and link (hover for its tooltip, shift-click to link it in chat), the required level, the owner, and the Claim state: "No claims yet", "Bob claimed it first", "You claimed it for Jaina", "Bob claimed it first (you claimed it for Jaina)". **Claim** claims it for the Character you're playing, and a right-click on it picks another of your Characters. **Withdraw** takes your Claim back. Rows none of your Characters is high enough level for are dimmed. There's no class or armour check. The heading shows your open Claims, out of 20.
- **Yours:** each of your Hand-me-downs, newest first, with the time left and its winning Claim ("Bob claimed it for Jaina (2 Claims)"). **Give** (once there's a winner) is for after you've mailed the item: it asks to confirm and records the Give. **Withdraw** takes it down. Given ones stay, dimmed, as "Given to Bob (Jaina)", until their 30 days are up. The heading shows how many are up, out of 20.

### Roster

The Crew heading shows "2 Hand-me-downs for you": other Members' open Hand-me-downs one of your Characters is high enough level for. Clicking it opens the tab.

## Changes to Core's interface

- **Commands:** `postHandMeDown(link, level, inBags?)`, where `inBags` is `{ guid, isBound, bindType }` from the bags: an untradeable item is refused, and the item GUID is kept locally, never in the record, `withdrawHandMeDown(id)`, `giveHandMeDown(id)`, `claimHandMeDown(ownerId, id, guid?)`, `withdrawClaim(ownerId, id)` and `handMeDownsSeen()`. Each write bumps the own record's version and goes out now. Like Reactions, they're local writes that work in combat and offline.
- **Reads:** `handMeDowns()` for the tab, `summary().handMeDowns` for the Roster's count, and `handMeDownItems()`, the item GUIDs of the open Hand-me-downs the Character being played posted (`{ [id] = itemGuid }`).
- **Listener events:** `handMeDown(news)`, like `reaction`. `awaySummary(summary)` gains `handMeDowns`, the notices then the Gives, newest first.
- **Ports:** `itemLink(itemString)`, optional: the game's link for an item string, or nil while it isn't cached.
- **Member record:** gains `handMeDowns` and `claims`. Like `reactions`, they're not part of the record's checked shape, so a client that doesn't know them keeps and relays them unchanged, and a malformed item is skipped rather than getting the record dropped.

## Dev

The `/bffdev` console has **Offer** (the simulated Member posts a test Hand-me-down: a plain one, an enchanted one or one with a scaling random suffix) and **Claim** (it claims your newest Hand-me-down) on each simulated Member's row. `/bffdev toast` includes sample Claim, Give and gave toasts.

## Not decided here

- Ending a Hand-me-down when its item leaves the bags: ADR 0004, the follow-up to #74.
- A modifier-click on bag buttons to offer an item.
- Detecting the mail being sent; Give is a button.
- A Reaction on gave entries, a want/craft list, class or armour suitability.
