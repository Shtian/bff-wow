// Builds the Camp's art from pixel grids: Media/CampSprites.tga (every
// sprite, a 1-pixel transparent gutter round each cell),
// Media/Dither50.tga and Media/Dither25.tga (the Dungeons tab's bar fills),
// Media/CampBackdrop.tga (the static night sky, hills, pines and the fire's
// glow on the ground), Media/CampPocketBackdrop.tga (the Pocket Camp's
// soft-edged piece of it), the same two by day (…Day) and in winter
// (…Winter, …DayWinter), Media/CampLight.tga (the fire's light on the
// window under the band), Media/EmptyStates.tga (the empty states'
// vignettes) and UI/CampSheet.lua (where each sprite sits). The
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
  Z: "#adabb8", F: "#7fc4ee", f: "#3f7fb8", N: "#ece8d8", A: "#c89a5a", a: "#8f6a3a", r: "#5a1620",
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
// The sky's lights (docs/design/camp.md, Day and night; chosen in #267):
// the sun, its rays pulsing between two frames, and the crescent moon.
// Light sources, so not outlined. The stars are single pixels in the
// backdrop's star tones, the brightest the glint.
const SUN_PAL = { W: "#fff3c4", Y: "#ffe9a0", G: "#ffd14a" };
const SUN = [
  ["....G....", ".G..G..G.", "...YYY...", "..YWWWY..", "GGYWWWYGG", "..YWWWY..", "...YYY...", ".G..G..G.", "....G...."],
  [".........", "....G....", "..GYYYG..", "..YWWWY..", ".GYWWWYG.", "..YWWWY..", "..GYYYG..", "....G....", "........."],
];
const MOON = ["..MMMM", ".MMM..", "MMM...", "MMM...", "MMM...", ".MMM..", "..MMMM"];
const MOON_PAL = { M: "#d8d4c4" };
const STAR_TONES = { dim: "#4a4c6e", mid: "#7d7f9e" };
// The Pocket Camp's poses and one-off animations (docs/design/pocket-camp.md).
// Fishing (chosen in round 3 of prototypes/camp-fishing.html, on the
// prototype/fishing-visuals branch): a rod arcing out from a seated
// figure's hand towards the fire, in runs of 2, 2, 1, 1 then flat with the
// tip drooping a pixel, outlined so it reads on the ground behind it. Its
// line hangs straight down from the tip (FISH_LINE_X, in the figure's
// columns, with CampScene placing the rod at 7) to a bobber in a pond on
// the ground rows under the seat, with rings round the bobber. All of it
// is drawn mirrored on the fire's right. The line's two frames bob the
// bobber; a fish leaps along a path CampScene holds and lands in a splash.
// CampSheet.fishing carries the pond's and line's geometry.
const ROD = outlined(["....AA.", "...A..N", "..A....", "..A....", ".A.....", ".A.....", "a......"]);
const FISH_LINE_X = 14;
const FISH_LINE = [
  ["Z", "Z", "Z", "Z", "Z", "Z", "Z", "N", "R", "."],
  ["Z", "Z", "Z", "Z", "Z", "Z", "Z", "Z", "N", "R"],
];
const LEAP_FISH = outlined([".F.", "FFf"]);
const POND_PAL = { w: "#0e2238", d: "#1d4a7a", m: "#2f6fae", l: "#6fb3e6", g: "#d8f0ff" };
const SPLASH = ["g.N.g", ".N.N."];
// The pond's core is open water across the figure's columns 0 to 14; each
// row reaches past it at both ends, its outermost columns in the listed end
// tones (outermost first), so the whole pond is 21 columns from -3. Rows
// top first: the lip, the middle (with the glints), the deep bottom. Two
// neighbours' ponds would overlap, so CampScene cuts the ends that face
// each other and joins the cores with POND_WATER, one column of the rows'
// fills. A glint shows on the middle row for 5 ticks at a time, at columns
// 0, 8, none, 4 and 12 in turn, as the prototype twinkled them.
const POND_CORE = [0, 14];
const POND_ROWS = [
  { fill: "l", ends: ["w"] },
  { fill: "m", ends: ["w", "d", "m"] },
  { fill: "d", ends: ["w"] },
];
const POND_REACH = Math.max(...POND_ROWS.map((row) => row.ends.length));
const POND_GLINTS = [0, 8, null, 4, 12];
const POND_WATER = POND_ROWS.map((row) => row.fill);
// The rings round the bobber on the pond's middle row: a step out, two
// steps out, then none.
const RIPPLES = [".g.g.", "l...l"];
function pond(glint) {
  const from = POND_CORE[0] - POND_REACH, to = POND_CORE[1] + POND_REACH;
  return paint(POND_ROWS.map((row, i) => {
    let line = "";
    for (let u = from; u <= to; u++) {
      const out = Math.max(POND_CORE[0] - u, u - POND_CORE[1], 0);
      const end = out > 0 ? row.ends.length - out : -1;
      if (out > row.ends.length) line += ".";
      else if (end >= 0) line += row.ends[end];
      else line += i === 1 && u === glint ? "g" : row.fill;
    }
    return line;
  }), POND_PAL);
}
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
// A dark outline round a grid's shape, one pixel on every side (corners
// too), so a tool still reads with the game world behind it.
function outlined(rows) {
  const w = rows[0].length + 2, h = rows.length + 2;
  const at = (x, y) => (rows[y - 1] && rows[y - 1][x - 1] && rows[y - 1][x - 1] !== "." ? rows[y - 1][x - 1] : null);
  const out = [];
  for (let y = 0; y < h; y++) {
    let line = "";
    for (let x = 0; x < w; x++) {
      const own = at(x, y);
      if (own) { line += own; continue; }
      let near = false;
      for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) if (at(x + i, y + j)) near = true;
      line += near ? "K" : ".";
    }
    out.push(line);
  }
  return out;
}

// Head pieces (docs/design/camp.md, Head pieces), from the prototype
// (prototypes/look-hats.html on the prototype/241-head-pieces branch):
// fill-only grids, outlined like the tools, in PAL plus HAT_PAL. Untinted,
// drawn over a figure's head. brow is the fill row whose underside sits on
// the seated figure's forehead (its row 2), so CampScene can place each one
// on any pose; CampSheet.hats carries it.
const HAT_PAL = {
  x: "#1d1b26", X: "#34303f", q: "#55506a",
  g: "#2c5a33", h: "#468a46", i: "#6db35e",
  v: "#2c1d4f", V: "#45307e", u: "#6f55b5",
  d: "#1c2440", e: "#2c3a66", E: "#4a5d94",
};
const HATS = [
  { key: "templar", brow: 3, rows: [
    "....GO....",
    "...ZGOT...",
    "..ZNGOTt..",
    ".ZNZGOTTt.",
    ".ZZZGOTTt.",
    "GGGGGGGGGO",
    "ZKKKGOKKKt",
    "GGGGGGGGOO",
    ".TKTGOKTt.",
  ] },
  { key: "centurion", brow: 3, rows: [
    "...RRRR...",
    "....rR....",
    "...ZZZT...",
    "..ZNZZTt..",
    ".ZNZZZTTt.",
    ".ZZZZZTTt.",
    "ZKKKKKKKKt",
    "ZZZTKKZTTt",
    ".ZZTKKTTt.",
    ".ZT.KK.Tt.",
  ] },
  { key: "dwarf", brow: 2, rows: [
    "...TZZT...",
    "..TZNZTt..",
    ".TZZZTTTt.",
    "GGGGGGGGGO",
    "T...GO...t",
    "T...GO...t",
    "aAaaaaaaAa",
    ".aaAaaAaa.",
    "...aaaa...",
  ] },
  { key: "wolfskin", brow: 4, rows: [
    ".Tt....tT.",
    "..TTTTTT..",
    ".TYTTTTYT.",
    ".tTTZZTTt.",
    "TtTNZZNTtT",
    "Tt......tT",
    "t........t",
  ] },
  { key: "coonskin", brow: 3, rows: [
    ".aAAAAAAa.",
    ".AAaAAaAA.",
    ".AaAAaAAAB",
    ".BBBBBBBBA",
    ".........b",
    ".........A",
    ".........b",
  ] },
  { key: "cowboy", brow: 4, rows: [
    "....AAAA....",
    "...AaAAAA...",
    "...bbbbbb...",
    "a..AAAAAA..a",
    "aAAAAAAAAAAa",
  ] },
  { key: "straw", brow: 4, rows: [
    "....GYYG....",
    "...GYWYYGO..",
    "...RRRRRR...",
    ".OGYYYYYYGO.",
    "aOGGGGGGGGOa",
  ] },
  { key: "fez", brow: 3, rows: [
    "...RRRRr..",
    "...RORRrG.",
    "...RORRrG.",
    "..RRRRRRr.",
  ] },
  { key: "beret", brow: 3, rows: [
    ".....d....",
    "..dEeeed..",
    ".dEeeeeeed",
    "..dddddddd",
  ] },
  { key: "circlet", brow: 1, rows: [
    "....YG....",
    ".GOGFfGOG.",
  ] },
  { key: "bandana", brow: 2, rows: [
    "...RRRR...",
    "..ROORRR..",
    ".rRRRRRRrR",
    "........rR",
    ".........r",
  ] },
  { key: "cap", brow: 4, rows: [
    ".........R",
    "...hhh..RO",
    "..hiihhRO.",
    ".ghhhhhRhg",
    "gggggggggg",
  ] },
  { key: "wizard", brow: 4, rows: [
    "......vv..",
    ".....uV...",
    "...vuVVv..",
    "..vuVGVVv.",
    "vvuuVVVVvv",
  ] },
  { key: "horns", brow: 3, rows: [
    "N........N",
    "N..TZZT..N",
    "NNTZZTTTNN",
    ".tTTTTTTt.",
  ] },
  { key: "tophat", brow: 4, rows: [
    "..XXXXXX..",
    "..XqXXXx..",
    "..XqXXXx..",
    "..rrrrrr..",
    "xXXXXXXXXx",
  ] },
];

// Pets (docs/design/camp.md, Pets), from the prototype
// (prototypes/camp-pets.html on the prototype/242-pets branch), its large
// size: fill-only grids facing right, outlined like the tools, in PAL plus
// PET_PAL. Each has an awake sprite, its idle's second frame (a blink, a
// wag, an ear twitch or a tail flick) and a curled-up asleep one, no wider
// than Core's LAYOUT.pet outlined. CampScene mirrors them on the fire's
// right, so they face their Member.
const PET_PAL = { g: "#2c5a33", h: "#468a46", i: "#9bd47a", c: "#b8501c" };
const PETS = {
  cat: {
    sit: [".....T..T", ".....TTTT", "t....YTYT", "t....TPTT", ".t..TTTTT", ".tTTTTTNT", "..TTTTTNT", "..TtTtTTT"],
    idle: [".....T..T", ".....TTTT", "t....tTtT", "t....TPTT", ".t..TTTTT", ".tTTTTTNT", "..TTTTTNT", "..TtTtTTT"],
    asleep: [".......T.T", "...TTTTTTT", "..TtTTTtTt", ".TTTtTTTTP", "tTTTTtTTTT", ".ttttttttt"],
  },
  dog: {
    sit: ["....AAAA..", "...aAAKAAA", "...aAAAANK", "a..aAAAN..", "a..AAANN..", ".AAAAANN..", ".AAAAAAN..", ".AaAAAaA.."],
    idle: ["....AAAA..", "a..aAAKAAA", "a..aAAAANK", ".a.aAAAN..", "..AAAANN..", ".AAAAANN..", ".AAAAAAN..", ".AaAAAaA.."],
    asleep: [".....AAA...", "....aAAaAA.", "..AAaAAaANK", ".aAAAAAAANN", "aAAAAAAANNN"],
  },
  owl: {
    sit: ["bb.....bb", ".bBBBBBb.", "BNNBBBNNB", "NYKNBNKYN", "BNNBOBNNB", "BBBBOBBBB", ".BAbAbAB.", ".BbAbAbB.", "..O...O.."],
    idle: ["bb.....bb", ".bBBBBBb.", "BNNBBBNNB", "NbbNBNbbN", "BNNBOBNNB", "BBBBOBBBB", ".BAbAbAB.", ".BbAbAbB.", "..O...O.."],
    asleep: [".bBBBBBb.", "BNNBBBNNB", "NbbNBNbbN", "BNNBOBNNB", "BBBBBBBBB", ".BAbAbAB.", "..BBBBB.."],
  },
  frog: {
    sit: [".WW...WW.", "WKWhhhWKW", "hhhhhhhhh", "hgggggggh", "hhhiiihhh", "ghhiiihhg", "hhg...ghh"],
    idle: [".hh...hh.", "hgghhhggh", "hhhhhhhhh", "hgggggggh", "hhiiiiihh", "ghiiiiihg", "hhg...ghh"],
    asleep: [".gg...gg.", "hhhhhhhhh", "hgggggggh", "hhhiiihhh", "hhg...ghh"],
  },
  rabbit: {
    sit: [".....NP..", ".....NP..", ".....NP..", "....NNNN.", "....NKNNP", "N..NNNNN.", "NNNNNNNZ.", "NNNNNNN..", ".ZNNZNN.."],
    idle: ["....NP...", "....NP...", ".....NP..", "....NNNN.", "....NKNNP", "N..NNNNN.", "NNNNNNNZ.", "NNNNNNN..", ".ZNNZNN.."],
    asleep: ["....NPPPN..", "..NNNNNNNN.", ".NNNNNNNZNP", "NNNNNNNNNN.", ".ZNNNNNNZ.."],
  },
  fox: {
    sit: ["......R.R..", "......OOO..", "N.....OKOOK", "NO....OONN.", "OO...OOON..", "OO..OOOON..", ".OOOOOOON..", "..ObOObON.."],
    idle: ["......R.R..", "......OOO..", "......cOcOK", "NN....OONN.", "OOO..OOON..", ".OO.OOOON..", ".OOOOOOON..", "..ObOObON.."],
    asleep: [".......R.R.", "....OOOOOO.", "..OOOOOOcOK", ".OOOOOOOONN", "OOOOOOOONNN", "NNNOOOOOOb."],
  },
};
const PET_WIDTH = 13;
const petSprite = (key, frame) => "pet" + key[0].toUpperCase() + key.slice(1) + (frame || "");
for (const [key, pet] of Object.entries(PETS)) {
  for (const rows of Object.values(pet)) {
    if (outlined(rows)[0].length > PET_WIDTH) throw new Error(`${key} is wider than LAYOUT.pet`);
  }
}

