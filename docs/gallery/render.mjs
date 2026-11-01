// Renders the gallery images in slides.json to out/, one PNG per slide.
//   node docs/gallery/render.mjs              all slides
//   node docs/gallery/render.mjs 02           only the slides whose id starts with that
//   node docs/gallery/render.mjs --draft      render even with screenshots missing:
//                                             placeholders, and a DRAFT stamp on the slide
// Without --draft, a missing screenshot stops the render, so a placeholder can't ship.
import { chromium } from "playwright";
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const draft = args.includes("--draft");
const only = args.find((a) => !a.startsWith("--"));
const url = (path) => pathToFileURL(path).href;

const slides = JSON.parse(readFileSync(join(here, "slides.json"), "utf8"))
  .filter((slide) => !only || slide.id.startsWith(only));
if (!slides.length) {
  console.error(`No slide id starts with "${only}".`);
  process.exit(1);
}

const prepared = slides.map((slide) => {
  const shots = (slide.shots || []).map((shot) => {
    const path = join(here, "shots", shot.file);
    return { ...shot, url: existsSync(path) ? url(path) : null };
  });
  return { slide, shots, missing: shots.filter((s) => !s.url).map((s) => s.file) };
});

const missing = [...new Set(prepared.flatMap((p) => p.missing))];
if (missing.length && !draft) {
  console.error(`Missing screenshots in docs/gallery/shots/: ${missing.join(", ")}`);
  console.error("Add them, or pass --draft to render placeholders stamped DRAFT.");
  process.exit(1);
}

mkdirSync(join(here, "out"), { recursive: true });
const browser = await chromium.launch();
try {
  for (const { slide, shots, missing } of prepared) {
    const width = slide.width || 1920, height = slide.height || 1080;
    const page = await browser.newPage({ viewport: { width, height } });
    await page.addInitScript(([s, icon]) => { window.SLIDE = s; window.ICON = icon; },
      [{ ...slide, shots, draft: missing.length > 0 }, url(join(here, "..", "assets", "icon.png"))]);
    await page.goto(url(join(here, "template.html")));
    await page.evaluate(() => window.READY);
    await page.screenshot({ path: join(here, "out", `${slide.id}.png`), clip: { x: 0, y: 0, width, height } });
    const notes = [];
    if (missing.length) notes.push(`DRAFT, placeholder for ${missing.join(", ")}`);
    const uncropped = shots.filter((s) => s.url && !s.crop && !s.width).map((s) => s.file);
    if (uncropped.length) notes.push(`no crop on ${uncropped.join(", ")}: the whole screen is shown, so the panel will be small`);
    console.log(`${slide.id}.png${notes.length ? `  (${notes.join("; ")})` : ""}`);
    await page.close();
  }
} finally {
  await browser.close();
}
