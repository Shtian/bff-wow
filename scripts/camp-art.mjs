// Builds the Camp's art from pixel grids: Media/CampSprites.tga (every
// sprite, a 1-pixel transparent gutter round each cell),
// Media/CampBackdrop.tga (the static night sky, hills, pines and the fire's
// glow on the ground), Media/CampPocketBackdrop.tga (the Pocket Camp's
// soft-edged piece of it) and UI/CampSheet.lua (where each sprite sits). The
// grids come from the prototype (prototype/ui-personality). Run it after
// changing a grid: node scripts/camp-art.mjs. See docs/design/camp.md.
//
// Figures come as two layers with the same rectangle: cloth, in white and
// #9E9E9E so a class colour tint multiplies to the prototype's C and D, and
// skin and outline, drawn untinted over it.

import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const PAL = {
  K: "#0b0a12", S: "#e8b890", s: "#b98465", W: "#fff3c4", Y: "#ffe9a0", G: "#ffd14a", O: "#f0a21c",
  R: "#c9481c", B: "#5a3a24", b: "#3a2518", T: "#8c8796", t: "#5d5966", L: "#70e370", P: "#f2b8d0",
  Z: "#adabb8", F: "#7fc4ee", f: "#3f7fb8", N: "#ece8d8",
};
// Cloth tones: a white C and a 62% D, tinted by the class colour in game.
// Sleepers' cloth is 55% of that, as the prototype shaded bedrolls.
const CLOTH = { C: "#ffffff", D: "#9e9e9e" };
const BED_CLOTH = { C: "#8c8c8c", D: "#575757" };

const SIT = ["....KKKK....", "...KCCCCK...", "..KCCCCCCK..", "..KCSSSSCK..", "..KSKSSKSK..", "..KSSSSSsK..", "...KCCCCK...", "..KCCDDCCK..", ".KCCCDDCCCK.", ".KSCCDDCCSK.", ".KKCCCCCCKK.", "..KDDKKDDK..", "..KKK..KKK.."];
const HOP = ["..K.KKKK.K..", ".KSKCCCCKSK.", ".KCCCCCCCCK.", "..KCSSSSCK..", "..KSKSSKSK..", "..KSSSSSsK..", "...KCCCCK...", "..KCCDDCCK..", "..KCCDDCCK..", "..KCCDDCCK..", "..KCCCCCCK..", "..KDDKKDDK..", "..KKK..KKK.."];
const BED = ["....KKKK..........", "...KCCCCKKKKKKKKK.", "..KCSSSSKDDDDDDDDK", "..KSKKSSKDCDDDCDDK", "..KSSSSsKDDDDDDDDK", "...KKKKKKKKKKKKKK."];
const GRAVE = ["..TTTT..", ".TTTTTt.", "TTttttTt", "TTTTTTTt", "TTttttTt", "TTTTTTTt", "TTTTTTTt", "ttttttt."];
const FLOWER = [".P.", "PGP", ".P.", ".L."];
const SPARK = ["..W..", ".WGW.", "WGYGW", ".WGW.", "..W.."];
const FIRE = [
  [".....R.....", "....RR.....", "....ROR..R.", "...ROOR.RR.", ".R.ROOORRR.", ".RRROGGORR.", ".RROOGGOOR.", "RROOGYYGOOR", "ROOGGYYGGOR", "ROGGYYYYGOR", ".ROGYYWYGO.", "..ROGGGGO.."],
  [".........R.", "..R..R.....", "..RR.RR....", ".RORROR..R.", ".ROORROR.R.", ".ROOOOORRR.", ".ROGGOOGOR.", "RROGYGOGOOR", "ROOGYYGGGOR", "ROGGYYYYGOR", ".ROGYWYYGO.", "..ROGGGGO.."],
  ["...R.......", "...RR...R..", "..RORR..R..", "..ROOR.RR..", ".RROOORRO..", ".ROOGOOROR.", ".ROGGGOOOR.", "RROGGYGGOOR", "ROOGYYYGGOR", "ROGGYYYYGOR", ".ROGYYWYGO.", "..ROGGGGO.."],
];
const LOGS = ["..BB.......BB..", ".BBBBb...bBBBB.", "bbBBBBBBBBBBBbb", "..bbbbbbbbbbb.."];
const SEAT = ["BBBBBBBBBBBBBB", "bbbbbbbbbbbbbb", "bbbbbbbbbbbbbb"];
// Sleep marks: three z's, small to normal, rising from the sleeper's head.
const SLEEP = [
  ["ZZZ", ".Z.", "Z..", "ZZZ"],
  ["ZZZZ", "..Z.", ".Z..", "ZZZZ"],
  ["ZZZZZ", "...Z.", "..Z..", ".Z...", "ZZZZZ"],
];
// The Pocket Camp's poses and one-off animations (docs/design/pocket-camp.md).
// A fishing rod held out from a seated figure's hand, its line and bobber
// hanging from the tip; drawn mirrored on the fire's right.
const ROD = [".....B.", "....B.Z", "....B.Z", "...B..Z", "...B..Z", "..B...Z", "..B...Z", ".B....Z", ".B....R", "B......"];
// A sword raised in a standing figure's hand: adventuring.
const SWORD = [".W.", ".Z.", ".Z.", ".Z.", ".Z.", "GGG", ".B."];
// A ding's gold star, a rare find's fish held up, and a death's smoke.
const STAR = ["..G..", "GGYGG", ".GYG.", ".G.G.", "G...G"];
const FISH = [".FFF...F", "FFKFFFFF", "FfffFFFF", ".fff...f"];
const SMOKE = [
  ["..TT...", ".TTTT..", "TTtTTT.", ".TTTtT.", "..tt..."],
  [".T..TT.", "T.TT..T", ".T..T..", "T..T..T", "..T.T.."],
];
// A figure as a skeleton, for a while after a death: the seated figure's
// outline in bone: a skull, a spine, ribs and a pelvis. One layer, untinted.
const SKELETON = ["....KKKK....", "...KNNNNK...", "..KNNNNNNK..", "..KNKNNKNK..", "..KNKNNKNK..", "..KNNNNNNK..", "...KNNNNK...", "...KKNNKK...", ".KNNNNNNNNK.", ".KNKKNNKKNK.", ".KKNNNNNNKK.", "..KNKKKKNK..", "..KKK..KKK.."];
// The fire flaring for a Crew goal: each flame frame with its upper rows
// doubled, so it stands taller on the same logs.
const flare = (rows) => rows.flatMap((row, j) => (j < 8 ? [row, row] : [row]));
const EMBER = ["G"];
const EMBER_COOL = ["R"];