// What a Member is doing, for the Pocket Camp (docs/design/pocket-camp.md).
// Held in a standing figure's raised hand: a blade (fighting), a torch (in
// a dungeon or raid) and a hammer (crafting).
const BLADE = outlined(["..W..", ".WZt.", ".WZt.", ".WZt.", ".WZt.", ".WZt.", ".WZt.", "GGGGG", "..B..", "..G.."]);
const TORCH = outlined(["..R..", ".RO..", ".ROR.", "ROYOR", "ROYOR", ".OGO.", ".aAa.", "..A..", "..A..", "..a.."]);
const HAMMER = outlined(["ZZZZZt", "ZNZZZt", "ZZZZZt", "..Aa..", "..Aa..", "..Aa..", "..Aa..", "..Aa.."]);
// Gathering (set B of prototypes/camp-gathering.html, on the
// t3/prototype-animated-gathering-sprites branch), one looping animation
// per profession. Mining swings a straight pick with pale points down onto
// an ore node; chips fly on each hit and every 4th swing a piece of ore
// arcs up and twinkles. Herbalism kneels by three flowers, picks them one
// at a time into a basket behind it, then the patch grows back from buds.
// Skinning kneels by a boar, head toward the fire, and cuts it with a
// short knife, a drop of blood on each hit and a stain under it.
// The art is drawn as the prototype drew it, in a figure's columns (0 to
// 11, the fire beyond 11) and rows up from the ground, its figure standing
// on row 3. Every tick of each cycle becomes a frame: the figure's body
// and the sprite in each of CampScene's slots (back, behind the figure;
// node, held, fleck and find over it, each over the one before), each
// sprite at the column and row of its bottom-left pixel. Sprites that
// differ only in where they are drawn share a name. CampSheet.working
// carries the frames and how far each animation reaches past the figure,
// toward the fire and away; Core's LAYOUT gives each that much room.
const CROUCH = [...SIT.slice(0, 9), ".KSCDDDDCSK.", "KDDDDKKDDDDK", "KKKKK..KKKKK"];
const WORK_PAL = {
  ...PAL, h: "#468a46", g: "#2c5a33", i: "#9bd47a", c: "#c8682c", e: "#f2a868", p: "#e7e1f0",
  m: "#7a3e24", M: "#a8643a", n: "#4e2818", j: "#2a1410", u: "#c46a78", v: "#e89aa8", q: "#4a1c24",
  X: "#b8141e", E: "#d42a2a", V: "#9a5ce0", I: "#d6b4ff",
};
const FIGURE_COLUMNS = 12;
const ORE = ["..tTTt..", ".tTeTct.", "tTcTTTTt", "tTTTeTcT", "ttTtTTtt"];
const ORE_FIND = ["ec", "cc"];
const ORE_CHIPS = ["W", "Y", "t"];
const ORE_U = 7;
const PICK_UP = [[0, 0, "a"], [0, 1, "A"], [0, 2, "A"], [0, 3, "A"], [-3, 4, "N"], [-2, 4, "Z"], [-1, 4, "Z"], [0, 4, "t"], [1, 4, "Z"], [2, 4, "Z"], [3, 4, "N"], [-1, 5, "Z"], [0, 5, "Z"], [1, 5, "Z"]];
const PICK_DIAG = [[0, 0, "a"], [1, 1, "A"], [2, 2, "A"], [3, 3, "A"], [4, 4, "t"], [3, 5, "Z"], [2, 6, "N"], [5, 3, "Z"], [6, 2, "N"], [5, 5, "Z"]];
const RAISED = { body: "hop", hand: [9, 14] };
const STRIKE = [9, 9];
const SWING = [
  { ...RAISED, dir: [-1, 1], pick: "pickBack" }, { ...RAISED, dir: [-1, 1], pick: "pickBack" },
  { ...RAISED, dir: [0, 1], pick: "pickUp" }, { ...RAISED, dir: [1, 1], pick: "pickFore" },
  { body: "seated", hand: STRIKE, dir: [1, 0], pick: "pickStrike", hit: 0 },
  { body: "seated", hand: STRIKE, dir: [1, 0], pick: "pickStrike", hit: 1 },
  { body: "seated", hand: STRIKE, dir: [1, 0], pick: "pickStrike", hit: 2 },
  { ...RAISED, dir: [1, 1], pick: "pickFore" },
];
const FIND_EVERY = 4;
const BASKET = [".aaa.", "a...a", "AaAaA", "aAaAa", ".AaA."];
const FLOWERS = [{ u: 1, h: 4, c: "P" }, { u: 4, h: 5, c: "p" }, { u: 7, h: 4, c: "F" }];
const PATCH_U = 8;
const BASKET_U = -4;
const PER_FLOWER = 10;
const BOAR = [".....j.j.jj.....", "...jjjjjjjnj....", "..jmMMmmjmnmj...", ".jmMmnnmjmmmmj.N", "jmmmmmmmjmjNvvvN", "jmmnnmmjmmmNquqN", ".jnnnnnjnnnjuuuj", "..jnjjnjjnjjjjj."];
const BOAR_U = 6;
const CUT = [[1, 1], [1, 1], [1, 1], [1, 0], [1, 0], [1, 0]];
const KNIFE_HAND = [9, 4];

function layer() {
  const px = new Map();
  return {
    px,
    set(u, r, ch) { px.set(u + "," + r, ch); return this; },
    art(rows, u0, r0, swap = {}) {
      rows.forEach((line, i) => [...line].forEach((ch, j) => {
        if (ch !== ".") this.set(u0 + j, r0 + rows.length - 1 - i, swap[ch] || ch);
      }));
      return this;
    },
    outline() {
      const add = [];
      for (const key of px.keys()) {
        const [u, r] = key.split(",").map(Number);
        for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) if (!px.has(u + i + "," + (r + j))) add.push(u + i + "," + (r + j));
      }
      for (const k of add) px.set(k, "K");
      return this;
    },
  };
}

// A layer as a sprite grid, top row first, and where its bottom-left sits.
function asSprite(l) {
  const cells = [...l.px].map(([k, ch]) => [...k.split(",").map(Number), ch]);
  const us = cells.map((c) => c[0]), rs = cells.map((c) => c[1]);
  const u = Math.min(...us), row = Math.min(...rs);
  const w = Math.max(...us) - u + 1, h = Math.max(...rs) - row + 1;
  const grid = Array.from({ length: h }, () => Array(w).fill(null));
  for (const [cu, cr, ch] of cells) grid[h - 1 - (cr - row)][cu - u] = WORK_PAL[ch];
  return { grid, u, row };
}

function pick(hand, dir) {
  const l = layer(), [hu, hr] = hand, [dx, dy] = dir;
  if (dx !== 0 && dy !== 0) {
    const flip = dx < 0 ? -1 : 1;
    for (const [x, y, c] of PICK_DIAG) l.set(hu + x * flip, hr + y, c);
  } else {
    for (const [j, k, c] of PICK_UP) l.set(hu + dx * k - dy * j, hr + dy * k + dx * j, c);
  }
  return l.outline();
}
function knife(hand, dir) {
  const l = layer(), [hu, hr] = hand, [dx, dy] = dir;
  ["a", "a", "Z", "N", "W"].forEach((c, k) => l.set(hu + dx * k, hr + dy * k, c));
  return l.outline();
}
function chips(at, hit) {
  const l = layer(), [u, r] = at, [c1, c2, c3] = ORE_CHIPS;
  if (hit === 0) l.set(u + 1, r + 1, c1).set(u + 2, r + 2, c2).set(u - 1, r + 2, c1);
  if (hit === 1) l.set(u + 2, r + 3, c2).set(u + 3, r + 2, c1).set(u - 1, r + 4, c3);
  if (hit === 2) l.set(u + 3, r + 1, c3).set(u - 2, r + 3, c3);
  return l;
}
function arc(p, from, to, peak, steps) {
  const k = p / (steps - 1);
  return [Math.round(from[0] + (to[0] - from[0]) * k), Math.round(from[1] + (to[1] - from[1]) * k + peak * 4 * k * (1 - k))];
}
function twinkle(u, r, n) {
  const c = n % 2 ? "Y" : "W";
  return layer().set(u, r + 1, c).set(u, r - 1, c).set(u - 1, r, c).set(u + 1, r, c);
}
function flower(l, u, r, c) { return l.set(u, r, "Y").set(u - 1, r, c).set(u + 1, r, c).set(u, r + 1, c).set(u, r - 1, c); }
function patch(u0, r0, looks) {
  const l = layer();
  for (let x = 0; x < 9; x++) l.set(u0 + x, r0, x % 3 === 1 ? "g" : "h");
  for (const x of [0, 2, 6, 8]) l.set(u0 + x, r0 + 1, "h");
  FLOWERS.forEach((f, k) => {
    const look = looks[k], u = u0 + f.u;
    if (look === "gone") return;
    if (look === "bud") {
      for (let r = r0 + 1; r <= r0 + f.h - 3; r++) l.set(u, r, "i");
      l.set(u, r0 + f.h - 2, "h");
      return;
    }
    const top = r0 + f.h - 1 + (look === "lift" ? 1 : 0);
    for (let r = r0 + 1; r <= top - 2; r++) l.set(u, r, "i");
    flower(l, u, top, f.c);
  });
  return l.outline();
}

function mining(t) {
  const f = SWING[t % SWING.length];
  const frame = { body: f.body, node: ["ore", layer().art(ORE, ORE_U, 3).outline()], held: [f.pick, pick(f.hand, f.dir)] };
  if (f.hit != null) frame.fleck = [`oreChips${f.hit + 1}`, chips([12, STRIKE[1] + 1], f.hit)];
  const p = t % (SWING.length * FIND_EVERY) - 4;
  if (p >= 0 && p < 6) frame.find = ["oreFind", layer().art(ORE_FIND, ...arc(p, [10, 7], [9, 19], 3, 6)).outline()];
  else if (p >= 6 && p < 9) frame.find = [`oreTwinkle${p % 2 + 1}`, twinkle(10, 20, p)];
  return frame;
}
const LOOK_KEY = { full: "F", lift: "L", gone: "G", bud: "B" };
function herbalism(t) {
  const p = t % (PER_FLOWER * 3 + 6);
  const k = Math.min(3, Math.floor(p / PER_FLOWER)), q = p % PER_FLOWER, done = p >= PER_FLOWER * 3;
  const looks = FLOWERS.map((_, i) => done ? (p - PER_FLOWER * 3 < 3 ? "gone" : "bud") : i < k ? "gone" : i > k ? "full" : q < 4 ? "full" : q === 4 ? "lift" : "gone");
  const landed = done ? 3 : k + (q >= 9 ? 1 : 0);
  const basket = layer().art(BASKET, BASKET_U, 3).outline();
  for (let i = 0; i < landed; i++) basket.set(BASKET_U + 1 + i, 6, FLOWERS[i].c);
  const frame = {
    body: "crouch",
    back: [`basket${landed}`, basket],
    node: ["patch" + looks.map((look) => LOOK_KEY[look]).join(""), patch(PATCH_U, 3, looks)],
  };
  if (!done && q >= 5 && q < 9) {
    const at = arc(q - 5, [PATCH_U + FLOWERS[k].u, 7], [BASKET_U + 2, 8], 7, 4);
    frame.find = [`herb${k + 1}`, flower(layer(), ...at, FLOWERS[k].c).outline()];
  }
  return frame;
}
function skinning(t) {
  const n = t % CUT.length, dir = CUT[n], hit = n - 3;
  const boar = layer().art(BOAR, BOAR_U, 3).outline();
  boar.set(BOAR_U + 7, 2, "X").set(BOAR_U + 8, 2, "X");
  const frame = { body: "crouch", back: ["boar", boar], held: [dir[1] ? "knifeDown" : "knifeLevel", knife(KNIFE_HAND, dir)] };
  const tip = [KNIFE_HAND[0] + dir[0] * 4, KNIFE_HAND[1] + dir[1] * 4];
  const drop = [[tip[0] + 1, tip[1] + 1], [tip[0] + 1, tip[1]], [tip[0] + 2, tip[1] - 1]][hit];
  if (drop) frame.fleck = ["blood", layer().set(...drop, "X")];
  return frame;
}

