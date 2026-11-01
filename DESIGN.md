---
name: BFF – Best Friends in Forever
description: A warm, quiet record of a friend group's adventures, kept in a dark in-game window.
colors:
  ember-gold: "#ffd14a"
  ember-gold-deep: "#f0a21c"
  brand-teal: "#3fd6e0"
  night-window: "#0e0d14"
  header-plate: "#1a1821"
  raised-plate: "#1b1a23"
  brand-navy: "#0b1a4a"
  ash-text: "#e8e6e3"
  smoke-muted: "#adabb8"
  dusk-dim: "#8c8a99"
  hairline: "rgba(255,255,255,0.07)"
  border: "rgba(255,255,255,0.10)"
  hover-wash: "rgba(255,255,255,0.05)"
  bar-fill: "rgba(255,255,255,0.30)"
  bar-track: "rgba(255,255,255,0.08)"
  online-green: "#70e370"
  offline-grey: "#54525e"
  feed-death: "#f2665c"
  feed-crew: "#66bfff"
  feed-spare: "#c799ff"
  feed-left: "#9999a8"
  on-gold: "#1a1400"
typography:
  window-title:
    fontFamily: "Friz Quadrata (FRIZQT__.TTF)"
    fontSize: "13px"
  heading:
    fontFamily: "Friz Quadrata (FRIZQT__.TTF)"
    fontSize: "12px"
  label:
    fontFamily: "Friz Quadrata (FRIZQT__.TTF)"
    fontSize: "10px"
  body:
    fontFamily: "Arial Narrow (ARIALN.TTF)"
    fontSize: "15px"
  text:
    fontFamily: "Arial Narrow (ARIALN.TTF)"
    fontSize: "14px"
  small:
    fontFamily: "Arial Narrow (ARIALN.TTF)"
    fontSize: "12px"
  tiny:
    fontFamily: "Arial Narrow (ARIALN.TTF)"
    fontSize: "11px"
  brand-display:
    fontFamily: "Cinzel, serif"
    fontSize: "104px"
    fontWeight: 600
    lineHeight: 1.06
  brand-title:
    fontFamily: "Cinzel, serif"
    fontSize: "96px"
    fontWeight: 600
    lineHeight: 1.06
  brand-banner-title:
    fontFamily: "Cinzel, serif"
    fontSize: "84px"
    fontWeight: 600
    lineHeight: 1.06
  brand-numeral:
    fontFamily: "Cinzel, serif"
    fontSize: "80px"
    fontWeight: 600
    lineHeight: 1
  brand-step:
    fontFamily: "Archivo Narrow, Arial Narrow, sans-serif"
    fontSize: "40px"
    fontWeight: 400
    lineHeight: 1.3
  brand-caption:
    fontFamily: "Archivo Narrow, Arial Narrow, sans-serif"
    fontSize: "34px"
    fontWeight: 400
    lineHeight: 1.38
  brand-banner-caption:
    fontFamily: "Archivo Narrow, Arial Narrow, sans-serif"
    fontSize: "32px"
    fontWeight: 400
    lineHeight: 1.38
  brand-lockup:
    fontFamily: "Cinzel, serif"
    fontSize: "26px"
    fontWeight: 600
    letterSpacing: "0.12em"
rounded:
  none: "0px"
  chip-step: "2px"
  brand-frame: "10px"
  brand-icon: "22%"
spacing:
  gap: "6px"
  inset: "12px"
  inset-popup: "14px"
  header: "30px"
  nav-row: "30px"
  roster-row: "44px"
  feed-entry: "38px"
  goal-row: "84px"
  section-top: "12px"
