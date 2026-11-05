# Research: rendering pixel art in a WoW addon

For [#127](https://github.com/Shtian/bff-wow/issues/127), The Camp: how to draw crisp pixel art, sprite animation and a small animated scene in the client, and which of #127's art and rendering decisions hold up. Researched 2026-11-05, from source only. Nothing here has been run in a client.

Sources, pinned:

- **Forever:** Blizzard's UI at [`forever` 1.60.1.70790](https://github.com/Gethe/wow-ui-source/tree/eac30af597e5aaa43a60f6675ef5fdcea100375f), which is `## Interface: 16001`'s game. This branch exists and it's the best evidence we have.
- **Retail:** Blizzard's UI at [`live` 12.1.5.70783](https://github.com/Gethe/wow-ui-source/tree/297d7aaaa736f346b3e036f38ee088eaf7f8c07f).
- **Addons:** GitHub at the commits linked, and the local install. The installed ElvUI (v13.78) and WeakAuras (5.17.1) are interface 110002 builds from 2024, so every claim about them was rechecked against current upstream. DialogueUI has no repo I could find, so it's cited by local path.

How sure each claim is:

- **Source:** read in Blizzard's UI, its generated API docs, or an addon's code.
- **Wiki:** warcraft.wiki.gg, including blue posts it quotes.
- **Inferred:** my reasoning from those. Not stated anywhere.
- **Check:** only the client can settle it. See [Check in game](#check-in-game).

## Answer

The plan works, but #127's "3x" is wrong as a rendering rule, and that's the main change.

1. **Scale is the real problem, and snapping the band won't fix it.** 3 UI units is almost never a whole number of screen pixels: 4.22 at 1080p, 5.63 at 1440p. Nearest filtering then gives uneven pixels, and linear gives blur. The fix is one art pixel = a whole number of screen pixels, worked out at runtime. So "3x" becomes "about 3x", the band shows between about 250 and 375 art columns at full width, and the 300-pixel backdrop is too narrow.
2. **`NEAREST` is a real, documented filter mode, but I found nobody using it on visible art.** Blizzard never uses it. The addons that pass it use it on a plain white mask. It has to be set from Lua, since XML has no attribute for it. It's the first thing to test.
3. **Animation as planned is right.** Step `SetTexCoord` from one driver, like WeakAuras' stop-motion and Blizzard's own bonus roll spinner. Make the driver an `OnUpdate` on the Camp frame, since hiding the frame stops it for free. Use no `AnimationGroup` for the hop: the prototype's hop is a pose swap, not a slide.
4. **ElvUI changes textures that aren't its own.** Its current release lists interface 16001 and hooks the shared texture methods, turning pixel snapping off on every texture, including ours. The Camp can't rely on the default snapping.
5. **Tinting and TGA are confirmed, with one correction.** "Neutral" cloth must be white, not grey, because tinting multiplies. No restricted API is involved, and Forever's documented texture and animation API is byte-identical to retail's.

## 1. Filtering

**What `SetTexture` accepts.** `SetTexture(textureAsset, wrapModeHorizontal, wrapModeVertical, filterMode)`, all optional ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua#L604)). The generated docs type `filterMode` as a plain string and don't list values. The wiki gives `LINEAR` (default, bilinear), `TRILINEAR` (also samples mipmaps) and `NEAREST` ([Wiki](https://warcraft.wiki.gg/wiki/API:TextureBase_SetTexture)). The same page says the return value is always `true`, even for bad files or arguments, so it tells us nothing.

**Default.** `LINEAR` (Wiki). The Doom addon confirms what that means in practice: it widens its palette to 1024 pixels "to prevent texture bleeding" and samples inside each colour's span ([`frame.lua:55`](https://github.com/tna0y/wow-doom-within/blob/96a41b31db89f382f07ab2cd909984ee5f514b79/src/frame.lua#L55), [`:97`](https://github.com/tna0y/wow-doom-within/blob/96a41b31db89f382f07ab2cd909984ee5f514b79/src/frame.lua#L97)).

**Lua only.** `UI.xsd` has no filter attribute on `Texture`, only `snapToPixelGrid`, `texelSnappingBias` and the wrap modes ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_SharedXML/UI.xsd#L629-L655)).

**Nobody uses it on art.** `"NEAREST"` as a filter appears nowhere in Blizzard's Lua or XML on `forever` or `live`; Blizzard only ever passes `TRILINEAR`. The addons that do pass it use it on a white mask: [WeakAuras `AuraBar.lua:1172`](https://github.com/WeakAuras/WeakAuras2/blob/2837a63d8de281cbb3cb3b6c7d1f18df8aa31c93/WeakAuras/RegionTypes/AuraBar.lua#L1172) and AbstractFramework's flipbook mask. [Plumber](https://github.com/Peterodox/Plumber/blob/e822e0cdc0316220e6a0bfe7198ff221526de213/Modules/EventMap.lua#L426) has it commented out. So its visible result is a **Check**, not a known fact.

**Snapping is a different thing from filtering.** A Blizzard developer's description, as quoted on the wiki (I couldn't find the original post): with `snapToPixelGrid` "the texture's verts will be rounded to the nearest pixel during the rendering phase"; `texelSnappingBias` runs 0–1, "anything >0 implies snapToPixelGrid", and stronger bias selects a texel rather than blending, "a 'sharpening' sort of effect" ([Wiki](https://warcraft.wiki.gg/wiki/API:TextureBase_SetSnapToPixelGrid)).

- Snapping defaults to on. `UI.xsd` says `default="true"` ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_SharedXML/UI.xsd#L636)), and Blizzard's XML sets `snapToPixelGrid="false"` 258 times and `"true"` never. The API doc's `Default = false` is the argument's default, not the texture's. **Inferred** for textures made with `CreateTexture`; **Check**.
- Addons turn it off, for smooth art. Plumber calls the helper `DisableSharpening`, and WeakAuras does the same on [its textures](https://github.com/WeakAuras/WeakAuras2/blob/2837a63d8de281cbb3cb3b6c7d1f18df8aa31c93/WeakAuras/RegionTypes/AuraBar.lua#L1161-L1162). Pixel art wants the opposite, so copying that habit would be a mistake.
- Snapping doesn't replace `NEAREST`, and neither fixes a non-integer ratio. Rounded corners on a quad still stretch 4.2 pixels of art across it. **Inferred.**

**Does the filter survive?**

| Operation | Answer |
|---|---|
| `SetTexCoord` | Very likely. It takes only coordinates, and the filter is a `SetTexture` argument. **Inferred; Check.** |
| `SetVertexColor` | Same reasoning. **Inferred; Check.** |
| Atlases | `SetAtlas` has its own `filterMode` argument ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua#L368)), but addons can't register atlases (section 5). |
| `SetTexture` again, same file | A trap. Calls differing only in wrap mode were ignored ([WoWUIBugs #250](https://github.com/Stanzilla/WoWUIBugs/issues/250)), reported fixed in 11.1.5.59571, and WeakAuras has since dropped its workaround. Filter wasn't tested there. Set each texture's file and filter once. |

**Client settings.** I found no source saying Texture Resolution, Filtering or Render Scale affect UI textures. A TGA carries no mip chain, while almost every BLP surveyed does (section 5), so TGA with `NEAREST` should be the least exposed option. **Inferred; Check.**

## 2. UI scale

**The maths.** One screen pixel is `768 / physicalHeight` UI units at scale 1, divided by the region's effective scale. That's Blizzard's own [`PixelUtil.GetPixelToUIUnitFactor`](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_SharedXML/PixelUtil.lua#L3-L6), and BFF already has it as `screenPixel` in `UI/Skin.lua`.

**What #127's 3x really means.** Screen pixels per UI unit are `effectiveScale * height / 768`. The slider runs 0.65–1.15 ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_SettingsDefinitions_Shared/Graphics.lua#L931)), and with it off the wiki lists a default of 1.00 at 1080p and 0.64 at 1440p, noting that "might not be the whole story" ([Wiki](https://warcraft.wiki.gg/wiki/UI_scaling)). Rounding 3 units to whole pixels gives:

| Height | Scale | 3 units in pixels | Art pixel | In UI units | Art columns in 900 | Art rows in 120 |
|---|---|---|---|---|---|---|
| 768 | 1.00 | 3.00 | 3 px | 3.00 | 300 | 40 |
| 900 | 1.00 | 3.52 | 4 px | 3.41 | 264 | 35 |
| 900 | 0.71 | 2.50 | 2 px | 2.40 | 374 | 50 |
| 1080 | 1.00 | 4.22 | 4 px | 2.84 | 316 | 42 |
| 1080 | 0.71 | 3.00 | 3 px | 3.00 | 300 | 40 |
| 1200 | 1.00 | 4.69 | 5 px | 3.20 | 281 | 38 |
| 1440 | 0.64 | 3.60 | 4 px | 3.33 | 270 | 36 |
| 1440 | 1.00 | 5.63 | 6 px | 3.20 | 281 | 38 |
| 1440 | 0.53 (ElvUI) | 3.00 | 3 px | 3.00 | 300 | 40 |
| 2160 | 1.00 | 8.44 | 8 px | 2.84 | 316 | 42 |

At a raw 3x, only the exact-ratio rows are clean. Elsewhere, nearest filtering gives a mix of 4- and 5-pixel columns and linear gives blur. **Inferred**, from how sampling works.

**What pixel-perfect addons really do.** They don't fight per texture. They change the ratio or work in whole pixels:

- **ElvUI** sets `E.perfect = 768 / physicalHeight` and rescales `UIParent` itself ([`PixelPerfect.lua:97-100`](https://github.com/tukui-org/ElvUI/blob/afadbc32a8b6e037a485b9494dc10b26be139fc4/ElvUI/Game/Shared/General/PixelPerfect.lua#L97-L100)). BFF can't: that's the user's UI, not ours.
- **DialogueUI and Plumber** convert sizes with `pixelSize * (768/SCREEN_HEIGHT)/scale` ([Plumber `API.lua:1571`](https://github.com/Peterodox/Plumber/blob/e822e0cdc0316220e6a0bfe7198ff221526de213/API.lua#L1571-L1577), local `DialogueUI/API.lua:140`). DialogueUI redoes this on `UI_SCALE_CHANGED` and `DISPLAY_SIZE_CHANGED` (`API.lua:210-211`). This is the pattern to copy.
- **The wiki** recommends the same 768/height idea ([Wiki](https://warcraft.wiki.gg/wiki/UI_scaling)).

**`PixelUtil` has moved on.** `SetWidth`, `SetHeight`, `SetSize` and `SetPoint` are marked "DEPRECATED: Use SetRoundLayoutToNearestPixel instead" on both branches ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_SharedXML/PixelUtil.lua#L38)). `GetPixelToUIUnitFactor` and `GetNearestPixelSize` aren't. The native [`SetRoundLayoutToNearestPixel(enabled)`](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleScriptRegionAPIDocumentation.lua#L701) arrived in 12.1.5 ([Wiki](https://warcraft.wiki.gg/wiki/API:ScriptRegion_SetRoundLayoutToNearestPixel)) and is in Forever's docs. Retail's nameplates use it ([Source](https://github.com/Gethe/wow-ui-source/blob/297d7aaaa736f346b3e036f38ee088eaf7f8c07f/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua#L88)). I found no Lua caller on `forever`.

**ElvUI touches our textures.** ElvUI [v16.01](https://github.com/tukui-org/ElvUI/blob/afadbc32a8b6e037a485b9494dc10b26be139fc4/ElvUI/ElvUI.toc) lists `## Interface: 11509, 16001, ...`, so it targets Forever. It takes the shared metatable (`getmetatable(object).__index`), including the one for textures, and hooks `SetTexture`, `SetTexCoord` and `SetVertexColor` to call `SetSnapToPixelGrid(false)` and `SetTexelSnappingBias(0)` ([`Toolkit.lua:617-631`](https://github.com/tukui-org/ElvUI/blob/afadbc32a8b6e037a485b9494dc10b26be139fc4/ElvUI/Game/Shared/General/Toolkit.lua#L617-L631)). Every Camp sprite hits those hooks. Calling `SetSnapToPixelGrid(true)` clears its flag, and the next `SetTexCoord` turns snapping off again. So with ElvUI loaded, sprites land wherever the layout says, fractions included.

**Why position matters.** If every sprite's size and offset is a whole number of pixels from one origin, default snapping rounds them all the same way, whatever fraction the origin has. Without snapping, the origin itself must be on a whole pixel. **Inferred; Check.**

## 3. Animation

**FlipBook.** Created with `group:CreateAnimation("FlipBook")`; available since 10.0.0 ([Wiki](https://warcraft.wiki.gg/wiki/UIOBJECT_FlipBook)). The setters are identical on Forever and retail ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleAnimFlipBookAPIDocumentation.lua)).

- Blizzard uses it widely: 49 files on `forever`, such as the [rest loop](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_UnitFrame/Mainline/PlayerFrame.xml#L406-L408) and [LFG eye](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_LFGUtil/Mainline/LFGEye.xml#L49). Always atlas textures, always `flipBookFrameWidth="0"`.
- It works on Forever. `Shared\ActionButtonSpellAlerts.xml` holds FlipBooks and loads with [no game type restriction](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_ActionBar/Blizzard_ActionBar.toc#L19). **Inferred** from the TOC.
- It works on addon-shipped sheets. TRP3's dashboard cat is a 512×512 TGA, a 4×4 grid with only 10 frames used ([`Dashboard.xml`](https://github.com/Total-RP/Total-RP-3/blob/2c921b0b70adaca9fc7ce049ddf386b72d358cbf/totalRP3/Modules/Dashboard/Dashboard.xml#L57-L62)). Cell does it with a [PNG](https://github.com/enderneko/Cell/blob/2fbdca82e79d22d6ae4c8fb4e9ea2148aeaf0df7/Indicators/Supporter.lua#L152-L169). So a part-filled grid is how a power-of-two sheet copes with a frame count that doesn't divide it: 3 frames would be 1 row, 4 columns, 3 frames.
- Frames are spread evenly over `duration`, with no per-frame timing in the API.
- `SetFlipBookFrameWidth` has undocumented units. Eltruism sets 105×101 on a [512×1024 sheet](https://github.com/eltreum0/eltruism/blob/44869f0d062b67a0624a2f7ec1542083587a2b27/ElvUI_EltreumUI/Modules/Misc/Mail.lua#L24), and that doesn't fit an obvious reading. Avoid it.

**Known bugs.**

- `SetParent` on a frame with a FlipBook could crash the game ([WoWUIBugs #474](https://github.com/Stanzilla/WoWUIBugs/issues/474), closed). Eltruism [still works around it](https://github.com/eltreum0/eltruism/blob/44869f0d062b67a0624a2f7ec1542083587a2b27/ElvUI_EltreumUI/Modules/Misc/Mail.lua#L79); Cell reparents pooled flipbook frames, which suggests it's fixed.
- A hidden animation doesn't come back by itself ([WoWUIBugs #540](https://github.com/Stanzilla/WoWUIBugs/issues/540)). Blizzard's fix is manual: [`Stop` in `OnHide`, `Play` in `OnShow`](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.lua#L149-L159).

**Manual stepping.** Blizzard does this too: [`TextureUtil.AnimateTexCoords`](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_SharedXMLBase/TextureUtil.lua#L28) and the [bonus roll spinner](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua#L768-L773). WeakAuras' stop-motion never moved to FlipBook. It works out the frame from the clock, skips the call if nothing changed, then sets coordinates ([`StopMotion.lua:228`](https://github.com/WeakAuras/WeakAuras2/blob/2837a63d8de281cbb3cb3b6c7d1f18df8aa31c93/WeakAuras/BaseRegions/StopMotion.lua#L228), [`:71-84`](https://github.com/WeakAuras/WeakAuras2/blob/2837a63d8de281cbb3cb3b6c7d1f18df8aa31c93/WeakAuras/BaseRegions/StopMotion.lua#L71-L84)):

```lua
local newCurrentFrame = floor(timeSinceStart * (self.frameRate or 15))
if (newCurrentFrame == self.currentFrame) then return end
```

Its file name pattern also carries frame size and real file size ([`:59`](https://github.com/WeakAuras/WeakAuras2/blob/2837a63d8de281cbb3cb3b6c7d1f18df8aa31c93/WeakAuras/BaseRegions/StopMotion.lua#L59)), which is how it uses frames that don't fill a power-of-two file.

**`SetSpriteSheetCell(cell, numRows, numColumns, cellWidth, cellHeight)`** is a newer option, added in 12.0.0 and on Forever's docs ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua#L565)). Blizzard uses it for [raid target icons](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_UnitFrame/Mainline/TargetFrame.lua#L700). It's undocumented beyond the signature, and the Camp's sprites aren't one uniform grid, so plain `SetTexCoord` is simpler.

**Comparison for the Camp.**

| | FlipBook | `SetTexCoord` from `OnUpdate` |
|---|---|---|
| Works on both clients | Yes | Yes |
| Lua per tick | None | A few calls at 6 fps |
| Stops when hidden | Needs `OnHide`/`OnShow` handling | Free: `OnUpdate` is "blocked by hiding a frame or its parent" ([Wiki](https://warcraft.wiki.gg/wiki/UIHANDLER_OnUpdate)) |
| Fire, embers, z marks and hop on one clock | One group each | Yes |
| Uneven timing, positions in art pixels | No | Yes |
| Known use with `NEAREST` | None | None |

**Translation for the hop.** Fine for smooth motion, and Blizzard uses it everywhere (352 uses). It's the wrong tool here. It moves continuously, so a sprite drifts in single screen pixels between art pixels, which breaks the grid. It also needs both layers of a figure moved together. The prototype doesn't slide at all: for 700ms it draws a separate `HOP` sprite 2 art pixels higher ([`ui-personality.html`](https://github.com/Shtian/bff-wow/blob/prototype/ui-personality/prototypes/ui-personality.html)). That's a frame swap and an offset.

## 4. Tinting and layers

**`SetVertexColor`** multiplies each colour channel of the texture ([Wiki](https://warcraft.wiki.gg/wiki/API:Region_SetVertexColor)). So a white pixel becomes the class colour, 62% grey becomes 62% of it, and nothing gets brighter than the texture.

**Authoring the cloth layer.** The prototype's cloth has two tones: `C`, the class colour, and `D = shade(C, .62)`. Multiplying gives exactly that from a texture holding only white and `#9E9E9E` (0.62 × 255 = 158). The prototype's fallback `#888888` must not be copied into the sheet, or every class comes out at about half brightness. Priest stays white and grey, as in the prototype.

**Layers.** Draw layers are `BACKGROUND`, `BORDER`, `ARTWORK`, `OVERLAY`, `HIGHLIGHT`; sublevels run −8 to 7 ([Wiki](https://warcraft.wiki.gg/wiki/API:Frame_CreateTexture)). Core guarantees figures don't overlap, so cloth at `ARTWORK` 0 and skin and outline at `ARTWORK` 1 is enough. Both textures must share one rectangle and cell size, so they can never round apart.

**Not needed:**

- **`SetDesaturated`:** no use, since the art is already neutral.
- **Masks:** `CreateMaskTexture`, as in the [wiki example](https://warcraft.wiki.gg/wiki/API:Frame_CreateMaskTexture), is for shapes. Clipping is simpler for a rectangle.
- **`SetBlendMode`:** the default `BLEND` handles alpha ([Wiki](https://warcraft.wiki.gg/wiki/UITYPE_AlphaMode)). `ADD` is an option for embers if they should glow, as an art choice.

## 5. Asset formats

Survey of every image under the local `AddOns` folder, reading file headers:

| | Count | Notes |
|---|---|---|
| TGA | 1,132 by name | 903 RLE (type 10), 224 uncompressed (type 2), 5 are really BLP |
| TGA depth | 1,096 at 32-bit, 31 at 24-bit | |
| TGA origin | 602 top-left, 530 bottom-left | Both ship. BFF's own icon is bottom-left, uncompressed |
| TGA largest edge | 2048 | No limit found in any source |
| Not power-of-two | 2 TGAs (`waheart.tga` 80×80, a Details icon 256×130); no real BLP or PNG | 619 BLP and 267 PNG all power-of-two |
| BLP | 619 by header | 615 with mipmaps; 56 more `.blp` files are really RLE TGAs |
| PNG | 267 | DialogueUI 203, Plater 28 |

**Rules.**

- Power-of-two edges, not necessarily square; 32-bit for alpha ([Wiki](https://warcraft.wiki.gg/wiki/TGA_files)). RLE is supported ([Wiki](https://warcraft.wiki.gg/wiki/API:TextureBase_SetTexture)), and the survey agrees. Two non-power-of-two files ship, but I can't tell if they render, so they're no proof.
- **Path:** `Interface\AddOns\BFF\Media\Name`, no extension needed for TGA or BLP. PNG must include `.png` (Wiki). Case doesn't seem to matter: TRP3's XML says `resources`, its folder is `Resources`. Keep it exact anyway.
- **Mismatched extensions load:** 61 misnamed files ship in Details and Plater, so the client may look at the content. **Inferred.** Don't rely on it.
- **Failure is silent.** `SetTexture` returns `true` regardless (Wiki). Malformed BLPs rendered as green squares in [WoWUIBugs #773](https://github.com/Stanzilla/WoWUIBugs/issues/773), where the advice was to fix the file or "ship PNG/TGA".
- **New files:** "the WoW client only loads those files that existed when the client was first opened", so a new texture needs a client restart, while changed files don't ([wowprogramming.com](https://wowprogramming.com/docs/widgets/Texture.html)). That page is old. **Check.**
- **Loading is asynchronous.** A texture's size reads 0 until `IsObjectLoaded` (Wiki). Set sheets when the panel is built, not on first use.

**TGA or BLP.** TGA. BLP's usual DXT compression is lossy and would damage flat pixel colours. **Inferred** from how DXT works. TGA also has the fewest tools in the way: BFF already ships one.

**Atlases.** Addons can't add to the game's atlas table. `C_Texture` only reads it: `GetAtlasInfo`, `GetAtlasElements` and so on, with no register call ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/TextureUtilsDocumentation.lua)). The working pattern is a Lua table shaped like `AtlasInfo`, as in DetailsFramework ([`picture.lua:505`](https://github.com/Tercioo/Plater-Nameplates/blob/8aebe3c2f853f44ece2a9a0a27710b1eeb253650/libs/DF/picture.lua#L505)): `SetTexture(file, ...)` then `SetTexCoord(...)`.

## 6. Performance

- **Texture count isn't a concern.** WowFC runs 61,440 one-pixel textures with a [row-per-frame split](https://github.com/huchang47/WowFC/blob/fde07b2f8baf8ad4e72059b2de548ca4e1065ac9/WowFC/UltraRenderer.lua#L5-L7), and Doom runs 64,000, noting "[without splitting it into parts WoW crashes](https://github.com/tna0y/wow-doom-within/blob/96a41b31db89f382f07ab2cd909984ee5f514b79/src/frame.lua#L74)". The Camp needs roughly 50–80 textures. **Inferred** count.
- **Skip unchanged work.** WeakAuras, WowFC and Doom all only touch a texture when its value changed.
- **`OnUpdate` against a ticker.** `OnUpdate` fires every drawn frame, so it needs a throttle ([Wiki](https://warcraft.wiki.gg/wiki/UIHANDLER_OnUpdate)); here that's one clock read and a compare. A `C_Timer.NewTicker` fires less often but runs while hidden unless cancelled. BFF's panel, toasts and Together tab already use `OnUpdate`.
- **Hidden frames.** `OnUpdate` stops. `AnimationGroup`s need the handling in section 3.

## 7. Midnight restrictions and Forever

**Nothing here touches secret values, as long as the inputs are plain.** `SetTexture`, `SetTexCoord`, `SetVertexColor` and `SetDesaturated` are `AllowedWhenTainted`. The others are `AllowedWhenUntainted`, which only bites if a secret value is passed in. The Camp's inputs are Core's own data and `RAID_CLASS_COLORS`. If a secret ever reached `SetVertexColor`, it would add the `VertexColor` secret aspect to the region ([Source](https://github.com/Gethe/wow-ui-source/blob/eac30af597e5aaa43a60f6675ef5fdcea100375f/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleRegionAPIDocumentation.lua#L191-L194)), so don't feed it live unit data.

**Combat lockdown.** `SetPoint`, `SetSize`, `SetScale`, `SetIgnoreParentScale` and `SetRoundLayoutToNearestPixel` are `IsProtectedFunction`. The wiki's reading is a restriction on *protected objects* from insecure code in combat ([Wiki](https://warcraft.wiki.gg/wiki/API:Region_SetIgnoreParentScale)). BFF's panel is plain `CreateFrame`, so a hop or a relayout in combat should be fine. **Inferred; Check.** Keep the Camp's frames away from anything secure.

**Forever against retail.** Twelve documentation files are byte-identical between `forever` and `live`: `SimpleTextureBase`, `SimpleTexture`, `SimpleMaskTexture`, `SimpleRegion`, `SimpleAnimFlipBook`, `SimpleAnimGroup`, `SimpleAnim`, `SimpleAnimTranslation`, `SimpleAnimAlpha`, `Screen`, `UITimer` and `TextureUtils`. `PixelUtil.lua` and `TextureUtil.lua` too. Forever's extras are unrelated: input synthesis methods and a `FrameStrata` secret aspect. `UI.xsd` differs only by additions on Forever. **This shows the API matches, not the renderer.** I found nothing on whether the Forever client samples or snaps differently, so that's a **Check**.

## 8. Prior art

I found no addon that draws filtered pixel art from a sheet with `NEAREST`. The Camp would be the first one I can point to. GitHub code search was rate-limited part way through, and CurseForge-only addons weren't read, so this isn't proof none exist. No Tetris or tamagotchi addon turned up.

| Addon | What it draws | Technique |
|---|---|---|
| [WowFC](https://github.com/huchang47/WowFC/blob/fde07b2f8baf8ad4e72059b2de548ca4e1065ac9/WowFC/UltraRenderer.lua#L1-L16) | NES emulator, 256×240 | One texture per pixel, `SetColorTexture`, dirty check. A [second renderer](https://github.com/huchang47/WowFC/blob/fde07b2f8baf8ad4e72059b2de548ca4e1065ac9/WowFC/PaletteRenderer.lua#L1-L15) recolours by `SetTexCoord` on a shared palette. `OnUpdate` driver, because `C_Timer` tops out at 60 Hz by its [author's note](https://github.com/huchang47/WowFC/blob/fde07b2f8baf8ad4e72059b2de548ca4e1065ac9/WowFC/WowFC.lua#L717-L719). |
| [Doom Within](https://github.com/tna0y/wow-doom-within/blob/96a41b31db89f382f07ab2cd909984ee5f514b79/src/frame.lua#L49-L60) | Doom | A texture per pixel on a shared palette, sampled inside each texel to dodge bilinear bleed. |
| [TRP3 dashboard](https://github.com/Total-RP/Total-RP-3/blob/2c921b0b70adaca9fc7ce049ddf386b72d358cbf/totalRP3/Modules/Dashboard/Dashboard.xml#L20-L62) | Animated cat | Two TGA flipbooks in XML, swapped by alpha, `nounload="true"`. Closest to a sprite. |
| [Cell](https://github.com/enderneko/Cell/blob/2fbdca82e79d22d6ae4c8fb4e9ea2148aeaf0df7/Indicators/Supporter.lua#L146-L176) | Supporter effects | PNG flipbook, `ag:Play()` in `OnShow`, frames pooled. |
| [WeakAuras](https://github.com/WeakAuras/WeakAuras2/blob/2837a63d8de281cbb3cb3b6c7d1f18df8aa31c93/WeakAuras/BaseRegions/StopMotion.lua#L71-L84) | Stop-motion regions | Manual `SetTexCoord` from a shared tick; one frame drives every region. |
| [EmreSnake](https://github.com/emredogan1904-lang/EmreSnake/blob/4ccfa278a75c6516237090ff779889ffe6cb5f21/Snake.lua#L244), [GameRoom](https://github.com/Racksoup/GameRoom/blob/70c93cd1fe4fe68819c326cfec6ad9a0d6f8f239/snake.lua#L45) | Snake | Solid `SetColorTexture` cells on a grid, ticker or `OnUpdate`. No art files. |
| [GoblinGames](https://github.com/ZifixSempi/GoblinGames/blob/89b5740a9d8492c0da474a07fa0605813ffcefa0/GoblinGames/UI/CardWidget.lua#L24) | Card games | TGA in a power-of-two file, cropped: `CROP = 183 / 256`. |
| ElvUI, DialogueUI, Plumber | Pixel-exact UI | Section 2. Whole-pixel maths; snapping off, since their art is smooth. |
| Details!, Plater | Icons | Lua atlas tables, `TRILINEAR` for smooth scaling. |

## Design consequences

Corrections to #127 first, then the recommendation for each area.

**Corrections**

1. **"Pixel art at 3x" becomes a target, not a rule.** Work out a whole-pixel size per art pixel:

   ```lua
   local function artUnit(frame, target) -- target: 3 in the Camp, 2 on Roster rows
     local onePixel = PixelUtil.GetPixelToUIUnitFactor() / frame:GetEffectiveScale()
     local pixels = math.max(1, math.floor(target / onePixel + 0.5))
     return pixels * onePixel
   end
   ```

   `UI/Skin.lua`'s `screenPixel` already has the first line. Sizes and offsets are then `artPixels * artUnit(...)`. Recalculate on `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED` and panel resize.
2. **The backdrop is too small.** 300×40 art pixels covers only some configurations; the worst case needs about 375×50. Author about **384×52 inside a 512×64 TGA**. The power-of-two file is that size anyway.
3. **`camp(width)` should take art columns, not UI width.** Only UI knows the art unit, so it passes `floor(bandWidth / unit)`. Core stays free of scale. `camp_spec`'s width sweep has to cover about **128 to 375 columns**, not 153 to 300: the panel runs 460–900 units, and an art unit can land anywhere from 2.4 to 3.6 UI units. The short band can drop to about 22 art rows, so check the scene still fits.
4. **Replace "cropped by texture coordinates" with clipping.** A centred crop lands on fractions of a texel at most widths, shifting the backdrop off the sprites' grid. Instead use a fixed-size backdrop texture, anchored on a whole art pixel, in a band with `SetClipsChildren(true)`, which `UI/TogetherTab.lua` already uses. The short band's bottom alignment comes free. Clipping also enables render layer flattening ([Wiki](https://warcraft.wiki.gg/wiki/API:Frame_SetClipsChildren)), so check labels still draw right.
5. **"If the sprites smear, snapping the band … is the likely fix" is wrong as a first fix.** Smearing or uneven pixels come from the ratio, so correction 1 is the fix. Band snapping is a second, smaller step that keeps the origin on the grid.
6. **"Neutral" cloth means white and `#9E9E9E`,** not mid-grey.
7. **The hop is a pose swap,** as the prototype does it, not a motion. 0.7s still holds.

**Recommendations**

- **Filtering:** `SetTexture(path, "CLAMP", "CLAMP", "NEAREST")` in Lua, once per texture, on every Camp texture. Leave snapping at its default, and don't copy the `SetSnapToPixelGrid(false)` habit. Leave a 1-pixel transparent gutter between cells, so an off-by-a-rounding sample can't show a neighbour.
- **Scale:** `artUnit` as above. Round the band's origin with `band:SetRoundLayoutToNearestPixel(true)` where it exists, and don't rely on default snapping, because of ElvUI. Keep name labels in UI units. Avoid `PixelUtil.SetSize` and friends. Don't `SetScale` the Camp, since that would rescale its fonts too.
- **Animation:** one `OnUpdate` on the Camp frame reads the clock, computes the tick and returns early if unchanged. On a new tick it steps fire, embers and z marks by `SetTexCoord`, and it advances a hop if there is one. This meets "one timer that only runs while the Camp is shown" with no cancel logic. Embers and z marks move in whole art pixels. Use no FlipBook, no Translation.
- **Tinting:** two textures per figure with the same rectangle: cloth tinted by `RAID_CLASS_COLORS` at `ARTWORK` 0, skin and outline untinted at `ARTWORK` 1. No masks, no desaturation. Confirmed as #127 has it.
- **Format:** 32-bit TGA, power-of-two, in `Media`; uncompressed or RLE, both ship. Confirmed. Keep sprite rectangles in one Lua table, `AtlasInfo`-shaped. Add every sheet's file early, since a new file likely means a client restart.
- **Roster rows and toasts:** use `artUnit(frame, 2)`. Any toast that slides will drift between pixels while moving, so check it.
- **Restrictions:** none needed. #127's "keeps working in lockdown" holds for rendering, as far as source shows.

## Check in game

On retail now, then repeat 1–5 on Forever when possible. A throwaway test sheet with single-pixel checkers and a 1-pixel grid shows all of these at once. Take screenshots and zoom in.

1. **`NEAREST` works on a TGA with `SetTexCoord`:** no blending between neighbouring texels, on retail and on Forever. Everything else depends on this.
2. **Snap defaults:** print `IsSnappingToPixelGrid()` and `GetTexelSnappingBias()` on a `CreateTexture` texture. Confirms section 1.
3. **`artUnit` gives even pixels:** every column the same width at UI scale off, 0.71, 0.9 and 1.15, in a window, and on the Mac's Retina display (compare `GetPhysicalScreenSize` and `GetScreenDPIScale`).
4. **Origin:** drag the panel to odd positions and resize it. Does the grid stay even, with and without `SetRoundLayoutToNearestPixel`?
5. **Tint and filter together:** `SetVertexColor` on the `NEAREST` texture stays crisp, and white and `#9E9E9E` match the prototype's colours. Compare against real gamma, per #127's note.
6. **ElvUI:** with ElvUI on, confirm snapping is off on Camp textures and the grid still holds. If not, fall back to setting `tex.PixelSnapDisabled = true` after `SetSnapToPixelGrid(true)`, which stops its hooks. Treat that as a workaround tied to ElvUI's internals.
7. **Clipping:** `SetClipsChildren` crops sprites without resampling and leaves labels intact.
8. **Client settings:** Texture Resolution low, Render Scale below 100%. Does the art change?
9. **Assets:** a TGA with top-left and one with bottom-left origin, to learn the exporter's right setting, then what a missing file looks like, and whether a new file needs a restart.
10. **Combat and instances:** the Camp animates, hops and resizes during combat and a boss encounter, with no taint or `ADDON_ACTION_BLOCKED`.
11. **Cost:** with the panel closed, confirm no BFF CPU from the Camp in the addon performance readout.