// Crafting ("at the bench" in prototypes/camp-crafting.html, on the
// prototype/animated-crafting branch), one looping animation per
// profession, drawn and framed exactly as gathering is. Alchemy kneels at
// a flask bubbling on a burner that flashes, puffs and changes colour.
// Blacksmithing stands at an anvil and swings a hammer with its near arm
// only, the hot bar cooling a step each swing. Enchanting stands, a rod in
// its near hand, at a gem floating over a rune until it glows. Engineering
// ratchets a wrench on a gadget until it bangs, the figure jumps and it
// smokes. Leatherworking scrapes a hide on a frame, tailoring kneels at a
// spinning wheel, cooking stirs a pot over its own fire, and first aid
// winds a bandage up off the ground, a green + when it's done, a kit
// behind. A hop hides the held and fleck slots, so fleck is only ever
// what the tool throws off. Their sprites are named by what they are and
// numbered by look, so one drawn in several places is one sprite.
const STAND = [...SIT.slice(0, 10), "..KCCCCCCK..", "..KDDKKDDK..", "..KKK..KKK.."];
const STAND_RAISED = [STAND[0], STAND[1], "..KCCCCCCKK.", "..KCSSSSCKSK", "..KSKSSKSKCK", "..KSSSSSsKCK", "...KCCCCKCK.", "..KCCDDCCCK.", ".KCCCDDCCK..", ".KSCCDDCCK..", ...STAND.slice(10)];
const STAND_STRIKE = [...STAND.slice(0, 5), "..KSSSSSsKK.", "...KCCCCCCSK", "..KCCDDCCKK.", ".KCCCDDCCK..", ".KSCCDDCCK..", ...STAND.slice(10)];
const STAND_JUMP = [...STAND, "............"];
const CLOUD = [
  [[0, 0], [1, 0]],
  [[0, 0], [1, 0], [0, 1], [1, 1]],
  [[-1, 0], [0, 0], [1, 0], [2, 0], [0, 1], [1, 1]],
  [[-1, 0], [1, 0], [2, 0], [0, 1], [1, 1], [0, 2]],
  [[-1, 1], [2, 0], [1, 2], [0, 1]],
  [[-1, 2], [2, 1]],
];
const HAMMER_AXIS = [[0, 0, "a"], [0, 1, "A"], [0, 2, "A"], [0, 3, "A"], [-1, 4, "Z"], [0, 4, "Z"], [1, 4, "t"], [-1, 5, "N"], [0, 5, "Z"], [1, 5, "Z"]];
const HAMMER_DIAG = [[0, 0, "a"], [1, 1, "A"], [2, 2, "A"], [3, 3, "A"], [3, 5, "N"], [4, 4, "Z"], [5, 3, "Z"], [4, 5, "Z"], [5, 4, "Z"], [4, 6, "Z"], [5, 5, "Z"], [6, 4, "t"]];
const WRENCH = [[0, 0, "t"], [0, 1, "T"], [0, 2, "T"], [0, 3, "Z"], [-1, 4, "Z"], [1, 4, "Z"]];
const FLASK = ["..N..", "..N..", ".NxN.", "NxxxN", "NxxxN", ".NNN."];
const BURNER = ["T.f.T", "TTTTT"];
const BREWS = ["L", "E", "F", "V"];
const BREW_FOR = 24;
const ANVIL_SMALL = ["ZZZZZZZ", "tZZZZZt", "..TTt..", ".TTTTt."];
const SMITH_RAISED = { body: "raise", hand: [10, 12] };
const SMITH_STRIKE = { body: "strike", hand: [10, 9], dir: [1, 0] };
const SMITH_SWING = [
  { ...SMITH_RAISED, dir: [0, 1] }, { ...SMITH_RAISED, dir: [0, 1] }, { ...SMITH_RAISED, dir: [1, 1] },
  { ...SMITH_STRIKE, hit: 0 }, { ...SMITH_STRIKE, hit: 1 }, { ...SMITH_RAISED, dir: [1, 1] },
];
const HEAT = ["YWY", "OYO", "ROR", "rRr"];
const RUNE = [".VVVVV.", "V.....V", ".VVVVV."];
const GEM = [".I.", "IWI", ".I."];
const ENCHANT_FOR = 18;
const GADGET = ["ZZZZZ", "TggTT", "TggTZ", "ttttt"];
const TINKER_FOR = 24;
const HIDE_FRAME = ["BBBBBBB", "b.....b", "b.....b", "b.....b", "b.....b", "b.....b", "b.....b", "b.....b", "BBBBBBB", "b.....b", "b.....b"];
const HIDE = [".AeA.", "AAAaA", "AaAAA", "AAAAa", "AAaAA", "eAAAA", ".AAA."];
const SCRAPE_FOR = 10;
const WHEEL = ["..BBB..", ".B...B.", "B.....B", "B.....B", "B.....B", ".B...B.", "..BBB.."];
const SPOKES = [[0, 1], [1, 1], [1, 0], [1, -1]];
const POT = ["ZccccccZ", "TTTTTTTT", "TTTTTTTt", ".TTTTTt.", "..tttt.."];
const STIR = [0, 1, 2, 1];
const KIT = [".t.t.", "NNENN", "NEEEN", "NNENN"];
const BANDAGE_FOR = 24;

function merge(...layers) {
  const l = layer();
  for (const part of layers) for (const [k, ch] of part.px) l.px.set(k, ch);
  return l;
}
function named(prefix) {
  const looks = new Map();
  return (l) => {
    const look = JSON.stringify(asSprite(l).grid);
    if (!looks.has(look)) looks.set(look, prefix + (looks.size + 1));
    return [looks.get(look), l];
  };
}
function tool(axis, diag, hand, dir) {
  const l = layer(), [hu, hr] = hand, [dx, dy] = dir;
  if (dx !== 0 && dy !== 0) for (const [x, y, c] of diag) l.set(hu + x * dx, hr + y * dy, c);
  else for (const [j, k, c] of axis) l.set(hu + dx * k - dy * j, hr + dy * k + dx * j, c);
  return l.outline();
}
function star(u, r, c1, c2) { return layer().set(u, r, c1).set(u + 1, r, c2).set(u - 1, r, c2).set(u, r + 1, c2).set(u, r - 1, c2); }
function puff(u, r, k, c, fade) {
  const l = layer();
  for (const [du, dr] of CLOUD[k]) l.set(u + du, r + k + dr, k < 3 ? c : fade);
  return l;
}

const ALCHEMY = { node: named("brewNode"), held: named("brewVial"), find: named("brewPuff") };
function alchemy(t) {
  const p = t % BREW_FOR, brew = Math.floor(t / BREW_FOR), now = BREWS[(brew + (p >= 14 ? 1 : 0)) % BREWS.length];
  const frame = {
    body: "crouch",
    node: ALCHEMY.node(layer().art(BURNER, 11, 3, { f: t % 2 ? "Y" : "O" }).art(FLASK, 11, 5, { x: p === 14 || p === 15 ? "W" : now }).outline()),
    held: ALCHEMY.held(layer().art(["N", "x", "x"], 10, 5, { x: BREWS[(brew + 1) % BREWS.length] }).outline()),
  };
  if (p < 14) {
    const bubbles = layer().set(12 + (t % 3), 6 + (t % 2), "W");
    for (const k of [0, 2]) {
      const r = 12 + ((p + k) % 4);
      if (r < 15) bubbles.set(13 + (k ? 0 : (p >> 1) % 2), r, "N");
    }
    frame.find = ALCHEMY.find(bubbles);
  }
  if (p === 14 || p === 15) frame.find = ALCHEMY.find(star(13, 13, "W", "Y"));
  if (p >= 16 && p < 16 + CLOUD.length) frame.find = ALCHEMY.find(puff(12, 12, p - 16, now, "Z"));
  return frame;
}

const SMITHING = { held: named("smithHammer"), fleck: named("smithSparks"), find: named("smithBar") };
function blacksmithing(t) {
  const f = SMITH_SWING[t % SMITH_SWING.length], heat = HEAT[Math.floor(t / SMITH_SWING.length) % HEAT.length];
  const frame = {
    body: f.body,
    node: ["anvilSmall", layer().art(ANVIL_SMALL, 9, 3).outline()],
    held: SMITHING.held(tool(HAMMER_AXIS, HAMMER_DIAG, f.hand, f.dir)),
    find: SMITHING.find(merge(...[...heat].map((c, i) => layer().set(13 + i, 7, c)))),
  };
  if (f.hit === 0) frame.fleck = SMITHING.fleck(layer().set(16, 9, "Y").set(17, 10, "W").set(12, 9, "O"));
  if (f.hit === 1) frame.fleck = SMITHING.fleck(layer().set(17, 11, "O").set(12, 11, "Y").set(17, 8, "R"));
  return frame;
}

const ENCHANTING = { back: named("rune"), node: named("enchantGem"), held: named("enchantRod"), find: named("enchantSparkles") };
function enchanting(t) {
  const p = t % ENCHANT_FOR, glow = p >= 12, flash = p === 12 || p === 13;
  const gem = flash ? { I: "W", W: "W" } : glow ? { I: "V", W: "I" } : { I: "f", W: "F" };
  const frame = {
    body: "stand",
    back: ENCHANTING.back(layer().art(RUNE, 11, 1, { V: (t >> 1) % 2 ? "V" : "I" })),
    node: ENCHANTING.node(layer().art(GEM, 13, 9 + ((t >> 1) % 2), gem).outline()),
    held: ENCHANTING.held(layer().set(10, 7, "c").set(11, 8, "O").set(12, 9, p % 2 ? "W" : "I").outline()),
  };
  const sparkles = layer();
  if (!glow) {
    if (p % 2 === 0) sparkles.set(13, 8, "I");
    for (const [u, k] of [[12, 0], [15, 3], [17, 5]]) sparkles.set(u, 3 + ((p + k) % 6), (p + k) % 2 ? "I" : "W");
  }
  if (flash) sparkles.set(12, 12, "W").set(16, 12, "W").set(12, 8, "W").set(16, 8, "W");
  if (sparkles.px.size) frame.find = ENCHANTING.find(sparkles);
  return frame;
}

const TINKERING = { node: named("gadget"), find: named("gadgetBang") };
function engineering(t) {
  const p = t % TINKER_FOR, bang = p === 14 || p === 15, shake = bang ? 1 : 0;
  const turned = (t >> 1) % 2;
  const gadget = layer().art(GADGET, 12 + shake, 3, { g: turned ? "G" : "O" })
    .set(13 + shake, 5, turned ? "O" : "G").set(14 + shake, 4, turned ? "O" : "G")
    .set(15 + shake, 7, "t").set(15 + shake, 8, "t").set(15 + shake, 9, p % 6 < 3 ? "R" : "L").outline();
  const frame = { body: p === 14 ? "jump" : bang ? "stand" : "crouch", node: TINKERING.node(gadget) };
  if (!bang) frame.held = ["wrench", tool(WRENCH, [], [8, 5 + ((p >> 1) % 2)], [1, 0])];
  if (bang) frame.find = TINKERING.find(star(14, 11, "W", "Y"));
  if (p >= 16 && p < 16 + CLOUD.length) frame.find = TINKERING.find(puff(13, 9, p - 16, "T", "t"));
  return frame;
}

const SCRAPING = { node: named("hide") };
function leatherworking(t) {
  const p = t % SCRAPE_FOR, down = p < 5 ? p : null;
  const hide = layer().art(HIDE_FRAME, 11, 3).art(HIDE, 12, 6);
  if (down !== null) for (let k = 0; k <= down; k++) hide.set(14, 12 - k, "e");
  const frame = { body: "crouch", node: SCRAPING.node(hide.outline()) };
  if (down !== null) {
    const r = 12 - down;
    frame.held = ["scraper", layer().set(10, r, "a").set(11, r, "a").set(12, r, "a").set(13, r, "Z").set(14, r, "N").set(15, r, "Z").outline()];
    if (down > 1) frame.fleck = ["shaving", layer().set(16 + (t % 2), r - 1, "e")];
  }
  return frame;
}

function tailoring(t) {
  const [cu, cr] = [14, 9], [dx, dy] = SPOKES[t % SPOKES.length];
  const wheel = layer().art(WHEEL, cu - 3, cr - 3)
    .set(cu, cr, "b").set(cu + dx, cr + dy, "a").set(cu - dx, cr - dy, "a").set(cu + 2 * dx, cr + 2 * dy, "a").set(cu - 2 * dx, cr - 2 * dy, "a")
    .set(12, 4, "b").set(12, 5, "b").set(16, 4, "b").set(16, 5, "b");
  for (let u = 11; u <= 17; u++) wheel.set(u, 3, "b");
  return {
    body: "crouch",
    node: [`wheel${t % SPOKES.length + 1}`, wheel.outline()],
    held: ["wool", layer().set(9, 6, "N").set(10, 6, "N").set(10, 5, "Z").outline().set(11, 7, "N").set(12, 8, "N")],
  };
}

const COOKING = { back: named("ladle"), node: named("pot"), find: named("potSteam") };
function cooking(t) {
  const s = STIR[(t >> 1) % STIR.length];
  const flames = t % 2 ? "ROYOR" : "OYROY";
  const pot = layer();
  [...flames].forEach((c, i) => pot.set(12 + i, 3, c));
  pot.art(POT, 10, 4).set(12 + ((t >> 1) % 4), 8, "e");
  const steam = layer().set(13 + s, 8, "A");
  for (const [u, k] of [[13, 0], [15, 3]]) {
    const q = (t + k) % 6;
    steam.set(u + ((q >> 1) % 2), 8 + q, q % 2 ? "Z" : "N");
  }
  return {
    body: "crouch",
    back: COOKING.back(layer().set(11 + s, 10, "a").set(12 + s, 9, "A").set(13 + s, 8, "A").outline()),
    node: COOKING.node(pot.outline()),
    find: COOKING.find(steam),
  };
}

const BANDAGING = { node: named("bandage") };
function firstAid(t) {
  const p = t % BANDAGE_FOR, left = p < 18 ? 6 - Math.floor(p / 3) : 0;
  const frame = {
    body: "crouch",
    back: ["kit", layer().art(KIT, -5, 3).outline()],
    held: [`roll${t % 2 + 1}`, layer().art(t % 2 ? ["NZ", "ZN"] : ["ZN", "NZ"], 10, 5).outline()],
  };
  if (left) {
    const strip = layer().set(11, 4, "N");
    for (let i = 0; i < left; i++) strip.set(12 + i, 3, i % 3 === 2 ? "Z" : "N");
    frame.node = BANDAGING.node(strip.outline());
  }
  if (p >= 18) {
    const r = 17 + ((p - 18) >> 1);
    frame.find = ["heal", layer().set(5, r, "L").set(4, r, "L").set(6, r, "L").set(5, r + 1, "L").set(5, r - 1, "L").outline()];
  }
  return frame;
}

