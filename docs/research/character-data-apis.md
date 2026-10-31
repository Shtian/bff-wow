# Character data APIs under Midnight (12.x)

Research for issue #4: *Which game APIs give us level, XP, zone and deaths under Midnight?*

Researched 2026-10-31 against wow-ui-source `live` at commit `d07eb00` ("12.1.5 (70688)").

**Legend.** **Confirmed** means a primary source states it: Blizzard's generated API docs in [Gethe/wow-ui-source], Blizzard FrameXML, or the Warcraft Wiki page that documents the API. **Inferred** means it follows from those sources but nobody states it outright, or it still needs an in-game check.

## TL;DR

- Every API BFF needs for class, level, XP, max XP, zone, death and login/logout is available. **None returns a secret value when queried for `"player"`**, in combat or out of it. *(Confirmed: none carries a secret flag, and the one that does, `UnitClass`, only goes secret for units that aren't player-controlled.)*
- Secrecy in Midnight is declared per API in Blizzard's generated docs. Combat secrecy targets health, power, auras, casts, threat, the combat log, damage meters and similar data. It does not touch progression data.
- The real Midnight constraint for BFF is **sending**, not reading. `C_ChatInfo.SendAddonMessage` has `SecretArguments = "NotAllowed"`, and addon messages can be locked down in restricted content. Queue Feed entries and sync outside instances and combat.
- `GetServerTime()` is a good shared clock: Unix epoch seconds from the server, described as "guaranteed to be synchronized between clients". *(Confirmed, Warcraft Wiki.)*
- There is no "first login" API. Detect a new Character with a heuristic: its GUID is missing from account-wide SavedVariables **and** `TIME_PLAYED_MSG.totalTimePlayed` is small. *(Inferred.)*

## How Midnight marks secret values (background)

Blizzard's generated docs (`Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua`) annotate each function and event with secrecy metadata. The flags below come from `SecretPredicatesDocumentation.lua`:

- `SecretReturns`, `SecretWhenInCombat`, `SecretWhenUnit*Restricted`, `SecretInChatMessagingLockdown`, `SecretOnRestrictedMaps`, and others mark *when* an API produces secrets.
- `SecretWhenUnitIdentityRestricted`: "Guarded APIs and events produce secret values when the unit isn't player-controlled or in the party/raid."
- `SecretInChatMessagingLockdown`: "…produce secret values when encounter, challenge mode, or PvP match addon restrictions are in effect, and when the player is on a communication-restricted map such as a dungeon or raid."
- `SecretArguments` controls whether a function *accepts* secrets as arguments. `AllowedWhenUntainted` means "a function only accepts secret values if execution isn't tainted", and `NotAllowed` means "will never accept secret values, even from untainted callers" ([Warcraft Wiki: Secret Values]). Most APIs, including `UnitLevel`, carry `AllowedWhenUntainted`. That only matters if an addon passes in a secret, and BFF passes the literal `"player"`.
- What tainted (addon) code cannot do with a secret: compare it, test it as a boolean, do arithmetic on it, index it, or use it as a table key. It *can* store a secret and concatenate it ([Warcraft Wiki: Secret Values]). `issecretvalue(v)` and `canaccessvalue(v)` are available as runtime guards.

In this build only 19 functions carry blanket `SecretReturns`, and only 4 carry `SecretWhenInCombat` (all `C_DamageMeter.*`). Those 19 cover health, absorbs, range, cast targets, raid markers and `CombatLogGetCurrentEventInfo`. *(Confirmed, grep of the generated docs.)*

## Per-API findings

The flags were read straight from the generated docs at the commit above. "Secret flags" lists every `Secret*` or `ConditionalSecret` annotation on the API.

| Need | API / event | Source file | Secret flags | Out of combat | Secret for `"player"`? |
|---|---|---|---|---|---|
| Class | `UnitClass(unit)` → `className, classFilename, classID` | `UnitDocumentation.lua` | `SecretWhenUnitIdentityRestricted`; `className` is `ConditionalSecret` | Yes | **No.** The predicate applies only to units that aren't player-controlled or in your group. Use `classFilename` or `classID` for logic anyway, since they carry no flag. *(Confirmed)* |
| Level | `UnitLevel(unit)` | `UnitDocumentation.lua` | none (only `SecretArguments = AllowedWhenUntainted`) | Yes | No *(Confirmed)* |
| Level change | `PLAYER_LEVEL_UP` (level, healthDelta, …), `PLAYER_LEVEL_CHANGED` (oldLevel, newLevel, real), `UNIT_LEVEL` | `UnitDocumentation.lua` | none | Yes | No *(Confirmed)* |
| XP | `UnitXP(unit)`, `UnitXPMax(unit)` | `UnitDocumentation.lua` | none | Yes | No *(Confirmed)* |
| XP change | `PLAYER_XP_UPDATE` (unitTarget) | `UnitDocumentation.lua` | none | Yes | No *(Confirmed)* |
| XP disabled | `IsXPUserDisabled()` | `PlayerScriptDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Max level | `GetMaxLevelForPlayerExpansion()`, `GetMaxLevelForLatestExpansion()` | `ExpansionDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Max level | `GetMaxPlayerLevel()` | `PlayerScriptDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Zone name | `GetZoneText()`, `GetRealZoneText([mapID])`, `GetSubZoneText()` | `ZoneScriptDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Zone (map) | `C_Map.GetBestMapForUnit(unit)` → `uiMapID` (nilable; "Only works for the player and party members.") | `MapDocumentation.lua` | none | Yes | No *(Confirmed)*. It can return `nil`, for example during loading screens *(Inferred from `Nilable = true`)* |
| Zone (map) | `C_Map.GetMapInfo(uiMapID)` → name, mapType, parentMapID | `MapDocumentation.lua` | none (`MayReturnNothing`) | Yes | No *(Confirmed)* |
| Zone change | `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS` (no payload) | `MapDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Death | `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` (no payload) | `DeathInfoDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Dead state | `UnitIsDeadOrGhost(unit)` | `UnitDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Login | `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD` (isInitialLogin, isReloadingUi) | `SystemDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Logout | `PLAYER_LOGOUT`, `PLAYER_LEAVING_WORLD` | `SystemDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Played time | `RequestTimePlayed()` → `TIME_PLAYED_MSG` (totalTimePlayed, timePlayedThisLevel) | `PlayerScriptDocumentation.lua`, `SystemDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Identity | `UnitGUID(unit)` | `UnitDocumentation.lua` | `SecretWhenUnitIdentityRestricted` | Yes | **No** for `"player"` (same predicate as `UnitClass`) *(Confirmed)* |
| Clock | `GetServerTime()` | `SystemTimeDocumentation.lua` | none | Yes | No *(Confirmed)* |
| Sending | `C_ChatInfo.SendAddonMessage` | `ChatInfoDocumentation.lua` | `SecretArguments = "NotAllowed"` | n/a | You must never pass a secret value into it *(Confirmed)* |

### Notes per area

**Level and max level.**
- `PLAYER_LEVEL_UP` carries the new level as its first payload value.
- `PLAYER_LEVEL_CHANGED` also has a `real` flag. Blizzard's chat frame uses it for the level-up message (`Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua`). *(Confirmed.)*
- Detect max level with `UnitLevel("player") >= GetMaxLevelForPlayerExpansion()`. The latter respects the account's expansion entitlement. *(Inferred.)*
- A `PLAYER_MAX_LEVEL_UPDATE` event also exists in `UnitDocumentation.lua`. *(Confirmed it exists; its exact semantics are not checked.)*

**XP.**
- Re-read `UnitXP` and `UnitXPMax` on `PLAYER_XP_UPDATE` and on `PLAYER_LEVEL_UP`, since max XP changes with level.
- At max level, or when `IsXPUserDisabled()` is true, the XP bar is meaningless and should be hidden. *(Inferred.)*

**Zone.**
- `GetRealZoneText()` returns the real zone name, while `GetZoneText()` returns the displayed one. In instances they can differ. *(Inferred from Warcraft Wiki naming. Not verified in game.)*
- For a stable, locale-independent key, store `C_Map.GetBestMapForUnit("player")` (a uiMapID) and resolve the name with `C_Map.GetMapInfo` on the reader's client. Clients in different locales then show their own zone names. *(Inferred.)*
- Update on `ZONE_CHANGED_NEW_AREA` and `PLAYER_ENTERING_WORLD`.

**Deaths.**
- There is no per-character death-count API in the generated docs. `C_ChallengeMode.GetDeathCount` is Mythic+ only. BFF should increment its own counter on `PLAYER_DEAD`. *(Confirmed that no such API exists; the approach is inferred.)*
- Optionally, seed the counter from the achievement statistic "Total deaths" via the legacy global `GetStatistic(id)`. It returns a display **string**, so wrap it in `tonumber()` ([Warcraft Wiki: API GetStatistic]).
- `GetStatistic` is still used by Blizzard's `Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua`, so it exists in 12.x. *(Confirmed.)* The statistic ID for total deaths (commonly cited as 60) is **not verified**, so check it in game.
- Open questions for an in-game test: does `PLAYER_DEAD` fire on Feign Death? Does it fire again on login while dead? *(Unknown.)*

**Login and logout (online status).**
- `PLAYER_ENTERING_WORLD.isInitialLogin` is true on a character login, including relogging from character select. It is false on `/reload` and loading screens ([Warcraft Wiki: PLAYER_ENTERING_WORLD]). *(Confirmed.)*
- `PLAYER_LOGOUT` fires on logout **and on UI reload**, "just before SavedVariables are saved", after `PLAYER_LEAVING_WORLD` ([Warcraft Wiki: PLAYER_LOGOUT]). *(Confirmed.)*
- Implication: BFF can't tell a logout from a reload at `PLAYER_LOGOUT`, and shouldn't count on an addon message sent at that moment reaching anyone. Stamp `lastSeen = GetServerTime()` into SavedVariables there. Peers should treat a Character as offline after a heartbeat timeout. *(Inferred.)*

## Is `GetServerTime()` a good shared clock?

**Yes.** *(Confirmed.)*
- [Warcraft Wiki: API GetServerTime] says it returns "Time in seconds since the epoch" from the server, and that it is "guaranteed to be synchronized between clients".
- By contrast, `time()` reads the local machine clock, which the user can change. The wiki's example shows a 2-second skew between the two.
- Caveat from the same page: changing the system clock while the client is running "may result in this function returning incorrect timestamps".
- `C_DateAndTime.GetServerTimeLocal()` is offset by the realm's time zone, so it is **not** Unix time. Don't use it for ordering.
- The wiki lists `GetServerTime` as available in the Forever flavor. It carries no secret flags.

Recommendation: timestamp every Feed entry with `GetServerTime()`, and sort and deduplicate by `(timestamp, characterGUID, seq)`. Expect a skew of up to a few seconds, which is fine for a Feed. *(Inferred.)*

## Can an addon detect a Character's first login?

There is no dedicated API. *(Confirmed: no `FirstLogin`/`NewCharacter` function or event appears in the generated docs.)* The available signals are:

1. **Account-wide SavedVariables absence.** Key Characters by `UnitGUID("player")`, which is stable and not secret for `"player"`. If the GUID is missing from the account-wide table, BFF has never seen this Character. But that also covers Characters created before BFF was installed, or played on another machine. It is a "new to BFF" signal, not a "new Character" signal. *(Inferred.)*
2. **Played time.** Call `RequestTimePlayed()` and read `TIME_PLAYED_MSG.totalTimePlayed` (seconds). A value of a few minutes or less on `isInitialLogin` means a freshly created Character. *(Inferred.)* Caveat: Blizzard's chat frames register `TIME_PLAYED_MSG` in the SYSTEM chat group and print it (`ChatTypeInfoConstantsOverride.lua`, `ChatFrameOverrides.lua`). An unprompted request will therefore show a "/played" line in chat unless BFF temporarily suppresses that handling. *(Confirmed that it prints; how to suppress it is not researched.)*
3. **Starting level.** Most Characters start at level 1, but some class and race combinations start higher (for example Death Knight, Demon Hunter, Evoker). Level alone is not reliable. *(Inferred.)*

Recommendation: call it a **new Character** when (1) the GUID is absent **and** (2) `totalTimePlayed` is below a small threshold such as 5 minutes. Otherwise call it **newly seen** and backfill its current state without a "new Character" Feed entry. *(Inferred.)*

## Implications for BFF

- Reading progression data is not blocked by Midnight's secret values for the player's own Character. No `issecretvalue` guards are needed on these specific calls, though a cheap defensive `issecretvalue` check before serialising is harmless.
- Use `classFilename` or `classID`, not the localized `className`, which is `ConditionalSecret`.
- Sync is the risky part. Defer sending while in combat, in instances, or during encounters (addon-message lockdown, and `SecretInChatMessagingLockdown` for chat-type APIs). Queue Feed entries in SavedVariables and flush them when restrictions lift. The exact lockdown conditions for `SendAddonMessage` (`Enum.SendAddonMessageResult.AddOnMessageLockdown`, added in 11.1.0) are **not** documented in the sources checked and need their own research or an in-game test.
- Separately, [Warcraft Wiki: API C_ChatInfo.SendAddonMessage] says "Forever and modern clients starting in patch 12.1.7 prohibit trial and veteran accounts from sending addon messages". This matters if any Crew Member plays on a trial account. *(Confirmed per wiki.)*

## Open questions (need an in-game test)

- Statistic ID for "Total deaths" via `GetStatistic`.
- Whether `PLAYER_DEAD` fires on Feign Death or on login while dead.
- The exact conditions under which `SendAddonMessage` returns `AddOnMessageLockdown` in Midnight.
- `UnitXPMax` and `UnitXP` values at max level.

## Sources

- [Gethe/wow-ui-source] at `d07eb00` (12.1.5.70688). Generated docs:
  - `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
  - `MapDocumentation.lua`
  - `ZoneScriptDocumentation.lua`
  - `DeathInfoDocumentation.lua`
  - `SystemDocumentation.lua`
  - `SystemTimeDocumentation.lua`
  - `ExpansionDocumentation.lua`
  - `PlayerScriptDocumentation.lua`
  - `ChatInfoDocumentation.lua`
  - `SecretPredicatesDocumentation.lua`
- The same repo, FrameXML:
  - `Blizzard_ChatFrameBase/Mainline/ChatFrameOverrides.lua`
  - `Blizzard_ChatFrameBase/Mainline/ChatTypeInfoConstantsOverride.lua`
  - `Blizzard_ChatFrameBase/Shared/SlashCommands.lua`
  - `Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua`
- [Warcraft Wiki: Secret Values]
- [Warcraft Wiki: Patch 12.0.0/API changes]
- [Warcraft Wiki: API GetServerTime]
- [Warcraft Wiki: API C_ChatInfo.SendAddonMessage]
- [Warcraft Wiki: API GetStatistic]
- [Warcraft Wiki: PLAYER_ENTERING_WORLD]
- [Warcraft Wiki: PLAYER_LOGOUT]
- [Warcraft Wiki: PLAYER_DEAD]
- [Warcraft Wiki: TIME_PLAYED_MSG]

[Gethe/wow-ui-source]: https://github.com/Gethe/wow-ui-source/tree/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns
[Warcraft Wiki: Secret Values]: https://warcraft.wiki.gg/wiki/Secret_Values
[Warcraft Wiki: Patch 12.0.0/API changes]: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
[Warcraft Wiki: API GetServerTime]: https://warcraft.wiki.gg/wiki/API_GetServerTime
[Warcraft Wiki: API C_ChatInfo.SendAddonMessage]: https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage
[Warcraft Wiki: API GetStatistic]: https://warcraft.wiki.gg/wiki/API_GetStatistic
[Warcraft Wiki: PLAYER_ENTERING_WORLD]: https://warcraft.wiki.gg/wiki/PLAYER_ENTERING_WORLD
[Warcraft Wiki: PLAYER_LOGOUT]: https://warcraft.wiki.gg/wiki/PLAYER_LOGOUT
[Warcraft Wiki: PLAYER_DEAD]: https://warcraft.wiki.gg/wiki/PLAYER_DEAD
[Warcraft Wiki: TIME_PLAYED_MSG]: https://warcraft.wiki.gg/wiki/TIME_PLAYED_MSG