// The tent: a pitched canvas with a dark doorway and a gold pennant, its
// peak at the middle column.
function tent() {
  const rows = 17, flag = 5, half = Math.floor((rows - 1) * 0.95) + 1;
  const width = half * 2 + 1;
  const grid = Array.from({ length: rows + flag }, () => Array(width).fill(null));
  const cx = half;
  for (let j = 0; j < rows; j++) {
    const w = Math.floor(j * 0.95) + 1;
    for (let i = -w; i <= w; i++) {
      let color = Math.abs(i) === w ? "#0b0a12" : i > 0 ? "#7d6248" : "#5a4636";
      if (Math.abs(i) < j * 0.32) color = "#120e14";
      grid[flag + j][cx + i] = color;
    }
  }
  for (let y = 0; y < flag; y++) grid[y][cx] = "#ffd14a";
  grid[0][cx + 1] = grid[0][cx + 2] = grid[0][cx + 3] = "#ffd14a";
  grid[1][cx + 1] = grid[1][cx + 2] = "#ffd14a";
  grid[flag - 1][cx] = "#3a2518";
  return grid;
}

// A grid of characters as colours; chars the palette lacks are clear.
function paint(rows, palette) {
  return rows.map((row) => [...row].map((ch) => palette[ch] || null));
}

// The skin-and-outline layer: everything but cloth.
const skin = (rows) => paint(rows, PAL);
const cloth = (rows, tones) => rows.map((row) => [...row].map((ch) => tones[ch] || null));

const SPRITES = [
  ["seatedCloth", cloth(SIT, CLOTH)], ["seated", skin(SIT)],
  ["hopCloth", cloth(HOP, CLOTH)], ["hop", skin(HOP)],
  ["asleepCloth", cloth(BED, BED_CLOTH)], ["asleep", skin(BED)],
  ["grave", skin(GRAVE)], ["flower", skin(FLOWER)], ["spark", skin(SPARK)],
  ["fire1", skin(FIRE[0])], ["fire2", skin(FIRE[1])], ["fire3", skin(FIRE[2])],
  ["logs", skin(LOGS)], ["seat", skin(SEAT)], ["sleep1", skin(SLEEP[0])], ["sleep2", skin(SLEEP[1])], ["sleep3", skin(SLEEP[2])],
  ["ember", skin(EMBER)], ["emberCool", skin(EMBER_COOL)],
  ["tent", tent()],
  ["rod", skin(ROD)], ["sword", skin(SWORD)], ["star", skin(STAR)], ["fish", skin(FISH)],
  ["smoke1", skin(SMOKE[0])], ["smoke2", skin(SMOKE[1])], ["skeleton", skin(SKELETON)],
  ["flare1", skin(flare(FIRE[0]))], ["flare2", skin(flare(FIRE[1]))], ["flare3", skin(flare(FIRE[2]))],
];

function hex(color) {
  const n = parseInt(color.slice(1), 16);
  return [n >> 16, (n >> 8) & 255, n & 255];
}

