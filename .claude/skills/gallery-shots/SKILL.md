---
name: gallery-shots
description: Retake the README and CurseForge gallery screenshots with the user, one shot at a time.
disable-model-invocation: true
---

# Gallery shots

The user plays on another machine and sends each screenshot as a chat attachment. You place it, crop it, render its slide, and direct the next shot. `docs/gallery/README.md` is the source of truth for the pipeline, what each shot needs and how to crop: read it first.

## Steps

1. **Scope.** Read `docs/gallery/slides.json`. Ask with AskUserQuestion: retake every shot, or pick slides (multiSelect, options named by slide id and title). The Pocket Camp animation (`out/pocket-camp.webp`/`.gif`) is made outside this pipeline: leave it alone. Done when you hold an ordered list of shot files. Order it as `slides.json` does, with the panel tabs back to back so they share one panel position.
2. **Setup brief.** One message with the README's rules for every shot (1920×1080 full screen, scenic spot, UI scale up, Start sim in `/bffdev`), plus: send each screenshot here as an attachment.
3. **Shot loop.** For one shot at a time:
   1. Direct it: the tab or popup to open, what should be on screen for the slide's `title` and `caption`, and how to get it (README notes, `/bffdev`). End your turn and wait for the attachment.
   2. Read the screenshot. Copy it to `docs/gallery/shots/<file>` and recompress it: `sips -s format jpeg -s formatOptions 85 <file>`.
   3. Set its `crop` in `slides.json` from the panel's pixel bounds in the screenshot. A later panel tab taken with the panel unmoved reuses the previous crop.
   4. Render the slide (`npm run gallery -- <id>`; run `npm ci` first if a module is missing) and Read the PNG. The shot is done when the panel is sharp, nothing but scenery sits around it, and the content shows what the caption claims. Otherwise re-crop, or ask for a retake and say what to change.
   5. Report the shot in a line or two and direct the next one in the same message.
4. **Thin data.** When the sim can't fill a tab, fix `Dev/Sim.lua` (pushed to a branch the user pulls on the game machine) and ask for a retake after `/reload` and a restart of the sim. Its data passes the same validation as real data: check the Core module's validator before adding fields.
5. **Finish.** Run `npm run gallery` for every slide, Read each changed PNG, and check that `git status` lists only the slides in scope under `out/`. Then commit on a branch, push, and open a PR with a before/after table per slide (raw.githubusercontent.com URLs pinned to the base and head SHAs). Tell the user that the CurseForge gallery carousel is uploaded by hand (README, "The listing's text"); the README and the description update on merge.
