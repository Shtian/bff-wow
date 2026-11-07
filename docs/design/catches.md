# Catches

Answers [Catches: record and share the Crew's fishing catches](https://github.com/Shtian/bff-wow/issues/137), the foundation of Catches, [Catches: the Catches tab](https://github.com/Shtian/bff-wow/issues/138), and [Catches: a Goals track, rare finds in the Feed and While you were away](https://github.com/Shtian/bff-wow/issues/139). Builds on owner-written records (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`), the way Clears are kept in each Member's own record (`docs/adr/0005-clears-kept-in-each-members-own-record.md`), and Gossip's send timing (`docs/design/code-structure.md`). Domain vocabulary from `CONTEXT.md` (**Catch**, **Type**, **Extra**, **Unlisted catch**, **Rare find**, **Waters**). The list and the API findings come from `docs/research/fishing-catches.md`. The look comes from the prototype on branch `prototype/catches` (`prototypes/catches.html`, round 4).

## The idea in one line

Each Member's own client records what they fish, per type, in their record. The Crew's Catches is the union: each type is filled in the first time anyone catches it, credited to whoever caught it earliest.

## The list (data)

`Core/Catches.lua` ships the list as data. A new type or a new zone is one row.

- **Waters** (`Catches.WATERS`): zone-level bands, lowest first: Level 1–10, 10–25, 20–35, 30–45, 40–55, 50–60, and New on Forever. Each has the zones it covers, as an English client names them, and its lowest and highest zone level (`low`, `high`; none for New on Forever). Bands follow zone level, not fishing skill, since Forever's skill thresholds aren't known (research §2).
- **Types** (`Catches.TYPES`), in the list's order. Each has an `id` (the item ID, or a family's key such as `"catfish"`), its item IDs, an English `name` (shown only while the game hasn't cached the item), a `kind`, its waters (lowest first) and, for an Extra, why it isn't counted.
  - **Counted (46):** 25 fish (`fish`), Nat Pagle's 4 quest fish (`quest`), the 10 bloated fish (`bloated`) and 7 families of fish sold by weight (`family`: Mud Snapper, Catfish, Yellowtail, Redgill, Mightfish, Lobster, Salmon). Every weight of a family counts as the one type.
  - **Extras (shown, never counted):** the seasonal Summer Bass and Winter Squid (`season`), the Sunday fishing contest's 4 fish (`contest`), and what isn't confirmed on Forever yet (`unconfirmed`): Whimsyfin, Raw Plated Armorfish and 15 chests, crates, trunks, a clam and a message in a bottle (`treasure`).
- A type may have a `note` for its tooltip: where it bites ("Only in Loch Modan"), how to open it ("Right-click it to open it"), which quest wants it.
- Names and icons come from the game by item ID (`C_Item.GetItemInfo`), so every locale works and renames such as Raw Winter Squid show up. A family shows its first item's icon.
- Every item ID belongs to one type at most. `Catches.typeOf(itemId)` gives its type's id.

The in-game check ticket may correct the list (research §5).

## Detecting a catch (own client only)

- App listens for `LOOT_READY` and keeps each loot window's catch once, until `LOOT_CLOSED` (the event can fire more than once for one window). A window that doesn't read as fished is read again on the next `LOOT_READY`, in case `IsFishingLoot()` wasn't true yet. With auto-loot, the slots are still filled when it fires.
- `Snapshot.catch()` hands `Catches.read(api)` the loot globals (`IsFishingLoot`, `GetNumLootItems`, `GetLootSlotLink`, `GetLootSlotInfo`), `GetRealZoneText`, `GetSubZoneText`, `C_Map.GetBestMapForUnit("player")` and `issecretvalue`. Offline tests hand it a fake.
- Only `IsFishingLoot()` says it was fished. Fishing's cast events can hide their spell ID from addons (`SecretWhenUnitSpellCastRestricted`), and Forever has 12 Fishing spells, so they aren't used.
- Each slot with an item link is an item (its ID from the link, its quantity from `GetLootSlotInfo`). Coin and currency slots are skipped. Opening a fished chest later isn't fishing loot, so its contents aren't Catches.
- A value that reads secret, or a read that errors, reads nothing: it costs that catch, never anything else.
- **Not built yet:** the `CHAT_MSG_LOOT` fallback. It's only needed if the in-game check finds that `IsFishingLoot()` misses catches (for example with auto-loot). Its text is localized and doesn't say how the item was got.

## Saving

`core:caught(loot)` writes what was fished into the own record, inside a Crew or not (a Character must have been reported):

- A Member-level field `catches`: `{ [key] = { t, n, z, s, m, c } }`. `key` is the type's id (an item ID or a family's key), or the item ID of an unlisted catch. `t` is the first catch's time, `z`, `s` and `m` its zone, subzone and map ID, `c` the GUID of the Character who caught it, and `n` how many have been caught (each slot's quantity added). Later catches only add to `n`. Short names, since it rides every DATA.
- **Unlisted catches** are kept the same way, under their item ID, so the list can grow: once a later release lists the item, the same entry counts. At most `Catches.UNLISTED_CAP` (50) are kept; a new one past it is dropped, while listed types and later catches of ones held still go in.
- **"Later" urgency**, like professions and gold: a catch waits for the next send or the 5-minute heartbeat. A rare find is Feed news, so it goes out now.

