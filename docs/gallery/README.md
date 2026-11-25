# Gallery images

The CurseForge gallery and the README banner, all in one look: the game's own scenery behind, the addon's dark window and gold, the icon's teal as a thin accent, Cinzel titles and Archivo Narrow text. The rules are in the brand register of `DESIGN.md`.

1. Put in-game screenshots in `shots/`, named as in `slides.json`: `away.jpg`, `toast.jpg`, `pocket.png`, `camp.jpg`, `roster.jpg`, `feed.jpg`, `goals.jpg`, `spares.jpg`, `when.jpg`, `professions.jpg` and `together.jpg`. WoW saves JPGs; any format a browser reads works if `slides.json` names it.
2. `npm run gallery` writes `out/<id>.png`: 1920×1080 for the gallery, 1600×520 for the README banner. `npm run gallery -- 02` renders only the slides whose id starts with `02`.

A missing screenshot stops the render. To preview the layout before you have them all, run `npm run gallery -- --draft`: missing shots become dashed placeholders, and those slides get a red DRAFT stamp so they can't be uploaded by mistake.

## Taking screenshots

- Full screen at native resolution, with a scenic spot behind the panel. That screenshot is the slide's background, only lightly softened, so pick a place worth seeing.
- Raise the UI scale a step or two. A frame is never enlarged past 1.4x, so a bigger panel in the capture means bigger, sharper text in the image.
- **Crop every shot** with `"crop": [x, y, width, height]` (pixels in the screenshot) in `slides.json`. Take about 1.3–1.5x the panel's size, so some bright scenery frames the dark panel. Without a crop the whole screen is shown, the panel ends up tiny, and the render warns about it.
- `camp.jpg` is the Camp band at the top of the panel. Crop it wide and short, around the band with a little of the panel below, and have a few friends online and asleep, a grave with a flower and a spark (`/bffdev` can set these up).
- `pocket.png` is the Pocket Camp, used on the banner and on its own slide. Have four or five friends online doing different things (one fighting, one fishing, one in a dungeon doorway), and crop it tight to the Camp with a little scenery around it.
- `away.jpg` is the While you were away popup: Start sim, then Away in `/bffdev`; it shows once sync settles (about 10 s).
- `toast.jpg` is shown below the While you were away popup on the cover. Crop it tight to one or two toasts (`/bffdev toast`, a death next to a ding).
- The panel tabs (`roster`, `feed`, `goals` (Trophies), `spares`, `when` (Play Times), `professions`, `together` (Dungeons)) share one crop: take them in one session without moving or resizing the panel or turning the camera, and keep minimap buttons and the quest tracker clear of the crop's corners.
- Fill each tab before the shot: alts expanded on the Roster, reactions sent in the Feed, a cleared dungeon on the Trophies shelf (Dungeon in `/bffdev`), one Spare claimed, every Member's professions shared. If a tab stays thin, the gap is in the sim's data in `Dev/Sim.lua`.
- Mock data (dev checkout): `/bffdev` opens the simulator console, which fills the panel with simulated Members, and `/bffdev toast` shows sample toasts.

## Slides

Each entry in `slides.json` has:
- `id`: the file name.
- `layout`: `left` or `right` (the copy's side), `hero` (the cover, copy on the left, with the small BFF lockup), `steps` (a numbered how-to, no screenshot) or `banner` (the icon and title, with its shot on the right when it has one).
- `title`: 2–4 words, so it reads in a CurseForge thumbnail (about 300px wide).
- `caption`: one sentence, for the full-size view.
- `shots`: one, or two on the hero, where the second sits below the first.
- `steps`: for `steps` only. Wrap a chat command in backticks to set it in gold.
- `pixelated`: on a shot, scale it without smoothing. For pixel art like the Pocket Camp; leave it off for shots with text.

`width` and `height` default to 1920×1080. Keep product terms lowercase in captions ("crew", "characters"); the reader doesn't know them yet.

## The listing's text

The CurseForge description lives in [`docs/curseforge-description.md`](../curseforge-description.md). CurseForge doesn't read it from the repo: paste it into the project's description (Markdown) after changing it. Its images load from `out/` on `main`, so commit and merge new renders before pasting.

The rest of the listing is set by hand in the authors console:

- **Summary:** "Keep up with friends who play at different times: see what they did while you were away, and keep a campfire of everyone online on screen."
- **Images:** give each gallery image the slide's `title` as its title and its `caption` as its description, keep them in `slides.json` order, and turn on the carousel (shown at the top of the project page).
- **Links:** Source (the GitHub repo), Issues (`/issues`) and the buy me a coffee page, in the project's social links.
