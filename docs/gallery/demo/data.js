// The demo Crew: the simulator's names (Dev/Sim.lua), at Forever's levels.
// Picked so the addon's own rules come out right: Crew levels (each Member's
// highest, summed) is 149, one ding short of the 150 rung, and Simbadsson and
// Simone are within 3 levels of you ("can play"). Fiction, not real players.
const icon = (name) => `assets/icons/${name}.jpg`;
const CLASS = { MAGE: "#3fc7eb", WARRIOR: "#c69b6d", ROGUE: "#fff468", DRUID: "#ff7c0a", PRIEST: "#ffffff", WARLOCK: "#8788ee" };
const CLASS_NAME = { MAGE: "Mage", WARRIOR: "Warrior", ROGUE: "Rogue", DRUID: "Druid", PRIEST: "Priest", WARLOCK: "Warlock" };
const YOU_LEVEL = 24;
const EDGES = { ding: "#70e370", maxLevel: "#ffd14a", goal: "#ffd14a", death: "#f2665c", newCharacter: "#66bfff", joined: "#66bfff",
  left: "#9999a8", gave: "#c799ff", claimed: "#c799ff", given: "#c799ff", newProfession: "#e6b86b", cheer: "#70e370" };
const PICTURES = { ding: "spell_chargepositive", maxLevel: "achievement_level_80", goal: "achievement_general", death: "inv_misc_bone_humanskull_01",
  newCharacter: "inv_misc_groupneedmore", joined: "inv_misc_grouplooking", left: "ability_vanish", gave: "inv_misc_bag_08",
  claimed: "inv_misc_bag_08", given: "inv_letter_15", newProfession: "inv_misc_book_11", cheer: "inv_misc_missilesmall_red" };
const REACTIONS = {
  cheer: { icon: "inv_misc_missilesmall_red", name: "Cheer" },
  respects: { icon: "inv_misc_flower_04", name: "Pay respects" },
  welcome: { icon: "achievement_reputation_01", name: "Welcome" },
};

const initialMembers = () => [
  { id: "you", display: "Gahzuria", own: true, online: true, chars: [
    { name: "Gahzuria", cls: "MAGE", level: 24, zone: "Nightsong Woods", xp: 0.62, deaths: 3, gold: "12g 40s", main: true, playing: true },
  ] },
  { id: "simbad", display: "Simbad", online: true, chars: [
    { name: "Simbadsson", cls: "WARRIOR", level: 25, zone: "Wetlands", xp: 0.34, deaths: 6, gold: "8g 12s", main: true, playing: true },
    { name: "Simbad", cls: "ROGUE", level: 38, zone: "Redridge Mountains", seen: "7m ago", deaths: 4 },
  ] },
  { id: "simone", display: "Simone", online: true, chars: [
    { name: "Simone", cls: "MAGE", level: 27, zone: "Westfall", xp: 0.81, deaths: 5, gold: "21g 3s", main: true, playing: true },
    { name: "Simonette", cls: "PRIEST", level: 18, zone: "Darkshore", seen: "2d ago", deaths: 1 },
    { name: "Simonetta", cls: "WARLOCK", level: 5, zone: "Elwynn Forest", seen: "1h ago", deaths: 0 },
  ] },
  { id: "simba", display: "Simba", online: false, chars: [
    { name: "Simba", cls: "DRUID", level: 60, zone: "Teldrassil", seen: "7m ago", xp: 0, deaths: 2, gold: "63g 90s", main: true },
  ] },
];

const initialFeed = () => [
  { day: "TODAY" },
  { key: "max", kind: "maxLevel", text: "Simba reached max level!", time: "21:48", gold: true, reaction: "cheer", unseen: true },
  { key: "alt", kind: "newCharacter", text: "Simone has a new Character: Simonetta (Warlock)", time: "21:12", reaction: "cheer", unseen: true },
  { key: "sdeath", kind: "death", text: "Simone died 2 times", time: "20:57", reaction: "respects", unseen: true },
  { key: "sding", kind: "ding", text: "Simone dinged 27", time: "20:41", reaction: "cheer", reactors: ["Simbad"], unseen: true },
  { key: "bdeath", kind: "death", text: "Simbad's Alt Simbad died", time: "20:20", reaction: "respects", unseen: true },
  { key: "bding2", kind: "ding", text: "Simbad's Alt Simbad dinged 38", time: "20:06", reaction: "cheer", unseen: true },
  { key: "bding", kind: "ding", text: "Simbad dinged 25", time: "19:44", reaction: "cheer", reactors: ["Simone"], unseen: true },
  { day: "YESTERDAY" },
  { key: "you", kind: "ding", text: "You dinged 24", time: "23:02", own: true, reactors: ["Simone"], reaction: "cheer", noButton: true },
  { key: "goal", kind: "goal", text: "The Crew reached 100 Crew levels!", time: "22:37", gold: true },
  { key: "prof", kind: "newProfession", icon: "trade_tailoring", text: "You picked up Tailoring", time: "21:15", own: true },
  { key: "gave", kind: "gave", text: "Simbad gave Simone [Staff of Westfall]", time: "20:50" },
  { key: "joined", kind: "joined", text: "Simba joined the Crew", time: "19:31", gold: true, reaction: "welcome", reacted: true },
];

