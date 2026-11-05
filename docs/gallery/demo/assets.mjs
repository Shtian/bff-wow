// Builds assets/ for the demo prototype. Run once: npm run demo:assets
//   - icons: the addon's own game icons (by the names in UI/Skin.lua), fetched
//     at 56px. Blizzard's art, so assets/ is gitignored.
//   - Friz Quadrata: copied from a local WoW install if there is one. Without
//     it the panel falls back to Cinzel, which is visibly less like the game.
//   - backdrop.jpg: shots/toast.jpg (the only clean shot, no panel in it) with
//     its toasts painted out and the unit frame's level changed from the dev
//     client's 70 to one that fits Forever's 1-60.
import { chromium } from "playwright";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const assets = join(here, "assets");
mkdirSync(join(assets, "icons"), { recursive: true });
mkdirSync(join(assets, "fonts"), { recursive: true });

const ICONS = `spell_chargepositive achievement_level_80 inv_misc_bone_humanskull_01 inv_misc_groupneedmore
inv_misc_grouplooking ability_vanish achievement_general inv_misc_bag_08 inv_letter_15 inv_misc_book_11
inv_misc_missilesmall_red inv_misc_flower_04 achievement_reputation_01 achievement_level_20 achievement_level_30
inv_pick_02 inv_misc_note_06 inv_misc_head_human_01 inv_misc_head_dragon_black inv_misc_questionmark
classicon_mage classicon_warrior classicon_rogue classicon_druid classicon_priest classicon_warlock classicon_hunter
classicon_paladin trade_alchemy trade_blacksmithing trade_engraving trade_engineering trade_herbalism
inv_misc_armorkit_17 trade_mining inv_misc_pelt_wolf_01 trade_tailoring inv_misc_food_15 trade_fishing
spell_holy_sealofsacrifice inv_fabric_linen_01 inv_gauntlets_17 inv_weapon_shortblade_05 inv_staff_08`.split(/\s+/);

for (const name of ICONS) {
  const path = join(assets, "icons", `${name}.jpg`);
  if (existsSync(path)) continue;
  const response = await fetch(`https://wow.zamimg.com/images/wow/icons/large/${name}.jpg`);
  if (!response.ok) throw new Error(`${name}: ${response.status}`);
  writeFileSync(path, Buffer.from(await response.arrayBuffer()));
}
console.log(`icons: ${ICONS.length}`);

const friz = join(assets, "fonts", "frizqt__.ttf");
if (!existsSync(friz)) {
  let found = "";
  try {
    found = execSync(`find "/Applications/World of Warcraft" -iname 'frizqt__.ttf' 2>/dev/null | head -1`).toString().trim();
  } catch { /* no install */ }
  if (found) copyFileSync(found, friz);
}
console.log(existsSync(friz) ? "font: Friz Quadrata" : "font: no local Friz Quadrata, falling back to Cinzel");

const browser = await chromium.launch();
const page = await browser.newPage();
const dataUrlOf = (path, type) => `data:${type};base64,${readFileSync(path).toString("base64")}`;
const shot = dataUrlOf(join(here, "..", "shots", "toast.jpg"), "image/jpeg");
const font = existsSync(friz) ? dataUrlOf(friz, "font/ttf") : null;
await page.setContent("<canvas id=c></canvas>");
const dataUrl = await page.evaluate(async ({ shot, font }) => {
  const image = new Image();
  image.src = shot;
  await image.decode();
  if (font) {
    const face = new FontFace("Friz", `url(${font})`);
    await face.load();
    document.fonts.add(face);
  }
  const canvas = document.getElementById("c");
  canvas.width = image.width; canvas.height = image.height;
  const g = canvas.getContext("2d");
  g.drawImage(image, 0, 0);

  // A patch mirrored from just below, feathered in so its edges don't show.
  const [x, y, w, h, feather] = [1252, 0, 326, 118, 20];
  const patch = document.createElement("canvas");
  patch.width = w; patch.height = h;
  const p = patch.getContext("2d");
  p.translate(0, h); p.scale(1, -1);
  p.drawImage(image, x, y + h, w, h, 0, 0, w, h);
  p.setTransform(1, 0, 0, 1, 0, 0);
  p.globalCompositeOperation = "destination-in";
  const across = p.createLinearGradient(0, 0, w, 0);
  across.addColorStop(0, "transparent"); across.addColorStop(feather / w, "#000");
  across.addColorStop(1 - feather / w, "#000"); across.addColorStop(1, "transparent");
  p.fillStyle = across; p.fillRect(0, 0, w, h);
  const down = p.createLinearGradient(0, 0, 0, h);
  down.addColorStop(0, "#000"); down.addColorStop(1 - feather / h, "#000"); down.addColorStop(1, "transparent");
  p.fillStyle = down; p.fillRect(0, 0, w, h);
  g.drawImage(patch, x, y);

  // The unit frame's level: cover the 70 with the bare strip beside it.
  g.drawImage(canvas, 590, 755, 26, 14, 614, 755, 26, 14);
  g.font = `11px ${font ? "Friz" : "serif"}`;
  g.textAlign = "right"; g.textBaseline = "alphabetic";
  g.fillStyle = "#000"; g.fillText("24", 636, 767);
  g.fillStyle = "#ffd100"; g.fillText("24", 635, 766);
  return canvas.toDataURL("image/jpeg", 0.95);
}, { shot, font });
writeFileSync(join(assets, "backdrop.jpg"), Buffer.from(dataUrl.split(",")[1], "base64"));
await browser.close();
console.log("backdrop: done");