const WORK_SLOTS = ["back", "node", "held", "fleck", "find"];
const WORK_POSES = {
  mining: [mining, SWING.length * FIND_EVERY], herbalism: [herbalism, PER_FLOWER * 3 + 6], skinning: [skinning, CUT.length],
  alchemy: [alchemy, BREW_FOR * BREWS.length], blacksmithing: [blacksmithing, SMITH_SWING.length * HEAT.length],
  enchanting: [enchanting, ENCHANT_FOR], engineering: [engineering, TINKER_FOR], leatherworking: [leatherworking, SCRAPE_FOR],
  tailoring: [tailoring, SPOKES.length], cooking: [cooking, STIR.length * 2 * 3], firstAid: [firstAid, BANDAGE_FOR],
};
const WORK_SPRITES = new Map();
const WORK_REACH = {};
const WORK_FRAMES = Object.fromEntries(Object.entries(WORK_POSES).map(([pose, [draw, ticks]]) => {
  let min = 0, max = FIGURE_COLUMNS - 1;
  const frames = [];
  for (let t = 0; t < ticks; t++) {
    const drawn = draw(t), frame = { body: drawn.body };
    for (const slot of WORK_SLOTS) {
      if (!drawn[slot]) continue;
      const [name, l] = drawn[slot], { grid, u, row } = asSprite(l);
      const known = WORK_SPRITES.get(name);
      if (known && JSON.stringify(known) !== JSON.stringify(grid)) throw new Error(`${name} has two looks`);
      WORK_SPRITES.set(name, grid);
      frame[slot] = [name, u, row];
      min = Math.min(min, u);
      max = Math.max(max, u + grid[0].length - 1);
    }
    frames.push(frame);
  }
  WORK_REACH[pose] = { fore: max - (FIGURE_COLUMNS - 1), aft: -min };
  return [pose, frames];
}));
// An anvil at a crafter's feet.
const ANVIL = outlined(["ZZZZZZZZZ", "TZZZZZZZt", ".TTTTTtt.", "...TTt...", "..TTTTt..", ".TTTTTTt."]);
// A doorway of stone behind a figure in a dungeon, and a raid's with a
// skull for a keystone.
const ARCH = [
  ".....TTTTTT.....", "...TTTTTTTTTt...", "..TTTttttttTTt..", ".TTTtKKKKKKtTTt.", ".TTtKKKKKKKKtTt.", "TTTtKKKKKKKKtTTt",
  "TTtKKKKKKKKKKtTt", "TttKKKKKKKKKKtTt", "TTtKKKKKKKKKKttt", "TTtKKKKKKKKKKtTt", "TTtKKKKKKKKKKtTt", "tttKKKKKKKKKKtTt",
  "TTtKKKKKKKKKKtTt", "TTtKKKKKKKKKKttt", "TttKKKKKKKKKKtTt", "TTtKKKKKKKKKKtTt", "TTtKKKKKKKKKKtTt",
];
const ARCH_RAID = [
  ".....NNNNNN.....", "....NNNNNNNN....", "...TNRRNNRRNT...", "..TTNNNKKNNNTT..", ".TTTtNKNNKNtTTt.",
  ...ARCH.slice(4).map((row) => row.replaceAll("K", "r")),
];
// At a seated figure's feet: a vendor's coin bag and the auction house's
// stacked gold.
const BAG = outlined(["..A.A..", "...a...", "..AAA..", ".AAAAA.", "AAAGAAa", "AAGGGAa", "AAAGAAa", ".AAAAa."]);
const COINS = outlined([".GYYG.", "GYWWYG", "OGYYGO", "GOGGOG", "OGYYGO", "GOGGOG", "OGYYGO", ".OGGO."]);
// The Pocket Camp's crate by the fire, there while Spare notices wait
// unseen: a wooden crate, its lid lifted on something gold. Outlined.
const CRATE = outlined([".GYG..", "AAAAAA", "aAaaAa", "aAaaAa", "AAAAAA"]);
// The Pocket Camp's trophy cup, floating over the fire while a Trophy
// reached this session is under an hour old: a gold cup with handles on a
// stepped foot. Outlined. Two sparkle frames twinkle round it.
const TROPHY_CUP = outlined(["G.GYYYYYG.G", "GGGYWYYOGGG", ".G.GYYYO.G.", "....GYO....", ".....O.....", "....GYO....", "...GGOOO..."]);
const CUP_SPARKLE = [["..W..", ".WGW.", "..W.."], ["W...W", "..G..", "W...W"]];
// An inn's sign over a resting figure's head: a post on the side away from
// the fire (mirrored on its right), and a tankard on a board hung by chains.
const INN_SIGN = [
  "aAAAAAAAAAAA", "Aa...Z...Z..", "Aa...Z...Z..", "Aa.TTTTTTTTT", "Aa.TbNNNNbbt", "Aa.TbGGGGZbt", "Aa.TbGOGGbZt", "Aa.TbGOGGbZt",
  "Aa.TbGOGGZbt", "Aa.TbGGGGbbt", "Aa.Ttttttttt", ...Array(15).fill("Aa.........."),
];
// A quest handed in: the gold question mark, over the head.
const QUEST = outlined([".GGG.", "GYYGG", "G..GG", "...GG", "..GG.", "..GG.", ".....", "..GG.", "..GG."]);
// "ALT" over the head of a Member on an Alt, in the same letters as AFK
// but pale blue, so it reads as a label and not an alert. Outlined.
const ALT = outlined([".F..F...FFF", "F.F.F....F.", "FFF.F....F.", "F.F.F....F.", "F.F.FFF..F."]);
// "AFK" over an away figure's head, in 3 by 5 letters, outlined.
const AFK = outlined([".W..WWW.W.W", "W.W.W...W.W", "WWW.WW..WW.", "W.W.W...W.W", "W.W.W...W.W"]);
// A Member coming online walks in (two frames, facing right, mirrored
// when walking left) and waves (two frames, one arm raised) with a "hi!"
// speech bubble over their head.
const WALK = [
  ["....KKKK....", "...KCCCCK...", "..KCCCCCCK..", "..KCSSSSCK..", "..KSKSSKSK..", "..KSSSSSsK..", "...KCCCCK...",
    "..KCCDDCCK..", ".KSCCDDCCK..", "..KCCDDCCSK.", "..KCCCCCCK..", ".KDDK..KDDK.", ".KKK....KKK."],
  ["....KKKK....", "...KCCCCK...", "..KCCCCCCK..", "..KCSSSSCK..", "..KSKSSKSK..", "..KSSSSSsK..", "...KCCCCK...",
    "..KCCDDCCK..", "..KCCDDCCK..", "..KSCDDCSK..", "..KCCCCCCK..", "...KDDDDK...", "...KKKKKK..."],
];
const WAVE = [
  ["....KKKK..K.", "...KCCCCKSK.", "..KCCCCCCCK.", "..KCSSSSCK..", "..KSKSSKSK..", "..KSSSSSsK..", "...KCCCCK...",
    "..KCCDDCCK..", ".KSCCDDCCK..", "..KCCDDCCK..", "..KCCCCCCK..", "..KDDKKDDK..", "..KKK..KKK.."],
  ["....KKKK...K", "...KCCCCK.KS", "..KCCCCCCKCK", "..KCSSSSCCK.", "..KSKSSKSK..", "..KSSSSSsK..", "...KCCCCK...",
    "..KCCDDCCK..", ".KSCCDDCCK..", "..KCCDDCCK..", "..KCCCCCCK..", "..KDDKKDDK..", "..KKK..KKK.."],
];
// "hi!" in 3 by 5 letters on a white bubble with a dark rim, its tail
// pointing down to the head.
const HI = ["K...K.K", "K.....K", "KKK.K.K", "K.K.K..", "K.K.K.K"];
function bubble(text) {
  const inner = text[0].length + 2;
  const edge = "." + "K".repeat(inner) + ".";
  const blank = "K" + "W".repeat(inner) + "K";
  const lines = text.map((row) => "KW" + row.replaceAll(".", "W") + "WK");
  const tail = ["...KWK", "....K."].map((row) => row.padEnd(inner + 2, "."));
  return [edge, blank, ...lines, blank, edge, ...tail];
}
const HI_BUBBLE = bubble(HI);
// A griffin under a flying figure, facing the fire (mirrored on its right).
// The rider sits on its columns 3 to 14, their bottom row on its sixth. The
// wing is drawn over the rider's legs, its right end on the griffin's
// column 14 and its top two rows above the back; the raised one is its
// other frame, a row taller.
const GRIFFIN = outlined([
  "...............NNNNN..", "................NKNOO.", "................NNNOR.", "...............NNNNN..", "................NNNN..",
  "......AAAAAAAAAaNNNN..", ".aaa.AAAAAAAAAAAaNNA..", "a...aAAAAAAAAAAAAAAA..", "a....AAAaAAAAAAAAAA...", ".a..aAAa.....aAAAa....",
  "..aa.AAa......OO......", ".....AAAa.....OOO.....",
]);
const GRIFFIN_WING = outlined(["NNNNNNNNNNNNNNNNN", "...ZNNNNNNNNNNNNN", "......ZNNNNNZNNNN", ".........ZNNNNNNN", "............ZNNNN"]);
const GRIFFIN_WING_UP = outlined([
  "NNNN.............", "ZNNNNNNNN........", "...ZNNNNNNNNNNNNN", "......ZNNNNNZNNNN", ".........ZNNNNNNN", "............ZNNNN",
]);
// The fire flaring for a Crew goal: each flame frame with its upper rows
// doubled, so it stands taller on the same logs, and burning purple: the
// flame's reds to yellows as deep purple to pale lilac.
const flare = (rows) => rows.flatMap((row, j) => (j < 8 ? [row, row] : [row]));
const FLARE_PAL = { R: "#5b2a9e", O: "#8a45d6", G: "#b77bf2", Y: "#dcc0ff", W: "#f6ecff" };
const EMBER = ["G"];
const EMBER_COOL = ["R"];
// Between the two, for an ember drifting down from the fire into the panel.
const EMBER_WARM = ["O"];
// A Cheer's burst over the hopping figure: pixels white, then pale gold,
// then the ember's gold and warm orange (docs/design/camp.md, Reactions).
const GLINT = ["W"];
const GLINT_PALE = ["Y"];
// A petal drifting up from a Grave's flower as it blooms.
const PETAL = ["P"];

// The tent: a pavilion after the game's own, cone roof laced down the
// middle over a scalloped valance and walls that flare a little, the front
// flaps tied back round the centre pole, a gold knob on top. Its canvas is
// lit on the right, the fire's side; CampScene mirrors it on the fire's
// right. A 1-pixel outline goes round it last.
const CANVAS = ["#c2b394", "#958974", "#695f52", "#4a433b"]; // lit to deepest
function tent() {
  const [lit, mid, shade, deep] = CANVAS;
  const darker = { [lit]: mid, [mid]: shade, [shade]: deep, [deep]: deep };
  // Across the canvas, -1 (the far side) to 1 (the fire's side).
  const tone = (u) => (u < -0.6 ? deep : u < -0.12 ? shade : u < 0.08 ? mid : u < 0.78 ? lit : mid);
  const width = 33, cx = 16;
  const grid = Array.from({ length: 23 }, () => Array(width).fill(null));
  const set = (i, y, c) => { grid[y][cx + i] = c; };
  set(0, 0, PAL.G); set(0, 1, PAL.a);
  // The roof: two darker gores, laced down the middle.
  for (let j = 0; j < 9; j++) {
    const hw = Math.round(1 + j * 1.6);
    for (let i = -hw; i <= hw; i++) {
      const u = i / hw;
      let c = tone(u * 0.9 + 0.05);
      if (Math.abs(Math.abs(u) - 0.55) < 0.09 && hw > 3) c = darker[c];
      if (i === 0) c = j % 2 ? PAL.A : PAL.a;
      set(i, 2 + j, c);
    }
  }
  // The valance: laced, with a scalloped hem.
  for (let i = -15; i <= 15; i++) {
    set(i, 11, i % 2 === 0 ? PAL.A : tone(i / 15));
    if ((i + 15) % 3 !== 2) set(i, 12, darker[tone(i / 15)]);
  }
  // The walls: two seams, the doorway between the folds of the tied-back
  // flaps, the pole in it, and the ties.
  const door = [2, 3, 4, 4, 5, 5, 5, 6, 6, 6];
  for (let j = 0; j < 10; j++) {
    const y = 13 + j, hw = j < 3 ? 13 : j < 7 ? 14 : 15, d = door[j];
    for (let i = -hw; i <= hw; i++) {
      let c = tone(i / hw);
      if (Math.abs(i) === 10) c = darker[c];
      if (Math.abs(i) < d) c = j >= 8 ? "#1f1820" : "#120e14";
      else if (Math.abs(i) === d) c = i > 0 ? lit : mid;
      else if (Math.abs(i) === d + 1) c = darker[tone(i / hw)];
      if (i === 0 && j >= 1) c = PAL.B;
      set(i, y, c);
    }
    if (j === 4) { set(-6, y, PAL.A); set(-7, y, PAL.a); set(6, y, PAL.A); set(7, y, PAL.A); }
  }
  // The outline, on the four sides only, so the roof's slopes stay thin.
  const out = Array.from({ length: grid.length + 2 }, (_, y) =>
    Array.from({ length: width + 2 }, (_, x) => (grid[y - 1] && grid[y - 1][x - 1]) || null));
  const filled = (x, y) => out[y] && out[y][x] && out[y][x] !== PAL.K;
  for (let y = 0; y < out.length; y++) for (let x = 0; x < width + 2; x++) {
    if (!out[y][x] && (filled(x - 1, y) || filled(x + 1, y) || filled(x, y - 1) || filled(x, y + 1))) out[y][x] = PAL.K;
  }
  return out;
}

// Winter (docs/design/camp.md, Seasons), from the prototype
// (prototypes/camp-winter.html on PR #260's branch): snow on the tent's
// roof and each bedroll, a small pine with baubles, coloured lights on the
// tent's roof, falling flakes, and the ground away from the fire's glow
// under snow, in its own copy of each backdrop.
const SNOW = { cap: PAL.N, shade: PAL.Z, far: "#8c8a9e", ground: "#262838", dusk: "#3e4058" };
const TREE_PAL = { g: "#2c5a33", h: "#468a46", i: "#6db35e", j: "#9bd47a" };
// Lit on the right, the fire's side when left of it; CampScene mirrors it on the fire's right.
const PINE = [
  "....Y....",
  "...YWY...",
  "....h....",
  "...ghi...",
  "..gRhhi..",
  "...ghj...",
  "..gFhhi..",
  ".gghhhGi.",
  "..ghhhj..",
  ".gPhhhhi.",
  "gghhhRhhj",
  "....B....",
];
const LIGHTS = ["#ff5a44", "#ffd14a", "#70e370", "#7fc4ee", "#f2b8d0"];
// A sleeper's snow, along the bedroll's top edge over the blanket.
const BED_SNOW = { x: 9, rows: ["ZNNNNNNZ"] };
// The roof's snow, over the tent: the top pixel of each column of the
// roof that isn't outline, and the one under it in every other column, so
// it reads on the pale canvas.
function tentSnow(grid) {
  const out = grid.map((row) => row.map(() => null));
  for (let x = 0; x < grid[0].length; x++) {
    for (let y = 3; y <= 13; y++) {
      const c = grid[y][x];
      if (c && c !== PAL.K) {
        out[y][x] = SNOW.cap;
        if (y < 12) out[y + 1][x] = x % 2 ? SNOW.cap : SNOW.shade;
        break;
      }
    }
  }
  return out;
}
// The tent's lights, on its outline just outside the roof's slopes, three
// a side, as x from the sprite's left and y from its top.
const TENT_CX = 17;
const TENT_LIGHTS = [[8, -1], [5, -1], [2, -1], [2, 1], [5, 1], [8, 1]].map(([j, side]) => {
  const hw = Math.round(1 + j * 1.6);
  return [TENT_CX + side * (hw + 1), 3 + j];
});

