# Research: fishing catches on WoW: Forever

For the **Catches** prototype (`prototypes/catches.html`): which items can be fished on Forever, how to group the waters by level, how an addon can tell that something was fished (and where), and whether BFF can ship a fixed list of "all types" for "23 of 35 types".

**Status (2026-11-07): desk research only, no Forever fishing logged yet.** Item IDs, names and qualities come from Forever's own client data, so they're solid. *Where* each item is fished is decided by the server and isn't in the client files. The only per-zone source found is Wowhead's crowd-sourced "Fished in" data for 25 fish. Treasure, oddities and Forever's new catches still need a person with a Forever client.

How sure each answer is:

- **Documented:** a source says so. Forever's client data and UI source are primary sources; guides and Wowhead are marked *third party*.
- **Expected:** classic's answer, which Forever may have changed.
- **To confirm:** needs a fishing session on Forever.

## Sources

- **Forever client data**: the DB2 tables of build **1.60.1.70862** (product `wowf`), read from [wago.tools](https://wago.tools/db2/ItemSparse?build=1.60.1.70862): `ItemSparse` (name, quality), `Item` (class), `SpellName`, `AreaTable`. This is datamined from Blizzard's client files, so it's primary, but it only shows that an item **exists**, not that it can be fished. Below, "Forever data" means this.
- **Forever UI source**: the [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) `forever` branch, **1.60.1 (70862)**, commit [`9dc84f0`](https://github.com/Gethe/wow-ui-source/tree/9dc84f0d3bbae1768ac3405b3716000bd93eda06). Below, `UI:` is short for `https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/`.
- **Wowhead "Fished in"** (*third party*, crowd-sourced from players' uploads): Wowhead has a Forever database (`wowhead.com/forever/item=…`), but it blocks automated fetches. The GatherLite addon commits a scrape of the "Fished in" zone lists for 25 Forever fish: [`tools/wowhead/fish.json`](https://github.com/Wuild/GatherLite/blob/3293e73d1498892628de8c9050b1c877269fbe47/tools/wowhead/fish.json), made by [`update_fish_wowhead.py`](https://github.com/Wuild/GatherLite/blob/3293e73d1498892628de8c9050b1c877269fbe47/tools/update_fish_wowhead.py), which checks that each page is `wowhead.com/forever/item=<id>`. It's a scrape of a crowd-sourced list, so it has some noise (e.g. Lightning Eel "fished in" Elwynn Forest).
- **Guides** (*third party*, written against **beta** clients): [classicwowforever.com fishing guide](https://classicwowforever.com/professions/fishing/) (updated 2026-10-03, beta 1.60.1.70009), [Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/fishing/), and a player's [forum post](https://us.forums.blizzard.com/en/wow/t/fishing-in-wow-forever/2371569) (2026-10-04). Icy Veins and WowVendor refused automated fetches.
- **No official Blizzard post** on Forever fishing turned up.

## 1. What can be fished

Qualities below are Forever's own (0 poor, 1 common, 2 uncommon, 3 rare, 4 epic). Every ID was checked to exist in Forever data.

### Fish (common, food or reagent)

"Fished in" is Wowhead's list (*third party*), trimmed to the main zones. Zones with one-off reports are left out.

| ID | Name | Fished in (Wowhead Forever) | Notes |
|---|---|---|---|
| 6291 | Raw Brilliant Smallfish | starting zones, capitals, Westfall, Loch Modan, Darkshore, Barrens, Ashenvale | inland, low skill |
| 6303 | Raw Slitherskin Mackerel | coasts of Durotar, Teldrassil, Darkshore, Westfall, Silverpine, Tirisfal, Barrens | coastal, low skill |
| 6289 | Raw Longjaw Mud Snapper | capitals and 1–30 zones (Elwynn, Loch Modan, Redridge, Wetlands, Hillsbrad, Ashenvale …) | |
| 6317 | Raw Loch Frenzy | Loch Modan only | |
| 6361 | Raw Rainbow Fin Albacore | Westfall, Darkshore, Silverpine, Barrens, Wetlands, Hillsbrad, Ashenvale | coastal |
| 6308 | Raw Bristle Whisker Catfish | most 10–40 inland waters, capitals | |
| 21071 | Raw Sagefish | Loch Modan, Silverpine, Hillsbrad, Ashenvale, Stonetalon | |
| 6522 | Deviate Fish | Barrens (Wailing Caverns oases), plus scattered reports | |
| 6358 | Oily Blackmouth | coasts 20–55 (Wetlands, Arathi, STV, Desolace, Dustwallow, Tanaris …) | |
| 6359 | Firefin Snapper | coasts 20–50 | |
| 8365 | Raw Mithril Head Trout | inland 25–55 (Alterac, Arathi, STV, Swamp of Sorrows, Felwood, Plaguelands …) | |
| 6362 | Raw Rockscale Cod | coasts 30–50 (Arathi, STV, Desolace, Dustwallow, Tanaris, Feralas …) | |
| 21153 | Raw Greater Sagefish | Alterac Mountains, Stranglethorn Vale | |
| 4603 | Raw Spotted Yellowtail | coasts 30–55 (STV, Dustwallow, Tanaris, Feralas, Hinterlands, Azshara …) | |
| 13754 | Raw Glossy Mightfish | STV, Tanaris, Feralas, Hinterlands, Azshara | |
| 13756 | Raw Summer Bass | STV, Tanaris, Feralas, Hinterlands, Azshara, EPL | **seasonal** (summer) in classic: **expected** |
| 13755 | Raw Winter Squid | STV, Tanaris, Feralas, Hinterlands, Azshara | **seasonal** (winter) in classic: **expected**. Renamed: Forever data says *Raw* Winter Squid |
| 13422 | Stonescale Eel | STV, Tanaris, Feralas, Hinterlands, Azshara, EPL | |
| 13758 | Raw Redgill | 40–60 inland (Felwood, Un'Goro, Plaguelands, Winterspring, Burning Steppes …) | |
| 13759 | Raw Nightfin Snapper | 40–60 inland | night-time in classic: **expected** |
| 13760 | Raw Sunscale Salmon | 40–60 inland | daytime in classic: **expected** |
| 13757 | Lightning Eel | 50–60 inland, scattered | |
| 13889 | Raw Whitescale Salmon | 50–60 (Plaguelands, Winterspring, Burning Steppes, Silithus, Deadwind) | |
| 13888 | Darkclaw Lobster | Azshara, Eastern Plaguelands | |
| 13893 | Large Raw Mightfish | Azshara, Eastern Plaguelands | |

Wowhead's scrape doesn't cover these, but they exist in Forever data:

| ID | Name | Quality | Source | How sure |
|---|---|---|---|---|
| 251524 | **Whimsyfin** (new on Forever) | 1 | Redridge Mountains, found by one beta tester ([classicwowforever](https://classicwowforever.com/professions/fishing/), *third party*). Cooks into Savory Whimsyfin Delight (251525). | **To confirm** |
| 13890 | Raw Plated Armorfish | 1 | Forever adds a recipe (Plated Armorfish 286152, Cooking 225) ([classicwowforever](https://classicwowforever.com/professions/fishing/)). Forever data lists the raw fish as a **quest-class** item (class 12). Where it's caught is unknown. | **To confirm** |
| 12238 | Darkshore Grouper | 1 | Darkshore in classic | **Expected** |
| 6299 | Sickly Looking Fish | 1 | Tirisfal Glades ([classicwowforever](https://classicwowforever.com/professions/fishing/), *third party*) | **Expected** |
| 8959 | Raw Spinefin Halibut | 1 | Sold by Kilxx on Forever ([classicwowforever](https://classicwowforever.com/professions/fishing/)). In classic, it's fished in pools in the 50s. | **To confirm** |

### Uncommon "bloated" fish (open with a right-click)

Forever data has **ten** of these at quality 2: 6643 Bloated Brilliant Smallfish, 6645 Bloated Mud Snapper, 6647 Bloated Bristle Whisker Catfish, 8366 Bloated Mithril Head Trout, 21162 Bloated Oily Blackmouth, 21163 Bloated Firefin Snapper, 21164 Bloated Rockscale Cod, 21243 Bloated Glossy Mightfish, 13881 Bloated Redgill, 13891 Bloated Whitescale Salmon. Guides say the ten are now uncommon and bind on pickup ([classicwowforever](https://classicwowforever.com/professions/fishing/), *third party*), which fits that count (**documented**). 6644 Bloated Mackerel and 6646 Bloated Albacore are still quality 1. They look like leftovers, but **to confirm**. Each comes from the waters of its base fish (**expected**).

Forever's camp objects, the **Fishing Rack** (Fishing 140) and **Fishing Hut** (Fishing 300), give a buff that lets you catch "uncommon and rare fish" ([Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/fishing/), *third party*). Which items those are is unknown. They may be these bloated fish, or something not yet seen (**to confirm**).

### Rare and named fish

| ID | Name | Quality | Where | How sure |
|---|---|---|---|---|
| 16970 | Misty Reed Mahi Mahi | 1 (quest) | Swamp of Sorrows | Nat Pagle's Artisan quest fish ([classicwowforever](https://classicwowforever.com/professions/fishing/), *third party*); the zones match classic (**expected**) |
| 16968 | Sar'theris Striker | 1 (quest) | Desolace | same |
| 16967 | Feralas Ahi | 1 | Feralas | same |
| 16969 | Savage Coast Blue Sailfin | 1 (quest) | Stranglethorn Vale | same |
| 19807 | Speckled Tastyfish | 1 | STV coast, **tournament only** | Stranglethorn Fishing Extravaganza |
| 19805 | Keefer's Angelfish | 2 | STV coast, tournament only | same |
| 19806 | Dezian Queenfish | 2 | STV coast, tournament only | same |
| 19803 | Brownell's Blue Striped Racer | 2 | STV coast, tournament only | same |

Trophy-weight fish (one item ID per weight, all quality 1, sold to vendors): Mud Snapper 6292/6294/6295, Catfish 6309/6310/6311/6363/6364, Salmon 13901–13906, Lobster 13907–13913, Redgill 13882–13887, Yellowtail 13876–13880 (renamed from classic's Grouper), Mightfish 13914–13917. All exist in Forever data. Forever prices them at about a silver per pound ([classicwowforever](https://classicwowforever.com/professions/fishing/), *third party*). For Catches, count each family as **one type**, not one per weight. Which waters give them is **expected** from classic and **to confirm**.

### The Stranglethorn Fishing Extravaganza (changed on Forever)

- It still exists. Forever adds **Extravagant Extravaganza Coin** (274026, quality 3): "Awarded to the winners of the Stranglethorn Fishing Extravaganza. Exchange for a prize of your choosing from Jang." (Forever data, **documented**).
- It's reworked to have many winners: "the first 50" according to a [player's forum post](https://us.forums.blizzard.com/en/wow/t/fishing-in-wow-forever/2371569). Tastyfish now stack to 40 ([classicwowforever](https://classicwowforever.com/professions/fishing/)). Both are *third party*.
- Prizes, all present in Forever data: Hook of the Master Angler 19979, Master Angler's Fishing Hat 276272, Empty Fish Bucket 276273, Surfer Shoes 276274, Bitter Baitling (pet) 276275, Message in a Bottle 274974 (a new version, quality 2). These are **bought**, not fished, so they aren't Catches.
- When: classic's was Sundays 14:00–16:00 server time. A beta tester reported Sunday 14:00 ([classicwowforever](https://classicwowforever.com/professions/fishing/)), so **expected**.

### Treasure, clams and oddities

None of these is in Wowhead's scrape. The containers and clams exist in Forever data, and the list is classic's set of fished containers (**expected**, every one **to confirm**):

| ID | Name | Quality | Notes |
|---|---|---|---|
| 6351 | Dented Crate | 1 | "Venture Company Supplies" |
| 6352 | Waterlogged Crate | 1 | same |
| 6357 | Sealed Crate | 1 | same |
| 13874 | Heavy Crate | 1 | same (238985 is a different Heavy Crate, a quest item) |
| 6356 | Battered Chest | 1 | |
| 6354 / 6355 | Small / Sturdy Locked Chest | 1 | need lockpicking |
| 13875 / 13918 | Ironbound / Reinforced Locked Chest | 1 | need lockpicking |
| 21150 | Iron Bound Trunk | 1 | |
| 21228 | Mithril Bound Trunk | 1 | |
| 21113 | Watertight Trunk | 1 | |
| 20708 | Tightly Sealed Trunk | 1 | |
| 7973 | Big-mouth Clam | 1 | |
| 5523 / 5524 / 15874 | Small Barnacled / Thick-shelled / Soft-shelled Clam | 1 | more often mob drops; whether they're fished is **to confirm** |
| 6307 | Message in a Bottle | 1 | classic's old one |

Possible Forever oddities, all **to confirm**:

- **Wishing-fountain coins**: about 60 poor-quality coins (286263–286328, e.g. "Rhonin's Gold Coin", "A Footman's Copper Coin"), each with a wish as its flavour text. In Wrath, coins like these were fished from Dalaran's fountain. Forever has a City of Dalaran dungeon, so they may be fishable there. That's a guess from the names.
- Poor-quality items with no known source, such as 271646 "How to Make Friend", 271647 "Once Used Shoe", 271648 "Ogre Tooth Cleaner" and 251523 "The Friends We Made Along the Way". Nothing ties them to fishing. Log them if they show up.
- Fishing in wreckage and schools gives cloth and leather ([Warcraft Tavern](https://www.warcrafttavern.com/forever/guides/fishing/), *third party*). The exact items aren't known.

**Junk:** no source names a fishing junk item on Forever. Classic's open-water failure was "Your fish got away", not a junk item (**expected**).

### Not on Forever: fix in the prototype

- **Old Ironjaw, Old Crafty, Nat's Lucky Coin, The 1 Ring**: not in Forever data at all (Old Ironjaw and Old Crafty are Burning Crusade).
- **Winter Squid** is now **Raw Winter Squid** (13755).
- **Feralas Ahi, Misty Reed Mahi Mahi, Savage Coast Blue Sailfin, Sar'theris Striker** are quality 1 on Forever (quest fish), not 2. **Keefer's Angelfish** is quality 2, not 3.
- **Yellowtail** trophy fish are "40–68 Pound Yellowtail", not Grouper.

## 2. Waters by level

Zone levels are classic's ([Zones by level (Classic)](https://warcraft.wiki.gg/wiki/Zones_by_level_(Classic)), **expected**). Each zone's fish come from Wowhead's Forever lists above. Classic's zone fishing-skill thresholds aren't confirmed on Forever. Guides say they're unknown ([classicwowforever](https://classicwowforever.com/professions/fishing/)), and Wowhead gives no skill per zone. So bands follow zone level, not skill.

| Band | Name idea | Zones | Signature catches |
|---|---|---|---|
| 1–10 | Home waters | Elwynn Forest, Dun Morogh, Teldrassil, Durotar, Mulgore, Tirisfal Glades; the six capitals | Brilliant Smallfish, Slitherskin Mackerel, Longjaw Mud Snapper (capitals), Sickly Looking Fish (Tirisfal) |
| 10–25 | Lakes and shores | Westfall, Loch Modan, Darkshore, Silverpine Forest, The Barrens, Redridge Mountains | Rainbow Fin Albacore, Loch Frenzy, Bristle Whisker Catfish, Sagefish, Deviate Fish, Darkshore Grouper, **Whimsyfin** |
| 20–35 | Rivers and marsh | Ashenvale, Duskwood, Hillsbrad Foothills, Wetlands, Stonetalon Mountains, Thousand Needles | Catfish, Sagefish, Mithril Head Trout, Oily Blackmouth, Firefin Snapper |
| 30–45 | Warm coasts | Stranglethorn Vale, Arathi Highlands, Alterac Mountains, Desolace, Dustwallow Marsh, Swamp of Sorrows | Rockscale Cod, Spotted Yellowtail, Greater Sagefish; Nat Pagle's Mahi Mahi, Striker, Sailfin |
| 40–55 | Far coasts | Tanaris, Feralas, The Hinterlands, Azshara, Felwood, Un'Goro Crater | Glossy Mightfish, Summer Bass / Winter Squid, Stonescale Eel, Redgill, Feralas Ahi |
| 50–60 | Cold and deep | Western and Eastern Plaguelands, Winterspring, Burning Steppes, Silithus, Moonglade, Deadwind Pass | Whitescale Salmon, Nightfin Snapper, Sunscale Salmon, Lightning Eel; Darkclaw Lobster and Large Raw Mightfish (Azshara, EPL) |
| event | The Extravaganza | Stranglethorn coast, Sundays | Speckled Tastyfish, Keefer's Angelfish, Dezian Queenfish, Brownell's Racer |

**Forever's new zones.** These top-level zones are new in Forever data ([AreaTable](https://wago.tools/db2/AreaTable?build=1.60.1.70862)): **Riverglades** (16591), **Gilneas** (17065), **Ruins of Gilneas** (16756), **Shen'dralas** (16651), **Shark-Infested Waters** (17066), and **Mount Hyjal** (616, unused in classic). The client data has no level ranges for them (`ContentTuningID` is 0). Riverglades' item levels (38–41) suggest the 35–45 band, and Hyjal's (55–60) suggest 50–60 (**inferred**). A beta guide says Hyjal has Sunscale Salmon, Redgill and Lightning Eel ([MMOExp](https://www.mmoexp.com/News/wow-forever-fishing-guide-2026-new-beta-mechanics-crafts-rare-fish-tournament-rework-unique-loot.html), *third party*). "Shark-Infested Waters" and the new Fishing Harpoon (208773, "A must-have for the aspiring shark hunter!") may be a fishing spot or something else entirely (**to confirm**).

Keep the bands as data, not code. Then a new zone is one table row.

## 3. Detecting a catch (API)

Short answer: use **`LOOT_READY` + `IsFishingLoot()` + `GetLootSlotLink`/`GetLootSlotInfo`**, and read the zone with **`C_Map.GetBestMapForUnit("player")`** and **`GetSubZoneText()`** at that moment. Nothing in that path is restricted outside combat and encounters. Fishing happens outside both.

| API | What the Forever source says | How sure |
|---|---|---|
| `LOOT_READY(autoloot)` and `LOOT_OPENED(autoLoot, isFromItem)` | Both are in Forever's API docs with plain payloads and no secret flags ([UI: LootDocumentation.lua L218–L237](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootDocumentation.lua#L218-L237)). `LOOT_READY` fires first. With auto-loot on, the slots are already filled when it fires, before they're taken ([wiki: LOOT_READY](https://warcraft.wiki.gg/wiki/LOOT_READY)). | **Documented** |
| `IsFishingLoot()` | Blizzard's own Forever loot frame calls it on `LOOT_OPENED` to play the reel-in sound ([UI: Mainline/LootFrame.lua L128–L140](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/LootFrame.lua#L128-L140)), and Forever loads that file ([toc L127](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc#L127)). It returns true when the loot window comes from fishing ([wiki](https://warcraft.wiki.gg/wiki/API_IsFishingLoot)). | Exists: **documented**. Its value during `LOOT_READY` with auto-loot: **to confirm** |
| `GetNumLootItems`, `GetLootSlotInfo`, `GetLootSlotLink` | Used by the same file ([L227–L228](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/LootFrame.lua#L227-L228), [L515](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/LootFrame.lua#L515)). `GetLootSlotInfo` returns texture, name, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin. The item ID comes from the link. These old globals, like `IsFishingLoot`, aren't in the generated API docs, so the docs say nothing about secret values for them. | Exist: **documented**. Not secret: **to confirm** |
| `CHAT_MSG_LOOT` | In Forever's docs **without** `SecretInChatMessagingLockdown`, the flag that `CHAT_MSG_SAY` and about 100 other events carry ([UI: ChatInfoDocumentation.lua L1814–L1839](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua#L1814-L1839), compare [L2398–L2399](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua#L2398-L2399)). It doesn't say *how* the item was got, and its text is localized, so it's only a fallback. | **Documented** |
| `UNIT_SPELLCAST_CHANNEL_START` / `_SUCCEEDED` / `_CHANNEL_STOP` | Payload `unitTarget, castGUID, spellID`, marked `SecretWhenUnitSpellCastRestricted` ([UI: UnitDocumentation.lua L4613–L4640](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L4613-L4640), [L4845–L4857](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L4845-L4857)). So `spellID` can be secret in restricted states. Fishing isn't usually done in those, but `IsFishingLoot()` makes these events unnecessary. | **Documented** |
| Fishing spell IDs | Forever data has **12** spells named "Fishing": classic's 7620, 7731, 7732, 18248, plus 13615, 24303, 1229271, 1240948, 1240959, 1240970, 1240983, 1283866 ([SpellName](https://wago.tools/db2/SpellName?build=1.60.1.70862)). Which one the cast uses is unknown. Don't hard-code it. | **To confirm** |
| Restrictions | `Enum.AddOnRestrictionType`: Combat, Encounter, ChallengeMode, PvPMatch, **Map** ("a map that applies addon restrictions"), Chat ([UI: RestrictedActionsConstantsDocumentation.lua L19–L33](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua#L19-L33)). `C_RestrictedActions.IsAddOnRestrictionActive(type)`, `GetAddOnRestrictionState` and `ADDON_RESTRICTION_STATE_CHANGED` report them ([RestrictedActionsDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsDocumentation.lua#L29-L106)). Recording a catch only writes the Member's own record. It goes out on the next DATA send, as with marked bag items (`docs/research/bag-items.md`). | **Documented**. Which maps are restricted: **to confirm** |
| `C_Map.GetBestMapForUnit("player")` | Returns `uiMapID`; `SecretArguments = "AllowedWhenUntainted"`, so a plain addon call is fine ([UI: MapDocumentation.lua L49–L63](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua#L49-L63)). Locale-independent, so store this. | **Documented** |
| `GetZoneText`, `GetSubZoneText`, `GetMinimapZoneText`, `GetRealZoneText` | Plain returns, no secret flags ([UI: ZoneScriptDocumentation.lua L19–L58](https://github.com/Gethe/wow-ui-source/blob/9dc84f0d3bbae1768ac3405b3716000bd93eda06/Interface/AddOns/Blizzard_APIDocumentationGenerated/ZoneScriptDocumentation.lua#L19-L58)). They're **localized**, so they're fine for display ("Jaguero Isle") but not as a key. | **Documented** |

**Proposed flow:**

1. On `LOOT_READY`, if `IsFishingLoot()` is true, read each slot's link → item ID, plus `GetBestMapForUnit("player")` and `GetSubZoneText()`.
2. Record the first catch of each type in the Member's own record. Don't record pooled coin or currency (`isCoin`).
3. A fished chest or clam is the catch itself. Opening it later fires `LOOT_OPENED` with `isFromItem = true` and `IsFishingLoot()` false, so its contents aren't Catches.
4. Fallback if `IsFishingLoot()` turns out unusable with auto-loot: a Fishing channel stop within ~1 s before the loot. Match the spell by name, not ID.

## 4. Can we ship a fixed "all types" list?

**Yes. It has to be a curated, shipped list, because the game can't produce one.**

- **The client can't say what's fishable.** Fishing loot tables are on the server. Forever data only says an item exists (e.g. Raw Spinefin Halibut and the fountain coins exist, but whether they're fished is unknown). There's no fishing-loot API.
- **Ship IDs, not names.** Store `{itemID, type (fish | rare | treasure), band}` per entry, plus a list version. Get name, icon and quality at runtime from `C_Item.GetItemInfo` / `Item:CreateFromItemID` (cached asynchronously), so it works in every locale and picks up renames like Raw Winter Squid.
- **Families.** A trophy-fish family (seven weights of Lobster) counts as one type: map all its IDs to one entry.
- **Some types can't be completed by everyone.** Summer Bass and Winter Squid are seasonal, the tournament fish are weekly, and some catches need the Rack or Hut buff. Mark them in the data. The UI can then say "in season" or "Sundays", rather than leaving the Crew stuck at 34 of 35.
- **Keeping it current.** Treat the list like `finals` in `Core/Together.lua`. When `IsFishingLoot()` gives an item ID that isn't in the list, record it anyway as an "unlisted catch". Log it in a dev checkout, like the encounter logger in `docs/research/boss-kills.md`. Adding it is then a one-line data change in a release. Don't count unlisted catches in the denominator, but do show them, so a new Forever fish still makes Feed news.
- **A first list of 35–45 types**, if the Rack/Hut fish stay unknown: the 25 Wowhead-confirmed fish, plus Whimsyfin, Darkshore Grouper, Sickly Looking Fish and Deviate Fish (already in the 25). Add the four Nat Pagle fish and the four tournament fish, the bloated fish as **one** "Bloated fish" type or ten, the seven trophy families, and the containers once a test confirms them. Choose by what the Crew should chase.

## 5. To check in game on Forever

1. With auto-loot **on** and **off**: is `IsFishingLoot()` true during `LOOT_READY` and during `LOOT_OPENED`? Are `GetLootSlotLink`/`GetLootSlotInfo` readable, or `issecretvalue`?
2. Which spell ID does `UNIT_SPELLCAST_CHANNEL_START` give when you cast Fishing? Is it readable?
3. Does `CHAT_MSG_LOOT` arrive with readable text for a fished item, including during `InChatMessagingLockdown()`?
4. Opening a fished chest: is `isFromItem` true and `IsFishingLoot()` false?
5. Are any fishing waters on a restricted **Map** (`C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Map)`)?
6. Log every fished item ID with `uiMapID` and subzone for a few sessions in different bands. That confirms which containers, clams, bloated fish and oddities are fishable, and where.
7. Whimsyfin: Redridge only? Which waters, and what skill?
8. Fishing Rack and Fishing Hut buffs: which uncommon and rare items do they add?
9. Is Raw Plated Armorfish fishable, and where?
10. Riverglades, Gilneas, Shen'dralas, Mount Hyjal, Shark-Infested Waters: what's caught there, and at what level and skill?
11. Can you fish in City of Dalaran's fountain, and does it give the wishing coins?
12. Are Summer Bass and Winter Squid still seasonal, and Nightfin and Sunscale still tied to time of day?
13. Extravaganza: day and time on live realms, and whether the rare fish (Angelfish, Queenfish, Racer) still appear only during it.
