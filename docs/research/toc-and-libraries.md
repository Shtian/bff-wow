# Research: `.toc` version, libraries, and packager for WoW: Forever

Answers issue #3. Researched 2026-10-31, against Forever **1.60.1 beta** (Gethe `forever` branch, build 70532, 2026-10-22) and retail **12.1.5** (`live` branch, build 70688). Forever launches around 2026-11-04, so check these values again after the launch build ships.

Legend: **[confirmed]** = read directly in a primary source (Blizzard UI source, library source, or packager source). **[wiki]** = Warcraft Wiki, which is contributor-maintained and summarizes Blizzard beta notes. **[inferred]** = my own conclusion from the sources, not stated anywhere.

## TL;DR

| Question | Answer |
|---|---|
| `## Interface` for Forever | `16001` (= 1.60.1) [confirmed]. A live/launch value is not published yet. |
| Forever TOC suffix | `_Camelot.toc` is the canonical one. `_Forever.toc` is an accepted alias since Beta 4 [wiki]. Forever is also in the `_Mainline` family [wiki]. |
| Game type for `AllowLoadGameType` | `camelot` [confirmed]. Retail Midnight is `standard`, and both belong to the `mainline` family [confirmed]. |
| `WOW_PROJECT_ID` on Forever | `WOW_PROJECT_CAMELOT = 18`, **not** `WOW_PROJECT_MAINLINE (1)` [confirmed] |
| AceComm-3.0 + ChatThrottleLib | Work. Updated for 12.0 secrets and lockdown. Ace3 trunk lists `16001` [confirmed] |
| LibSerialize, LibDeflate | Pure Lua with no game API calls, so they are unaffected [confirmed source; compatibility inferred] |
| LibDataBroker-1.1 | Pure Lua. Unchanged since 2015 and not affected [confirmed source; compatibility inferred] |
| LibDBIcon-1.0 | Trunk TOC lists `16001` and was updated 2026-10-10 [confirmed] |
| BigWigs packager | Supported since **v2.6.0** (2026-09-18). `BigWigsMods/packager@v2` currently resolves to v2.6.1 [confirmed] |

## 1. TOC: interface number, suffix, game type

### Interface number
- **`16001`** is the Forever 1.60.1 interface number. It follows the usual formula `major*10000 + minor*100 + patch` (1.60.1 → 16001). Sources:
  - Warcraft Wiki *TOC format* lists Forever Beta/Test = `16001` and Forever Live = *no value listed* [wiki]. <https://warcraft.wiki.gg/wiki/TOC_format>
  - Ace3 trunk `Ace3.toc`: `## Interface: 11508, 11509, 16001, ..., 120100, 120105, 120107` [confirmed]. <https://github.com/WoWUIDev/Ace3/blob/master/Ace3.toc>
  - LibDBIcon-1.0 trunk TOC has the same list, including `16001` [confirmed]. <https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0.toc>
  - The packager README example includes `16001` "for ... Forever Beta" [confirmed]. <https://github.com/BigWigsMods/packager#multiple-interface-values>
- **Unknown:** whether the launch build stays at 1.60.1 (`16001`) or bumps. Check `select(4, GetBuildInfo())` in the launch client.
- For reference, retail Midnight is currently `120105` live and `120107` on PTR [wiki].