// Autumn, the lunar new year and Midsummer (docs/design/camp.md, Seasons),
// from the prototype (prototypes/camp-seasons.html on PR #261's branch).
// Autumn: a carved pumpkin by the fire, outlined and lit on the right like
// the tree, its face glowing (1 bright, 2 dim, swapped on the other
// flicker frame); bats crossing the sky in two wing frames, not outlined;
// the fire's frames tinted a touch more orange.
const PUMPKIN_PAL = { p: "#cc621a", q: "#8a3c14", u: "#ee8a32", s: "#5a7a2a", v: "#3a5420" };
const PUMPKIN_GLOW = ["#ffe9a0", "#f0a21c"];
const PUMPKIN = [
  ".....sv....",
  "...qpspuu..",
  ".qqpppppuu.",
  "qqp1ppp1ppu",
  "qp111p111pu",
  "qppppp2pppu",
  "qp1p1p1p1pu",
  "qpp21212ppu",
  ".qqpppppuu.",
  "..qqpppuu..",
];
const pumpkin = (k) => paint(outlined(PUMPKIN), { ...PAL, ...PUMPKIN_PAL, 1: PUMPKIN_GLOW[k], 2: PUMPKIN_GLOW[1 - k] });
const BAT_PAL = { T: "#77708a", t: "#4f4960", e: "#c9481c" };
const BAT = [
  ["t.....t", "tt.T.tt", ".ttTtt.", "...T..."],
  ["..tTt..", ".tTeTt.", "tt...tt", "t.....t"],
];
const AUTUMN_FIRE_PAL = { R: "#b8381a", O: "#e8701c", G: "#f6922a", Y: "#ffbe62", W: "#ffe0a4" };
// The lunar new year: red and gold paper lanterns on a string (one pixel
// of the string's colour, stretched), and the max-level burst's spark in
// red for the firework, beside the gold one it already has.
const LANTERN = ["..s..", ".ccc.", "reeef", "reyef", "ryyyf", "reeef", ".ccc.", "..x.."];
const LANTERN_PALS = {
  lanternRed: { c: "#ffd14a", x: "#f0a21c", e: "#d0302a", r: "#7a1a1c", f: "#ff6a4a", y: "#ffb060", s: "#6a4a2e" },
  lanternGold: { c: "#c9481c", x: "#c9481c", e: "#f0a21c", r: "#8a5a18", f: "#ffd14a", y: "#fff3c4", s: "#6a4a2e" },
};
const LANTERN_STRING = "#6a4a2e";
// A lantern seat while you're alone in the Crew (#279): a post with an arm
// reaching toward the fire and the gold lantern hung from it. CampScene
// draws it beside a seat log, mirrored on the right of the fire.
const LANTERN_POST = ["BBBBB..", "B...Z..", ...LANTERN.map((row) => "B." + row), "B......", "B......", "B......", "B......"];
const SPARK_RED = { K: PAL.K, W: "#ffb08a", G: "#e0482c", Y: "#ff8a5a" };
// Midsummer: a bonfire, new frames wider and taller than the fire's in its
// palette; the Midsummer pole, a leafy mast with a crossbar, two arms from
// the top to its ends and a wreath hung from each, not outlined (an outline
// fills the triangle in), lit on the right; and fireflies, lit and dim.
const BONFIRE = [
  ["......R......", "......RR.....", ".....RORR....", "..R..ROOR..R.", "..RR.ROOOR.R.", ".RORRROGORRR.", ".ROORROGGOOR.", ".ROOOOGGGOOR.",
    "RROGOGGYGGORR", "ROOGGGYYYGOOR", "ROGGYYYYYGGOR", "ROGYYYWYYYGOR", "ROGYYWWWYYGOR", ".ROGYYWYYGOR.", ".ROGYYYYYGOR.", "..ROGGGGGOR..", "...ROOOOOR..."],
  ["..........R..", "...R......R..", "...RR.R..RR..", "..RORRR..ROR.", "..ROORORRROR.", ".RROOOOORROR.", ".ROOGOOOOGOR.", ".ROGGOGGOGOR.",
    "RROGGGGYGGORR", "ROOGGYYYGGOOR", "ROGGYYYYYYGOR", "ROGYYWYYYYGOR", "ROGYWWWYYYGOR", ".ROGYYWYYGOR.", ".ROGYYYYYGOR.", "..ROGGGGGOR..", "...ROOOOOR..."],
  ["....R........", "....RR....R..", "...RORR...RR.", "...ROORR.ROR.", ".R.ROOOR.ROR.", ".RRROGOORROR.", "RROOOGGOOOOR.", "ROOGGGGGGOOR.",
    "RROGGYGGGGORR", "ROOGYYYYGGOOR", "ROGGYYYYYGGOR", "ROGYYYYWYYGOR", "ROGYYYWWWYGOR", ".ROGYYYWYGOR.", ".ROGYYYYYGOR.", "..ROGGGGGOR..", "...ROOOOOR..."],
];
const POLE_PAL = { g: "#2c5a33", h: "#468a46", i: "#6db35e" };
const MIDSUMMER_POLE = [
  ".......Y.......",
  "......hih......",
  ".....h.h.i.....",
  "....h..h..i....",
  "...h...h...i...",
  "..h....h....i..",
  ".h.....h.....i.",
  "ghhihhiPhihhihi",
  ".hg....h....gi.",
  "h..W...i...P..i",
  "g..h...h...h..i",
  ".hg....h....gi.",
  ".......h.......",
  "......gh.......",
  ".......h.......",
  ".......hi......",
  ".......h.......",
  ".......h.......",
  "......gh.......",
  ".......h.......",
  ".......hi......",
  ".......h.......",
  ".......h.......",
  "......ghi......",
];
const FIREFLY = { on: "#d8f070", dim: "#6a8a30" };

// Shapeshift forms (docs/design/pocket-camp.md), from the prototype
// (prototypes/shapeshift-sprites.html on PR #217's branch): fill-only grids facing right, the
// way a figure left of the fire faces it, outlined like the tools. Each
// form has its own palette, K being the outline's. Ghost Wolf trots (two
// frames); the bear stands breathing (two frames), rears up and swipes,
// with claw marks in front of its paw; the night elf's cat (Alliance) and
// the tauren's lion (Horde) prowl and swish their tails; the travel form,
// a sabre-toothed cheetah, trots; the seal waves a flipper and the moonkin
// blinks.
const FORM_PAL = {
  wolf: { d: "#2f4a6e", F: "#5f86b8", V: "#a9d4f5", W: "#e2f6ff", E: "#e2f6ff" },
  catElf: { d: "#241c36", m: "#5566a8", M: "#4f3f6b", n: "#8a76b0", E: "#ffd14a", W: "#ece8d8" },
  catLion: { M: "#d9a03c", A: "#d9a03c", a: "#9e6a24", N: "#f3d590", B: "#7a4a26", b: "#4a2c16", H: "#ece8d8", E: "#3a2518", W: "#ece8d8" },
  bear: { B: "#8a4f26", b: "#5a3018", A: "#b8743c", a: "#d8a86a", E: "#0b0a12", W: "#ece8d8" },
  claws: { W: "#fff3c4" },
  travel: { A: "#cf9238", a: "#94591f", N: "#ecd3a0", s: "#3f2412", W: "#fffaf0", E: "#0b0a12" },
  seal: { T: "#7d8794", t: "#4f5866", N: "#c9d0d6", E: "#0b0a12" },
  moonkin: { B: "#6b4f38", b: "#3f2c1e", N: "#ece8d8", G: "#ffd14a", a: "#c89a5a", E: "#ffe9a0" },
  leaves: { L: "#70e370", g: "#ffd14a" },
  spirit: { V: "#bfe8ff", F: "#5fb4ef" },
};
for (const palette of Object.values(FORM_PAL)) palette.K = PAL.K;
const WOLF_RUN = [
  ["..........d.d.", ".........dFdF.", ".....d.ddFFFF.", "dd..dFdFFFEFFF", ".d..FFFFFFFFFK", "..dFFFFFFFVVV.",
    "..dFVVVVVFF...", ".dFF....dFF...", "dFF......dFF..", "VV........VVV."],
  ["..........d.d.", ".........dFdF.", ".....d.ddFFFF.", "dd..dFdFFFEFFF", ".d..FFFFFFFFFK", "..dFFFFFFFVVV.",
    "..dFVVVVVFF...", "...dFF.dFF....", "...dFF.dFF....", "...VVV.VVV...."],
];
const BEAR_STAND = [
  ["........AAA.b.b.", "....AAAABBBBbBb.", "..AABBBBBBBBBBB.", ".ABBBBBBBBBbBEaa", ".BBBBBBBBBBbBBaK", ".BBBBBBBBBBbBba.",
    ".bBBBBBBBBBBBb..", ".bBBb.bbbbbBBb..", "..BBb.....bBBb..", "..BBb.....bBBb..", "..bbb.....bbbb.."],
  ["............b.b.", "....AAAAAAAAbBb.", "..AABBBBBBBBBBB.", ".ABBBBBBBBBbBEaa", ".BBBBBBBBBBbBBaK", ".BBBBBBBBBBbBba.",
    ".bBBBBBBBBBBBb..", ".bBBb.bbbbbBBb..", "..BBb.....bBBb..", "..BBb.....bBBb..", "..bbb.....bbbb.."],
];
const BEAR_REAR = [
  "......b.b.......", "......bBBBB.....", "......BBBEaa....", "......BBBBaK..WW", ".....ABBBBB..BBW", "....AABBBBBBBBB.",
  "....ABBBBBBBB...", "....BBBBBBBb....", "....BBBBaaBb....", "....BBBBaaBb....", "...bBBBBBBBb....", "...bBBBBBBBb....",
  "...bBBb.bBBb....", "...bBBb.bBBb....", "..bbbb..bbbbb...",
];
const BEAR_SWIPE = [
  "......b.b.......", "......bBBBB.....", "......BBBEaa....", "......BBBBaK....", ".....ABBBBB.....", "....AABBBBBB....",
  "....ABBBBBBBBB..", "....BBBBBBBbBBBW", "....BBBBaaBb..WW", "....BBBBaaBb....", "...bBBBBBBBb....", "...bBBBBBBBb....",
  "...bBBb.bBBb....", "...bBBb.bBBb....", "..bbbb..bbbbb...",
];
// The swipe's claw marks, not outlined: drawn in front of the paw, at
// column 16 and row 4 of the outlined swipe frame (CampScene's CLAWS).
const BEAR_CLAWS = ["....W..W", "...W..W.", "..W..W..", ".W..W...", "W..W...."];
const CAT_ELF = [
  ["d.............", "d.............", ".d....m.m..d.d", ".d...mmmmmMMMM", "..MMMMMmMdMMEM", "..MMMMMMMdMMMK",
    "..MnnnnnnMMWW.", "..dM...dM.....", "..dM...dM.....", "..nn...nnn...."],
  ["..............", "d.............", "dd....m.m..d.d", ".d...mmmmmMMMM", "..MMMMMmMdMMMM", "..MMMMMMMdMMMK",
    "..MnnnnnnMMWW.", "..dM...dM.....", "..dM...dM.....", "..nn...nnn...."],
];
const CAT_LION = [
  ["b..............", "b.............H", ".a....bBbB.HHHH", ".a...bBBBBAAAA.", "..AAABBBBBAAEA.", "..AAAABBBBAANNK",
    "..AaNNNNBBANWW.", "..aA...aA......", "..aA...aA......", "..aa...aaa....."],
  ["...............", "b.............H", "ba....bBbB.HHHH", ".a...bBBBBAAAA.", "..AAABBBBBAAAA.", "..AAAABBBBAANNK",
    "..AaNNNNBBANWW.", "..aA...aA......", "..aA...aA......", "..aa...aaa....."],
];
const TRAVEL_RUN = [
  ["...........a.a.", "..........AAAA.", "..........AAAEA", "a..AsAAsAAAAAAK", ".a.AAAsAAsAAAa.", "..aAsAAAAAsN.W.",
    "..aNNNNNNNN..W.", ".aA.......aA...", "aA.........aA..", "A...........AA."],
  ["...........a.a.", "..........AAAA.", "..........AAAEA", "a..AsAAsAAAAAAK", ".a.AAAsAAsAAAa.", "..aAsAAAAAsN.W.",
    "..aNNNNNNNN..W.", "....aA.aA......", "....aAaA.......", "...AA.AA......."],
];
const SEAL = [
  ["..........TTT..", ".........TTTET.", ".........TTTTTK", ".........tTNN..", "........TTNNN..", "......TTTTNNN..",
    "...TTTTTTTNNt..", ".tTTTTTTTTTNt..", "ttNNNNNNNNTtt..", "t.t........tttt"],
  ["..........TTT..", ".........TTTET.", ".........TTTTTK", ".........tTNN..", "........TTNNN..", "......TTTTNNNtt",
    "...TTTTTTTNNttt", ".tTTTTTTTTTNt..", "ttNNNNNNNNTt...", ".t............."],
];
const MOONKIN = [
  ["..a......a..", "..aa....aa..", "...aBBBBa...", "..BBBBBBBB..", "..BEBGGBEB..", "..BBBGGBBB..", ".BBBNNNNBBB.",
    "BBBNNNNNNBBB", "BBBNNNNNNBBB", ".BBNNNNNNBB.", "..BBBBBBBB..", "..BBB..BBB..", "..bbb..bbb.."],
  ["..a......a..", "..aa....aa..", "...aBBBBa...", "..BBBBBBBB..", "..BBBGGBBB..", "..BBBGGBBB..", ".BBBNNNNBBB.",
    "BBBNNNNNNBBB", "BBBNNNNNNBBB", ".BBNNNNNNBB.", "..BBBBBBBB..", "..BBB..BBB..", "..bbb..bbb.."],
];
// Shifting puffs leaves (a druid) or spirit wisps (Ghost Wolf), two
// frames each, not outlined.
const LEAVES = [
  ["..L.......L..", ".LL..g....LL.", "......L......", "L...........g", "..g.......L..", "......L......", ".L.........L."],
  ["L....L....g.L", "..g.......L..", ".............", "g...........L", ".............", "..L.......g..", "L.....L.....L"],
];
const SPIRIT = [
  ["....V..V.....", "..V.......V..", ".V...F.F...V.", "V..F.....F..V", ".V...F.F...V.", "..V.......V..", "....V..V....."],
  [".V....V....V.", "V...........V", "....F...F....", "V...........V", "....F...F....", "V...........V", ".V....V....V."],
];
// Ghost Wolf's glow: a pale ring one pixel out from the outlined sprite,
// all round it (corners too), so it's 2 wider and 2 taller. CampScene
// draws it faintly behind the see-through wolf.
const GLOW = "#8cd2ff";
function glow(rows) {
  const sprite = outlined(rows);
  return outlined(sprite).map((row, y) => [...row].map((ch, x) => {
    const own = sprite[y - 1] && sprite[y - 1][x - 1];
    return ch === "K" && (!own || own === ".") ? "g" : ".";
  }).join(""));
}
// An outlined form sprite in its palette.
const form = (rows, palette) => paint(outlined(rows), FORM_PAL[palette]);

