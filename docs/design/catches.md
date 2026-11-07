# Catches

Answers [Catches: record and share the Crew's fishing catches](https://github.com/Shtian/bff-wow/issues/137), the foundation of Catches. The tab and the Feed news build on it in later tickets. Builds on owner-written records (`docs/adr/0001-owner-written-records-gossiped-by-server-time.md`), the way Clears are kept in each Member's own record (`docs/adr/0005-clears-kept-in-each-members-own-record.md`), and Gossip's send timing (`docs/design/code-structure.md`). Domain vocabulary from `CONTEXT.md` (**Catch**, **Type**, **Extra**, **Unlisted catch**, **Waters**). The list and the API findings come from `docs/research/fishing-catches.md`. The look comes from the prototype on branch `prototype/catches` (`prototypes/catches.html`, round 4).

## The idea in one line

Each Member's own client records what they fish, per type, in their record. The Crew's Catches is the union: each type is filled in the first time anyone catches it, credited to whoever caught it earliest.

## The list (data)

`Core/Catches.lua` ships the list as data. A new type or a new zone is one row.

- **Waters** (`Catches.WATERS`): zone-level bands, lowest first: Level 1–10, 10–25, 20–35, 30–45, 40–55, 50–60, and New on Forever. Each has the zones it covers, as an English client names them. Bands follow zone level, not fishing skill, since Forever's skill thresholds aren't known (research §2).
- **Types** (`Catches.TYPES`), in the list's order. Each has an `id` (the item ID, or a family's key such as `"catfish"`), its item IDs, an English `name` (shown only while the game hasn't cached the item), a `kind`, its waters (lowest first) and, for an Extra, why it isn't counted.
  - **Counted (46):** 25 fish (`fish`), Nat Pagle's 4 quest fish (`quest`), the 10 bloated fish (`bloated`) and 7 families of fish sold by weight (`family`: Mud Snapper, Catfish, Yellowtail, Redgill, Mightfish, Lobster, Salmon). Every weight of a family counts as the one type.
  - **Extras (shown, never counted):** the seasonal Summer Bass and Winter Squid (`season`), the Sunday fishing contest's 4 fish (`contest`), and what isn't confirmed on Forever yet (`unconfirmed`): Whimsyfin, Raw Plated Armorfish and 15 chests, crates, trunks, a clam and a message in a bottle (`treasure`).
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
- **"Later" urgency**, like professions and gold: a catch waits for the next send or the 5-minute heartbeat.

## Sharing and the shape check

The field travels with the rest of the record. The record itself isn't checked for it, so a malformed field costs only the catches, and it's relayed unchanged, as older clients relay a field they don't know. When the Crew's catches are worked out, a field that isn't a table, or has more than 400 entries, is ignored, and so is each entry that isn't `{ t (number), n (whole number above 0), z, s, c (text, optional), m (whole number, optional) }`, or whose key is neither a whole item ID nor a family this client's list knows. Past `UNLISTED_CAP` unlisted catches in one record, the later ones are skipped. A family item kept under its own ID (by an older list) counts as the family.

## The read

`core:catches()` works over every Member held who hasn't left, you included:

- `total`: how many types count (46), `caught`: how many of those someone has caught, and `title` ("The Crew has caught 3 of 46 types."). Extras never count.
- `types`: every type in the list's order, with `id`, `itemId` (the item whose name and icon the game shows), `items`, `name`, `kind`, `waters`, `extra`, `count` (the Crew's total) and `first`, nil until caught.
- `unlisted`: each unlisted catch, earliest first, with `itemId`, `count` and `first`.
- `waters`: the bands, lowest first.
- `first` is the earliest catch across the Crew (ties by Member id): `memberId`, `displayName`, `own`, `character` and `classFilename` (from the record's Characters; nil once it doesn't have that Character), `time`, `since` ("5m ago"), `zone`, `subzone`, `mapId`, and `text`, who and where in words ("Bob (Bobby), Westfall, The Jansen Stead, 5m ago", "You" for your own).

## Dev

- `/bff catches` (dev checkout only, like `/bff sim`) prints the Crew's catches: the count of types caught, then each type and unlisted catch with the Crew's count and who caught it first, where and when. It stands in until the Catches tab exists.
- `/bff sim`: the first two simulated Members have a few days of past catches. The console's **Fish** button (and `/bff sim fish`, for a random online Member) catches something on the list in the Member's zone, or now and then an unlisted find.

## Not in this

The Catches tab and the Feed news (their own tickets), trophy steps, and the chat loot fallback (see above).