## Sharing and the shape check

The field travels with the rest of the record. The record itself isn't checked for it, so a malformed field costs only the catches, and it's relayed unchanged, as older clients relay a field they don't know. When the Crew's catches are worked out, a field that isn't a table, or has more than 400 entries, is ignored, and so is each entry that isn't `{ t (number), n (whole number above 0), z, s, c (text, optional), m (whole number, optional) }`, or whose key is neither a whole item ID nor a family this client's list knows. Past `UNLISTED_CAP` unlisted catches in one record, the later ones are skipped. A family item kept under its own ID (by an older list) counts as the family.

## The read

`core:catches()` works over every Member held who hasn't left, you included:

- `total`: how many types count (46), `caught`: how many of those someone has caught, and `title` ("The Crew has caught 3 of 46 types."). Extras never count.
- `types`: every type in the list's order, with `id`, `itemId` (the item whose name and icon the game shows), `items`, `name`, `kind`, `waters`, `extra`, `note`, `count` (the Crew's total), `first`, nil until caught, and `others`, every other Member who has caught it (`memberId`, `displayName`, `own`), in the order they first did.
- `unlisted`: each unlisted catch, earliest first, with `itemId`, `count`, `first` and `others`.
- `waters`: the bands, lowest first.
- `first` is the earliest catch across the Crew (ties by Member id): `memberId`, `displayName`, `own`, `character` and `classFilename` (from the record's Characters; nil once it doesn't have that Character), `time`, `since` ("5m ago"), `zone`, `subzone`, `mapId`, `who` ("You" for your own, else the display name) and `text`, who and where in words ("Bob (Bobby), Westfall, The Jansen Stead, 5m ago", "You" for your own).

## The tab

The **Catches** tab, after Together (Dungeons) in the sidebar, or `/bff catches`, is a field guide of the Crew's catches. `core:catchesTab(group, show)` words all of it over `catches()`; `UI/CatchesTab.lua` asks the game for each item's name, icon and quality and draws it.