// A grid of characters as colours; chars the palette lacks are clear.
function paint(rows, palette) {
  return rows.map((row) => [...row].map((ch) => palette[ch] || null));
}

// The skin-and-outline layer: everything but cloth.
const skin = (rows) => paint(rows, PAL);
const cloth = (rows, tones) => rows.map((row) => [...row].map((ch) => tones[ch] || null));

const hatSprite = (key) => "hat" + key[0].toUpperCase() + key.slice(1);

const SPRITES = [
  ["seatedCloth", cloth(SIT, CLOTH)], ["seated", skin(SIT)],
  ["hopCloth", cloth(HOP, CLOTH)], ["hop", skin(HOP)],
  ["asleepCloth", cloth(BED, BED_CLOTH)], ["asleep", skin(BED)],
  ["grave", skin(GRAVE)], ["flower", skin(FLOWER)], ["spark", skin(SPARK)],
  ["fire1", skin(FIRE[0])], ["fire2", skin(FIRE[1])], ["fire3", skin(FIRE[2])],
  ["logs", skin(LOGS)], ["seat", skin(SEAT)], ["sleep1", skin(SLEEP[0])], ["sleep2", skin(SLEEP[1])], ["sleep3", skin(SLEEP[2])],
  ["ember", skin(EMBER)], ["emberCool", skin(EMBER_COOL)], ["emberWarm", skin(EMBER_WARM)],
  ["glint", skin(GLINT)], ["glintPale", skin(GLINT_PALE)], ["petal", skin(PETAL)],
  ["tent", tent()], ["tentSnow", tentSnow(tent())], ["bedSnow", skin(BED_SNOW.rows)],
  ["treePine", paint(outlined(PINE), { ...PAL, ...TREE_PAL })],
  ["sun1", paint(SUN[0], SUN_PAL)], ["sun2", paint(SUN[1], SUN_PAL)], ["moon", paint(MOON, MOON_PAL)],
  ["starDim", paint(["S"], { S: STAR_TONES.dim })], ["starMid", paint(["S"], { S: STAR_TONES.mid })],
  ["snowflake", paint(["N"], { N: SNOW.cap })], ["snowflakeFar", paint(["N"], { N: SNOW.far })],
  ...LIGHTS.map((color, i) => [`light${i + 1}`, paint(["L"], { L: color })]),
  ["pumpkin1", pumpkin(0)], ["pumpkin2", pumpkin(1)],
  ["bat1", paint(BAT[0], BAT_PAL)], ["bat2", paint(BAT[1], BAT_PAL)],
  ["fireAutumn1", paint(FIRE[0], AUTUMN_FIRE_PAL)], ["fireAutumn2", paint(FIRE[1], AUTUMN_FIRE_PAL)],
  ["fireAutumn3", paint(FIRE[2], AUTUMN_FIRE_PAL)],
  ...Object.entries(LANTERN_PALS).map(([name, palette]) => [name, paint(LANTERN, palette)]),
  ["lanternString", paint(["s"], { s: LANTERN_STRING })], ["sparkRed", paint(SPARK, SPARK_RED)],
  ["bonfire1", skin(BONFIRE[0])], ["bonfire2", skin(BONFIRE[1])], ["bonfire3", skin(BONFIRE[2])],
  ["midsummerPole", paint(MIDSUMMER_POLE, { ...PAL, ...POLE_PAL })],
  ["firefly", paint(["F"], { F: FIREFLY.on })], ["fireflyDim", paint(["F"], { F: FIREFLY.dim })],
  ["rod", skin(ROD)], ["star", skin(STAR)], ["fish", skin(FISH)],
  ["smoke1", skin(SMOKE[0])], ["smoke2", skin(SMOKE[1])], ["skeleton", skin(SKELETON)],
  ["flare1", paint(flare(FIRE[0]), FLARE_PAL)], ["flare2", paint(flare(FIRE[1]), FLARE_PAL)],
  ["flare3", paint(flare(FIRE[2]), FLARE_PAL)],
  ["blade", skin(BLADE)], ["torch", skin(TORCH)], ["hammer", skin(HAMMER)], ["anvil", skin(ANVIL)],
  ["arch", skin(ARCH)], ["archRaid", skin(ARCH_RAID)],
  ["bag", skin(BAG)], ["coins", skin(COINS)], ["innSign", skin(INN_SIGN)], ["quest", skin(QUEST)], ["crate", skin(CRATE)], ["trophyCup", skin(TROPHY_CUP)], ["cupSparkle1", skin(CUP_SPARKLE[0])], ["cupSparkle2", skin(CUP_SPARKLE[1])],
  ["griffin", skin(GRIFFIN)], ["griffinWing", skin(GRIFFIN_WING)], ["griffinWingUp", skin(GRIFFIN_WING_UP)],
  ["afk", skin(AFK)],
  ["walkCloth1", cloth(WALK[0], CLOTH)], ["walk1", skin(WALK[0])],
  ["walkCloth2", cloth(WALK[1], CLOTH)], ["walk2", skin(WALK[1])],
  ["waveCloth1", cloth(WAVE[0], CLOTH)], ["wave1", skin(WAVE[0])],
  ["waveCloth2", cloth(WAVE[1], CLOTH)], ["wave2", skin(WAVE[1])],
  ["hi", skin(HI_BUBBLE)], ["alt", skin(ALT)],
  ["wolfRun1", form(WOLF_RUN[0], "wolf")], ["wolfRun2", form(WOLF_RUN[1], "wolf")],
  ["wolfGlow1", paint(glow(WOLF_RUN[0]), { g: GLOW })], ["wolfGlow2", paint(glow(WOLF_RUN[1]), { g: GLOW })],
  ["bearStand1", form(BEAR_STAND[0], "bear")], ["bearStand2", form(BEAR_STAND[1], "bear")],
  ["bearRear", form(BEAR_REAR, "bear")], ["bearSwipe", form(BEAR_SWIPE, "bear")],
  ["bearClaws", paint(BEAR_CLAWS, FORM_PAL.claws)],
  ["catElf1", form(CAT_ELF[0], "catElf")], ["catElf2", form(CAT_ELF[1], "catElf")],
  ["catLion1", form(CAT_LION[0], "catLion")], ["catLion2", form(CAT_LION[1], "catLion")],
  ["travelRun1", form(TRAVEL_RUN[0], "travel")], ["travelRun2", form(TRAVEL_RUN[1], "travel")],
  ["seal1", form(SEAL[0], "seal")], ["seal2", form(SEAL[1], "seal")],
  ["moonkin1", form(MOONKIN[0], "moonkin")], ["moonkin2", form(MOONKIN[1], "moonkin")],
  ["leaves1", paint(LEAVES[0], FORM_PAL.leaves)], ["leaves2", paint(LEAVES[1], FORM_PAL.leaves)],
  ["spirit1", paint(SPIRIT[0], FORM_PAL.spirit)], ["spirit2", paint(SPIRIT[1], FORM_PAL.spirit)],
  ...HATS.map((hat) => [hatSprite(hat.key), paint(outlined(hat.rows), { ...PAL, ...HAT_PAL })]),
  ...Object.entries(PETS).flatMap(([key, pet]) => [
    [petSprite(key), paint(outlined(pet.sit), { ...PAL, ...PET_PAL })],
    [petSprite(key, "Idle"), paint(outlined(pet.idle), { ...PAL, ...PET_PAL })],
    [petSprite(key, "Asleep"), paint(outlined(pet.asleep), { ...PAL, ...PET_PAL })],
  ]),
  ["lanternPost", paint(LANTERN_POST, { ...PAL, ...LANTERN_PALS.lanternGold })],
  ...POND_GLINTS.map((glint, i) => [`pond${i + 1}`, pond(glint)]),
  ["pondWater", paint(POND_WATER, POND_PAL)],
  ...RIPPLES.map((ripple, i) => [`ripple${i + 1}`, paint([ripple], POND_PAL)]),
  ["fishLine1", skin(FISH_LINE[0])], ["fishLine2", skin(FISH_LINE[1])],
  ["leapFish", skin(LEAP_FISH)], ["splash", paint(SPLASH, { ...PAL, ...POND_PAL })],
  ["crouchCloth", cloth(CROUCH, CLOTH)], ["crouch", skin(CROUCH)],
  ["standCloth", cloth(STAND, CLOTH)], ["stand", skin(STAND)],
  ["raiseCloth", cloth(STAND_RAISED, CLOTH)], ["raise", skin(STAND_RAISED)],
  ["strikeCloth", cloth(STAND_STRIKE, CLOTH)], ["strike", skin(STAND_STRIKE)],
  ["jumpCloth", cloth(STAND_JUMP, CLOTH)], ["jump", skin(STAND_JUMP)],
  ...WORK_SPRITES,
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
// The backdrops by night and by day (docs/design/camp.md, Day and night;
// chosen in #267 from prototypes/camp-day-night.html on the
// prototype/267-day-night branch). Night is the sky as it always was;
// day is look A, Clear: a blue sky dithered to a pale horizon, a few
// clouds, blue-grey hills with a lit crest, grass, and the fire's glow
// reaching half as far. Each look's snow is winter's ground. UI fills the
// band above the art with the sky's top colour.
const NIGHT = {
  sky: ["#070a1e", "#0a0d26", "#0e1030", "#141335", "#1c1636"], hills: "#0e0f26",
  snow: { ground: SNOW.ground, dusk: SNOW.dusk, far: SNOW.far },
};
const DAY = {
  sky: ["#3b62a8", "#4a74b6", "#5c86c2", "#7299cc", "#8fb0d8"], clouds: { c: "#eef0f4", s: "#c4cede" },
  hills: "#6a7f9a", crest: "#7d92aa", pines: "#2f4a3a",
  ground: ["#4f6b3a", "#3e5730"], glow: ["#6a6a34", "#86743a"], glowReach: 0.5,
  snow: { ground: "#d4dae4", dusk: "#b4bece", far: "#9aa6b8" },
};
const CLOUDS = [
  ["....cccc.....", "..ccccccccc..", ".cccccccccccc", "..sssssssss.."],
  ["..ccc...", ".cccccc.", "cccccccc", ".ssssss."],
];
// [x in the 384-wide art, y from its top, shape]; the fire is on x 192.
const CLOUD_SPOTS = [[38, 14, 0], [112, 18, 1], [226, 13, 0], [298, 17, 1], [350, 14, 1], [150, 13, 1]];
const mix = (a, b, t) => "#" + hex(a).map((v, i) => Math.round(v + (hex(b)[i] - v) * t).toString(16).padStart(2, "0")).join("");
// Day pines: a shadow side, a side lit by the sun from the right, a dark
// band under each tier, a lit tip on each tier's right, a trunk, and a
// hazier far tree line along the hills' crest.
function dayTrees(L) {
  const far = mix(L.pines, L.hills, 0.55);
  return { mid: L.pines, deep: mix(L.pines, "#0b0a12", 0.42), lit: mix(L.pines, "#e8f0a0", 0.2),
    tip: mix(L.pines, "#f0f4c0", 0.38), far, farLit: mix(far, L.crest, 0.6), trunk: mix("#3a2518", L.hills, 0.2),
    snowLit: L.snow.ground, snowShade: L.snow.dusk };
}
// Night pines: the old silhouette colour, a darker shadow side and under
// each tier, a faint cool rim of moonlight on the right, the fire's warmth
// on the lower branches facing it (fading out 80 columns away), and a far
// tree line barely lighter than the hills.
const NIGHT_TREES = { mid: "#090a18", deep: "#05060e", lit: "#11142c", tip: "#181c38", far: "#0c0d22", farLit: "#101230",
  trunk: "#120c10", warm: "#2c1b17", snowLit: "#3e4058", snowShade: "#262838" };

function backdrop(look, winter) {
  const night = look === NIGHT, L = look;
  const img = image(FILE_W, FILE_H);
  const ox = (FILE_W - BACK_W) / 2, oy = FILE_H - BACK_H;
  const W = BACK_W, H = BACK_H;
  const put = (x, y, color) => set(img, ox + x, oy + y, color);
  const rect = (x, y, w, h, color) => { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) put(x + i, y + j, color); };
  const cx = W / 2, horizon = H - 13;
  const sky = L.sky;
  // The file's rows above the art carry on the top colour.
  for (let y = 0; y < oy; y++) for (let x = 0; x < FILE_W; x++) set(img, x, y, sky[0]);
  for (let y = 0; y < horizon; y++) for (let x = 0; x < W; x++) {
    const f = (y / horizon) * (sky.length - 1), i = Math.floor(f), d = f - i;
    put(x, y, sky[Math.min(sky.length - 1, i + (d > BAYER[y % 4][x % 4] ? 1 : 0))]);
  }
  if (night) {
    for (let i = 0; i < W * 0.28; i++) {
      const x = Math.floor(rnd(i + 1) * W), y = Math.floor(rnd(i + 50) * (horizon - 8));
      put(x, y, rnd(i + 9) > 0.8 ? "#fff3c4" : rnd(i + 3) > 0.5 ? "#7d7f9e" : "#4a4c6e");
    }
    for (const [dx, dy, w] of [[2, 0, 4], [1, 1, 3], [0, 2, 3], [0, 3, 3], [0, 4, 3], [1, 5, 3], [2, 6, 4]]) {
      rect(Math.floor(W * 0.83) + dx, 4 + dy, w, 1, "#d8d4c4");
    }
  }
  if (L.clouds) {
    for (const [x, y, k] of CLOUD_SPOTS) {
      CLOUDS[k].forEach((row, j) => [...row].forEach((ch, i) => { if (ch !== ".") put(x + i, y + j, L.clouds[ch]); }));
    }
  }
  const hill = (x) => 7 + Math.round(3 * Math.sin(x * 0.05) + 2 * Math.sin(x * 0.13 + 1));
  for (let x = 0; x < W; x++) {
    const h = hill(x);
    rect(x, horizon - h, 1, h, L.hills);
    if (L.crest) put(x, horizon - h, L.crest);
  }
  const T = night ? NIGHT_TREES : dayTrees(L);
  const b = (x, y) => BAYER[(y + 64) % 4][(x + 64) % 4];
  for (let x = 2, i = 0; x < W; x += 3 + Math.floor(rnd(i + 300) * 3), i++) {
    const h = 3 + Math.floor(rnd(i + 310) * 4), base = horizon - hill(x) + 2;
    for (let y = 0; y < h; y++) {
      const w = Math.floor((y + 1) * 0.6);
      for (let k = -w; k <= w; k++) put(x + k, base - h + y, k > 0 && b(x + k, y) < 0.6 ? T.farLit : T.far);
    }
  }
  const pine = (x, h, seed) => {
    const top = horizon - h, tier = 4 + Math.floor(rnd(seed) * 2);
    put(x, top - 1, winter ? T.snowLit : T.mid);
    const warmth = T.warm ? Math.max(0, 1 - Math.abs(x - cx) / 80) : 0, toFire = Math.sign(cx - x);
    let aboveL = 0, aboveR = 0;
    for (let y = 0; y < h; y++) {
      const inTier = y % tier, row = top + y;
      const w = Math.floor((inTier + y * 0.55) * 0.62) + 1;
      const wl = w - (inTier === tier - 1 || rnd(seed + y * 1.3) > 0.7 ? 0 : 1);
      const wr = w - (inTier === tier - 1 || rnd(seed + y * 2.1) > 0.75 ? 0 : 1);
      for (let k = -wl; k <= wr; k++) {
        const u = k / Math.max(1, w), d = b(x + k, row);
        let c = T.mid;
        if (u > 0.3 && (u - 0.3) / 0.7 > d * 0.85) c = T.lit;
        else if (u < -0.25 && (-u - 0.25) / 0.75 > d * 0.8) c = T.deep;
        if (inTier <= 1 && y > 2 && Math.abs(k) < w - 1 && !(u > 0.5 && d < 0.4)) c = T.deep;
        if (inTier === tier - 1 && k === wr && w > 1) c = T.tip;
        if (warmth && Math.sign(k) === toFire && Math.abs(u) > 0.45 && y > h * 0.35 && d < warmth * 0.9) c = T.warm;
        const exposed = y === 0 || k < -aboveL || k > aboveR;
        if (winter && exposed && d < 0.8) c = k >= 0 ? T.snowLit : T.snowShade;
        put(x + k, row, c);
      }
      aboveL = wl; aboveR = wr;
      if (inTier === tier - 1 && w > 2 && rnd(seed + y * 3.7) > 0.5) put(x - wl - 1, row + 1, T.deep);
    }
    rect(x, horizon - 1, 1, 3, T.trunk);
  };
  for (let i = 0; i < W / 9; i++) {
    const x = Math.floor(i * 9 + rnd(i + 20) * 7), far = Math.abs(x - cx) < 30;
    if (far && rnd(i) > 0.3) continue;
    pine(x, 12 + Math.floor(rnd(i + 70) * (far ? 5 : 11)), i * 13.7 + 5);
  }
  const glow = ["#141019", "#201619", "#35231a", "#573518", "#7a4c18"];
  for (let y = horizon; y < H; y++) for (let x = 0; x < W; x++) {
    const dx = (x - cx) / 52, dy = (y - (H - 5)) / 9, d = Math.sqrt(dx * dx + dy * dy), bayer = BAYER[y % 4][x % 4];
    if (night) {
      const v = Math.max(0, 1 - d) * (glow.length - 1), i = Math.floor(v);
      put(x, y, glow[Math.min(glow.length - 1, i + (v - i > bayer ? 1 : 0))]);
      continue;
    }
    const f = (y - horizon) / (H - horizon - 1);
    let c = L.ground[f > bayer ? 1 : 0];
    const g = 1 - d / L.glowReach;
    if (g > 0) {
      const v = g * L.glow.length, i = Math.floor(v), k = i + (v - i > bayer ? 1 : 0);
      if (k > 0) c = L.glow[Math.min(L.glow.length - 1, k - 1)];
    }
    put(x, y, c);
  }
  return winter ? withSnow(img, L.snow, !night) : img;
}

