# Addon message reliability: why Crew updates arrive minutes late

Desk research, 2026-11-08, for the review of sync speed and reliability. Sources: the vendored libraries at the versions pinned in `.pkgmeta` (Ace3 `Release-r1403`: AceComm-3.0 MINOR 14, ChatThrottleLib v32, both byte-identical to Ace3 `master` today), Blizzard's generated API docs from `Gethe/wow-ui-source` (branch `forever`, build 1.60.1.70862, commit `9dc84f0`; and `live` 12.1.5.70783, commit `297d7aa`), the warcraft.wiki.gg API page, and the current source of other addons. Library paths below are relative to `Libs/`. Nothing here was tested in game; anything not checked on Forever is marked **(unverified on Forever)**.

> **Status, 2026-11-08 (v1.2.0):** sections 1–5 still describe the libraries and the API. Section 6's behaviour list and the "BFF turns any one failed chunk…" bullet below describe BFF **before v1.2.0**. #146 then implemented recommendations 1, 3 and 4, most of 5, and 7. #145 implemented most of 8. Recommendation 2 was decided against. For what BFF does now, see `docs/design/code-structure.md` (the link port, Gossip) and `docs/adr/0006-a-confirming-digest-instead-of-acks.md`. In-game results are in [Findings in game](#findings-in-game-on-forever-2026-11-08) at the end.

## Answer

