// The demos. Each is a script of cursor moves and news arriving; crop is the
// part of the 1920x1080 frame its GIF keeps. capture.mjs records them; open
// index.html to watch one, or pick "free play" and click around yourself.
const showPanel = (tab) => { S.tab = tab; $("#panel").hidden = false; if (tab === "together") { S.togInit = true; S.togX = lx(YOU_LEVEL) - 250; } render(); };
const moveCursor = (x, y) => { Cursor.x = x; Cursor.y = y; refreshHover(); };
const PANEL_CROP = [100, 0, 1560, 878];
const scrollFeed = (to, ms = 700) => { const from = S.feedScroll; return tween(ms, (t) => { S.feedScroll = from + (to - from) * t; $("#feedinner").style.transform = `translateY(${-S.feedScroll}px)`; placeThumb(); refreshHover(); }, easeInOut); };

const SCENES = {
  // Log in, see what you missed, react, and read the Feed.
  away: { title: "While you were away", crop: [240, 80, 1500, 844], async run() {
    $("#fade").style.opacity = 1;
    moveCursor(1300, 860);
    await fadeFrom(800);
    await wait(500);
    chat("Simone cheered your ding to 24.");
    await wait(500);
    $("#away").hidden = false; drawAway();
    await wait(1700);
    await moveTo('[data-key="max"]');
    await wait(900);
    await click('[data-key="max"]');
    await wait(500);
    await click('[data-key="sding"]');
    await wait(300);
    await click('[data-key="sdeath"]');
    await wait(900);
    await click("#openfeed");
    await wait(1800);
    await moveTo('[data-entry="sdeath"] .meta', 700);
    await wait(1100);
    await moveTo([1010, 640], 500);
    await scrollFeed(190);
    await wait(1200);
  } },

  // News arrives while you play; a toast takes one click to answer.
  toasts: { title: "Live toasts", crop: [900, 0, 1020, 574], async run() {
    moveCursor(1180, 520);
    await wait(900);
    toast({ kind: "ding", text: "Simone dinged 28", key: "t1", reaction: "cheer" });
    await wait(1100);
    await click('[data-key="t1"]');
    await wait(600);
    toast({ kind: "death", text: "Simbad died 2 times", key: "t2", reaction: "respects" });
    await wait(800);
    await moveTo('[data-key="t2"]');
    await wait(700);
    await click('[data-key="t2"]');
    await wait(700);
    toast({ kind: "maxLevel", text: "Simba reached max level!", key: "t3", reaction: "cheer", gold: true });
    await wait(700);
    await click('[data-key="t3"]');
    await wait(600);
    toast({ kind: "cheer", text: "Simone cheered your ding to 24" });
    await wait(2000);
    await moveTo("#mm");
    await wait(1800);
    await moveTo([1250, 520]);
    await wait(1800);
  } },

  // Everyone's whereabouts, by person, alts and all.
  roster: { title: "Roster", crop: PANEL_CROP, async run() {
    moveCursor(1320, 420);
    await wait(500);
    await click("#mm");
    await wait(1100);
    await moveTo('[data-row="simone"]');
    await wait(1800);
    await click('[data-row="simone"]');
    await wait(900);
    await moveTo(".alt:nth-of-type(n) .name");
    await wait(1200);
    await click('[data-row="simbad"]');
    await wait(1100);
    await click("#sort");
    await wait(600);
    await click('[data-item="Level"]');
    await wait(1500);
    await moveTo([1260, 700]);
    await wait(900);
    // Simba logs in.
    memberOf("simba").online = true;
    memberOf("simba").chars[0].playing = true;
    memberOf("simba").chars[0].zone = "Winterspring";
    render();
    await wait(2400);
  } },

  // One ding, and the Crew's bar crosses a rung. Nobody is ranked.
  goals: { title: "Crew goals", crop: PANEL_CROP, async run() {
    showPanel("goals");
    moveCursor(1240, 560);
    await wait(900);
    await moveTo('[data-tile="levels"]', 800);
    await wait(1000);
    toast({ kind: "ding", text: "Simone dinged 28", key: "g1", reaction: "cheer" });
    await wait(900);
    const levels = S.goals.tiles[0];
    levels.value = 150; levels.shown = 149 / 150;
    render();
    await tween(500, (t) => { $('[data-tile="levels"] .bar i').style.width = `${(149 / 150 + t / 150) * 100}%`; });
    await wait(450);
    const g = S.goals;
    g.latest = { icon: "achievement_level_20", text: "The Crew reached 150 Crew levels!", sub: "4 Nov" };
    g.total = 15;
    g.medals.unshift({ icon: "achievement_level_20", tier: "rare", value: "150", date: "4 Nov", fresh: true, tip: ["Crew levels", "150 · 4 Nov"] });
    Object.assign(levels, { value: 150, goal: 200, shown: undefined, cap: "3 reached · last 4 Nov" });
    render();
    toast({ kind: "goal", text: "The Crew reached 150 Crew levels!", gold: true });
    await wait(1600);
    await moveTo("#medal0");
    await wait(2000);
    await moveTo("#medal1");
    await wait(1700);
    await moveTo([1250, 720]);
    await wait(1400);
  } },

  // Offer an item, someone claims it, mail it, Give it.
  spares: { title: "Spares", crop: PANEL_CROP, async run() {
    showPanel("spares");
    moveCursor(1420, 930);
    await wait(700);
    await click("#claim-barb");
    await wait(1100);
    await moveTo([1400, 830], 500);
    holdItem(icon("inv_gauntlets_17"));
    UI.dropping = { id: "gloves", item: "Willow Gloves", color: "#1eff00", icon: "inv_gauntlets_17", level: 16, info: "30d left · No claims yet" };
    await wait(400);
    await click("#drop", 950);
    await wait(1000);
    const linen = S.spares.yours[0];
    linen.winner = "Simone"; linen.info = "30d left · Simone claimed it for Simone";
    render();
    toast({ kind: "claimed", text: "Simone claimed [Linen Cloth] for Simone", opens: "spares" });
    chat("Simone claimed [Linen Cloth] for Simone.");
    await wait(1700);
    await click("#give-linen");
    await wait(1300);
    await click("#yes");
    await wait(1800);
  } },

  // When does everyone actually play?
  when: { title: "Play times", crop: PANEL_CROP, async run() {
    showPanel("when");
    moveCursor(1250, 640);
    await wait(900);
    await moveTo('[data-cell="1-21"]');
    await wait(1500);
    await moveTo('[data-cell="5-15"]');
    await wait(1500);
    await click("#whenpick");
    await wait(700);
    await click('[data-item="Simone"]');
    await wait(900);
    await moveTo('[data-cell="2-7"]');
    await wait(1700);
    await click("#whenpick");
    await wait(600);
    await click('[data-item="You"]');
    await wait(1800);
    await moveTo([1250, 680]);
    await wait(700);
  } },

  // Who can craft what.
  professions: { title: "Professions", crop: PANEL_CROP, async run() {
    showPanel("professions");
    moveCursor(1250, 620);
    await wait(800);
    await moveTo('[data-tile="Simbad-10"]');
    await wait(1600);
    await moveTo('[data-tile="Simone-4"]');
    await wait(1400);
    await click("#ph10");
    await wait(1400);
    await click("#ph11");
    await wait(1500);
    await moveTo([1250, 640]);
    await wait(900);
  } },

  // Who can I play with, and where?
  together: { title: "Together", crop: PANEL_CROP, async run() {
    showPanel("together");
    moveCursor(1260, 640);
    await wait(900);
    await moveTo('[data-bar="Blackfathom Deeps"]');
    await wait(1800);
    await click('[data-friend="simone"]');
    await wait(1800);
    await click('[data-friend="simbad"]');
    await wait(1800);
    await moveTo('[data-bar="Shadowfang Keep"]');
    await wait(1500);
    await click(".toolbar [data-act=unpick]");
    await wait(600);
    await click("#togshow");
    await wait(500);
    await click('[data-item="Alts"]');
    await wait(900);
    const from = S.togX;
    await moveTo([1250, 700]);
    await tween(1800, (t) => { S.togX = from + (lx(60) + 90 - 500 - from) * t; $("#track").style.transform = `translateX(${-S.togX}px)`; $("#win").style.left = `${(S.togX / (lx(60) + 90)) * 100}%`; }, easeInOut);
    await wait(1200);
  } },

  card: { title: "Opening card", hidden: true, async run() {
    Cursor.shown = false; placeCursor();
    $("#card").hidden = false;
    $("#card").innerHTML = `<img src="../../assets/icon.png" alt=""><h1>Best Friends in Forever</h1><div class="braid"><i></i><b></b><i></i></div><p>Keep up with your friends in WoW: Forever, even when you play at different times.</p>`;
    await wait(3200);
  } },
};