// Winter's ground: snow away from the fire's glow, by how far each spot is
// from the fire (0 at the fire, 1 well clear), solid a way out and
// dithered where it meets the glow, darker at the top. By night a dithered
// far-tone edge runs along the horizon; by day that edge read as a rail
// through the scene, so it's dropped and the ground row under it is
// snowed too.
const HORIZON_ROW = 12;
function withSnow(back, snow, day) {
  const img = { width: back.width, height: back.height, pixels: Uint8Array.from(back.pixels) };
  const fire = FILE_W / 2;
  const clear = (x, row) => {
    const dx = (x - fire) / 52, dy = (row - 4) / 9;
    return Math.min(1, Math.max(0, (Math.sqrt(dx * dx + dy * dy) - 0.55) / 0.45));
  };
  const lit = (x, y) => img.pixels[(y * img.width + x) * 4 + 3] > 0;
  for (let x = 0; x < img.width; x++) {
    const bayer = (y) => BAYER[y % 4][x % 4];
    const top = FILE_H - 1 - HORIZON_ROW;
    if (!day && lit(x, top) && bayer(top) < clear(x, HORIZON_ROW)) set(img, x, top, snow.far);
    for (let row = 0; row < HORIZON_ROW - (day ? 0 : 1); row++) {
      const y = FILE_H - 1 - row, k = clear(x, row);
      if (!lit(x, y) || k <= 0 || bayer(y) >= k) continue;
      set(img, x, y, row >= HORIZON_ROW - 3 && bayer(y) < k - 0.5 ? snow.dusk : snow.ground);
    }
  }
  return img;
}

// The Pocket Camp's backdrop: the backdrop's bottom POCKET_H rows round
// the fire, with soft edges so it doesn't sit on the game world as a hard
// rectangle. A rounded shape, solid in the middle and dithered away towards
// its rim. The Pocket Camp grows wider with the Crew online, so the file
// holds one band per width, POCKET_W, POCKET_W + POCKET_STEP and so on up
// to POCKET_MAX_W, top to bottom, each POCKET_BAND rows high with its art
// at the band's bottom and the fire on column POCKET_FILE_W / 2. A wider
// band is the narrowest's ends with a stretch of solid middle between
// them. POCKET_W, POCKET_MAX_W, POCKET_STEP and POCKET_H are Core's
// pocketColumns, pocketMaxColumns, pocketStep and pocketRows
// (Core/Camp.lua).
const POCKET_W = 112, POCKET_MAX_W = 304, POCKET_STEP = 32, POCKET_H = 34;
const POCKET_BAND = 36, POCKET_FILE_W = 512, POCKET_FILE_H = 256;
const POCKET_WIDTHS = [];
for (let w = POCKET_W; w <= POCKET_MAX_W; w += POCKET_STEP) POCKET_WIDTHS.push(w);
if (POCKET_WIDTHS.length * POCKET_BAND > POCKET_FILE_H || POCKET_MAX_W > BACK_W) throw new Error("pocket bands don't fit");
function pocketBackdrop(back) {
  const img = image(POCKET_FILE_W, POCKET_FILE_H);
  // How round the ends are (2 is an ellipse, higher is squarer), how much
  // of the way in from an end the fade takes (of the narrowest's half
  // width), the row its middle is on, and how far out the bottom row
  // counts: the ground under the figures stays mostly solid.
  const round = 4, fade = 0.22, middle = 20, bottom = 0.86, half = POCKET_W / 2;
  POCKET_WIDTHS.forEach((width, band) => {
    const fromX = FILE_W / 2 - width / 2, fromY = FILE_H - POCKET_H;
    const toX = POCKET_FILE_W / 2 - width / 2, toY = (band + 1) * POCKET_BAND - POCKET_H;
    for (let j = 0; j < POCKET_H; j++) for (let i = 0; i < width; i++) {
      const end = Math.min(i + 0.5, width - i - 0.5);
      const u = Math.max(0, 1 - end / half), y = j + 0.5;
      const v = y < middle ? (middle - y) / middle : (y - middle) / (POCKET_H - middle) * bottom;
      const d = Math.pow(Math.pow(u, round) + Math.pow(v, round), 1 / round);
      if ((1 - d) / fade <= BAYER[j % 4][i % 4]) continue;
      const from = ((fromY + j) * back.width + fromX + i) * 4, to = ((toY + j) * img.width + toX + i) * 4;
      img.pixels.set(back.pixels.subarray(from, from + 4), to);
    }
  });
  return img;
}

// The fire's light on the panel under the band (docs/design/camp.md,
// Firelight): the fire's orange, strongest at the middle of the top edge,
// where the fire is, and fading out in a half ellipse. Smooth, not
// dithered: it's light falling on the window, not art. UI draws it added
// to what's under it, at a low alpha.
const LIGHT_W = 256, LIGHT_H = 128, LIGHT_FALLOFF = 1.6;
function light() {
  const img = image(LIGHT_W, LIGHT_H);
  const [r, g, b] = hex(PAL.O);
  for (let y = 0; y < LIGHT_H; y++) for (let x = 0; x < LIGHT_W; x++) {
    const u = (x + 0.5) / (LIGHT_W / 2) - 1, v = (y + 0.5) / LIGHT_H;
    const d = Math.min(1, Math.hypot(u, v));
    img.pixels.set([r, g, b, Math.round(255 * Math.pow(1 - d, LIGHT_FALLOFF))], (y * LIGHT_W + x) * 4);
  }
  return img;
}

// The Dungeons tab's dithered bar fills, in the Camp's pixel language:
// white, tiled and tinted. Dither50 is a checker (a bar ahead of you),
// Dither25 one pixel in four (one you've outlevelled). A texel is one art
// pixel; the tab tiles them at the Camp's art unit.
const DITHER = 8;
function dither(on) {
  const img = image(DITHER, DITHER);
  for (let y = 0; y < DITHER; y++)
    for (let x = 0; x < DITHER; x++)
      if (on(x, y)) img.pixels.set([255, 255, 255, 255], (y * DITHER + x) * 4);
  return img;
}

// The empty states' vignettes (DESIGN.md, Empty states; chosen in #239):
// one small scene per empty tab, and the alone state's. Every one is the
// same VIGNETTE_W x VIGNETTE_H, its subject inside a ~24 x 14 box standing
// on one ground line (VIGNETTE_BASE), outlined like the Pocket Camp's tools
// (light sources, fire and moon, aren't), lit from the left, on a dithered
// patch of ground: cool everywhere, warm only under a fire. Each is a list
// of frames and how many ticks of the band's 6 a second each holds; one
// frame is still. Packed into Media/EmptyStates.tga.
const VIGNETTE_W = 40, VIGNETTE_H = 22, VIGNETTE_BASE = 19;
// The ground's tones, on top of PAL: v w x the backdrop's firelit glow,
// g h a cool unlit ground just lighter than the window, so outlines read.
const VIGNETTE_PAL = { ...PAL, v: "#201619", w: "#35231a", x: "#573518", g: "#17151e", h: "#211e29" };
const COOL = ["h", "g"], WARM = ["x", "w", "v"];

// A small painter: everything ends as row strings.
function canvas(w, h) {
  const px = Array.from({ length: h }, () => Array(w).fill("."));
  const c = {
    set(x, y, ch) {
      x = Math.round(x); y = Math.round(y);
      if (x >= 0 && y >= 0 && x < w && y < h && ch && ch !== ".") px[y][x] = ch;
      return c;
    },
    stamp(rows, x, y) { rows.forEach((r, j) => [...r].forEach((ch, i) => c.set(x + i, y + j, ch))); return c; },
    line(x0, y0, x1, y1, ch) {
      const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
      for (let k = 0; k <= n; k++) c.set(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n, ch);
      return c;
    },
    // A patch of ground: an ellipse, dithered from the first tone (middle)
    // to the last (edge).
    ground(cx, cy, rx, ry, tones) {
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry, d = Math.sqrt(dx * dx + dy * dy);
        if (d > 1) continue;
        const v = (1 - d) * tones.length, i = Math.floor(v), f = v - i;
        const k = Math.min(tones.length - 1, i + (f > BAYER[y % 4][x % 4] ? 1 : 0));
        if (k <= 0 && d > 0.92 && BAYER[y % 4][x % 4] > 0.5) continue;
        c.set(x, y, tones[tones.length - 1 - Math.min(tones.length - 1, k)]);
      }
      return c;
    },
    rows() { return px.map((r) => r.join("")); },
  };
  return c;
}
const scene = (tones, cx = 20, rx = 15) => canvas(VIGNETTE_W, VIGNETTE_H).ground(cx, VIGNETTE_BASE + 0.6, rx, 2.6, tones);
// An outlined sprite standing on the ground line, centred on cx; drop
// sinks it that many rows.
const stand = (c, rows, cx, drop = 0) => c.stamp(rows, Math.round(cx - rows[0].length / 2), VIGNETTE_BASE + 1 + drop - rows.length + 1);
const STONE = outlined([".TT.", "TZTt", "Tttt"]);
const STONE_S = outlined(["TZ", "tt"]);
const EMBER_HEAP = [
  ["....R..O....", "..RROGOGRR..", ".ROOGYGOOOR.", "RROGOOGORORR"],
  ["......R.....", "..RRGOOORR..", ".ROGOGYGOOR.", "RROOGOOGORRR"],
  [".....O..R...", "..RROOGORR..", ".ROOGOGYOOR.", "RRGOOGOORORR"],
];