### Suffix and game type
- Blizzard's own Forever-branch TOCs use the game type **`camelot`**. The branch has 201 `[AllowLoadGameType camelot]` inline directives and lines such as `## AllowLoadGameType: standard, camelot` [confirmed]. <https://github.com/Gethe/wow-ui-source/tree/forever>
- Warcraft Wiki lists the suffixes `_Forever.toc` / `_Camelot.toc` for the Forever game type and `_Mainline.toc` for the family (standard, forever, camelot, plunderstorm, wowhack) [wiki].
- 1.60.1 Beta 4 (build 70291) notes: "Forever is now accepted as an alias for Camelot in TOC file suffixes", in the `[Game]` variable, and in game-type folder lookup. The TOC page adds: "The Camelot value may be changed to Forever in the future." [wiki] <https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes>
- `WOW_PROJECT_ID`: `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` sets `WOW_PROJECT_CAMELOT = 18; WOW_PROJECT_ID = WOW_PROJECT_CAMELOT;` [confirmed]. Any code (ours or a library's) that tests `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` will treat Forever as *not retail*.

### Relationship to Midnight
Beta notes dated 2026-09-15 [wiki]:
- "WoW Forever shares Mainline WoW's UI architecture, including the vast majority of APIs available in 12.1.5."
- "Forever and modern WoW (Midnight) are two game types within the Mainline code family."
- "The addon disarmament changes introduced in Midnight, including secrets, will also be active in Forever."
- Beta 4: "Trial accounts can no longer send addon messages."

### Recommendation for BFF [inferred]
BFF is Forever-only, so use a single `BFF.toc` with:
```toc
## Interface: 16001
## AllowLoadGameType: camelot
```
- With a single unsuffixed TOC, the packager reads `16001` and maps it to the `forever` game type with no extra config (see §3).
- Avoid `BFF_Forever.toc`. The client accepts it, but the packager (v2.6.1) only recognizes the `_Camelot` suffix (see §3). If a suffixed file is ever needed, use `_Camelot.toc`.
- `AllowLoadGameType: camelot` is optional. It keeps BFF from loading on retail if someone installs it there. Keep `camelot` rather than `forever` until it is confirmed which spelling the TOC directive accepts. The wiki only confirms the alias for suffixes, `[Game]`, and folder lookup.

## 2. Libraries

### AceComm-3.0 + ChatThrottleLib (Ace3)
- Ace3 changelog [confirmed] (<https://github.com/WoWUIDev/Ace3/blob/master/changelog.txt>):
  - r1377 (2025-10-28): "AceComm-3.0: Updated ChatThrottleLib for WoW 12.0"
  - r1403 (2026-08-12): "AceComm-3.0/ChatThrottleLib: Fixed errors from secrets during chat lockdown"
- In the current source, `AceComm-3.0` MINOR = 14 and `ChatThrottleLib` version = 32. The CTL hooks skip secret values (`if issecretvalue and (issecretvalue(text) or issecretvalue(destination)) then return end`), and sends use `Enum.SendAddonMessageResult` [confirmed].
- The Forever branch has `Enum.SendAddonMessageResult.AddOnMessageLockdown = 11` and `C_ChatInfo.InChatMessagingLockdown()` [confirmed: `Blizzard_APIDocumentationGenerated/ChatConstantsDocumentation.lua`, `ChatInfoDocumentation.lua`].
- **Caveat [inferred from CTL source]:** CTL only retries throttle results (`AddonMessageThrottle`). A send rejected with `AddOnMessageLockdown` is dropped, and the callback gets `didSend=false, sendResult`. BFF should check `C_ChatInfo.InChatMessagingLockdown()` and hold its own outbound queue while it returns true, instead of trusting AceComm to deliver.
- **Release state:** the last tagged release, **r1403** (2026-08-12), does **not** list `16001` in its TOC. Trunk added it in "Bump toc" commits (2026-09-17 / 2026-10-21). Trunk also has Forever fixes that r1403 lacks: AceDB "Compatibility with WoW Forever" (2026-09-18), AceGUI ColorPicker alpha fix for Forever (2026-10-02), AceDB RP-PvP for Forever (2026-10-28). None of them touch AceComm, so AceComm in r1403 should behave the same as trunk [inferred]. Pull Ace3 from trunk (`https://repos.wowace.com/wow/ace3/trunk/AceComm-3.0`, as BigWigs' `.pkgmeta` does) or from the GitHub mirror's `master`.

### LibSerialize
- Latest commit 2026-10-06 (div-by-zero fix). MINOR = 7. <https://github.com/rossnichols/LibSerialize> [confirmed]
- The source uses only Lua stdlib plus LibStub and calls no WoW APIs [confirmed by reading `LibSerialize.lua`]. Midnight/Forever API changes can't affect it [inferred]. Secrets only matter if we pass secret values *into* it, and BFF serializes its own data.

### LibDeflate
- Version `1.0.2-release`. Last commit 2021-05-05. <https://github.com/SafeteeWoW/LibDeflate> [confirmed]
- Pure Lua 5.1 with no WoW API calls [confirmed]. It is unmaintained but stable, and WeakAuras still embeds it [confirmed: WeakAuras2 `.pkgmeta`]. Compatible [inferred].

### LibDataBroker-1.1
- `LibStub:NewLibrary("LibDataBroker-1.1", 4)`. The repo was last pushed in 2015. <https://github.com/tekkub/libdatabroker-1-1> [confirmed]
- It only uses LibStub and CallbackHandler, with no game APIs [confirmed]. Compatible [inferred]. LibDBIcon's trunk also bundles a copy.

### LibDBIcon-1.0
- Hosted on WoWAce SVN, not GitHub: `https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0` (this is the URL BigWigs' `.pkgmeta` uses). `LibDBIcon-1.0.lua` is MINOR 57, last modified 2026-10-10 (svn rev 165). The trunk TOC lists `16001` [confirmed].
- It uses `Minimap` and `AddonCompartmentFrame`. Both exist on Forever: `Blizzard_Minimap/Camelot/AddonCompartment.xml` and `Camelot/Minimap.lua` [confirmed].

## 3. BigWigs packager

- **v2.6.0 (2026-09-18): "Add WoW Forever support" (PR #202).** v2.6.1 followed the same day. The floating tag `v2` points at the same commit as `v2.6.1` (e50a250), so `uses: BigWigsMods/packager@v2` already includes Forever support [confirmed]. <https://github.com/BigWigsMods/packager/releases>, <https://github.com/BigWigsMods/packager/pull/202>
- How it detects Forever (from `release.sh`) [confirmed]:
  - Any interface `16???` maps to game type `forever` (`toc_to_type`). `16001` becomes game version `1.60.1`.
  - `-g forever` or `-g camelot` forces the game type. `-g 1.60.1` also works, because a version `1.6x.y` is treated as forever.
  - `_Camelot.toc` is recognized as a flavored TOC. **`_Forever.toc` is not**: the suffix regexes and TOC search lists only include `Mainline|Classic|Vanilla|BCC|TBC|Wrath|WOTLKC|Cata|Mists|Camelot`. `_Mainline.toc` accepts both retail and forever interface values.
  - `## Interface-Forever:` / `## Interface-Camelot:` lines work for split-TOC builds, and TOC creation writes `_Camelot.toc`.
  - Build keywords `@version-forever@` / `@non-version-forever@` are supported.
  - CurseForge upload uses `gameVersionTypeID` **88568** for Forever. If the exact version (e.g. `1.60.1`) isn't listed on CurseForge yet, the packager falls back to the next-lower or highest Forever version and prints a warning.
  - WoWInterface: "WoW Forever uploads to WoWInterface are not supported, ignoring."
- **Configuration [inferred]:** no special setup. Put `## Interface: 16001` in `BFF.toc`, set `CF_API_KEY` (and `GITHUB_OAUTH`) as usual, and run `BigWigsMods/packager@v2` on tag push. Externals go in `.pkgmeta` (Ace3 trunk paths, LibDBIcon WoWAce SVN path, GitHub URLs for LibSerialize, LibDeflate and LibDataBroker).

## 4. Not verified / open

- **CurseForge Forever game-version list:** `https://wow.curseforge.com/api/game/wow/versions` needs an API token, so I couldn't check whether `1.60.1` or a launch version is listed under type 88568. The packager's fallback covers this, but check the first upload's game-version tag.
- **Launch interface number:** only the beta value (`16001`) is published.
- **`_Forever` vs `camelot` naming at launch:** Blizzard says Camelot "may be changed to Forever". If that happens, the `AllowLoadGameType` value and the packager suffix list may change.

## 5. Side finding relevant to Member/Character identity

AceDB-3.0 trunk (2026-09-18 to 2026-10-28) shows that Forever uses **region-unique character names with surnames** and **rulesets instead of realms** [confirmed in `AceDB-3.0.lua`]:
```lua
if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
  -- realmKey = "Hardcore" | "RP-PvP" | "RP" | "PvP" | "PvE" via C_GameRules.IsGameRuleActive(...)
  local name, surname = UnitNameUnmodified("player")
  charKey = name .. " " .. surname
```
Commit message: "Remove `realmKey` from `charKey` in WoW Forever as names are unique across all rulesets." For BFF this means a Character's identity probably shouldn't be `Name-Realm`. Also, the addon-message `sender` format on Forever (with or without realm or surname) is **unverified** and should be tested in-game before deciding how Characters are keyed [inferred].
