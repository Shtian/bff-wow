# Demo prototype

**A web mock of the addon's frames, for recording demo videos and GIFs. It isn't the addon.** Nothing here runs in the game: the world is one still screenshot, the Crew is fictional, and the news is scripted. Label anything published from it as a mock-up.

```sh
npm ci
npm run demo:assets        # once: icons, Friz Quadrata, backdrop.jpg into assets/
npm run demo               # every scene, then the tour, into out/
npm run demo -- away goals # only those scenes
npm run demo -- --still=away:4500,9000   # PNGs at those times, for checking a frame
```

Open `index.html` to watch a scene or click around (the "free play" link at the bottom left). It needs `npm run demo:assets` first.

- `out/<scene>.mp4`: 1920×1080, 30fps.
- `out/<scene>.gif`: 960px wide, 15fps, cropped to the scene's `crop`.
- `out/tour.mp4`: an opening card and every scene, cut together with short fades.

`assets/` holds Blizzard's icons and font, so it's gitignored. The GIFs are committed, because the repo's README uses them: `away.gif` plays at the top and the others are behind its Watch it links. The MP4s are gitignored; they're too big to keep in the repo.

## How it works

- `engine.js`: a virtual clock. Nothing animates by CSS or real time, so `capture.mjs` can step a scene exactly one frame at a time and nothing stutters. The cursor is the only input, scripted or real, so hover and clicks work the same either way.
- `ui.js`: the frames, drawn from `S`. Sizes and wording follow `UI/*.lua`, colours follow `UI/Skin.lua`. `#ui` is zoomed 1.5×, which is the "raise the UI scale" advice in `docs/gallery/README.md`.
- `data.js`: the Crew. Levels are chosen so the addon's rules hold: Crew levels is 149, so one ding crosses the 150 rung on camera.
- `scenes.js`: the scripts. A scene is an async function of `moveTo`, `click`, `wait` and state changes, plus the `crop` for its GIF.

## Keeping it honest

This is a copy, so it can drift from the addon. When a frame's layout or wording changes in `UI/`, change it here too. A scene should only show what the addon does: no toast, animation or feature that isn't shipped.

Not mocked: Settings, the trophy cabinet behind See all, map pins, the Roster's right-click menu and the setup view. The bar fill on Goals is eased, where the addon jumps.