const VIGNETTES = {
  // The Feed: a fire burned down, charred logs with their cracks still
  // glowing in a ring of stones, one thread of smoke going up.
  feed() {
    const charred = outlined(["..BB.......BB..", ".BBRBb...bBRBB.", "BBBBBBRBBBBBBBb", ".bbbbbbbbbbbbb."]);
    const frames = [0, 1, 2, 3, 4, 5].map((f) => {
      const c = scene(WARM, 20, 16);
      stand(c, STONE, 8); stand(c, STONE, 32); stand(c, STONE_S, 11, 1); stand(c, STONE_S, 29, 1);
      stand(c, charred, 20);
      c.stamp(EMBER_HEAP[f % 3], 14, 13);
      // A pixel on every row so it reads as a line, swaying more as it
      // rises, thinning out at the top.
      for (let y = 12; y >= 2; y--) {
        const k = 12 - y, x = 20 + Math.round(Math.sin(k * 0.55 - f * 0.8) * (0.3 + k * 0.16));
        if (y <= 4 && (y + f) % 2) continue;
        c.set(x, y, k < 4 ? "T" : "t");
      }
      if (f === 2) c.set(23, 9, "O");
      return c.rows();
    });
    return { frames, hold: 1 };
  },
  // Trophies: a wooden stand with the Pocket Camp's cup missing from it,
  // only its outline in dim brass where it will stand.
  trophies() {
    const stand_ = outlined([
      "AAAAAAAAAAAAAAAAAAAa", "aaaaaaaaaaaaaaaaaaaa", ".Aa..............Aa.", ".Aa..............Aa.",
      ".AAAAAAAAAAAAAAAAAa.", ".Aa..............Aa.", ".Aa..............Aa.",
    ]);
    const ghost = TROPHY_CUP.map((r) => [...r].map((ch) => (ch === "K" ? "a" : ".")).join(""));
    const c = scene(COOL);
    stand(c, stand_, 20);
    c.stamp(ghost, 14, 12 - ghost.length + 2);
    return { frames: [c.rows()], hold: 1 };
  },
  // Play times: an hourglass under a crescent moon, the top bulb still
  // full, a grain falling, a small pile below.
  playTimes() {
    const glass = (grain) => outlined([
      "AAAAAAAAAAAAa", "aaaaaaaaaaaaa", ".Z.FYGGGGf.t.", ".Z.FYGGGGf.t.", ".Z..FGGGf..t.", ".Z...FGf...t.", ".Z....G....t.",
      grain === 0 ? ".Z...FGf...t." : ".Z...F.f...t.", grain === 1 ? ".Z..F.G.f..t." : ".Z..F...f..t.",
      ".Z.F..G..f.t.", ".Z.F.GGG.f.t.", "AAAAAAAAAAAAa", "aaaaaaaaaaaaa",
    ]);
    const moon = [".NNN.", "NNW..", "NW...", "NW...", "NNW..", ".NNN."];
    const frames = [0, 1, 2].map((grain) => {
      const c = scene(COOL);
      c.stamp(moon, 7, 3);
      stand(c, glass(grain), 20);
      c.set(31, 4, "Z").set(28, 1, "t").set(34, 9, grain === 0 ? "W" : "Z");
      return c.rows();
    });
    return { frames, hold: 2 };
  },
  // Spare Items: the Pocket Camp's crate, emptied: open, dark inside, its
  // lid leaning against its side.
  spares() {
    const crate = outlined([
      ".aaaaaaaaaaaa.", "abbbbbbbbbbbba", "abbbbbbbbbbbba", "AAAAAAAAAAAAAa",
      "AAaaaaAAaaaaAa", "AAaaaaAAaaaaAa", "AAaaaaAAaaaaAa", "AAAAAAAAAAAAAa",
    ]);
    const lid = outlined(["AAa....", "AAAa...", ".AAa...", ".AAAa..", "..AAa..", "..AAAa.", "...AAa.", "...AAAa", "....AAa"]);
    const c = scene(COOL);
    stand(c, crate, 18);
    c.stamp(lid, 24, VIGNETTE_BASE + 1 - lid.length + 1);
    return { frames: [c.rows()], hold: 1 };
  },
  // Professions: an anvil on a stump, a hammer propped by it. Cold:
  // nobody's working it.
  professions() {
    const raw = canvas(16, 12).stamp([
      "....NZZZZZZZZZZt", "NZZZZZZZZZZZZZZt", "..ZZZZZZZZZZZZZt", "....tTTTTTTTTtt.",
      ".......TTTt.....", ".......TTTt.....", ".....TTTTTTTt...", "....tttttttttt..",
    ], 0, 0).stamp([".aAAAAAAAAAAAAa.", "BBBBbBBBBBBbBBBb", "BbBBbBBBBBBbBBbb", ".bbbbbbbbbbbbbb."], 0, 8);
    const c = scene(COOL);
    stand(c, outlined(raw.rows()), 18);
    stand(c, HAMMER, 30);
    return { frames: [c.rows()], hold: 1 };
  },
  // Catches: a rod propped on a forked stick on the bank, its line down to
  // a bobber in a pond that fades out at its edges, a ring spreading.
  catches() {
    const rod = canvas(VIGNETTE_W, VIGNETTE_H);
    rod.line(2, 18, 24, 6, "B").line(22, 7, 24, 6, "A");
    rod.line(9, 19, 9, 16, "a").set(8, 15, "a").set(10, 15, "a");
    const rodRows = outlined(rod.rows()).slice(1, VIGNETTE_H + 1).map((r) => r.slice(1, VIGNETTE_W + 1));
    const frames = [0, 1, 2].map((r) => {
      const c = scene(COOL, 18, 17);
      c.ground(27, VIGNETTE_BASE + 0.2, 12, 2.4, ["f", "f", "h"]);
      [[22, 18], [31, 19], [26, 20]].forEach(([x, y], i) => c.set(x + ((r + i) % 3) - 1, y, "F"));
      c.line(15, 19, 15, 16, "A").line(17, 19, 17, 17, "a").line(37, 19, 37, 17, "a");
      c.stamp(rodRows, 0, 0);
      const bob = r === 2 ? 1 : 0;
      c.line(24, 6, 28, 17 + bob, "Z");
      c.set(28, 17 + bob, "R").set(28, 16 + bob, "W");
      c.set(28 - 2 - r, 18, "F").set(28 + 2 + r, 18, "F");
      return c.rows();
    });
    return { frames, hold: 2 };
  },
  // The alone state: a log by the fire with nobody on it.
  alone() {
    const log = outlined([".BBBBBBBBBBBBBAAa.", "BBBbBBBBBbBBBAaaAa", "BbBBBBBbBBBBBAaAaA", ".bbbbbbbbbbbbbaaa."]);
    const frames = [0, 1, 2].map((f) => {
      const c = scene(WARM, 16, 18);
      c.stamp(LOGS, 4, 17).stamp(FIRE[f], 6, 6);
      stand(c, log, 30); stand(c, STONE_S, 2, 1); stand(c, STONE_S, 20, 1);
      c.set(11 + (f - 1), 3, f === 1 ? "G" : "R");
      return c.rows();
    });
    return { frames, hold: 1 };
  },
};

// Packs every vignette's frames in rows across a 256-wide file, each cell
// with a 1-pixel gutter on every side.
const VIGNETTE_FILE_W = 256;
function vignetteSheet() {
  const cellW = VIGNETTE_W + 2, cellH = VIGNETTE_H + 2, across = Math.floor(VIGNETTE_FILE_W / cellW);
  const art = [];
  let n = 0;
  for (const [name, make] of Object.entries(VIGNETTES)) {
    const { frames, hold } = make();
    const cells = frames.map((rows) => {
      const x = (n % across) * cellW + 1, y = Math.floor(n / across) * cellH + 1;
      n++;
      return { rows, x, y };
    });
    art.push({ name, hold, cells });
  }
  let height = 1;
  while (height < Math.ceil(n / across) * cellH) height *= 2;
  const img = image(VIGNETTE_FILE_W, height);
  for (const { cells } of art) for (const { rows, x, y } of cells) {
    rows.forEach((row, j) => [...row].forEach((ch, i) => set(img, x + i, y + j, VIGNETTE_PAL[ch])));
  }
  return { img, art };
}

const { img, placed } = sheet();
writeFileSync(join(root, "Media", "CampSprites.tga"), tga(img));
for (const [name, look, winter] of [
  ["", NIGHT, false], ["Winter", NIGHT, true], ["Day", DAY, false], ["DayWinter", DAY, true],
]) {
  const back = backdrop(look, winter);
  writeFileSync(join(root, "Media", `CampBackdrop${name}.tga`), tga(back));
  writeFileSync(join(root, "Media", `CampPocketBackdrop${name}.tga`), tga(pocketBackdrop(back)));
}
writeFileSync(join(root, "Media", "CampLight.tga"), tga(light()));
writeFileSync(join(root, "Media", "Dither50.tga"), tga(dither((x, y) => (x + y) % 2 === 0)));
writeFileSync(join(root, "Media", "Dither25.tga"), tga(dither((x, y) => x % 2 === 0 && y % 2 === 0)));
const vignettes = vignetteSheet();
writeFileSync(join(root, "Media", "EmptyStates.tga"), tga(vignettes.img));

const luaColor = (color) => hex(color).map((v) => +(v / 255).toFixed(3)).join(", ");
const skyColor = (look) => luaColor(look.sky[0]);
// A Camp name sits on a tag in the outline's black, with a lighter lip along its top.
const NAME_TAG = { fill: PAL.K, lip: "#1d1a26" };
const lines = placed.map((s) => `    ${s.name} = { ${s.x}, ${s.y}, ${s.w}, ${s.h} },`);
const vignetteLines = vignettes.art.map((v) =>
  `      ${v.name} = { hold = ${v.hold}, ${v.cells.map((c) => `{ ${c.x}, ${c.y} }`).join(", ")} },`);
writeFileSync(join(root, "UI", "CampSheet.lua"), `local _, ns = ...

ns.CampSheet = {
  file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampSprites",
  width = ${img.width},
  height = ${img.height},
  sprites = {
${lines.join("\n")}
  },
  backdrop = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampBackdrop",
    seasons = { winter = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampBackdropWinter" },
    day = {
      file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampBackdropDay",
      seasons = { winter = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampBackdropDayWinter" },
    },
    width = ${FILE_W},
    height = ${FILE_H},
    fire = ${FILE_W / 2},
  },
  pocketBackdrop = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampPocketBackdrop",
    seasons = { winter = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampPocketBackdropWinter" },
    day = {
      file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampPocketBackdropDay",
      seasons = { winter = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampPocketBackdropDayWinter" },
    },
    width = ${POCKET_FILE_W},
    height = ${POCKET_FILE_H},
    fire = ${POCKET_FILE_W / 2},
    band = ${POCKET_BAND},
    columns = ${POCKET_W},
    step = ${POCKET_STEP},
  },
  light = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampLight",
    width = ${LIGHT_W},
    height = ${LIGHT_H},
  },
  dither = {
    half = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\Dither50",
    quarter = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\Dither25",
    size = ${DITHER},
  },
  vignettes = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\EmptyStates",
    width = ${vignettes.img.width},
    height = ${vignettes.img.height},
    columns = ${VIGNETTE_W},
    rows = ${VIGNETTE_H},
    art = {
${vignetteLines.join("\n")}
    },
  },
  hats = {
${HATS.map((hat) => `    ${hat.key} = { sprite = "${hatSprite(hat.key)}", brow = ${hat.brow} },`).join("\n")}
  },
  pets = {
${Object.keys(PETS).map((key) => `    ${key} = { awake = "${petSprite(key)}", idle = "${petSprite(key, "Idle")}", asleep = "${petSprite(key, "Asleep")}" },`).join("\n")}
  },
  fishing = {
    core = { ${POND_CORE[0]}, ${POND_CORE[1]} },
    reach = ${POND_REACH},
    ponds = ${POND_GLINTS.length},
    line = ${FISH_LINE_X},
    ripple = { x = ${FISH_LINE_X - (RIPPLES[0].length - 1) / 2}, row = 1 },
    ripples = ${RIPPLES.length},
  },
  working = {
${Object.entries(WORK_FRAMES).map(([pose, frames]) => `    ${pose} = {
      reach = { fore = ${WORK_REACH[pose].fore}, aft = ${WORK_REACH[pose].aft} },
${frames.map((frame) => `      { body = "${frame.body}"${WORK_SLOTS.filter((slot) => frame[slot]).map((slot) => {
    const [name, u, row] = frame[slot];
    return `, ${slot} = { "${name}", ${u}, ${row} }`;
  }).join("")} },`).join("\n")}
    },`).join("\n")}
  },
  winter = {
    bedSnow = ${BED_SNOW.x},
    tentLights = { ${TENT_LIGHTS.map(([x, y]) => `{ ${x}, ${tent().length - 1 - y} }`).join(", ")} },
    lights = ${LIGHTS.length},
  },
  sky = { night = { ${skyColor(NIGHT)} }, day = { ${skyColor(DAY)} } },
  nameTag = { fill = { ${luaColor(NAME_TAG.fill)} }, lip = { ${luaColor(NAME_TAG.lip)} } },
}
`);
console.log(`CampSprites ${img.width}x${img.height}, ${placed.length} sprites; CampBackdrop ${FILE_W}x${FILE_H}; EmptyStates ${vignettes.img.width}x${vignettes.img.height}`);