components:
  button-primary:
    backgroundColor: "{colors.ember-gold}"
    textColor: "{colors.on-gold}"
    typography: "{typography.text}"
    rounded: "{rounded.none}"
    height: "24px"
    width: "96px"
  button-secondary:
    backgroundColor: "rgba(255,255,255,0.06)"
    textColor: "{colors.ash-text}"
    typography: "{typography.text}"
    rounded: "{rounded.none}"
    height: "24px"
    width: "96px"
  button-small:
    backgroundColor: "rgba(255,255,255,0.06)"
    textColor: "{colors.ash-text}"
    typography: "{typography.small}"
    rounded: "{rounded.none}"
    height: "20px"
  button-disabled:
    backgroundColor: "rgba(255,255,255,0.06)"
    textColor: "{colors.dusk-dim}"
    typography: "{typography.text}"
    rounded: "{rounded.none}"
  progress-bar:
    backgroundColor: "{colors.bar-track}"
    textColor: "{colors.bar-fill}"
    rounded: "{rounded.none}"
    height: "6px"
  section-label:
    textColor: "{colors.dusk-dim}"
    typography: "{typography.label}"
  window:
    backgroundColor: "{colors.night-window}"
    textColor: "{colors.ash-text}"
    rounded: "{rounded.none}"
  window-header:
    backgroundColor: "{colors.header-plate}"
    textColor: "{colors.ember-gold}"
    typography: "{typography.window-title}"
    height: "{spacing.header}"
  nav-item:
    textColor: "{colors.smoke-muted}"
    typography: "{typography.text}"
    height: "{spacing.nav-row}"
  nav-item-selected:
    backgroundColor: "rgba(255,255,255,0.08)"
    textColor: "{colors.ash-text}"
    rounded: "{rounded.chip-step}"
  edit-box:
    backgroundColor: "rgba(0,0,0,0.35)"
    textColor: "{colors.ash-text}"
    typography: "{typography.text}"
    padding: "0 8px"
    height: "24px"
  badge:
    backgroundColor: "rgba(255,255,255,0.08)"
    textColor: "{colors.ash-text}"
    typography: "{typography.small}"
    height: "14px"
  badge-unseen:
    backgroundColor: "{colors.ember-gold}"
    textColor: "{colors.on-gold}"
    typography: "{typography.tiny}"
    height: "14px"
  toast:
    backgroundColor: "{colors.night-window}"
    textColor: "{colors.ash-text}"
    width: "300px"
    height: "40px"
  brand-frame:
    backgroundColor: "{colors.night-window}"
    rounded: "{rounded.brand-frame}"
---

# Design System: BFF – Best Friends in Forever

## Overview

**Creative North Star: "The Campfire Ledger"**

BFF is the record a group of friends keeps by the fire: who went where, who dinged, who died, who left a bag of loot for the others. The window is dark and calm so it sits quietly over the game world. Gold marks the moments worth noticing: a title, a highlight in the Feed, the one action that matters. Everything else is ash and smoke greys on near-black.

The system has two registers. **In the game** it's a ledger: flat, dense and legible at 10–15px, built from solid colour textures and 1px hairlines, so it never depends on Blizzard's frame templates. **On brand surfaces** (the CurseForge gallery, README banner, docs) the same palette sits over the game's own scenery. Teal joins gold as a thin accent, taken from the icon's second ring, and depth comes from the screenshot behind and a soft shadow under each frame.

BFF has its own flat skin. It deliberately rejects Blizzard's parchment, stone frames and ornate gilded borders.

**Key Characteristics:**
- Near-black windows (97% opaque) over the game, with 1px white hairlines at 7–10% for structure.
- Ember Gold is the only accent in the game, and it means news. Gold and teal appear together only on brand surfaces and inside the icon.
- Friz Quadrata names things (titles, headings, labels) and Arial Narrow carries everything else in the game. Cinzel and Archivo Narrow stand in for them on the web.
- Square corners in the game; rounding is faked with stepped pixels only where a chip needs it.
- Full-colour game icons with a faded 1px edge in their kind's colour carry the meaning of each Feed entry.

## Colors

A night palette: one warm accent glowing against cool, slightly violet near-blacks, plus small semantic colours for kinds of news.

### Primary
- **Ember Gold** (ember-gold): window titles; news text (the Feed's max level, joined and goal entries, toasts for them, While you were away's goal lines and "joined" tag); a goal bar once complete; "can play"; the primary button; unseen-count badges; checkbox ticks; and the Play times heatmap, where it's a scale rather than news. On brand surfaces it's the solid title colour and the numerals of a how-to; **Ember Gold Deep** (ember-gold-deep) is the gold half of the braid divider.

