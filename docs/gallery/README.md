# Gallery images

The CurseForge gallery and the README banner, all in one look: the game's own scenery behind, the addon's dark window and gold, the icon's teal as a thin accent, Cinzel titles and Archivo Narrow text. The rules are in the brand register of `DESIGN.md`.

1. Put in-game screenshots in `shots/`, named as in `slides.json`: `away.jpg`, `toast.jpg`, `roster.jpg`, `feed.jpg`, `goals.jpg`, `spares.jpg` and `when.jpg`. WoW saves JPGs; any format a browser reads works if `slides.json` names it.
2. `npm run gallery` writes `out/<id>.png`: 1920×1080 for the gallery, 1600×520 for the README banner. `npm run gallery -- 02` renders only the slides whose id starts with `02`.

A missing screenshot stops the render. To preview the layout before you have them all, run `npm run gallery -- --draft`: missing shots become dashed placeholders, and those slides get a red DRAFT stamp so they can't be uploaded by mistake.

## Taking screenshots

- Full screen at native resolution, with a scenic spot behind the panel. That screenshot is the slide's background, only lightly softened, so pick a place worth seeing.
- Raise the UI scale a step or two. A frame is never enlarged past 1.4x, so a bigger panel in the capture means bigger, sharper text in the image.
- **Crop every shot** with `"crop": [x, y, width, height]` (pixels in the screenshot) in `slides.json`. Take about 1.3–1.5x the panel's size, so some bright scenery frames the dark panel. Without a crop the whole screen is shown, the panel ends up tiny, and the render warns about it.
- `toast.png` is shown below the While you were away popup on the cover. Crop it tight to one or two toasts.
- Mock data (dev checkout): `/bffdev` opens the simulator console, which fills the panel with simulated Members, and `/bffdev toast` shows sample toasts.

## Slides

Each entry in `slides.json` has:
- `id`: the file name.
- `layout`: `left` or `right` (the copy's side), `hero` (the cover, copy on the left, with the small BFF lockup), `steps` (a numbered how-to, no screenshot) or `banner`.
- `title`: 2–4 words, so it reads in a CurseForge thumbnail (about 300px wide).
- `caption`: one sentence, for the full-size view.
- `shots`: one, or two on the hero, where the second sits below the first.
- `steps`: for `steps` only. Wrap a chat command in backticks to set it in gold.

`width` and `height` default to 1920×1080. Keep product terms lowercase in captions ("crew", "characters"); the reader doesn't know them yet.
