# Spike: do two clients see each other over the Crew channel?

Results for [#6](https://github.com/Shtian/bff-wow/issues/6). Run on 2026-10-31 on **retail 12.1.5.70688 (interface 120105)**, two WoW licences on one Battle.net account, side by side on one PC, realm Kazzak. Spike addon: branch `spike/channel-comms` (`Spike.lua`, throwaway). Retail only approximates Forever; re-check at Forever launch.

## Answer

The channel transport holds up. Two clients joined the hidden channel automatically and received each other's addon messages within 0–1 s, in both directions. The whisper-mesh fallback is not needed.

## Findings

| Check | Result |
|---|---|
| Join and hide | `JoinTemporaryChannel` 10 s after login joins with no click (index known 0.5 s later). `RemoveChatWindowChannel` hides the channel's messages. **Channel system notices still print in chat**: owner changed, moderator set, "X left channel". Membership survives `/reload`. |
| Two-way | Both directions, latency 0–1 s. |
| Sender format | `sender` is `Name-Realm` (`Falli-Kazzak`) even on the same realm; `Ambiguate(sender, "none")` gives `Falli`. `target` is `5. BFFSpike6`, `localID` the channel index, `name` the bare channel name, `zoneChannelID` 0. **The sender receives its own messages.** |
| Throttle | 10 messages per prefix in a burst return `Success`; the rest return `Enum.SendAddonMessageResult.AddonMessageThrottle` (a return value, not an error) and are dropped. Refill roughly 1 per second (not measured precisely). Under a burst, delivery lagged up to 6 s. |
| Lockdown | Ordinary combat does not lock chat (`ADDON_RESTRICTION_STATE_CHANGED` type 0, `InChatMessagingLockdown()` false). A boss encounter does (types 1 and 5, true from `ENCOUNTER_START` to `ENCOUNTER_END`). **Messages sent to a client in lockdown are dropped**, not delivered late: AUTO 4 and 5 never arrived, AUTO 6 arrived right after the encounter. |
| Logout | A real logout leaves the channel *before* `PLAYER_LEAVING_WORLD` / `PLAYER_LOGOUT`; sends from them return `GeneralError` and never arrive. During `/reload` the same sends arrive. Others get a "X left channel" notice at the moment of logout. |
| Faction | Custom channels don't cross factions: a Horde and an Alliance character in `BFFSpike6` never heard each other. |
| Realm | A character on another (non-connected) realm never heard Kazzak. Connected realms untested (Kazzak has none). |
| Account flags | `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` returned `true` on a full account that sent fine; don't rely on it. One of the two accounts was a Trial account (`IsTrialAccount()` true, confirmed later), and it sent and received like the other: Trial accounts aren't restricted from addon messages on a custom channel. |

## Design consequences

Applied in `docs/design/code-structure.md`:

1. No send at logout: it can't arrive.
2. The "left channel" notice is an instant offline signal; the 12-minute timeout stays as the fallback.
3. The channel link filters the Crew channel's system notices out of chat.
4. Core ignores messages carrying its own Member id; echo mode is the link not dropping them.
5. A send refused with `AddonMessageThrottle` or `GeneralError` makes the link go `down()` and straight back `up()`, so Core's usual "on `up()`, send a fresh DIGEST and own DATA if changed" rule recovers it.
6. No receive-only mode: Trial accounts send like any other. (BFF first made Trial and Veteran accounts receive-only, from a misread of this spike; removed once the Trial account was confirmed.)
7. On retail a Crew needs one faction and one realm (connected realms untested). Forever's rulesets need re-checking at launch.
