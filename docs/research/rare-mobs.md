# Research: rare mob kills on WoW: Forever

For a possible **rare trophy** idea: a Crew Trophy for killing one of a curated list of noteworthy rare mobs. It belongs to the Crew, not to a person: any Member's kill earns it. Three questions: where can a list of Forever's rares come from, which rares are worth a trophy, and how can an addon tell that someone in the Crew killed one under Forever's restricted API.

**Status (2026-11-13): desk research, plus one retail 12.x test with BFF's Rare logger (section 5); no Forever rare kill logged yet.** The API answers come from Forever's own UI source and are solid. RareScanner's Forever build suggests a corpse's GUID is readable when looting, which would make loot the main signal. That, whether an NPC's GUID is readable out of combat, and how tapping works on Forever, needs a person with a client (see section 5). The list of rares comes from Wowhead's Forever database, which is crowd-sourced.

How sure each answer is:

- **Documented:** a source says so. Forever's UI source and client data are primary sources; Wowhead and fan sites are marked *third party*.
- **Expected:** classic's answer, which Forever may have changed.
- **To confirm:** needs a test in game (Forever, or retail 12.x where the API is the same).

## Sources

- **Forever UI source**: the [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) `forever` branch, **1.60.1 (70938)**, commit [`bebcb6b`](https://github.com/Gethe/wow-ui-source/tree/bebcb6bf309cf41b41bd74f8ca651e6a105b2676). Below, `UI:` is short for `https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/`, and `Docs/` for `Blizzard_APIDocumentationGenerated/` inside it.
- **Wowhead Forever database** (*third party*, built from players' client uploads): NPC pages live at `https://www.wowhead.com/forever/npc=<id>`, and classic's at `/classic/npc=<id>`. The list pages (`/forever/npcs/classification:…`) render in JavaScript and block scripts, so they're no use to a tool. The **tooltip endpoint** works: `https://nether.wowhead.com/forever/tooltip/npc/<id>` returns JSON with the name, a "Level N Type (Rare)" line and the zone with sighting coordinates. Every level and classification in the tables below comes from it, fetched 2026-11-13, with `/classic/` for comparison.
  - Forever NPC IDs **are classic's IDs**: every classic rare checked has a Forever page under the same ID. Forever's new NPCs have new IDs (2xxxxx).
  - Caveat: for many classic rares, the Forever and classic sighting counts are identical (King Mosh: 194 and 194). That suggests Wowhead seeded Forever from classic data, so a Forever page alone doesn't prove the NPC spawns on Forever. Where the counts differ (Foreman Rigger: 17 on Forever, 76 on classic), there are Forever uploads. The table gives both counts.
- **Forever client data** (wago.tools, product `wowf`, build **1.60.1.70938**): Forever's `ItemSet` table ([wago.tools](https://wago.tools/db2/ItemSet?build=1.60.1.70938)) has the new rare sets. The client's `Creature` table only holds a few hundred companion and special NPCs ([wago.tools](https://wago.tools/db2/Creature?build=1.60.1.70938)), so **the client can't say which NPCs are rare.** Classification comes from the server, at runtime, via `UnitClassification`.
- **Fan sites** (*third party*, beta-era):
  - [ForeverChanges: rares](https://foreverchanges.pro/rares) lists Forever's new rares and changed drops, from players' reports and the client.
  - [The Forever Era: rares](https://theforeverera.com/en/rares/) lists CMaNGOS classic-db's 335 classic rares and marks the 23 its addon has seen on Forever (builds 70009–70862).
  - [Metaforge's Forever rare list](https://metaforge.app/wow-forever/rare-spawns) refused automated fetches.
- **Other addons** (*third party*): RareScanner's Forever build 1.60.1.6 ([Wago](https://addons.wago.io/addons/rarescanner)) and AllTheThings ([GitHub](https://github.com/ATTWoWAddon/AllTheThings), `1c4d146`). Section 4 says what each does.
- **Warcraft Wiki**: its NPC infoboxes show **retail** levels (scaled 15–30) and retail classification. Use it for history and drops, not for Forever's level or classification.
- **No official Blizzard post** on Forever rares turned up.

## 1. Where a list can come from

**Verdict: no source can be queried for "every rare on Forever". The list has to be curated by hand and shipped as data, keyed by NPC ID, like `finals` in `Core/Together.lua` and the Catches list.**

- Wowhead Forever is the best source per NPC: its tooltip endpoint confirms the name, level, classification and zone of a known ID. It can't be searched by classification from a script (*third party*).
- The fan lists above are useful leads, especially for Forever's new rares, but they're third party and partly contradict each other: ForeverChanges' header says "42 rares in 18 zones" but lists a different number.
- BFF doesn't need a complete list. A trophy is for a **curated** set, and the allowlist decides what counts, not `UnitClassification`. So a famous named **elite** that isn't a rare (Mor'Ladim) can still be on the list if it's wanted.

## 2. Forever changes found

- **New rares in every starting zone** (all new IDs, all Rare, levels 8–13 on Wowhead Forever): Ghostfang (276111, Dun Morogh), Matriarch Bristlefur (276189) and Elder Finseer (276180, Elwynn Forest), Shal'ma (276198) and Dustwind Eggtender (276194, Durotar), Snarlsnout (276109), Stormherald Ukta (276105) and Thornstarter Igleg (276108, Mulgore), Nightscreech (276101) and Wrathvine (276099, Teldrassil), The Condemned One (276089), Decrepit Harvester (276061), Blightsculler (271080) and Coldrasp (274300, Tirisfal Glades).
- **Zephras Isle** (zone 16593, new): Snapbeak the Quick (259394, Rare Elite 9), The Lost One (256028, Rare Elite 6), Slydris (255887, Rare Elite 6), Den'dralass (250936), Fernfeather (256492), Galemender Delanea (259398), Mystmane (259388) and Tel'daeor the Stormspeaker (259385), all Rare.
- **Mount Hyjal** (zone 616): Pexmit (266901), "Someone's Minion", Rare 60. Ruins of Lordaeron (Forever dungeon): Lordaeron Captain (255699), Rare Elite.
- **New elites that aren't rares**: Nightveiled Rotheap (270589, Wetlands, Elite 31–32), Elmpaw (248299, Elwynn, Elite 12) and Baron Marinous (270294, Darkshore, Elite 21, summoned). All three are Wowhead Forever data.
- **Rare sets** (Forever client data, `ItemSet`; drop rates from Wowhead Forever, *third party*):
  - **Blessing of Kalimdor** (2132): Mark of the Pack Leader (285331) from Humar the Pridelord (89%), Signet of the Zhevra (285330) from Swiftmane (93%), and Raptor Hide Cloak (285329) from Takk the Leaper (75%). 2-piece bonus: "Increases movement speed by 5% in The Barrens and Stonetalon Mountains."
  - **Rider of the Plaguelands** (2130): Signet of the Soulless Rider (284102), Blade of Senseless Slaughter (284101) and Horseman's Unyielding Shroud (284100), level 57. 2-piece bonus: 5% mounted speed in the Plaguelands. 3-piece: a chance on melee hit to deal 140 Shadow damage. Wowhead doesn't name the droppers yet. **To confirm.**
- **New rare drops**: the wiki lists Forever drops for Foreman Rigger ([Foreman's Helm](https://warcraft.wiki.gg/wiki/Foreman_Rigger)) and Azurous ([Magically Fortified Legguards](https://warcraft.wiki.gg/wiki/Azurous)). [ForeverChanges](https://foreverchanges.pro/rares) reports more (Heartrazor's Wyvern Heart Band, Taskmaster Whipfang's Skinsearer and others; *third party*).
- **Classification changes**: **Mother Fang** (471) is Rare 10 in classic but **Elite** 7–10 on Wowhead Forever. Broken Tooth's Forever level reads "37 – 60" against classic's 37; Ressan the Needler's reads "11 – 12" against 11. **To confirm.**
- Not rares at all, though they're often remembered as such: **Mor'Ladim** (522, Elite 35, a quest target), **Gazz'uz** (3204, Normal 14), **Old Murk-Eye** (391, Normal 20). This is the same on classic and Forever.

## 3. Shortlist

29 picks: famous ones first, spread over levels, both continents and both factions' zones. Every row was checked against Wowhead Forever's tooltip, 2026-11-13. The first sightings column is Wowhead's sighting count on Forever, then on classic. **New** means the NPC is new on Forever. "Why" cites the wiki unless marked otherwise.

| NPC ID | Name | Zone | Level | Class | Sightings (Forever / classic) | Why |
|---|---|---|---|---|---|---|
| 259394 | Snapbeak the Quick | Zephras Isle | 9 | Rare Elite | 7 / **new** | Forever's new starting isle; Thendal Watcher's Boots ([ForeverChanges](https://foreverchanges.pro/rares), *third party*) |
| 276089 | The Condemned One | Tirisfal Glades | 11 | Rare | 6 / **new** | New Forever starting-zone rare; Helm Splitter (ForeverChanges) |
| 276111 | Ghostfang | Dun Morogh | 10 | Rare | 11 / **new** | New, tameable cat (ForeverChanges) |
| 1132 | Timber | Dun Morogh | 10 | Rare | 11 / 60 | Classic Dun Morogh wolf |
| 100 | Gruff Swiftbite | Elwynn Forest | 12 | Rare | 6 / 64 | Elwynn's rare, now that Mother Fang is an elite |
| 3056 | Ghost Howl | Mulgore | 12 | Rare | 7 / 190 | Mulgore's ghostly wolf |
| 5824 | Captain Flat Tusk | Durotar | 11 | Rare Elite | 9 / 102 | Durotar's rare elite |
| 14429 | Grimmaw | Teldrassil | 11 | Rare | 8 / 11 | Teldrassil; Gnarlpine War Staff (ForeverChanges) |
| 573 | Foe Reaper 4000 | Westfall | 20 | Rare | 17 / 175 | Iconic Westfall harvester; Large Rucksack, Scarecrow Trousers; 4–6 h respawn ([wiki](https://warcraft.wiki.gg/wiki/Foe_Reaper_4000)) |
| 599 | Marisa du'Paige | Westfall | 18 | Rare Elite | 4 / 0 | Westfall's Defias rare elite |
| 521 | Lupos | Duskwood | 23 | Rare | 150 / 149 | Before 1.9 the only wolf with shadow damage; 4–6 h ([wiki](https://warcraft.wiki.gg/wiki/Lupos)) |
| 5828 | Humar the Pridelord | The Barrens | 23 | Rare Elite | 3 / 13 | Barrens legend, tameable; Forever set piece (Mark of the Pack Leader); 8–12 h respawn ([wiki](https://warcraft.wiki.gg/wiki/Humar_the_Pridelord)) |
| 5842 | Takk the Leaper | The Barrens | 19 | Rare Elite | 30 / 30 | Forever set piece (Raptor Hide Cloak); 4–6 h ([wiki](https://warcraft.wiki.gg/wiki/Takk_the_Leaper)) |
| 5831 | Swiftmane | The Barrens | 21 | Rare Elite | 6 / 39 | Forever set piece (Signet of the Zhevra) |
| 5797 | Aean Swiftriver | The Barrens | 25 | Rare Elite | 14 / 179 | One of four roaming Alliance Outrunners in Horde land |
| 5931 | Foreman Rigger | Stonetalon Mountains | 24 | Rare Elite | 17 / 76 | Forever drop, Foreman's Helm ([wiki](https://warcraft.wiki.gg/wiki/Foreman_Rigger)) |
| 10559 | Lady Vespia | Ashenvale | 22 | Rare | 23 / 23 | Ashenvale naga rare; seen on Forever by [The Forever Era](https://theforeverera.com/en/rares/) |
| 5934 | Heartrazor | Thousand Needles | 32 | Rare Elite | 9 / 20 | Wyvern Heart Band (ForeverChanges) |
| 14221 | Gravis Slipknot | Alterac Mountains | 36 | Rare | 61 / 57 | Syndicate Executioner's Slicer (ForeverChanges) |
| 2850 | Broken Tooth | Badlands | 37 (Forever shows 37–60) | Rare | 113 / 113 | Classic's most wanted hunter pet: "1.0 attack speed, which was the quickest in the game" ([wiki](https://warcraft.wiki.gg/wiki/Broken_Tooth)) |
| 2779 | Prince Nazjak | Arathi Highlands | 41 | Rare | 14 / 35 | Drops the Tidal Charm ([wiki](https://warcraft.wiki.gg/wiki/Prince_Nazjak)) |
| 14445 | Lord Captain Wyrmak | Swamp of Sorrows | 45 | Rare Elite | 299 / 297 | Black dragon outside the Sunken Temple ([wiki](https://warcraft.wiki.gg/wiki/Lord_Captain_Wyrmak)) |
| 4339 | Brimgore | Dustwallow Marsh | 45 | Rare Elite | 36 / 36 | Black dragon rare elite |
| 8215 | Grimungous | The Hinterlands | 50 | Rare Elite | 111 / 111 | Hinterlands giant |
| 10077 | Deathmaw | Burning Steppes | 53 | Rare | 55 / 55 | Burning Steppes wolf |
| 10200 | Rak'shiri | Winterspring | 57 | Rare | 63 / 63 | White frostsaber that hunters chase ([wiki](https://warcraft.wiki.gg/wiki/Rak'shiri)) |
| 10202 | Azurous | Winterspring | 59 | Rare Elite | 94 / 94 | Blue drake; Forever drop, Magically Fortified Legguards ([wiki](https://warcraft.wiki.gg/wiki/Azurous)) |
| 6584 | King Mosh | Un'Goro Crater | 60 | Rare Elite | 194 / 194 | Un'Goro's devilsaur king ([wiki](https://warcraft.wiki.gg/wiki/King_Mosh)) |
| 10119 | Volchan | Burning Steppes | 60 | Rare Elite | 582 / 582 | Molten giant; the only source of Plans: Volcanic Hammer ([wiki](https://warcraft.wiki.gg/wiki/Volchan)) |
| 266901 | Pexmit | Mount Hyjal | 60 | Rare | 2 / **new** | Rare in Forever's new Hyjal zone |

**Reserves**, all checked the same way, to swap in for a different mix:

- Low levels: Bjarn (1130, Dun Morogh, Rare 12), Mazzranache (3068, Mulgore, 9), Bayne (10356, Tirisfal, 10).
- Barrens: Dishu (5865, Rare 13).
- 20s: Ma'ruk Wyrmscale (2090, Wetlands, Rare 23), Taskmaster Whipfang (5932, Stonetalon, Rare Elite 22), Dro'zem the Blasphemous (214456, Redridge, Rare Elite 23; an ID from Season of Discovery, but on Forever), Commander Felstrom (771, Duskwood, Rare 32).
- 40s and 50s: Kurmokk (14491, STV, Rare 42), Snarler (5356, Feralas, Rare 42), Olm the Wise (14343, Felwood, Rare 52), Hematos (8976, Burning Steppes, Rare Elite 60).
- Silithus: Setis (14471, Rare Elite 61) and Rex Ashil (14475, Rare Elite 57).
- Forever's Lordaeron Captain (255699, Rare Elite, in the Ruins of Lordaeron dungeon).

Levels 25–35 and the Horde side of Eastern Kingdoms are thin in the main list. Rocklance (5841) or the Arathi ogres (Foulbelly 2601, Ruul Onestone 2602) would fill them.

## 4. Detecting a kill (API)

**Short answer: a rare trophy belongs to the Crew, not to a person. So BFF only needs *one* Member's client to notice *one* kill of each listed rare, and it can ignore who landed the blow. The most reliable signal is looting the corpse. Second is "my target died, and my group had the tag". `PARTY_KILL` counts whenever its GUID turns out to be readable.**

What the Crew scope changes:

- **One record is enough.** BFF doesn't need to give everyone in the party credit, so it doesn't matter that only the looter sees the loot.
- **Missed kills cost less.** Only one Member's client has to catch the kill, and a party gives several chances. A rare missed today can be killed again.
- **No cross-client matching.** Since 1.60.1 each client sees a different GUID for the same creature (see the GUID row below). That doesn't matter: the Crew keeps the **earliest record per NPC ID** and ignores the rest.
- **One check stays: the kill must be the Crew's.** Walking past a rare that strangers killed mustn't count. Looting proves your group had the tag. For the target path, `UnitIsTapDenied("target")` must be false.

Who and when go in the record for the feed ("Ana got Rak'shiri"), but nothing depends on them.

`ENCOUNTER_END`, which `docs/research/boss-kills.md` uses for Clears, doesn't help here. It hands over a plain encounter ID, but it only fires for scripted fights (instance bosses and some world bosses), and rares are ordinary open-world mobs (**expected**). The dev encounter logger (`Dev/Sim.lua`) records every `ENCOUNTER_END`, so a rare kill in a dev checkout would show it if Forever does fire one.

### How other addons do it

Both read on 2026-11-13.

- **RareScanner**: the Forever build **1.60.1.6** (`## Interface: 16001`), downloaded from [Wago](https://addons.wago.io/addons/rarescanner) (*third party*). It marks a rare as killed from three signals, all in `Core/Service/RSEventHandler.lua`:
  - **`PARTY_KILL`** (`OnPartyKill`, line 200): if `targetGUID` isn't secret, `C_CreatureInfo.GetCreatureID(targetGUID)` gives the NPC ID. A known rare is marked dead and its kill count goes up. If the GUID is secret, it silently does nothing. So this shows the author handles the secret case, not that the GUID is readable.
  - **Loot** (`OnLootOpened`, line 302): for each slot, `GetLootSourceInfo(i)` is split on `-` to get the type and NPC ID. A known rare is marked dead and counted. There's **no `issecretvalue` guard** here, while the rest of the file guards almost every unit read. That suggests the loot source GUID is readable on Forever, but it's an inference, not a test.
  - **Hidden tracking quests** (`RareScanner.lua` line 824): rares whose data has a `questID` count as killed once `C_QuestLog.IsQuestFlaggedCompleted` says so. This is how retail tracks rares. **Its Forever NPC table (`Tables/NpcInfoTables.lua`) has no `questID` at all**, so this path does nothing on Forever.

  It spots rares through target, mouseover, nameplates and soft target. It reads the GUID only when it isn't secret and `not InCombatLockdown()` (line 246). `UNIT_DIED` feeds only its respawn timers, with the same secret guard. Its description says Forever has **no vignettes** ("In Classic versions (including Forever), the game doesn't include vignettes"), so it relies on nameplates. Its changelog says Blizzard later restricted reading minimap tracking blips, and that it dropped Mother Fang as "a normal elite in Forever".
- **AllTheThings**: [GitHub](https://github.com/ATTWoWAddon/AllTheThings) at [`1c4d146`](https://github.com/ATTWoWAddon/AllTheThings/tree/1c4d146b518a3c2cda6d2488a27be6e2638d5360). It doesn't detect kills. It tracks collectibles, and marks a retail rare done through its hidden tracking quest (e.g. Alunira, `questID = 85158`, in `.contrib/.db/standard/02 - Outdoor Zones/15 Khaz Algar/Isle of Dorn/Rares.lua`). Its Forever data lists rares with their drops but **no tracking quests** (e.g. `n(RARES, …)` in `.contrib/.db/forever/zones/kalimdor/the barrens.lua`). The only `questID` in Forever's zone data is on treasures and ordinary quests. So on Forever, ATT only knows whether you got the loot.

Both agree: **Forever rares have no tracking quests and no vignettes.** An addon has to see the kill itself.

### API

| API | What Forever's source says | How sure |
|---|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | `HasRestrictions = true` ([UI: Docs/CombatLogDocumentation.lua L130–L136](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogDocumentation.lua#L130-L136)). In 12.0, "COMBAT_LOG_EVENT and COMBAT_LOG_EVENT_UNFILTERED will error when trying to register them" ([wiki: Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)). `GetCurrentEventInfo` moved to `C_CombatLogSecure`, `Environment = "SecureOnly"` ([UI: Docs/CombatLogSecureDocumentation.lua L6, L45](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/CombatLogSecureDocumentation.lua#L45)). | **Documented: unusable** |
| Loot: `LOOT_OPENED`/`LOOT_READY`, `GetLootSourceInfo(slot)` | Plain events (`docs/research/fishing-catches.md`). `GetLootSourceInfo` returns the GUID of each slot's corpse ([wiki](https://warcraft.wiki.gg/wiki/API_GetLootSourceInfo)). It isn't in the generated docs, so its secrecy isn't stated. RareScanner's Forever build reads it with no secret guard (above). Looting a corpse means your group had the tag. A rare with nothing for you to loot gives nothing. | Readable: **expected** (RareScanner), to confirm |
| `PLAYER_TARGET_DIED` (event) | New in 12.0, **no payload**, no secret flag ([UI: Docs/PlayerScriptDocumentation.lua L1872–L1876](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua#L1872-L1876)). Blizzard's combat audio alerts use it ([UI: Blizzard_CombatAudioAlerts/Blizzard_CombatAudioAlertManager.lua L118](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_CombatAudioAlerts/Blizzard_CombatAudioAlertManager.lua#L118)). A clean "your target just died" trigger. | **Documented** |
| `PARTY_KILL` (event) | New in 12.0 ([wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)). Payload `attackerGUID, targetGUID`, `SecretWhenUnitIdentityRestricted` ([UI: Docs/UnitDocumentation.lua L3724–L3734](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L3724-L3734)). The predicate: "secret values when the unit isn't player-controlled or in the party/raid" ([UI: Docs/SecretPredicatesDocumentation.lua L130–L133](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua#L130-L133)). A rare is neither, so `targetGUID` is **expected to be secret**, at least in combat. RareScanner uses it when it isn't. | Exists: **documented**. Readable GUID: **expected not**, to confirm |
| `UNIT_DIED` (event) | New in 12.0. Payload `unitGUID`, same secret flag ([L4224–L4233](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L4224-L4233)). Fires for any death, not just your group's kills, so it would need the tap check anyway. Not needed. | Same as `PARTY_KILL` |
| `UnitGUID(unit)` | `SecretWhenUnitIdentityRestricted`, `AllowedWhenUntainted` ([UnitDocumentation.lua L1241–L1255](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L1241-L1255)). The wiki puts the same rule for `UnitName` as: secret "if querying a non-player or pet unit while in combat" ([wiki: Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values)). So an NPC's GUID is expected to be readable **out of combat** and secret **in combat**. `C_Secrets.ShouldUnitIdentityBeSecret(unit)` says which, before the call ([UI: Docs/SecretPredicateAPIDocumentation.lua L305–L319](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicateAPIDocumentation.lua#L305-L319)). RareScanner reads it only when not secret and `not InCombatLockdown()`. | Flags: **documented**. Combat-only rule: **expected**, to confirm |
| `C_CreatureInfo.GetCreatureID(guid)` | Returns the NPC ID of a creature GUID. RareScanner's Forever build uses it everywhere instead of splitting the string. Neater than parsing the 6th field. | Used in a Forever addon. Check it's in Forever's generated docs before relying on it |
| GUID format on Forever | `Creature-0-[serverID]-[instanceID]-[zoneUID]-[npcID]-[spawnUID]`. On Forever 1.60.1, "the server ID and spawn ID portions of creature … GUIDs have been replaced with obfuscated values to prevent comparison to determine layer. They remain stable and unique within your own session, and the GUID string format is otherwise unchanged" ([wiki: GUID](https://warcraft.wiki.gg/wiki/GUID), [wiki: UnitGUID](https://warcraft.wiki.gg/wiki/API_UnitGUID)). The NPC ID is still there. Two Members see different GUIDs for the same kill, which doesn't matter for a Crew trophy. | **Documented** |
| `UnitIsDead`, `UnitIsTapDenied` | Both return a bool, `AllowedWhenUntainted`, no secret flag ([L1916–L1929](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L1916-L1929), [L2365–L2378](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L2365-L2378)). `UnitIsTapDenied` is true when someone outside your group has the tag. On a dead target, false means your group earned the kill. | Flags: **documented**. Tap rules on Forever rares: **to confirm** |
| `UnitClassification(unit)` | Returns a string, `AllowedWhenUntainted`, **no secret flag** ([UnitDocumentation.lua L966–L979](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L966-L979)). Forever's target frame treats `"rare"` and `"rareelite"` as the silver-dragon frame ([UI: Blizzard_UnitFrame/Camelot/TargetFrameUtils.lua L1–L3](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UnitFrame/Camelot/TargetFrameUtils.lua#L1-L3)). Useful for logging unlisted rares, not for the trophy. | **Documented** |
| `PLAYER_TARGET_CHANGED`, `NAME_PLATE_UNIT_ADDED`, `UPDATE_MOUSEOVER_UNIT` | Ways to see a rare before the pull ([UnitDocumentation.lua L3976](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L3976), [NamePlateManagerDocumentation.lua L120](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateManagerDocumentation.lua#L120)). Each needs `UnitGUID` to be readable then. | **Documented** |
| `C_VignetteInfo` | Exists in the API ([UI: Docs/VignetteInfoDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/VignetteInfoDocumentation.lua#L125-L150)), but RareScanner says Forever's rares have no vignettes. Not a signal. | **Documented** (*third party*) |
| Tracking quests (`C_QuestLog.IsQuestFlaggedCompleted`) | Retail's way to know a rare is dead. Neither RareScanner's nor ATT's Forever data has any for rares. Not a signal. | **Documented** (*third party*) |
| `ENCOUNTER_END` | Doesn't fire for open-world rares. | **Expected** |

### Proposed flow

1. **Loot (main).** On `LOOT_READY`, for each slot, read `GetLootSourceInfo(i)`. Skip it if it's secret or not a `Creature`. If the NPC ID is on the list, record the rare (once per loot window).
2. **Target died (second).** While out of combat, on `PLAYER_TARGET_CHANGED`, `UPDATE_MOUSEOVER_UNIT` and `NAME_PLATE_UNIT_ADDED`, if `not C_Secrets.ShouldUnitIdentityBeSecret(unit)`, read `UnitGUID`. If the NPC ID is on the list, remember the GUID for the session. On `PLAYER_TARGET_DIED`, and again on `PLAYER_REGEN_ENABLED`, check the target once its identity is readable: it's dead, its GUID is a remembered one, and `not UnitIsTapDenied("target")`. Then record it. This covers a rare nobody in the party loots.
3. **`PARTY_KILL` (when readable).** If `targetGUID` isn't secret and its NPC ID is on the list, record it. Costs nothing, and covers kills the other two miss if Blizzard leaves the GUID readable.
4. **Record.** Into the Member's own record: NPC ID, when, `uiMapID` and Character. Recording only writes your own record, and it goes out on the next DATA send, so comms lockdown doesn't matter, as with Clears and Catches. The Crew trophy is the **earliest record per NPC ID** across Members. No GUID matching.
5. **Unlisted rares.** As with unlisted catches: when a dead, untapped target has `UnitClassification` `"rare"`/`"rareelite"` but isn't on the list, log its NPC ID in a dev checkout. Adding it is then one row of data.

Guard every unit read with `issecretvalue`, as RareScanner does.

### Risks

- **Loot GUID might be secret.** RareScanner's code suggests it isn't, but nobody has tested it. If it is, the target path has to carry the feature, and that needs an NPC's GUID to be readable out of combat. Test both first (section 5).
- **Stranger kills.** A dead rare with `UnitIsTapDenied` false that nobody in your group tagged (an evade or reset death), or a retail-style shared tag (if Forever has those), could count. Loot doesn't have this problem.
- **Missed kills.** A rare nobody loots and nobody had targeted when it died is missed. For a Crew trophy that's a nuisance, not a bug: the next kill counts.
- Forever may restrict a whole zone as a **Map** (`Enum.AddOnRestrictionType`, see `fishing-catches.md`). No rare zone is known to be one.

## 5. To check in game

### Retail 12.x results (2026-11-13)

One test on retail with BFF's dev Rare logger (`/bffdev rares`), solo, out of combat. A normal NPC (Theramore Marine, 3385) was put on the list for the test, since the list decides what counts, not `UnitClassification`.

- **Q1, loot:** `GetLootSourceInfo` on the corpse during `LOOT_READY` read **not secret**, and its NPC ID matched. Loot works as the main signal.
- **Q2, unit identity out of combat:** `UnitGUID` read **not secret** on `target`, `mouseover` and `nameplate1`–`4`. The GUID was `Creature-0-1471-1-66-3385-000076EDF5`, the documented format, with the NPC ID in the 6th field.
- **Q4, `PLAYER_TARGET_DIED`:** fired for a solo kill. Target, dead and tap state all read, and the kill was found.
- **Q5, `PARTY_KILL`:** fired for a solo kill, with `targetGUID` **not secret**, against the expectation in section 4. It came first and recorded the kill.
- `PLAYER_REGEN_ENABLED` right after found no target: the dead target was gone by then. Harmless, since the kill was already in.
- Each signal after the first logged `had`, so one kill is recorded once.

Still open: Q3 (a GUID first read in combat), Q7 (a mob another player tagged should read `UnitIsTapDenied`), whether a party member's or pet's killing blow fires `PARTY_KILL` (Q5), and everything on Forever itself, which may restrict more than retail.

### The questions

On **retail 12.x** (the dev client) for the API, and on **Forever** for anything Forever-specific. In order of importance:

1. **Loot:** during `LOOT_READY` on an NPC corpse, is `GetLootSourceInfo(1)` readable (`issecretvalue` false)? Right after combat, and a while later? This decides the main signal.
2. Open world, out of combat, an NPC targeted: is `UnitGUID("target")` readable? What does `C_Secrets.ShouldUnitIdentityBeSecret("target")` return? Same for `"mouseover"` and `"nameplateN"`.
3. Same, **in combat**, and in the first frames after `PLAYER_REGEN_ENABLED`.
4. `PLAYER_TARGET_DIED`: does it fire when someone else lands the killing blow on your target?
5. `PARTY_KILL` for an open-world NPC: does it fire? Is `targetGUID` secret? Does it fire for a party member's or a pet's killing blow?
6. Is `C_CreatureInfo.GetCreatureID` in Forever's generated API docs, and does it return the right NPC ID for a Forever GUID? Compare against Wowhead for a known NPC.
7. Forever: tapping. Does a rare tagged by another group show `UnitIsTapDenied` true? Do rares have shared tags, as on retail?
8. Does a Forever rare ever fire `ENCOUNTER_END`? The dev encounter logger catches it if it does.
9. Is Mother Fang Elite on Forever? What is Broken Tooth's level?
10. Which rares drop the Rider of the Plaguelands set?
11. For every row in the shortlist with identical sighting counts: does it spawn on Forever? Seeing it once with a logger is enough.