- **Top:** "25 of 46 types caught" (the number in Body, the rest in Small Smoke Muted) on one line with the **Group** and **Show** pickers (the app's small picker buttons, opening the game's menu, like the Roster's Sort). Under it a 4px bar with a tick at each trophy step (`Catches.STEPS`: 10, 20, 30, 40 and every type) and "Next trophy at 30 types: 5 more to catch". With every type caught the count and the bar turn gold ("All 46 types caught"). When the pickers don't fit beside the count (a narrow panel, as at the minimum size), they show only what's picked ("Where to fish", "All"; their icons say which is which), and only if that still doesn't fit do they go on a line of their own under it.
- **Group:** Where to fish (default) or Type. **Show:** All, Fish, Rare catches, Extras or Not caught yet, each with how many tiles it shows. Under them the checkbox **Show names of fish not caught yet**, the `catchesNames` setting (off by default, saved in `BFF_DB`, so per Member); clicking it keeps the menu open. What Group and Show have picked is the UI's, like the Roster's sort, and resets on a reload.
  - Fish is the `fish` kind; Rare catches are Nat Pagle's, the bloated fish, the families and the contest fish. Extras show under Fish or Rare catches by their kind (treasure under neither). Unlisted catches show only under All.
- **The grid:** 28px tiles. **Each type shows once**, in the lowest water it's found in.
  - **Where to fish:** a section per water ("Level 30–45", its zones under it, and "8 / 12" for its counted types), then New on Forever (unlisted catches; "Nothing caught here yet" under All when there are none).
  - **Type:** Fish, Rare catches and, when there are any, "Not on the list yet" (unlisted catches).
  - Either way, **Extras** come last, with "Not counted" under the title and how many are caught. Sections with nothing to show under the Show picked are left out, but a section's count is always over all its counted types, so the counts add up to the total.
  - A caught tile is full colour on a Raised Plate, with a faded 1px edge in the item's quality colour (none for common), and a 2px gold line under it if it was first caught in the last 3 days (`Catches.FRESH`).
  - A tile not caught is faint, with a 1px edge, and shows "?". With names on, it shows the item's icon in grey instead.
- **Tooltip:** the name in its quality colour, or "???" while names are off and it isn't caught. Then its note, whether it's an Extra and why ("Extra, not counted: only in one season"), "First caught by Mira (Mira Vale)" (the Member in their Character's class colour, "You" in Ash Text), when and where ("2 days ago · Feralas, The Twin Colossals"), "The Crew has caught 212", who else has caught it ("Also caught by Tor and you"), and "Where:" with every water it's found in. On a tile not caught: "No one in the Crew has caught this yet.", and with names off how to show them. The note is left out while the name is hidden, since it can give the fish away.
- A section's count is over all its counted types, even when Show leaves fewer tiles in it.
- **Recent first catches:** a strip at the bottom with up to 3 first catches from the last 3 days, newest first, unlisted ones too: "Tor caught Feralas Ahi", the item in its quality colour and the rest not gold, with the zone and when on the right. In a short panel (under 300px of content) it holds 2, and in a narrow one the zone is left out.
- **States:** a Crew with no catches at all sees "No catches yet" and "When anyone in the Crew catches a fish, it shows up here. Start in the waters for your level: Level 20–35." (the highest band whose lowest level the Character you play has reached) above the grid. A Show that leaves nothing says so ("The Crew has caught every type." for Not caught yet) and "Change "Show" to see more."
- Item quality colours are allowed here by DESIGN.md's Catch Colours Rule (`Skin.ITEM_QUALITIES`).
- The sidebar now has 8 tabs. In a short window (the panel's minimum height with the Camp's short band) its rows get shorter than 30px so Settings stays clear of them.

## News

**Only big moments are news.** An everyday first catch (the Crew's first Brilliant Smallfish) stays in the Catches tab and makes no Feed entry, and an unlisted catch is never news.

- **Types caught**, a Crew goal track: steps at 10, 20, 30, 40 and every type, trophies in the cabinet, and a gold goal entry for each step (`docs/design/goals.md`).
- **Rare finds:** the Crew's first catch of one of Nat Pagle's 4 quest fish or the 4 contest fish (`quest` and `contest` kinds) is a `rareFind` Feed entry with a Cheer and a Live event. It reads like a game item link: "Tor caught Feralas Ahi", "Tor's Alt Jaina caught Feralas Ahi", "You caught Feralas Ahi"; not gold, with the item's name in its quality colour and a faded quality edge on its icon, none for common, and its toast shows the item rather than a Camp figure (`docs/design/feed.md`).
  - **The Crew's first** is decided per client, as a Member's record arrives: it newly holds a rare type, and no other Member held who hasn't left does. So one client makes one entry per type at most. Two Members catching the same fish before either hears of the other can each be credited on a different client, and the tab, which goes by the earliest catch, may then name the other one. Accepted as rare and harmless.
  - The first sight of a Member stays silent, as for all Feed entries, and so do catches made outside a Crew.
- **While you were away:** a Catches section. "4 new types caught (Tor 3, Mira 1)" counts the counted types first caught by **other** Members since you were last online, most first, never your own. Each rare find you missed has its own line with its Cheer. `db.lastOnline` is written every tick, since nothing tells Core of a logout, and a first login ever has no line. The game saves it on logout or a reload, so after a crash it's older and a type can be counted again. The count goes by when a type was caught, so a catch from before your last logout that only reaches you now isn't counted; a rare find, being an unseen entry, still shows.

## Dev

- `/bff sim`: the first two simulated Members have a few days of past catches. The console's **Fish** button (and `/bff sim fish`, for a random online Member) catches something on the list in the Member's zone, or now and then an unlisted find.

## Not in this

The chat loot fallback (see above).
