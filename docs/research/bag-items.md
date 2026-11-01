# Research: marking bag items, tradeability, items leaving the bags, item links

Results for [#65](https://github.com/Shtian/bff-wow/issues/65), feeding [#67](https://github.com/Shtian/bff-wow/issues/67). Desk research done on 2026-11-01, then partly tested on retail the same day: see [Results on retail](#results-on-retail). Where the results contradict the desk research, the results win.

Main source: Blizzard's UI source for Forever itself. The [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) mirror has a `forever` branch, **1.60.1 (70532)**, commit [`ca8368f`](https://github.com/Gethe/wow-ui-source/tree/ca8368f2f2380cbe696854f7f2646387c278a61b). Links below go to that commit; `UI:` is short for `https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/`. Forever loads the **Mainline** bag code (`[Family]\ContainerFrame.lua [AllowLoadGameType mainline]`) with a small Camelot override that doesn't touch item buttons ([toc lines 118–124](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc#L118-L124), [Camelot/ContainerFrame.lua](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/ContainerFrame.lua)). API facts come from the generated API docs in that branch (`Blizzard_APIDocumentationGenerated`) and from warcraft.wiki.gg.

How sure each answer is:

- **Documented:** Blizzard's source, Blizzard's API docs, or the wiki says so.
- **Inferred:** it follows from documented facts, but nobody has seen it happen.
- **Needs a game test:** see the checklist at the end.

## Answer

- **Marking:** Forever's bags have **no per-item right-click menu**. A plain right-click uses, equips or sells the item, so option (a) is out. Dragging an item onto a BFF drop slot (c) needs no hooks into Blizzard code and works the same with every bag addon. Use it, and keep `/bff spares add` plus shift-click as the fallback. A modifier-click hook (b) is possible but has more catches.
- **Tradeability:** check `C_Item.IsBound(itemLocation)` (soulbound or account-bound means no), plus the item's `bindType` from `C_Item.GetItemInfo` to reject quest items. No API flags conjured items. The tooltip is the only way to see that.
- **Leaving the bags:** when posting, remember the item's **GUID** on the posting character (`C_Item.GetItemGUID`), not in the record. After each `BAG_UPDATE_DELAYED`, ask `C_Item.GetItemLocation(guid)` where it is. Fall back to matching the trimmed item string. Don't decide anything until the bags have loaded after login.
- **Item links:** Blizzard's own comment in the Forever branch confirms the layout the code assumes: item ID 1, enchant 2, gems 3–6, suffix 7, unique ID 8. What still needs the game is whether Forever's random-stat items use negative suffix IDs at all, or bonus IDs, which the trimmed string drops.

## 1. Marking an item

| Option | What the source says | Taint | Combat / instances / chat lockdown | Status |
|---|---|---|---|---|
| **(a) Context menu** | Bag item buttons have no menu. `RegisterForClicks("LeftButtonUp", "RightButtonUp")`, and an unmodified right-click goes to `ContainerFrameItemButton_OnClick`, which calls `C_Container.UseContainerItem` (use, equip, sell or deposit) ([OnLoad L1646](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L1646-L1666), [L1540–L1619](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L1540-L1619)). The only bag menus with tags are the **bag** portrait menus `MENU_CONTAINER_FRAME` and `MENU_CONTAINER_FRAME_COMBINED` ([L777](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L777), [L2770](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L2770)), and they're per bag, not per item. Searching every `SetTag("MENU_…")` in the branch finds no item menu tag. | `Menu.ModifyMenu` exists ([Menu.lua L2724](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_Menu/Menu.lua#L2724)). Blizzard's guide says addons can add menu entries "without imparting taint" ([guide L407–418](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_Menu/11_0_0_MenuImplementationGuide.lua#L407-L418)). That doesn't help, because there's no item menu to add to. | n/a | **Documented:** not possible in the default bags. Hooking `OnClick` to open a menu of our own on modified right-click would really be option (b). |
| **(b) Modifier-click hook** | A click with a modifier goes to `OnModifiedClick` and doesn't use the item. Exception: AUTOLOOTTOGGLE on a lootable item ([L1668–L1684](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L1668-L1684)). `OnModifiedClick` calls the **global** `HandleModifiedItemClick(link, itemLocation)`, looked up at call time ([L1766–L1799](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L1766-L1799), [ItemButtonTemplate.lua L367](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_ItemButton/Mainline/ItemButtonTemplate.lua#L367-L398)). So `hooksecurefunc("HandleModifiedItemClick", f)` sees every modified bag click, with an `ItemLocation`. Catches: (1) a hook runs **after** Blizzard's handler and can't stop it, so Shift still links to chat and Ctrl still opens the dressing room. Pick a free modifier. (2) An EXPANDITEM click on a socketable item returns before the call. (3) The hook fires for modified clicks everywhere: loot, merchant, chat links, and with `itemLocation` nil. Act only when `itemLocation` is a bag slot. (4) Hooking the mixin's `OnModifiedClick` would miss buttons that already exist, since a mixin's methods are copied onto each button when it's created. The `EventRegistry` callback `ContainerFrameItemButton.OnItemClicked` fires only for unmodified clicks ([L1618](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L1618)), so it's no use here. | `hooksecurefunc` is "the only safe way to hook functions that execute protected functionality". The hook runs after the original, with the same arguments, and can't be removed ([wiki](https://warcraft.wiki.gg/wiki/API_hooksecurefunc)). Replacing `HandleModifiedItemClick` or an item button's `OnClick` with `SetScript` would taint. Blizzard guards these buttons on purpose: "Prevent bagID from tainting all interaction with items through attributes" ([L1823–L1828](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L1823-L1828)). The hook must not write fields onto the button. | Bag item buttons are plain `ItemButton`s, not secure templates ([XML L81](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml#L81)), and `HandleModifiedItemClick` isn't protected. So the hook should run in combat too (**inferred**). | **Documented** mechanism. Taint-free and combat behaviour **need a game test**. |
| **(c) Drag onto a BFF frame** | An addon frame's `OnReceiveDrag` reads the cursor. `C_Cursor.GetCursorItem()` returns the `ItemLocation` of the item being carried ([CursorDocumentation L11](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/CursorDocumentation.lua#L11-L19)), and `GetCursorInfo()` returns `"item", itemID, itemLink` ([wiki](https://warcraft.wiki.gg/wiki/API_GetCursorInfo)). `ClearCursor()` puts the item back ([GameCursorDocumentation L10](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/GameCursorDocumentation.lua#L10)). Bag buttons pick up on drag with `OnDragStart` → `OnClick("LeftButton")` → `C_Container.PickupContainerItem` ([L1815](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua#L1815-L1821)). A pick-up-then-click needs an `OnClick` on the slot too, since `OnReceiveDrag` covers only a real drag (**inferred**). | No Blizzard code is touched. `GetCursorItem`, `GetCursorInfo` and `ClearCursor` have no `HasRestrictions` flag in the docs (the API docs mark restricted calls that way, e.g. `C_Item.DeleteItem`). | Picking up bag items isn't restricted (`PickupContainerItem` has no `HasRestrictions`), so it should work in combat and instances (**inferred**). | **Documented** APIs. The click path and combat behaviour **need a game test**. |

**Chat lockdown applies to all three in the same way.** Marking only writes the owner's own record. The Crew sees it on the next DATA send. While `C_ChatInfo.InChatMessagingLockdown()` is true, BFF's channel link is already down (`Game/ChannelLink.lua`), and Core sends when it comes back up. That covers encounters and other restricted states (`Enum.AddOnRestrictionType`: Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat; [RestrictedActionsConstants](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/RestrictedActionsConstantsDocumentation.lua#L19)). **Inferred** from BFF's own code and the channel spike.

**Replacement bag addons** (matters for (b), not for (c)):

| Addon | What its buttons do | Effect on a `HandleModifiedItemClick` hook |
|---|---|---|
| Bagnon (BagBrother core, TOC lists 16001) | Live items inherit `ContainerFrameItemButtonTemplate` ([item.lua L7](https://github.com/Jaliborc/BagBrother/blob/0c5f459f5bd2b6d3fff77979c85cddd31ce5ce02/core/classes/item.lua#L7)), so they reach the same `OnModifiedClick`. Items from other characters (cached) use a dummy button that calls `HandleModifiedItemClick(link)` **with no location** ([L263–L268](https://github.com/Jaliborc/BagBrother/blob/0c5f459f5bd2b6d3fff77979c85cddd31ce5ce02/core/classes/item.lua#L263-L268)). **Alt+Left-click** is Bagnon's "flash find" ([L97–L104](https://github.com/Jaliborc/BagBrother/blob/0c5f459f5bd2b6d3fff77979c85cddd31ce5ce02/core/classes/item.lua#L97-L104)). | Works for live items (**inferred**). Ignore calls with no location. Don't use Alt+Left. |
| AdiBags | Also inherits `ContainerFrameItemButtonTemplate` ([ItemButton.lua L79–81](https://github.com/AdiAddons/AdiBags/blob/10808e8343d69e165c64c0983be22d8c766b9cbe/widgets/ItemButton.lua#L79-L81)). Last commit 2024-09, TOC 110002, so it may not run on Forever. | Works if it runs at all (**inferred**). |
| Baganator, ArkInventory | Not checked: I couldn't find Baganator's source repo, and the GitHub code search hit its rate limit. | Unknown. **Needs a game test.** |

With (c), any bag addon works that lets you pick an item up onto the cursor, which every bag addon does.

## 2. Tradeability

BFF Members are on different Battle.net accounts, so "account-bound to the wrong scope" means **any** account binding.

| Check | What it gives | Problem | Status |
|---|---|---|---|
| `C_Item.IsBound(itemLocation)` | "Whether or not the item is soul- or accountbound" ([wiki](https://warcraft.wiki.gg/wiki/API_C_Item.IsBound), [docs L1186](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L1186-L1199)). This is the item's state right now, so a BoE still in the bags is unbound and the same BoE after equipping is bound. | Doesn't catch unbound quest items or conjured items. | **Documented** |
| `C_Container.GetContainerItemInfo(bag, slot).isBound` | The same fact, by bag and slot ([docs L192, L766–L782](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua#L766-L782)). Blizzard uses it for the bag button's bound overlay. | Only works by bag and slot. `IsBound` takes the `ItemLocation` that the cursor, the hook and `GetItemLocation(guid)` all return. | **Documented** |
| `bindType` (14th return of `C_Item.GetItemInfo`) | The item template's binding: `Enum.ItemBind` None 0, OnAcquire 1, OnEquip 2, OnUse 3, **Quest 4**, ToWoWAccount 7, ToBnetAccount 8, ToBnetAccountUntilEquipped 9 ([GetItemInfo L626–L656](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L626-L656), [ItemBind L249–L266](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua#L249-L266)). | Static: a BoE reads 2 even after it's bound. On its own it can't tell an unbound BoE from a bound one. | **Documented** |
| `C_TooltipInfo.GetBagItem(bag, slot)` | Tooltip lines. There's a `TooltipDataLineType.ItemBinding` and a `TooltipDataItemBinding` enum (Quest, Soulbound, BindOnEquip, …) ([TooltipInfoShared L6–L24](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoSharedDocumentation.lua#L6-L24), [GetBagItem L137](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/TooltipInfoDocumentation.lua#L137)). | The docs don't name the field that holds the binding. Lines need `TooltipUtil.SurfaceArgs` ([wiki](https://warcraft.wiki.gg/wiki/Patch_10.0.2/API_changes)). There's no line type for "Conjured Item", so detecting conjured means matching localised text. Heavier than the other checks. | **Inferred** usable; field names **need a game test** |

**Pick: `C_Item.IsBound(itemLocation)` plus a `bindType` check.** Refuse the item if `IsBound` is true (soulbound, or account-bound at any scope). Also refuse if `bindType` is Quest (4) or 7, 8 or 9 (account bindings, a second check behind `IsBound`). Why: `IsBound` gives the item's current state, which `bindType` can't, and it takes the `ItemLocation` every marking path already has. `bindType` adds quest items cheaply, and the item is always cached because it's in the bags. The tooltip only adds conjured items, and those are rare, nearly worthless, and refused by the mail window anyway. So don't check for conjured: if one slips through, the owner just can't mail it. If that turns out to matter, a tooltip text match against `ITEM_CONJURED` is the fallback (**inferred**).

`C_AuctionHouse.IsSellItemValid(itemLocation, false)` exists in Forever ([docs L809](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua#L809-L823)). The server's AH rules reject bound, quest and conjured items (`Enum.AuctionHouseError.ConjuredItem` exists). It might work as a single check, but it's undocumented whether it answers away from an auction house, and the AH rules differ from the mail rules (damaged items, for example). Not recommended without a test.

All of these take `SecretArguments = "AllowedWhenUntainted"` and none has secret returns in the Forever docs, so plain addon calls work (**documented**).

## 3. Leaving the bags

| Approach | How | Stacks | Duplicate item | Status |
|---|---|---|---|---|
| **Item GUID** | On posting, store `C_Item.GetItemGUID(location)` ([docs L501](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L501-L514)). Later, `C_Item.GetItemLocation(guid)` returns a location or **nil** ([docs L786](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L786-L799); [wiki](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemLocation) lists it for Forever 1.60.1). `IsBagAndSlot()` / `IsEquipmentSlot()` tell bags from equipped ([ItemLocation.lua](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_ObjectAPI/Mainline/ItemLocation.lua#L56-L66)). | One GUID per stack. Whether splitting or merging stacks keeps the GUID isn't documented. | Tells two identical items apart: selling the other copy doesn't end this one. | API **documented**. Nil-when-gone and GUID stability across relog, bank and stacks **need a game test** |
| **Rescan by item string** | On `BAG_UPDATE_DELAYED`, fired "after all applicable BAG_UPDATE events for a specific action" ([wiki](https://warcraft.wiki.gg/wiki/BAG_UPDATE_DELAYED), [docs L677](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua#L675-L679)), walk bags 0–5 (plus keyring −1; [BagIndex](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua#L18-L52)) with `C_Container.GetContainerItemLink` → `Spares.itemString` and look for a match. | Unaffected by stacks. | Can't tell copies apart: it ends only when the **last** matching copy leaves. | **Documented** APIs. A scan takes about 100 slots; cheap (**inferred**) |
| **Events** (`MAIL_SEND_SUCCESS` etc.) | `MAIL_SEND_SUCCESS` carries no payload ([MailInfo L133](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/MailInfoDocumentation.lua#L130-L136)), so it doesn't say which item went. `SendMail` sits in the secure transfer UI and has `HasRestrictions` ([SecureTransfer L91](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecureTransferDocumentation.lua#L91-L94)), so don't hook it to read the recipient. Selling, destroying, trading and equipping each have different events, or none. | n/a | n/a | **Documented**: not enough on its own. At most a hint ("left while mailing"). |

The cases:

- **Sold, destroyed, traded, mailed:** the GUID resolves to nil, and the item string no longer matches (**inferred**; test).
- **Equipped:** `GetItemLocation` returns an equipment slot. Treat it as gone, as #67 says (**inferred**).
- **Bank:** Forever has a tabbed character bank (bag IDs 6–14) and an account bank (−3, 15–23) ([BagIndex](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/BagIndexConstantsDocumentation.lua#L18-L52), [Camelot/BankFrame.lua](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/BankFrame.lua#L27-L33)). A banked item can still be mailed, so **banked shouldn't count as gone**. With GUIDs, a bank location is "kept". Whether `GetItemLocation` resolves bank items while the bank is **closed** is unknown, and the wiki notes locations for bank-bag GUIDs are invalid. A rescan covering only bags 0–5 would end it wrongly. **Needs a game test.**
- **Mailed to yourself (an alt):** the item leaves this character, and BFF can't see the alt's mailbox. It reads as gone and the Spare ends. The owner re-posts from the alt. Simple and honest (**inferred**).
- **Stacks:** a Spare is one item, and stackable gifts are rare. If the GUID is gone but an item with the same item string is in the bags, take that item's GUID as the new one and keep the offer (**inferred**).
- **Item GUIDs and Forever's obfuscation:** Forever 1.60.1 obfuscates creature, vehicle, pet and game object GUIDs, "stable and unique within your own session" ([wiki, Beta Changes 5](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes)). Item GUIDs aren't on that list. Whether item GUIDs survive a relog **needs a game test**, and the GUID approach depends on it.

**Login timing.** `BAG_UPDATE` "may not fire on login" for the backpack, and APIs "can provide unreliable information during this event" ([wiki](https://warcraft.wiki.gg/wiki/BAG_UPDATE)). A nil from `GetItemLocation` before the bags have loaded looks exactly like "gone". So BFF should never end a Spare from a check that runs before the first `BAG_UPDATE_DELAYED` after `PLAYER_ENTERING_WORLD`, and should check that the backpack reports slots (`C_Container.GetContainerNumSlots(0) > 0`). The GUID lookup and the item-string rescan have the same problem here, and the same guard covers both (**inferred**; test).

Only the posting character can check its own bags, so the local GUID store has to be keyed by Character GUID, and checks run only while that character is logged in (**inferred** from the domain).

## 4. Item links (confirm only)

What the code assumes (`Core/Spares.lua`): fields after `item:` are 1 item ID, 2 enchant, 3–6 gems, 7 suffix, 8 unique ID. `itemString` keeps `id[:enchant[:suffix[:unique]]]`, with the unique ID only for a negative suffix. `fullItemString` puts them back at positions 1, 2, 7 and 8 and leaves everything after field 8 empty (`item:15210::::::-19:1238425`). `Snapshot.itemLink` / `Snapshot.requiredLevel` call `C_Item.GetItemInfo` (falling back to `GetItemInfo`) and read returns 2 and 5. `C_Item.GetItemInfo` returns `itemLink` 2nd and `itemMinLevel` 5th in Forever's docs ([L636–L656](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L636-L656)).

| Check | Finding | Status |
|---|---|---|
| Field layout | Blizzard's comment in the Forever branch: `item:itemID:enchantID:gemID1:gemID2:gemID3:gemID4:suffixID:uniqueID:linkLevel:specializationID:…` ([Blizzard_Reports.lua L388–L392](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_PTRFeedback/Blizzard_Reports.lua#L388-L392)). The wiki gives the same order through `crafterGUID:extraEnchantID` ([ItemLink](https://warcraft.wiki.gg/wiki/ItemLink)). **Matches the code.** | **Documented** |
| Short item strings resolve | `GetItemInfo` "accepts an item link, or minimally in `item:%d` format" ([wiki](https://warcraft.wiki.gg/wiki/API_C_Item.GetItemInfo)), so leaving off everything after field 8 is allowed. | **Documented** |
| Negative suffix + unique ID | The wiki's TBC Classic example is `item:6267::::::-9:1379794946:33:…` "[Disciple's Pants of the Owl]": a negative suffix with the unique ID set. But the wiki also calls the unique ID "No longer used". No primary source says the unique ID carries the suffix's stat factor. Keeping it is harmless either way. | Name and quality **need a game test**. That the unique ID carries the stat factor is **not sourced**. |
| Does Forever use suffixes at all? | Forever runs on the modern client. Whether its "of the Monkey" items use suffix IDs (field 7) or **bonus IDs** (after field 13) isn't documented. With bonus IDs, the trimmed string drops them, and the rebuilt link would show the plain item, without its suffix name or stats. | **Needs a game test**, the main open risk for Q4 |
| Uncached items | `GET_ITEM_INFO_RECEIVED(itemID, success)` exists in Forever ([docs L1815](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua#L1813-L1822)). `Item:CreateFromItemID(id):ContinueOnItemLoad(cb)` is a wrapper keyed by **item ID** that waits on `ITEM_DATA_LOAD_RESULT` via `C_Item.RequestLoadItemDataByID` ([Item.lua L330](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_ObjectAPI/Mainline/Item.lua#L328-L334), [AsyncCallbackSystem.lua L18](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua#L18)). Both work per item ID, so neither loads more than the other. BFF's approach (call `GetItemInfo`, redraw on `GET_ITEM_INFO_RECEIVED`) **is enough**. | **Documented** |

## Design consequences

### Recommended way to mark items

**(c) Drag-and-drop onto a drop slot in the Spares tab.** It also takes a click while an item is on the cursor. Read `C_Cursor.GetCursorItem()` for the location, run the tradeability check, post, then `ClearCursor()`. Why: no hook into Blizzard code, so no taint risk to Midnight-era bag buttons. It works the same with the default bags, Bagnon, AdiBags and anything else that puts items on the cursor. It gets an `ItemLocation` directly. The cost is that the BFF panel has to be open.

**Fallback: keep `/bff spares add` + shift-click.** It already works and uses Blizzard's own CHATLINK path, with no hook. It only gives a link, so to check tradeability and store the GUID it has to find the item in the bags by matching the item string (first match).

A modifier-click shortcut (b), e.g. Alt+Right-click through `hooksecurefunc("HandleModifiedItemClick", …)`, can come later if the retail tests below show no taint and no clash with modifiers.

### Recommended way to detect items leaving

**Item GUID, checked with `C_Item.IsItemGUIDInInventory`.** Tested on retail (see the results below). When posting, store `{ spare id → item GUID }` locally for the posting Character (SavedVariables only, never in the record). On each `BAG_UPDATE_DELAYED`, and only after the first one since login:

1. `C_Item.IsItemGUIDInInventory(guid)` false means the item has left (sold, destroyed, traded or mailed). It covers the bank even while the bank is closed, and right after login.
2. If it's true, `C_Item.GetItemLocation(guid)` with `IsEquipmentSlot()` tells whether it's been equipped, which also means gone. Read the location's fields only after `IsItemGUIDInInventory` is true. Don't call `IsValid()` on it (see below).
3. A sold item can be bought back with the same GUID. So don't end the Spare the moment the item disappears (to be decided).

The item-string scan isn't needed. It also can't see the bank while the bank is closed.

## Results on retail

Run on 2026-11-01 on **retail 12.1.5.70688 (interface 120105)**, one character, default bags. Spike addon: branch `spike/bag-items` (`Spike/BFFBagSpike`, throwaway). Steps refer to the checklist below. Steps 4–7 (the Alt+Right-click hook), 10 (trying to mail each item), 15 (stacks), 17–19 (item links) and parts of 13 (destroy, trade, mail) were **not run**. We stopped once the design questions were answered.

### Answer

- **Marking by drag or click works everywhere:** out of combat, in combat, in a dungeon, and during a boss fight with chat lockdown on. No blocked-action errors.
- **Tradeability:** `C_Item.IsBound` gave the expected answer for every item tested. An heirloom reports `bindType` 1, not 7–9, but `IsBound` is true, so it's refused anyway.
- **Leaving the bags:** use `C_Item.IsItemGUIDInInventory(guid)`, not `GetItemLocation(guid) == nil`. `GetItemLocation` never returned nil. For an item that was gone, or banked with the bank closed, it returned an empty location, and calling `IsValid()` on that raises a Lua error.
- **Login timing:** after a real login the bags are empty until the first `BAG_UPDATE_DELAYED`. Deciding earlier would end every Spare.

### Findings

| Step | Check | Result |
|---|---|---|
| 1 | Drag a bag item onto a frame | `OnReceiveDrag` fires. `GetCursorInfo` gives `item, id, link`. `C_Cursor.GetCursorItem()` gives bag and slot. `ClearCursor()` puts the item back in its slot. |
| 2 | Pick up, then click the frame | Works. The click may arrive as `OnClick` or as `OnReceiveDrag`; handle both the same. |
| 3 | Same, in combat / dungeon / boss fight | Works in all three. `InChatMessagingLockdown()` was **false** in combat in a dungeon and **true** only during the boss encounter. |
| 8–9 | `IsBound` and `bindType` | Unbound BoE (Heavy Woolen Pants): false, 2. Same BoE **after equipping**: true, 2. Soulbound (Grasp of the Broken Totem): true, 1. Trade goods (Aquamarine, Linen Cloth): false, 0. Heirloom (Dignified Headmaster's Charge, quality 7): true, **1**. Hearthstone: true, 1. Not tested: quest items, conjured items, "Warbound until equipped". |
| 11 | GUID stability | The same GUID after moving the item, `/reload`, a full logout and login, moving it to the character bank, and **equipping** it. Two copies of the same item have different GUIDs. |
| 11–12 | Bank | With the bank **open**: `GetItemLocation(guid)` gives bag 6 (`CharacterBankTab_1`), and `IsItemGUIDInInventory` is true. With the bank **closed**: `GetItemLocation` returns an ItemLocation with every field nil, and `IsValid()` on it errors (`bad argument #1 to 'DoesItemExist'`). Every bank container reports 0 slots, but `IsItemGUIDInInventory` is still **true**. After a fresh login, without opening the bank: still true. The account bank wasn't tested. |
| 13 | Sold | `IsItemGUIDInInventory` false, `GetItemLocation` empty (not nil). **Bought back:** same GUID, back in the same slot. |
| 14 | Equipped | `GetItemLocation(guid)` gives `equipped, slot 7`. |
| 16 | Login timing | Fresh login: `ADDON_LOADED` backpack 0 slots. `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`: 20 slots, **0 filled**, `IsItemGUIDInInventory` false. First `BAG_UPDATE_DELAYED`: 12 filled, item found. On `/reload`, the bags are already filled at `ADDON_LOADED`. |
| — | Bag indices | The reagent bag is bag 5. `Enum.BagIndex` on retail has character bank tabs 6–11, account bank tabs 12–16, and still lists `Keyring` (−1). Forever's numbering differs (see section 3). |

### Still open

- Forever-only: whether `IsItemGUIDInInventory` behaves the same, its bank layout, and random-suffix item links (steps 17–19). Re-check at Forever launch.
- Mail to an alt, trade, destroy: expected to read as false like selling, not tested.
- Whether a mailed item keeps its GUID on the receiving alt.

## Test on retail

The Forever beta is over, so these run on **retail (Midnight)**, the closest live client, as in the [channel spike](channel-spike.md). Default bags unless noted. Use `/dump` or a scratch addon. Forever loads retail's (Mainline) bag code, so the marking, tradeability and GUID results should carry over (**inferred**). Retail can't settle everything:

- Retail has no classic random-suffix "of the X" items, so steps 17–18 can only check plain and enchanted items there. Whether Forever's suffix items use suffix IDs or bonus IDs stays open until Forever launches.
- Retail has no keyring (bag −1), and its bank layout may differ from Forever's `Camelot/BankFrame.lua`. Re-check steps 11–12 on Forever.
- Forever-only API changes (GUID obfuscation, Patch 1.60.1) can't be seen on retail.

**Marking**

1. Make a frame with `OnReceiveDrag` that prints `C_Cursor.GetCursorItem():GetBagAndSlot()` and `GetCursorInfo()`, then calls `ClearCursor()`. Drag a bag item onto it. *Expect:* bag and slot, `"item", id, link` printed, and the item back in its slot.
2. Same frame with `OnClick`: click a bag item to pick it up, then click the frame. *Expect:* the same as step 1.
3. Repeat steps 1 and 2 **in combat** (attacking a training dummy), during a **boss encounter**, and with `/dump C_ChatInfo.InChatMessagingLockdown()` true. *Expect:* it works every time, with no `ADDON_ACTION_BLOCKED` or `ADDON_ACTION_FORBIDDEN`.
4. Add `hooksecurefunc("HandleModifiedItemClick", function(link, loc) print(link, loc and loc:IsBagAndSlot()) end)`. Alt+Right-click a bag item. *Expect:* one print with `true`, and the item is **not** used or sold (also at a vendor).
5. With the hook from step 4, `/console taintLog 2`, then in combat use bag items, swap gear, open the Professions frame, and `/reload`. *Expect:* no BFF entries in `Logs/taint.log`, no blocked-action errors.
6. `/dump GetModifiedClick("CHATLINK"), GetModifiedClick("DRESSUP"), GetModifiedClick("EXPANDITEM"), GetModifiedClick("SOCKETITEM"), GetModifiedClick("SPLITSTACK")`. *Expect:* a list of the modifiers already taken. Alt+Right should be free.
7. Install Bagnon (and Baganator if available), repeat steps 1 and 4. *Expect:* drag works. The hook fires for live items with a location, and with `loc` nil for another character's items.

**Tradeability**

8. `/dump C_Item.IsBound(loc)` on: an unbound BoE, the same BoE after equipping it, a BoP item, a warbound/account-bound item, a quest item, conjured food. *Expect:* false, true, true, true. Quest and conjured items: note what it says.
9. `/dump select(14, C_Item.GetItemInfo(link))` on the same items. *Expect:* 2, 2, 1, 7/8/9, 4. Conjured: note the value.
10. Try to mail each item to another account's character. *Expect:* only the items BFF would accept can be attached.

**Leaving the bags**

11. Note an item's `C_Item.GetItemGUID(loc)`. Move it to another slot, `/reload`, log out and back in, put it in the character bank, then the account bank. After each, `/dump C_Item.GetItemLocation(guid)` and the GUID read again. *Expect:* the same GUID, and a valid location each time.
12. With the item in the bank and the **bank closed**, `/dump C_Item.GetItemLocation(guid)` and `C_Container.GetContainerItemLink(6, 1)`. *Expect:* note whether they resolve (it decides "bank = kept").
13. Sell, destroy, trade, and mail the item (once to another player, once to an alt). After each, `/dump C_Item.GetItemLocation(guid)`. *Expect:* nil.
14. Equip it. *Expect:* `GetItemLocation(guid):IsEquipmentSlot()` is true.
15. Split a stack of 5 into 2+3, then merge it back. *Expect:* note which part keeps the original GUID.
16. In a scratch addon, print `C_Container.GetContainerNumSlots(0)` and the GUID lookup at `PLAYER_LOGIN`, at `PLAYER_ENTERING_WORLD` and at the first `BAG_UPDATE_DELAYED`. *Expect:* note the first point where both give real values. BFF must not decide before then.

**Item links**

17. Shift-click a plain item, an enchanted item and a random-suffix "of the X" item into chat, then `/dump` their links (`C_Container.GetContainerItemLink`). *Expect:* enchant in field 2, suffix (negative?) in field 7, unique ID in 8. Note whether the suffix item has **bonus IDs** after field 13 instead.
18. For each, run `/bff spares add` and check the Spares tab after `/reload`. *Expect:* the same name (with "of the X"), quality colour and tooltip stats as the original.
19. On a second client that has never seen the item, open the tab. *Expect:* "Loading...", then the right link once `GET_ITEM_INFO_RECEIVED` fires.
