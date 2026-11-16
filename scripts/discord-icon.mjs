// Draws BFF's Discord icon (docs/assets/discord-icon.png, 512 x 512) from the
// Camp's own sprites: two seated friends by a fire under a night sky.
// It reads Media/CampSprites.tga and UI/CampSheet.lua, so the figures are
// whatever the Camp draws today. Run it after changing the sprites or the
// scene below: node scripts/discord-icon.mjs
//
// Discord crops the icon to a circle, so everything sits inside the one
// centred in the square. Drawn at 64 x 64 and scaled up 8 times, so every
// pixel stays square, as in game.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync } from "node:zlib";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const SIZE = 64, SCALE = 8;

// The sprite sheet: 32-bit TGA, bottom-left origin, BGRA.
function readTga(path) {
  const buf = readFileSync(path);
  const w = buf.readUInt16LE(12), h = buf.readUInt16LE(14);
  const pixels = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const from = 18 + ((h - 1 - y) * w + x) * 4, to = (y * w + x) * 4;
      pixels.set([buf[from + 2], buf[from + 1], buf[from], buf[from + 3]], to);
    }
  }
  return { w, h, pixels };
}

const sheet = readTga(join(root, "Media", "CampSprites.tga"));
const rects = {};
for (const m of readFileSync(join(root, "UI", "CampSheet.lua"), "utf8").matchAll(/(\w+) = \{ (\d+), (\d+), (\d+), (\d+) \},/g)) {
  rects[m[1]] = m.slice(2).map(Number);
}

const canvas = new Uint8Array(SIZE * SIZE * 3);
const put = (x, y, [r, g, b]) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= SIZE || y >= SIZE) return;
  canvas.set([r, g, b], (y * SIZE + x) * 3);
};
const get = (x, y) => [...canvas.slice((y * SIZE + x) * 3, (y * SIZE + x) * 3 + 3)];
const hex = (c) => { const n = parseInt(c.slice(1), 16); return [n >> 16, (n >> 8) & 255, n & 255]; };
const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));

// Draws a sprite with its top left at (x, y). A tint multiplies the pixels,
// as the Camp tints a figure's cloth by class colour; a mirrored sprite
// faces the other way.
function sprite(name, x, y, { tint, mirror } = {}) {
  const [sx, sy, w, h] = rects[name];
  for (let j = 0; j < h; j++) {
    for (let i = 0; i < w; i++) {
      const at = ((sy + j) * sheet.w + sx + i) * 4;
      if (!sheet.pixels[at + 3]) continue;
      let c = [sheet.pixels[at], sheet.pixels[at + 1], sheet.pixels[at + 2]];
      if (tint) c = c.map((v, k) => Math.round((v * tint[k]) / 255));
      put(x + (mirror ? w - 1 - i : i), y + j, c);
    }
  }
}
const figure = (x, y, tint, mirror) => {
  sprite("seatedCloth", x, y, { tint, mirror });
  sprite("seated", x, y, { mirror });
};

const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]].map((r) => r.map((v) => (v + 0.5) / 16));
const rnd = (s) => { const x = Math.sin(s * 127.1) * 43758.5453; return x - Math.floor(x); };

// Sky: the Camp's night, dithered from its top colour to a warmer dusk, with
// the brand navy low down so the icon sits with the first one.
const sky = ["#070a1e", "#0a0d26", "#0b1a4a", "#141a4e", "#2a1f4e"].map(hex);
const horizon = 46;
for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    const f = Math.min(1, y / horizon) * (sky.length - 1), i = Math.floor(f), d = f - i;
    put(x, y, sky[Math.min(sky.length - 1, i + (d > BAYER[y % 4][x % 4] ? 1 : 0))]);
  }
}

// Stars, kept off the circle's edge.
for (let n = 0; n < 26; n++) {
  const x = 6 + Math.floor(rnd(n * 3 + 1) * 52), y = 5 + Math.floor(rnd(n * 3 + 2) * 24);
  if (Math.hypot(x - 32, y - 32) > 28) continue;
  put(x, y, hex(n % 5 === 0 ? "#ffecc8" : "#8c8a99"));
}

// Ground: rolling hills, then the clearing the fire lights.
const ground = [hex("#15131f"), hex("#262235")];
const hillAt = (x) => Math.round(horizon - 3 - 2.5 * Math.sin(x / 7) - 1.5 * Math.sin(x / 3 + 1));
for (let x = 0; x < SIZE; x++) {
  for (let y = hillAt(x); y < SIZE; y++) put(x, y, ground[y < hillAt(x) + 2 ? 1 : 0]);
}
// Pines on the hill line.
const pine = (x, base, h) => {
  for (let r = 0; r < h; r++) for (let dx = -Math.floor(r / 2); dx <= Math.floor(r / 2); dx++) put(x + dx, base - h + r, hex("#0b0a12"));
  put(x, base, hex("#0b0a12"));
};
pine(9, hillAt(9), 9); pine(15, hillAt(15), 6); pine(49, hillAt(49), 6); pine(55, hillAt(55), 9);

// The fire's light on the ground, dithered warm.
const fireX = 32, fireY = 41;
for (let y = 36; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    if (y < hillAt(x)) continue;
    const dist = Math.hypot((x - fireX) / 1.5, (y - fireY) * 1.3);
    const glow = Math.max(0, 1 - dist / 22) * 0.55;
    if (glow > BAYER[y % 4][x % 4] * 0.55) put(x, y, mix(get(x, y), hex("#c9481c"), Math.min(0.55, glow + 0.2)));
  }
}

// The fire, on its logs.
sprite("logs", 25, 52);
sprite("fire3", 27, 41);
// A spark above it: a ding, a friend arriving.
sprite("star", 30, 28);
sprite("spark", 21, 33);
sprite("spark", 38, 31);

// Two friends by it, in the brand's teal and gold: the two rings of the
// first icon, now people.
sprite("seat", 7, 53);
sprite("seat", 43, 53);
figure(8, 40, hex("#3fd6e0"), false);
figure(44, 40, hex("#ffd14a"), true);

// Scale up and write a PNG.
const W = SIZE * SCALE;
const raw = Buffer.alloc((W * 3 + 1) * W);
for (let y = 0; y < W; y++) {
  raw[y * (W * 3 + 1)] = 0;
  for (let x = 0; x < W; x++) {
    const from = (Math.floor(y / SCALE) * SIZE + Math.floor(x / SCALE)) * 3, to = y * (W * 3 + 1) + 1 + x * 3;
    raw[to] = canvas[from]; raw[to + 1] = canvas[from + 1]; raw[to + 2] = canvas[from + 2];
  }
}
const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const head = Buffer.alloc(8), tail = Buffer.alloc(4);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, "ascii");
  tail.writeUInt32BE(crc(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, tail]);
};
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(W, 4);
ihdr[8] = 8; ihdr[9] = 2;
const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0)),
]);
const out = join(root, "docs", "assets", "discord-icon.png");
writeFileSync(out, png);
console.log(`${out} ${W}x${W}`);