const AWAY = {
  noticed: [{ reaction: "cheer", text: "Simone cheered your ding to 24" }],
  intro: "7 things happened while you were away.",
  rows: [
    { cls: "WARRIOR", member: "Simbad", character: "Simbadsson", level: 25, from: 24, gained: "+1", cheer: "bding" },
    { label: "Alt Simbad", level: 38, from: 36, gained: "+2", deaths: 1, cheer: "bding2", respects: "bdeath" },
    { cls: "MAGE", member: "Simone", level: 27, from: 24, gained: "+3", deaths: 2, cheer: "sding", respects: "sdeath" },
    { label: "Alt Simonetta", level: 5, from: 0, gained: "new", cheer: "alt" },
    { cls: "DRUID", member: "Simba", level: 60, from: 46, gained: "+14", star: true, cheer: "max" },
  ],
};

const initialGoals = () => ({
  latest: { icon: "achievement_level_20", text: "The Crew reached 100 Crew levels!", sub: "3 Nov" },
  total: 14,
  medals: [
    { icon: "inv_misc_head_human_01", tier: "epic", value: "Deadmines", date: "3 Nov", tip: ["The Deadmines", "Cleared 3 Nov", "Simbad, Simone, You"] },
    { icon: "achievement_level_20", tier: "uncommon", value: "100", date: "3 Nov", tip: ["Crew levels", "100 · 3 Nov"] },
    { icon: "achievement_level_30", tier: "uncommon", value: "20", date: "2 Nov", tip: ["Everyone at level N", "20 · 2 Nov"] },
    { icon: "trade_fishing", tier: "rare", value: "Fishing", date: "1 Nov", tip: ["Every profession in the Crew", "Fishing · 1 Nov"] },
    { icon: "trade_herbalism", tier: "rare", value: "Herbalism", date: "31 Oct", tip: ["Every profession in the Crew", "Herbalism · 31 Oct"] },
    { icon: "inv_pick_02", tier: "uncommon", value: "1,000", date: "30 Oct", tip: ["Crew skill", "1,000 · 30 Oct"] },
    { icon: "achievement_level_20", tier: "uncommon", value: "50", date: "28 Oct", tip: ["Crew levels", "50 · 28 Oct"] },
  ],
  tiles: [
    { id: "levels", icon: "achievement_level_20", hue: "#70e370", title: "Crew levels", value: 149, goal: 150, cap: "2 reached · last 3 Nov" },
    { id: "everyone", icon: "achievement_level_30", hue: "#70e370", title: "Everyone at level 30", value: 24, goal: 30, cap: "2 reached · last 2 Nov" },
    { id: "deaths", icon: "inv_misc_bone_humanskull_01", hue: "#f2665c", title: "Crew deaths", value: 21, goal: 25, cap: "Not reached yet" },
    { id: "profs", icon: "inv_misc_book_11", hue: "#c799ff", title: "Every profession in the Crew", value: 9, goal: 12, cap: "9 reached · last 1 Nov" },
    { id: "skill", icon: "inv_pick_02", hue: "#c799ff", title: "Crew skill", value: 1584, goal: 2500, cap: "2 reached · last 30 Oct" },
    { id: "rank", icon: "inv_misc_note_06", hue: "#c799ff", title: "Everyone a Journeyman", value: 3, goal: 4, cap: "Not reached yet" },
  ],
});
const TIERS = { uncommon: "#1eff00", rare: "#3a9bff", epic: "#b55cf5", legendary: "#ff8000" };