### Secondary
- **Brand Teal** (brand-teal): the icon's second ring. On brand surfaces: the teal half of the braid divider and of a frame's top line, and a faint light on slides without scenery. In the addon it appears only inside the icon itself (the minimap button and the game's addon list), never as a UI colour.

### Neutral
- **Night Window** (night-window): every window's background, at 97% opacity in the game (toasts 88%). At 95%, bright world text read through a panel's empty space.
- **Header Plate** (header-plate): the title bar strip.
- **Raised Plate** (raised-plate): surfaces that sit a step above the window.
- **Brand Navy** (brand-navy): the icon's background, and the top of brand-surface gradients.
- **Ash Text** (ash-text): body text.
- **Smoke Muted** (smoke-muted): secondary text, the Character line under a Member, headerRight labels, unselected navigation.
- **Dusk Dim** (dusk-dim): tertiary text: section labels, deaths counts, tiny captions.
- **Hairline** (hairline) and **Border** (border): dividers and 1px frame edges. White at low alpha, so they work on any plate.
- **Bar Fill** (bar-fill) on **Bar Track** (bar-track): every progress bar (Roster XP, While you were away levels, open Crew goals). Neutral, so colour on a bar means something.

### Semantic
- **Online Green** (online-green): online dots and map-pin rings, ding edges, levels gained (the bar's jump, "+N" and "new"). **Offline Grey** (offline-grey) for offline.
- Feed kind edges: **feed-death** for deaths, **feed-crew** for new Characters and joining, **feed-spare** for Spares, **feed-left** for leaving.
- Class colours come from the game (`RAID_CLASS_COLORS`) for Character names and map-pin dots. Don't redefine them.

### Named Rules
**The One Ember Rule.** In the game, gold is the only accent. If everything glows, nothing happened. A window shows gold on its title, on what is genuinely news, and on at most one primary action. Progress, status and your own name are not news: open bars are neutral, "You" is Ash, a given Reaction has no gold edge, leaving is said in grey, a toast's timer line is faint, and a disabled button is never faded gold. The heatmap is the one place gold is a scale.

**The Two Rings Rule.** Gold and teal appear together only where the icon does: brand surfaces, and the icon itself where the game shows it. The addon never uses teal as a UI colour.

## Typography

**Display Font:** Friz Quadrata in the game; Cinzel on the web (with serif)
**Body Font:** Arial Narrow in the game; Archivo Narrow on the web (with Arial Narrow, sans-serif)

**Character:** A chiselled, slightly old-world serif for names of things, over a compact narrow sans that fits a lot of text into a 460px window without feeling cramped.

### Hierarchy
- **Window title** (Friz, 13px, Ember Gold): window and popup titles only.
- **Heading** (Friz, 12px, Ash Text): names of things inside a window: Crew goal names, an empty state's line ("Nothing yet").
- **Label** (Friz, 10px, Dusk Dim, in capitals): section labels (CREW, FROM THE CREW, YOURS, YOUR CREW NOTICED), Feed day labels (TODAY), column headings (LEVEL, GAINED) and setup labels (DISPLAY NAME, START A CREW). The strings are written in capitals; the game can't add letter spacing, and Friz holds capitals at 10px where Arial Narrow crowds.
- **Body** (Arial Narrow, 15px): Member names and primary row text.
- **Text** (Arial Narrow, 14px): default UI text, buttons, inputs, sidebar tabs.
- **Small** (Arial Narrow, 12px): Character lines, checkbox labels, header-right status, level badges, small buttons, intro and helper lines.
- **Tiny** (Arial Narrow, 11px): badge text ("NEW", unseen counts, the minimap count) and chart captions (heatmap hours and legend). Nothing smaller ships.
The gallery has its own scale, sized for 1920×1080 images that are also seen as roughly 300px-wide thumbnails on CurseForge:
- **Brand display** (Cinzel 600, 104px, 1.06, solid Ember Gold): the hero's title.
- **Brand title** (Cinzel 600, 96px): every other slide's title, 2–4 words, so it still reads in a thumbnail. Solid Ember Gold with a soft offset shadow for the scenery behind; never a gradient. 84px on the banner.
- **Brand caption** (Archivo Narrow, 34px, 1.38, Smoke Muted, at most 30ch): one sentence under a title. It's for the full-size view; the title alone has to carry the thumbnail. 32px on the banner.
- **Brand step** (Archivo Narrow, 40px) beside a **brand numeral** (Cinzel 600, 80px, Ember Gold): a numbered how-to. Chat commands in a step are Archivo Narrow 600 in Ember Gold, not a monospace.
- **Lockup** (Cinzel 600, 26px, 0.12em): "BFF" beside a 56px icon, on the hero only.
- No label above a title: the title names the feature itself.

### Named Rules
**The Two Faces Rule.** One serif to name things (titles, headings, labels), one narrow sans for everything else. No third family.

## Layout

The in-game windows are fixed-size and movable. The panel is 460×380, with a 124px sidebar of 30px tabs and the content to its right. Its height never changes between tabs, and long lists scroll inside it. Content is inset 12px (14px in the While you were away popup, which is 400 wide). Rows follow a steady rhythm: 44px Member rows with 20px alt rows under them, 38px Feed entries, 26px day and section headings, 84px Crew goal rows, and Play times cells 11px wide by 18px tall. In While you were away, each section starts 12px below what's above it, its label takes 16px and each line 20px, so groups sit about 22px apart and lines within them about 6px. Tabs are top-aligned. An empty view is never a lone line in a corner: its content is composed and centred (see Empty state). Toasts are 300×40 and stack 6px apart, up or down from a movable anchor that starts 160px from the top of the screen.

Brand images are 1920×1080, plus a 1600×520 banner. Split layouts put a 640px text column on one side, an 80px gap and 110–120px outer margins, and the screenshot column (`minmax(0, 1fr)`, 880px high) on the other side; the side alternates from slide to slide. Frames are measured into their column, so a wide shot can't push the copy, and never enlarged past 1.4x, so game text stays sharp. A second shot (a toast) sits below the first on the side away from the copy, overlapping only its bottom 28px. Only the hero carries the name and icon, small, top left: CurseForge already shows them beside the gallery. The last slide is a numbered how-to for starting a crew.

## Elevation & Depth

**In the game, depth is tonal, never shadowed.** Layers step from the transparent world to Night Window, then Header Plate or Raised Plate, then white washes (5–8%) for hover and selection. Structure comes from 1px hairlines. The only "lift" is the additive white highlight on hover.

**On brand surfaces, depth comes from the world.** The slide's own screenshot sits behind as scenery, only lightly softened (8px blur) so it still reads as a place, with Night Window falling over the text side. Slides without a screenshot (banner, how-to) use the navy-to-black gradient with a faint gold and teal light. A fine grain stops gradients banding. Screenshot frames sit on a soft offset shadow, with no mat, ring or glow.

### Shadow Vocabulary
- **Frame lift** (`0 0 0 1px rgba(255,255,255,.14), 0 4px 12px rgba(0,0,0,.35), 0 28px 64px rgba(0,0,0,.5)`): screenshot frames on brand images.
- **Mark lift** (`0 0 0 1px rgba(255,255,255,.15), 0 16px 48px rgba(0,0,0,.55)`): the icon on the banner (smaller on the hero lockup).
- **Title lift** (`text-shadow: 0 2px 10px rgba(14,13,20,.6)`): brand titles over scenery.

### Named Rules
**The Flat Ledger Rule.** Nothing in the addon casts a shadow. If something needs to stand out, give it a lighter plate or a gold edge.

## Shapes

Square in the game. Textures have no corner radius, so windows, buttons, inputs and pictures are hard-edged rectangles framed by 1px lines. A few places want softness: the selected-tab chip steps its corners in by 2px of single-pixel rows. Circles appear only through the game's portrait mask, for online dots and map pins (a class-coloured dot in a 3px ring, green while online, with a 1px Night Window keyline outside it so it reads on a bright map). Game icons are cropped inside their bevel (7–8% from each side) and given a faded 1px edge in their kind's colour.

Brand surfaces soften slightly: screenshot frames have a 10px radius, and the icon a radius of about 22% of its size.

## Components

Quiet and flat. Components are faint fills and hairlines, so the content and the gold moments lead.

### Buttons
- **Shape:** square, 96×24 by default.
- **Primary:** Ember Gold fill with near-black text (on-gold). One per window at most.
- **Secondary:** a 6% white fill with a 1px 10% white border, Ash Text.
- **Small:** the secondary plate at 20px high with Small text, for buttons inside rows and headings and for pickers that open a menu (Sort, Show, Withdraw). Window actions stay 24px.
- **Disabled:** primary or secondary, the secondary plate with Dusk Dim text and no hover. Never faded gold, which reads as a second primary.
- **Hover:** an additive white wash: 18% on primary, 6% on secondary.
- **Close:** a 22px square with a desaturated grey X and a 5% hover wash.

### Chips
- **Navigation chip:** the selected tab gets an 8% white chip and the hovered one a 4% chip, inset 6px×2px with 2px stepped corners.
- **Badge:** a 14px-high plate at 8% white with Small text, for levels. At least as wide as it is tall, and hidden when there's no value (no "-"). Unseen counts on tabs and "NEW" on Feed entries use a gold plate with near-black Tiny text. The minimap button's online count sits on a Night Window plate with Ash Tiny text, off the icon's rings.

### Cards / Containers
- **Window:** Night Window at 95%, 1px Border all round, a 30px Header Plate with a Hairline under it, a gold Friz title 12px in, and close and status on the right. Movable, closes on Escape.
- **Rows:** separated by top Hairlines, no backgrounds; hover gets a 5% wash. Your own Roster row has a 5% gold wash. No coloured side stripes on rows.

### Section label
A Label in capitals at the left, with a Hairline running from it to the right edge or to whatever sits at the right (a count, a small button). Used for every section and for the Feed's day labels, which keep an opaque Night Window back so the timeline's line stops behind them. No boxed chips for labels.

### Progress bar
Bar Fill on Bar Track, square. 6px on Crew goals, 4px in While you were away, 2px for Roster XP. Colour replaces the fill only when it means something: green for levels gained, Ember Gold for a completed goal.

### Inputs / Fields
- **Edit box:** 24px high, black at 35% with a 1px Border, 8px text inset.
- **Checkbox:** a 14px square at 4% white with a 25% white border, an Ember Gold tick inset 3px, and a Small Smoke Muted label clickable to its right.

### Navigation
- **Sidebar tabs:** 30px rows in a 124px sidebar at 25% black. Text labels only, Smoke Muted, or Ash Text on the selected tab's chip. The Feed and Spares tabs show a gold unseen-count badge at their right when another tab is open.

### Feed picture (signature)
A square full-colour game icon on an opaque Night Window back, with a 1px edge in its kind's colour at 55% alpha: green for dings, gold for max level and goals, red for deaths, blue for Crew news, violet for Spares, grey for leaving. Used on the Feed's timeline, where the line runs through the pictures' centres, and on toasts.

### Reaction button
A small square (18–20px) holding the Reaction's icon, desaturated at 55% alpha until clicked. Once given it's full colour with a faint 1px edge (30% white), and its tooltip says "You reacted". In a Feed entry's reactor list, "You" is Ash Text among Smoke Muted names.

### Toast
300×40, Night Window at 88%, a 24px Feed picture, Body text (Ember Gold for news), and an optional Reaction button. A 2px timer line shows the time left at 18% white on every toast. Toasts fade over 0.6s.

### Empty state
Centred in its view, built from the house's own shapes rather than an illustration. The empty Feed is a 120px stretch of the timeline with one node (the ding picture, desaturated at half strength, grey edge), a Heading beside it and one Small Smoke Muted line under that. The panel before joining a Crew is a 320px block centred in the window: Display name across, then Start a Crew and Join a Crew in two 150px columns split by a vertical Hairline.

### Tooltips
The game's own GameTooltip, with BFF's colours inside (class colour for the Character, Smoke Muted details, Online Green for online, Ember Gold for "can play"). A Roster row's tooltip opens beside the panel, level with the row, on whichever side has room; small controls (Reactions, heatmap cells, map pins) anchor to their right.

### Brand frame (brand surfaces)
A screenshot, usually cropped to about 1.3–1.5x the panel so scenery surrounds it, in a 10px-radius frame with a 1px hairline edge and a 2px gold-to-teal line along the top. A second, smaller frame may sit below it, overlapping only its bottom edge.

### Braid divider (brand surfaces)
A 2px line fading in from gold, meeting a teal line at a small white spark: the icon's two rings, drawn as a rule between a title and its caption.

## Do's and Don'ts

### Do:
- **Do** build in-game UI from `UI/Skin.lua` helpers (`window`, `button`, `chip`, `edge`, `feedPicture`) and its colour constants. Never add one-off RGB values.
- **Do** keep gold for news and the single primary action (The One Ember Rule).
- **Do** make every bar Bar Fill on Bar Track unless its colour means something.
- **Do** compose empty views, centred, from the timeline and Feed pictures.
- **Do** use the game's own icons, cropped and edged, for meaning. Class colours come from `RAID_CLASS_COLORS`.
- **Do** keep windows fixed in size across tabs, and scroll inside them.
- **Do** render brand images from `docs/gallery/` so every image shares one template.

### Don't:
- **Don't** use Blizzard parchment, stone frames, ornate gilded borders or Blizzard frame templates for BFF's look.
- **Don't** use teal in the addon (The Two Rings Rule).
- **Don't** add shadows, gradients or glows to in-game frames (The Flat Ledger Rule).
- **Don't** introduce a third typeface.
- **Don't** fade a gold button to show it's disabled, or mark a row with a coloured side stripe.
- **Don't** put icons in the sidebar or box a label in a chip.
- **Don't** set text smaller than 11px.