async function start(name) {
  const scene = SCENES[name];
  applyFit();
  await document.fonts.ready;
  await Promise.all([...document.images].map((image) => image.decode().catch(() => {})));
  await preload();
  placeCursor();
  window.__ready = true;
  if (!scene) { $("#panel").hidden = false; render(); window.__done = true; return; }
  await scene.run();
  window.__done = true;
}
// Every icon up front, so nothing pops in on a captured frame.
function preload() {
  const names = new Set();
  const walk = (value) => {
    if (typeof value === "string") { if (/^[a-z_0-9]+$/.test(value) && /_/.test(value)) names.add(value); return; }
    if (value && typeof value === "object") Object.values(value).forEach(walk);
  };
  walk([PICTURES, REACTIONS, initialGoals(), initialSpares(), initialFeed(), PROFESSIONS, "inv_gauntlets_17"]);
  Object.keys(CLASS).forEach((c) => names.add(`classicon_${c.toLowerCase()}`));
  return Promise.all([...names].map((name) => { const image = new Image(); image.src = icon(name); return image.decode().catch(() => {}); }));
}

const chosen = params.get("scene") || "free";
if (capturing) {
  $("#picker").hidden = true;
  document.body.style.cursor = "none";
} else {
  const links = [["free", "free play"], ...Object.entries(SCENES).filter(([, s]) => !s.hidden).map(([id, s]) => [id, s.title])];
  $("#picker").innerHTML = links.map(([id, label]) => `<a class="${id === chosen ? "on" : ""}" href="?scene=${id}">${label}</a>`).join("");
  live();
}
window.__scenes = Object.fromEntries(Object.entries(SCENES).map(([id, s]) => [id, { crop: s.crop, title: s.title }]));
start(chosen);