- **A lost chunk loses the whole message, silently.** AceComm has no message id, sequence number, checksum, timeout or resend. A missing first chunk makes the receiver drop the rest; a missing middle chunk makes it deliver first+last glued together (corrupt); a missing last chunk leaves the partial in the spool until the next first chunk overwrites it. Nothing tells the sender.
- **Almost every BFF DATA is multipart.** A measured own DATA is 283–601 bytes on the wire (2–3 chunks); a DIGEST is ~110 bytes (1 chunk). Each chunk is a separate chance of loss.
- **ChatThrottleLib (CTL) retries only `AddonMessageThrottle`.** Every other non-success result (`GeneralError`, `ChannelThrottle`, `AddOnMessageLockdown`, `TargetOffline`, …) drops that chunk, then CTL goes on sending the message's remaining chunks.
- **AceComm hides the result code.** BFF's `callbackFn` gets `didSend` (a boolean) but never the `Enum.SendAddonMessageResult`, so BFF can't tell "peer logged out" from "general error". It also gets no peer name unless it passes one as `callbackArg`.
- **Before v1.2.0, BFF turned any one failed chunk to any one peer into a 5-second link outage for everyone** (`onRefused`; fixed by #146). Own DATA was marked sent (`dirty = false`) before anything is known about delivery. So a ding lost on the wire was recovered only by the next DIGEST exchange or by the 5-minute heartbeat. That matched "minutes late".
- **Throttle model.** CTL's budget is global and counted in bytes (800 B/s, 4000 B burst, shared by every addon using CTL). It doesn't model the server's per-prefix 10-message allowance, but it doesn't need to: throttled sends are re-queued and retried every ≥0.35 s. Per the wiki, **whispers outside instanced content are exempt from the per-prefix throttle** (unverified on Forever), so BFF's whisper mesh may rarely hit it at all.
- **New risk: Forever 1.60.1 (2026-11-04) stops Trial and Veteran accounts from sending addon messages** (wiki patch history). This reverses the retail spike's design consequence 6. Whatever result such an account gets back will drive `onRefused` every time it sends. Check in game.
- **Recommendation, short:** keep the anti-entropy design, but (1) keep per-peer failures local, (2) follow each own DATA with a confirming DIGEST a little later instead of adding per-message ACKs, (3) make the DIGEST cover every Member over time (rolling), and (4) add a `/bff debug sync` trace that logs per-chunk results by peer.

## 1. AceComm-3.0 internals

| Topic | Finding | Source |
|---|---|---|
| Chunk size | A message of ≤255 bytes goes as one message. Longer ones go in 254-byte pieces, each led by one control byte, so a message of `n` bytes takes `ceil(n/254)` sends. | `AceComm-3.0/AceComm-3.0.lua:94-137` |
| Control bytes | `\001` first, `\002` next, `\003` last, `\004` escape (a single message whose first byte is `\001`–`\009`). BFF messages start with `1|`, so they're never escaped. | `:41-44`, `:106-113` |
| Stream key | Reassembly is keyed by `prefix .. "\t" .. distribution .. "\t" .. sender`. There's no message id, so only one multipart message per sender, prefix and distribution can be in flight. | `:165`, `:179`, `:200` |
| New first while a message is pending | Overwrites the spool silently (the warning is commented out). The earlier message is lost. | `:164-176` |
| Next or last with no first | Dropped silently. | `:183-186`, `:204-207` |
| Lost middle chunk | Not detected: `last` concatenates whatever was spooled and fires the callback with corrupt text. | `:199-219` |
| Lost last chunk | The partial stays in `multipart_spool` until that sender's next first chunk. There's no timeout: the file's TODO says "Time out old data rotting around from dead senders?" | `:16`, `:51` |
| Out-of-order arrival | No sequence numbers; chunks are appended in arrival order. | `:188-196` |
| Order per target | No guarantee from AceComm itself. It relies on CTL's FIFO and on one priority per message. The comment warns that mixing priorities "can easily lead to out-of-sequence delivery". | `:84` |
| Queue name | Hard-coded `queueName = prefix`: every whisper on prefix `BFF`, to every peer, shares one CTL pipe per priority. Callers can't change it. | `:96` |

## 2. `SendCommMessage` callbackFn

AceComm wraps the user callback as `ctlCallback(sent, sendResult)` and calls `callbackFn(callbackArg, sent, textlen, sendResult)` (`AceComm-3.0.lua:99-103`). CTL actually invokes its callback as `callbackFn(callbackArg, didSend, sendResult)` (`ChatThrottleLib.lua:429`, `:608`), and AceComm passes the byte count as CTL's `callbackArg` (`AceComm-3.0.lua:117,123,130,136`). So, in practice:

- **Arguments:** `(callbackArg, bytesSentSoFar, totalBytes, didSend)`. The fourth argument, named `sendResult` in AceComm, is CTL's **boolean** `didSend`. The enum `sendResult` is CTL's third argument, and AceComm drops it. BFF's `onSent(_, _, _, didSend)` reads this correctly (`Game/ChannelLink.lua:409-411`).
- **When:** once per chunk, when it is actually handed to `C_ChatInfo.SendAddonMessage`. That is either synchronously inside `SendCommMessage` (the direct path, `ChatThrottleLib.lua:596-612`) or later from `OnUpdate`.
- **Throttled chunks:** no callback. They're re-queued and the callback fires when a retry succeeds (`:403-406`, `:599`).
- **Any other failure:** callback with `didSend = false`. The chunk is dequeued and gone (`:409-430`).
- AceComm's own docs list only three callback arguments (`AceComm-3.0.lua:81`). Other addons' annotations copy that, for example RCLootCouncil `Classes/Services/Comms.lua:110`.

## 3. ChatThrottleLib v32

| Topic | Finding | Source |
|---|---|---|
| Priorities | `ALERT`, `NORMAL`, `BULK`. Each has a ring of pipes. **Not strict precedence:** available bandwidth is split equally among the priorities that have something queued. | `ChatThrottleLib.lua:9`, `:192-194`, `:507-515` |
| Pipes | One FIFO pipe per `queueName or prefix` within each priority, round-robined. AceComm always uses the prefix (above). | `:524-538`, `:627`, `:396-433` |
| Bandwidth | A single **global** byte budget shared by every addon that loads CTL: `MAX_CPS = 800` B/s, `BURST = 4000` B, and each message costs `#text + MSG_OVERHEAD (40)`. Sends that bypass CTL are hooked and subtracted. A full chunk costs ~295 B, so the budget allows ~13 chunks of burst and then ~2.7 chunks/s. | `:60-63`, `:291-301`, `:315-339`, `:593` |
| Hard clamp | For 5 s after login and after every `PLAYER_ENTERING_WORLD` (loading screens), the budget is capped at 400 B and refills at 80 B/s (~1 full chunk per 3.7 s). The rate is halved below 20 fps. | `:321-328`, `:439-441` |
| Direct vs queued | If nothing is queued and the budget allows, the message is sent at once. Otherwise it's queued, and so is a direct send that comes back throttled. | `:596-627` |
| Throttled retry | Only `AddonMessageThrottle` (3) counts as throttled. The pipe moves to a "blocked" ring and is relinked every ≥0.35 s, keeping the message at its head. | `:380-382`, `:403-406`, `:463-469` |
| Failure | Everything else, including `ChannelThrottle` (8), `GeneralError` (9), `AddOnMessageLockdown` (11), `TargetOffline` (12) and a Lua error in the send, is dequeued with `didSend = false`. | `:357-378`, `:407-430` |
| Fit to the server limit | The server limit is per prefix, 10 messages, refilling 1/s ([wiki](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage), "Message throttling"). CTL counts global bytes, so it can exceed the per-prefix count. That costs latency (a retry every 0.35 s), not data. The same wiki section says "This restriction does not apply to whispers outside of instanced content" and that the numbers "can be dynamically reconfigured by the server at any time". | wiki; CTL as above |

**Own pacing?** Not needed for correctness, since CTL already retries throttles. Pacing would only matter if Forever does throttle whispers per prefix (the spike measured CHANNEL, not WHISPER) **(unverified on Forever)**. If the trace shows many throttles, the fix is fewer messages per event (fan-out × chunks), not a second rate limiter. Note that Chomp raises CTL's global `BURST`/`MAX_CPS` on `WOW_PROJECT_MAINLINE` only, so it doesn't affect Forever (`Chomp/Internal.lua:512-517`).

## 4. Blizzard API (Forever 1.60.1 docs)

`Enum.SendAddonMessageResult` is identical on `forever` and `live` (`Blizzard_APIDocumentationGenerated/ChatConstantsDocumentation.lua:154-166` on `forever`):

| Value | Name | Value | Name |
|---|---|---|---|
| 0 | Success | 7 | InvalidChannel |
| 1 | InvalidPrefix | 8 | ChannelThrottle |
| 2 | InvalidMessage | 9 | GeneralError |
| 3 | AddonMessageThrottle | 10 | NotInGuild |
| 4 | InvalidChatType | 11 | AddOnMessageLockdown (11.1.0) |
| 5 | NotInGroup | 12 | TargetOffline (12.0.0) |
| 6 | TargetRequired | | |

- `C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)` returns a non-nilable `SendAddonMessageResult` (`ChatInfoDocumentation.lua:516-531`). The wiki says the result means the message "has been enqueued by the API for submission". So `Success` is not delivery: the spike saw `Success` for CHANNEL sends that never arrived (`docs/research/channel-spike.md`).
- Limits ([wiki](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)): message "at most 255 characters", no NUL; prefix at most 16 characters; WHISPER works for "players on the same or any connected realms". AceComm's comment confirms that bytes 256+ are silently truncated (`AceComm-3.0.lua:95`).
- **Whisper to an offline player:** the wiki says it "Prints a "Player is offline." system message", with return code 12 `TargetOffline` (added 12.0.0). On Forever the spike saw "No player named '%s' is currently playing." (`ERR_CHAT_PLAYER_NOT_FOUND_S`), which BFF filters (`Game/ChannelLink.lua:284-301`). Which code and which message Forever gives for a just-logged-out peer is **unverified on Forever**.
- **Trial/Veteran:** the wiki's patch history says "Patch 1.60.1 (2026-11-04): Trial accounts (including Veteran) can no longer send addon messages." The result code they get is not documented.
- `C_ChatInfo.InChatMessagingLockdown()`: "Returns true if API security restrictions regarding chat messaging are in effect" (`ChatInfoDocumentation.lua:293-301`).
- `ADDON_RESTRICTION_STATE_CHANGED(type, state)`: "always be fired before a restriction becomes active, or after it is deactivated". During that dispatch `state` is `Activating` (1), and `IsAddOnRestrictionActive` returns false while the event is being dispatched (`RestrictedActionsDocumentation.lua:58`, `:99`; `RestrictedActionsConstantsDocumentation.lua:13-15`). The types are Combat 0, Encounter 1, ChallengeMode 2, PvPMatch 3, Map 4, Chat 5 (`:26-31`).

## 5. How other addons do it (source read)

| Addon | What it does | Source |
|---|---|---|
| BigWigs | Raw `SendAddonMessage` with single short messages. On 3/8/9 (throttle, channel throttle, general error) it retries **once** after 1 s. It treats 11 (lockdown) as an expected silent drop and anything else as an error. | `BigWigs/Core/PluginPrototype.lua:249-258`; `Loader.lua:2080-2091` |
| DBM | CTL directly with single tab-separated messages (no AceComm multipart), `NORMAL` for most traffic and `ALERT` for urgent syncs. No acks. | `DBM-Core/modules/AddonComms.lua:103-125`, `:158-161` |
| WeakAuras | Pull model: the receiver asks for the data (`dR`), and the sender whispers it at `BULK` with the AceComm callback driving progress messages on a **separate prefix** at `ALERT`. Cross-realm sends use Chomp. No ack or resend: on failure the user just asks again. | `WeakAuras/Transmission.lua:596-632`, `:704-707` |
| Chomp | Every chunk carries a 12-hex-character header (flags, session id, message index, total), so reassembly is keyed by sender and session. It tolerates out-of-order chunks and interleaved messages and dispatches only once all `msgTotal` parts are in. No resend, no timeout. | `Chomp/Internal.lua:107-111`, `:170-212`, `:218-231` |
| RCLootCouncil | AceComm with LibSerialize, LibDeflate and `EncodeForWoWAddonChannel` (the same pipeline as BFF's Codec). Its "guaranteed" comms are queued while `ADDON_RESTRICTION_STATE_CHANGED` reports Active or Activating and re-sent when the restriction lifts. It has no other acks. | `Classes/Services/Comms.lua:170-238`, `:244-257`; `Classes/Services/CommsRestrictions.lua:20-31` |
| Details! | Guild sync is a request/list/missing-ids/data exchange, essentially a digest. It sends one item per whisper every 4 s from a ticker, with a "todo: need to check if the target is still online". | `core/network.lua:504-555` |

None of these use per-message ACKs. Reliability comes from keeping messages to one chunk (BigWigs, DBM), from the receiver re-asking (WeakAuras, Details!), or from re-sending after a lockdown (RCLootCouncil, BigWigs' single retry). Commits read: BigWigs `6eb1eac`, DBM `f9664b0`, WeakAuras `2837a63`, Chomp `6a30efd`, RCLootCouncil `e078396`, Details! `f7d6f19`.

## 6. What BFF did before v1.2.0, and recommendations

**Wire sizes.** These were measured with the vendored LibSerialize and LibDeflate through the same steps as `Core/Codec.lua:16-19`, on synthetic records. Real ones with Spares, Clears, Catches or Reactions will be larger.

| Message | Raw serialized | On the wire | Sends |
|---|---|---|---|
| DIGEST, 10 entries | 178 | 110 | 1 |
| Own DATA, 1 Character, no professions or Play times | 297 | 283 | 2 |
| Own DATA, 3 Characters, professions, Play times | 1083 | 546 | 3 |
| Own DATA, 6 Characters, professions, Play times | 1743 | 601 | 3 |
| Owed DATA, 5 such records | 4170 | 811 | 4 |

**Behaviour before v1.2.0 that made losses slow to heal** (line numbers are from that version; #146 changed or works around each one):

- `onSent` treats any `didSend == false` on any chunk to any peer as "link down for 5 s" (`Game/ChannelLink.lua:392-411`). While the link is down `send` drops everything (`:483-484`), and Gossip cancels owed replies (`Core/Gossip.lua:90-96`). A peer who just logged out (`TargetOffline`, if Forever returns it) or a Trial/Veteran sender can therefore keep the whole Crew's link flapping.
- Messages already in CTL's queue when lockdown starts still go out. They come back `AddOnMessageLockdown` and are dropped (CTL, above), which triggers `onRefused` again. The spike saw messages to a receiver in lockdown dropped while the sender got no error (`docs/research/channel-spike.md`, Lockdown).
- `sendOwn` sets `dirty = false` before the send's outcome is known (`Core/Gossip.lua:69-75`). After a loss, own DATA goes out again only through a DIGEST exchange or the 5-minute heartbeat (`:17`, `:219-221`).
- The DIGEST holds the own record plus the 9 highest versions (`Core/Ledger.lua:320-337`). `digestReceived` treats any record missing from it as owed (`Core/Gossip.lua:174-180`). With more than 10 Members, every DIGEST therefore triggers DATA for the records that didn't fit, and old changes are never confirmed by a DIGEST.

**Recommendations** (status as of v1.2.0 in [Findings in game](#findings-in-game-on-forever-2026-11-08)):

1. **Keep failures per peer.** Pass the peer key as `callbackArg` to `SendCommMessage` (AceComm forwards it; `AceComm-3.0.lua:101`). On `didSend == false`, mark that peer "needs resync": schedule a DIGEST to that peer only (one chunk) after a short delay, and drop the peer if a "No player named"/"Player is offline." notice follows. Don't take the link down. Taking the link down was meant for channel-wide throttles, and CTL already retries those.
2. **If BFF needs the result code** (to tell `TargetOffline` from `GeneralError` from lockdown), it has to bypass AceComm's wrapper. It could call `ChatThrottleLib:SendAddonMessage(prio, prefix, text, "WHISPER", target, queueName, cb, arg)` itself with its own Chomp-style chunk header (message id, index, total). That would also give per-peer `queueName`s and detection of a lost middle chunk (`ChatThrottleLib.lua:631-642`, `Chomp/Internal.lua:218-231`). This is optional: decide after the debug trace shows which codes actually occur.
3. **A confirming DIGEST instead of ACKs.** After own DATA goes out, send a DIGEST ~20–30 s later. A peer that missed the DATA sees a newer version for you and replies with its DIGEST, and the existing logic then re-sends (`Core/Gossip.lua:164-180`). Per-message ACKs would cost one message per peer per DATA in every direction and still need resend logic. None of the addons surveyed use them.
4. **Rolling DIGEST.** Rotate which records fill the 9 non-own slots (for example, round-robin by id), and don't treat absence from a size-limited DIGEST as "owed". Send one DIGEST every ~60 s while up instead of relying on the 5-minute own-DATA heartbeat. That costs 1 chunk per peer per minute, well under any throttle.
5. **Lockdown.** Don't send while `InChatMessagingLockdown()` is true, and on the `Activating` state of `ADDON_RESTRICTION_STATE_CHANGED`. Expect messages queued in CTL to be lost, and send a DIGEST when the restriction lifts (BFF already does this via `up()`, `Game/ChannelLink.lua:386-390`). RCLootCouncil handles this the same way.
6. **Size.** One-chunk DATA isn't achievable with whole-record DATA (≥283 B even for a minimal record). Keep DIGEST under 255 B (it is). Consider `CompressDeflate(s, {level = 9})` only if measured to drop a chunk. Note that raw deflate has no checksum (LibDeflate offers `CompressZlib` with Adler-32), so a glued first+last message may decode into garbage. `Ledger.merge`'s shape check is the last line of defence (`Core/Ledger.lua:383-404`).
7. **Priorities.** Using `ALERT` for single-chunk DIGESTs is safe, since single messages bypass the spool (`AceComm-3.0.lua:258-260`). Keep every multipart DATA on one priority, because chunks of two multipart messages on different priorities to the same peer would interleave in one spool key. Gains are small, since CTL shares bandwidth equally rather than by precedence.
8. **`/bff debug sync` trace** (one line per event, with `GetTime()`):
   - send: message type, id or version, peer, byte length and chunk count
   - per-chunk callback: peer, bytes, didSend (and the enum if recommendation 2 is done)
   - CTL state: `ChatThrottleLib.bQueueing`, `avail`, and whether BFF's pipe sits in the blocked ring
   - link up and down, with the reason (lockdown, refused, list)
   - `ADDON_RESTRICTION_STATE_CHANGED` type and state
   - "No player named" and "Player is offline." notices
   - receive: sender, type, versions, decode result (`invalid` or `newer`)
   - receive side: multipart first, next and last per sender. To see AceComm's silent drops, BFF would have to snoop `CHAT_MSG_ADDON` for prefix `BFF` itself and look at the control byte.
   - time from a peer's DATA version (server time) to its merge here: the actual "late by" figure.

## Open questions to check in game on Forever (as asked before v1.2.0)

1. What does `SendAddonMessage(..., "WHISPER", name)` return for a peer who just logged out: 0, 9 or 12? Which system message prints?
2. What does a Trial or Veteran account get back from an addon whisper since 1.60.1? Does it still receive?
3. Are WHISPER addon messages on Forever subject to the per-prefix 10/1 s throttle outside instances (the wiki says not on retail)? Send 30 whispers in one frame and count result codes.
4. Do multipart whisper chunks ever arrive out of order or missing a middle chunk? Log the control bytes on receive under load.
5. What do sends return during an encounter lockdown on Forever (11?), and are whispers to a receiver in lockdown dropped as on retail?
6. Real wire sizes of Members' records with Spares, Clears and Catches (log the length and chunk count in the trace).
7. How often does `onRefused` fire in a normal evening, and with which peers? That tells whether recommendation 1 alone fixes most of the lateness.

## Findings in game on Forever, 2026-11-08

From the sync trace (`/bff debug sync`) on v1.2.0 with one friend online on an older release, plus `/dump` checks (#147). Each answer is either checked in game, or not checked because it no longer changes a decision.

| # | Question | Answer |
|---|---|---|
| 1 | Result code and system message for a just-logged-out friend | **Not checked.** Since #146 every failed chunk is handled the same way whatever the code (a DIGEST to that friend only), so the code changes nothing. |
| 2 | Trial or Veteran accounts since 1.60.1 | **Not checked**, and not planned: no one in the Crew plays on one. "Trial and Veteran accounts can't send addon messages" still comes only from the wiki's patch history. |
| 3 | Per-prefix throttle on whispers outside instances | **Not checked.** ChatThrottleLib re-queues a throttled send itself, and anything lost is caught by the next DIGEST. |
| 4 | Chunks out of order or missing | **Not checked.** The trace logs messages only after AceComm has reassembled them. A lost chunk is caught by the next DIGEST. A glued first and last chunk would show as `receive · invalid`, and none were seen. |
| 5 | Sends during an encounter lockdown | **Not checked.** The link goes down on `InChatMessagingLockdown()`, and `up()` sends a DIGEST once it lifts. The `Activating` state is not acted on separately. |
| 6 | Real wire sizes | A friend's own DATA (level-20 Character, 40 deaths): **635 B, 3 chunks**. A DIGEST with 5 versions: **108 B, 1 chunk**. Both are in line with the synthetic sizes in section 6. |
| 7 | Refused sends in an evening | **None seen** in the session logged (no `chunk … failed` lines). |
| 8 | Bypass AceComm's send wrapper for the result code (recommendation 2)? | **No.** #146's recovery doesn't depend on the code, so there's nothing to gain. Revisit only if `late` figures stay in minutes. |

**How late updates arrive.** The trace's `late Ns` (the time from a record's version to its merge here) read **0, 16, 48, 14, 0, 17 s**, with the friend on an older release. That fits the send timing: news goes out straight away, zone changes after a 10 s debounce, and XP or gold within the 60 s "later" window. Which change each figure belongs to wasn't recorded. Nothing came near the old 5-minute heartbeat. The every-minute DIGEST went out 62 s apart, as designed.

**Forever names.** `UnitName("player")` and `UnitFullName("player")` both return `"Moorwyn", "Stormgaard"`: the last name comes **second, in the slot retail uses for the realm**. The member list, whisper senders and leave notices use `"Moorwyn Stormgaard"` with no realm. BFF compared only the first value, so it whispered every message to itself as well (seen as `receive DIGEST from you · ignored`), and a friend's leave notice never matched their saved Character, which kept them "online" for up to 12 minutes. Both are fixed in #152. Character records still hold the first name only.

**Recommendation status (v1.2.0):**

| # | Recommendation | Status |
|---|---|---|
| 1 | Keep failures per peer | Done (#146). |
| 2 | Bypass AceComm for the result code | Decided against (above). |
| 3 | Confirming DIGEST after own DATA | Done (#146; ADR 0006). |
| 4 | Rolling DIGEST, one every ~60 s | Done (#146). |
| 5 | Lockdown | The link is down during `InChatMessagingLockdown()`, and a DIGEST goes out on `up()`. `Activating` is not handled on its own. |
| 6 | Size | Unchanged: DATA stays multi-chunk, and a DIGEST fits in one. |
| 7 | Priorities | Done (#146): one-chunk messages go at `ALERT`, everything else at `NORMAL`. |
| 8 | `/bff debug sync` trace | Done (#145), except per-chunk result codes, ChatThrottleLib queue state, and per-chunk logging on receive. |