// When: weeks played per day (0 Monday) and hour, out of the last 4.
function fill(grid, days, from, to, weeks) {
  for (const d of days) for (let h = from; h <= to; h++) grid[d][h % 24] = weeks;
}
function memberGrid(blocks) {
  const grid = Array.from({ length: 7 }, () => Array(24).fill(0));
  blocks.forEach((b) => fill(grid, ...b));
  return grid;
}
const PLAY = {
  you: memberGrid([[[0, 1, 2, 3, 4], 20, 23, 4], [[5, 6], 14, 18, 3]]),
  simbad: memberGrid([[[0, 1, 2, 3], 19, 22, 3], [[4], 21, 23, 2], [[6], 10, 14, 3], [[5], 15, 18, 2]]),
  // The early bird of the Crew: barely overlaps anyone on a weekday.
  simone: memberGrid([[[0, 1, 2, 3, 4], 6, 8, 3], [[5], 13, 17, 4], [[1, 3], 21, 22, 2], [[6], 15, 17, 2]]),
  simba: memberGrid([[[4, 5], 21, 23, 3], [[6], 15, 19, 3], [[2], 20, 22, 2]]),
};
const crewGrid = () => {
  const grid = Array.from({ length: 7 }, () => Array(24).fill(0));
  for (const member of Object.values(PLAY)) {
    member.forEach((row, d) => row.forEach((weeks, h) => { if (weeks >= 2) grid[d][h] += 1; }));
  }
  return grid;
};

const PROFESSIONS = [
  ["Alchemy", "trade_alchemy"], ["Blacksmithing", "trade_blacksmithing"], ["Enchanting", "trade_engraving"],
  ["Engineering", "trade_engineering"], ["Herbalism", "trade_herbalism"], ["Leatherworking", "inv_misc_armorkit_17"],
  ["Mining", "trade_mining"], ["Skinning", "inv_misc_pelt_wolf_01"], ["Tailoring", "trade_tailoring"],
  ["Cooking", "inv_misc_food_15"], ["Fishing", "trade_fishing"], ["First Aid", "spell_holy_sealofsacrifice"],
];
const SKILLS = {
  Gahzuria: { Enchanting: 87, Tailoring: 119, Cooking: 55, "First Aid": 85 },
  Simbad: { Blacksmithing: 162, Mining: 198, Cooking: 120, Fishing: 211 },
  Simone: { Alchemy: 140, Herbalism: 187, Fishing: 70, "First Aid": 150 },
  Simba: null,
};

const DUNGEONS = [
  ["Ragefire Chasm", 13, 18], ["Hall of Thanes", 13, 18, 1], ["Ruins of Lordaeron", 15, 20, 1], ["Wailing Caverns", 17, 24],
  ["The Deadmines", 17, 26], ["Shadowfang Keep", 22, 30], ["Blackfathom Deeps", 24, 32], ["The Stockade", 24, 32],
  ["Excavation Site", 24, 29, 1], ["SM Graveyard", 28, 38], ["City of Dalaran", 28, 33, 1], ["Gnomeregan", 29, 38],
  ["SM Library", 29, 39], ["Razorfen Kraul", 30, 40], ["SM Armory", 32, 42], ["SM Cathedral", 35, 45],
  ["The Drowned City", 35, 40, 1], ["Razorfen Downs", 40, 50], ["Krol'dok Stronghold", 40, 45, 1], ["Uldaman", 42, 52],
  ["Zul'Farrak", 44, 54], ["Maraudon", 46, 55], ["Alcaz Prison", 48, 53, 1], ["Sunken Temple", 50, 60],
  ["Blackrock Depths", 52, 60], ["Lower Blackrock Spire", 55, 60], ["Blackmaw Hold", 55, 60, 1], ["Dire Maul", 56, 60],
  ["Scholomance", 58, 60], ["Stratholme", 58, 60], ["Shaper's Terrace", 58, 60, 1],
].map(([name, from, to, forever]) => ({ name, from, to, forever: !!forever }));

const initialSpares = () => ({
  crew: [
    { id: "barb", item: "Cruel Barb", color: "#0070dd", icon: "inv_weapon_shortblade_05", level: 18, owner: "Simbad", state: "No claims yet", claimed: false },
  ],
  yours: [
    { id: "linen", item: "Linen Cloth", color: "#ffffff", icon: "inv_fabric_linen_01", level: 0, info: "30d left · No claims yet" },
  ],
});