// A width x height RGBA image, top row first.
function image(width, height) {
  return { width, height, pixels: new Uint8Array(width * height * 4) };
}

function set(img, x, y, color) {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height || !color) return;
  const [r, g, b] = hex(color);
  const at = (y * img.width + x) * 4;
  img.pixels.set([r, g, b, 255], at);
}

// 32-bit uncompressed TGA, bottom-left origin, as BFF's icon is.
function tga(img) {
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(img.width, 12);
  header.writeUInt16LE(img.height, 14);
  header[16] = 32;
  header[17] = 8;
  const body = Buffer.alloc(img.width * img.height * 4);
  for (let y = 0; y < img.height; y++) {
    const row = img.height - 1 - y;
    for (let x = 0; x < img.width; x++) {
      const from = (y * img.width + x) * 4, to = (row * img.width + x) * 4;
      body[to] = img.pixels[from + 2];
      body[to + 1] = img.pixels[from + 1];
      body[to + 2] = img.pixels[from];
      body[to + 3] = img.pixels[from + 3];
    }
  }
  return Buffer.concat([header, body]);
}

// Packs the sprites in rows across a 128-wide sheet, each cell with a
// 1-pixel gutter on every side.
function sheet() {
  const width = 128;
  const placed = [];
  let x = 0, y = 0, rowHeight = 0;
  for (const [name, grid] of SPRITES) {
    const w = grid[0].length, h = grid.length;
    if (x + w + 2 > width) {
      x = 0;
      y += rowHeight;
      rowHeight = 0;
    }
    placed.push({ name, grid, x: x + 1, y: y + 1, w, h });
    x += w + 2;
    rowHeight = Math.max(rowHeight, h + 2);
  }
  let height = 1;
  while (height < y + rowHeight) height *= 2;
  const img = image(width, height);
  for (const sprite of placed) {
    sprite.grid.forEach((row, j) => row.forEach((color, i) => set(img, sprite.x + i, sprite.y + j, color)));
  }
  return { img, placed };
}

// The prototype's backdrop at 384 x 52, drawn into a 512 x 64 file with
// its bottom on the file's and its centre on column 256, where the fire is.
const BACK_W = 384, BACK_H = 52, FILE_W = 512, FILE_H = 64;
const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]].map((r) => r.map((v) => (v + 0.5) / 16));
const rnd = (s) => { const x = Math.sin(s * 127.1) * 43758.5453; return x - Math.floor(x); };
// The sky's top colour, which UI fills the band with above the art.
const SKY_TOP = "#070a1e";

function backdrop() {
  const img = image(FILE_W, FILE_H);
  const ox = (FILE_W - BACK_W) / 2, oy = FILE_H - BACK_H;
  const W = BACK_W, H = BACK_H;
  const put = (x, y, color) => set(img, ox + x, oy + y, color);
  const rect = (x, y, w, h, color) => { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) put(x + i, y + j, color); };
  const cx = W / 2, horizon = H - 13;
  const sky = [SKY_TOP, "#0a0d26", "#0e1030", "#141335", "#1c1636"];
  // The file's rows above the art carry on the top colour.
  for (let y = 0; y < oy; y++) for (let x = 0; x < FILE_W; x++) set(img, x, y, SKY_TOP);
  for (let y = 0; y < horizon; y++) for (let x = 0; x < W; x++) {
    const f = (y / horizon) * (sky.length - 1), i = Math.floor(f), d = f - i;
    put(x, y, sky[Math.min(sky.length - 1, i + (d > BAYER[y % 4][x % 4] ? 1 : 0))]);
  }
  for (let i = 0; i < W * 0.28; i++) {
    const x = Math.floor(rnd(i + 1) * W), y = Math.floor(rnd(i + 50) * (horizon - 8));
    put(x, y, rnd(i + 9) > 0.8 ? "#fff3c4" : rnd(i + 3) > 0.5 ? "#7d7f9e" : "#4a4c6e");
  }
  for (const [dx, dy, w] of [[2, 0, 4], [1, 1, 3], [0, 2, 3], [0, 3, 3], [0, 4, 3], [1, 5, 3], [2, 6, 4]]) {
    rect(Math.floor(W * 0.83) + dx, 4 + dy, w, 1, "#d8d4c4");
  }
  for (let x = 0; x < W; x++) {
    const h = 7 + Math.round(3 * Math.sin(x * 0.05) + 2 * Math.sin(x * 0.13 + 1));
    rect(x, horizon - h, 1, h, "#0e0f26");
  }
  const pine = (x, h, color) => {
    for (let y = 0; y < h; y++) {
      const w = Math.floor(((y % 5) + y * 0.55) * 0.62) + 1;
      rect(x - w, horizon - h + y, w * 2 + 1, 1, color);
    }
    rect(x, horizon, 1, 2, color);
  };
  for (let i = 0; i < W / 9; i++) {
    const x = Math.floor(i * 9 + rnd(i + 20) * 7), far = Math.abs(x - cx) < 30;
    if (far && rnd(i) > 0.3) continue;
    pine(x, 12 + Math.floor(rnd(i + 70) * (far ? 5 : 11)), "#090a18");
  }
  const glow = ["#141019", "#201619", "#35231a", "#573518", "#7a4c18"];
  for (let y = horizon; y < H; y++) for (let x = 0; x < W; x++) {
    const dx = (x - cx) / 52, dy = (y - (H - 5)) / 9, d = Math.sqrt(dx * dx + dy * dy);
    const v = Math.max(0, 1 - d) * (glow.length - 1), i = Math.floor(v);
    put(x, y, glow[Math.min(glow.length - 1, i + (v - i > BAYER[y % 4][x % 4] ? 1 : 0))]);
  }
  return img;
}

