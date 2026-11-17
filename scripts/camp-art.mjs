// Builds the Camp's art from pixel grids: Media/CampSprites.tga (every
// sprite, a 1-pixel transparent gutter round each cell),
// Media/Dither50.tga and Media/Dither25.tga (the Dungeons tab's bar fills),
// Media/CampBackdrop.tga (the static night sky, hills, pines and the fire's
// glow on the ground), Media/CampPocketBackdrop.tga (the Pocket Camp's
// soft-edged piece of it), Media/CampLight.tga (the fire's light on the
// window under the band) and UI/CampSheet.lua (where each sprite sits). The
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
// The Pocket Camp's poses and one-off animations (docs/design/pocket-camp.md).
// A fishing rod held out from a seated figure's hand, its line and bobber
// hanging from the tip; drawn mirrored on the fire's right.
const ROD = [".....B.", "....B.Z", "....B.Z", "...B..Z", "...B..Z", "..B...Z", "..B...Z", ".B....Z", ".B....R", "B......"];
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

// What a Member is doing, for the Pocket Camp (docs/design/pocket-camp.md).
// Held in a standing figure's raised hand: a blade (fighting), a torch (in
// a dungeon or raid), a hammer (crafting) and a pick (gathering).
const BLADE = outlined(["..W..", ".WZt.", ".WZt.", ".WZt.", ".WZt.", ".WZt.", ".WZt.", "GGGGG", "..B..", "..G.."]);
const TORCH = outlined(["..R..", ".RO..", ".ROR.", "ROYOR", "ROYOR", ".OGO.", ".aAa.", "..A..", "..A..", "..a.."]);
const HAMMER = outlined(["ZZZZZt", "ZNZZZt", "ZZZZZt", "..Aa..", "..Aa..", "..Aa..", "..Aa..", "..Aa.."]);
const PICK = outlined(["..ZZZZZZ..", ".ZZtAatZZ.", "ZZ..Aa..ZZ", "Z...Aa...Z", "....Aa....", "....Aa....", "....Aa....", "....Aa...."]);
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

const SPRITES = [
  ["seatedCloth", cloth(SIT, CLOTH)], ["seated", skin(SIT)],
  ["hopCloth", cloth(HOP, CLOTH)], ["hop", skin(HOP)],
  ["asleepCloth", cloth(BED, BED_CLOTH)], ["asleep", skin(BED)],
  ["grave", skin(GRAVE)], ["flower", skin(FLOWER)], ["spark", skin(SPARK)],
  ["fire1", skin(FIRE[0])], ["fire2", skin(FIRE[1])], ["fire3", skin(FIRE[2])],
  ["logs", skin(LOGS)], ["seat", skin(SEAT)], ["sleep1", skin(SLEEP[0])], ["sleep2", skin(SLEEP[1])], ["sleep3", skin(SLEEP[2])],
  ["ember", skin(EMBER)], ["emberCool", skin(EMBER_COOL)], ["emberWarm", skin(EMBER_WARM)],
  ["glint", skin(GLINT)], ["glintPale", skin(GLINT_PALE)], ["petal", skin(PETAL)],
  ["tent", tent()],
  ["rod", skin(ROD)], ["star", skin(STAR)], ["fish", skin(FISH)],
  ["smoke1", skin(SMOKE[0])], ["smoke2", skin(SMOKE[1])], ["skeleton", skin(SKELETON)],
  ["flare1", paint(flare(FIRE[0]), FLARE_PAL)], ["flare2", paint(flare(FIRE[1]), FLARE_PAL)],
  ["flare3", paint(flare(FIRE[2]), FLARE_PAL)],
  ["blade", skin(BLADE)], ["torch", skin(TORCH)], ["hammer", skin(HAMMER)], ["pick", skin(PICK)], ["anvil", skin(ANVIL)],
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

const { img, placed } = sheet();
const back = backdrop();
writeFileSync(join(root, "Media", "CampSprites.tga"), tga(img));
writeFileSync(join(root, "Media", "CampBackdrop.tga"), tga(back));
writeFileSync(join(root, "Media", "CampPocketBackdrop.tga"), tga(pocketBackdrop(back)));
writeFileSync(join(root, "Media", "CampLight.tga"), tga(light()));
writeFileSync(join(root, "Media", "Dither50.tga"), tga(dither((x, y) => (x + y) % 2 === 0)));
writeFileSync(join(root, "Media", "Dither25.tga"), tga(dither((x, y) => x % 2 === 0 && y % 2 === 0)));

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
  -- The Pocket Camp's backdrop, soft-edged: the same, for its own file,
  -- which holds a band per width the Pocket Camp can be, top to bottom
  -- from \`columns\` in steps of \`step\`, each \`band\` texels high.
  pocketBackdrop = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampPocketBackdrop",
    width = ${POCKET_FILE_W},
    height = ${POCKET_FILE_H},
    fire = ${POCKET_FILE_W / 2},
    band = ${POCKET_BAND},
    columns = ${POCKET_W},
    step = ${POCKET_STEP},
  },
  -- The fire's light on the panel under the band, with the fire on the
  -- middle of its top edge.
  light = {
    file = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\CampLight",
    width = ${LIGHT_W},
    height = ${LIGHT_H},
  },
  -- The Dungeons tab's bar fills, white to tint, tiled: a texel is an art
  -- pixel.
  dither = {
    half = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\Dither50",
    quarter = "Interface\\\\AddOns\\\\BFF\\\\Media\\\\Dither25",
    size = ${DITHER},
  },
  -- The sky's top colour, above the backdrop's art.
  sky = { ${skyR}, ${skyG}, ${skyB} },
}
`);
console.log(`CampSprites ${img.width}x${img.height}, ${placed.length} sprites; CampBackdrop ${FILE_W}x${FILE_H}`);