// The Pocket Camp's backdrop: the POCKET_W x POCKET_H art pixels of the
// backdrop round the fire, with soft edges so it doesn't sit on the game
// world as a hard rectangle. A rounded shape, solid in the middle and
// dithered away towards its rim. In a 128 x 64 file, its bottom on the
// file's and the fire on column 64. POCKET_W and POCKET_H are Core's
// pocketColumns and pocketRows (Core/Camp.lua).
const POCKET_W = 112, POCKET_H = 34, POCKET_FILE_W = 128, POCKET_FILE_H = 64;
function pocketBackdrop(back) {
  const img = image(POCKET_FILE_W, POCKET_FILE_H);
  const fromX = FILE_W / 2 - POCKET_W / 2, fromY = FILE_H - POCKET_H;
  const toX = POCKET_FILE_W / 2 - POCKET_W / 2, toY = POCKET_FILE_H - POCKET_H;
  // How round the shape is (2 is an ellipse, higher is squarer), how much
  // of the way out from the middle the fade takes, the row its middle is
  // on, and how far out the bottom row counts: the ground under the
  // figures stays mostly solid.
  const round = 4, fade = 0.22, middle = 20, bottom = 0.86;
  for (let j = 0; j < POCKET_H; j++) for (let i = 0; i < POCKET_W; i++) {
    const u = Math.abs((i + 0.5) / (POCKET_W / 2) - 1), y = j + 0.5;
    const v = y < middle ? (middle - y) / middle : (y - middle) / (POCKET_H - middle) * bottom;
    const d = Math.pow(Math.pow(u, round) + Math.pow(v, round), 1 / round);
    if ((1 - d) / fade <= BAYER[j % 4][i % 4]) continue;
    const from = ((fromY + j) * back.width + fromX + i) * 4, to = ((toY + j) * img.width + toX + i) * 4;
    img.pixels.set(back.pixels.subarray(from, from + 4), to);
  }
  return img;
}

const { img, placed } = sheet();
const back = backdrop();
writeFileSync(join(root, "Media", "CampSprites.tga"), tga(img));
writeFileSync(join(root, "Media", "CampBackdrop.tga"), tga(back));
writeFileSync(join(root, "Media", "CampPocketBackdrop.tga"), tga(pocketBackdrop(back)));

const [skyR, skyG, skyB] = hex(SKY_TOP).map((v) => +(v / 255).toFixed(3));
const lines = placed.map((s) => `    ${s.name} = { ${s.x}, ${s.y}, ${s.w}, ${s.h} },`);
writeFileSync(join(root, "UI", "CampSheet.lua"), `-- CampSheet: where each Camp sprite sits in Media\\CampSprites.tga, as
-- { x, y, width, height } in texels from the top left, and the backdrop's
-- file. Generated by scripts/camp-art.mjs; edit the grids there and run it
-- again. See docs/design/camp.md.

local _, ns = ...

ns.CampSheet = {
  file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampSprites",
  width = ${img.width},
  height = ${img.height},
  sprites = {
${lines.join("\n")}
  },
  -- The backdrop's file, its size in texels, and the column the fire's
  -- centre sits on.
  backdrop = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampBackdrop",
    width = ${FILE_W},
    height = ${FILE_H},
    fire = ${FILE_W / 2},
  },
  -- The Pocket Camp's backdrop, soft-edged: the same, for its own file.
  pocketBackdrop = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampPocketBackdrop",
    width = ${POCKET_FILE_W},
    height = ${POCKET_FILE_H},
    fire = ${POCKET_FILE_W / 2},
  },
  -- The sky's top colour, above the backdrop's art.
  sky = { ${skyR}, ${skyG}, ${skyB} },
}
`);
console.log(`CampSprites ${img.width}x${img.height}, ${placed.length} sprites; CampBackdrop ${FILE_W}x${FILE_H}`);
