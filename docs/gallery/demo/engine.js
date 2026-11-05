// A virtual clock, so a scene plays the same live and when captured frame by
// frame. Nothing animates by CSS or real time: everything goes through
// wait() and tween(), and tick() moves them on. The cursor is the only input,
// real or scripted, so hover and clicks behave the same in both.
const Clock = { now: 0, timers: [], tweens: [], updates: [] };

function after(ms, fn) { Clock.timers.push({ at: Clock.now + ms, fn }); }
function wait(ms) { return new Promise((resolve) => after(ms, resolve)); }
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
function tween(ms, on, ease = easeOut) {
  return new Promise((resolve) => {
    on(0);
    Clock.tweens.push({ start: Clock.now, ms, on, ease, resolve });
  });
}
function tick(dt) {
  Clock.now += dt;
  const due = Clock.timers.filter((t) => t.at <= Clock.now).sort((a, b) => a.at - b.at);
  Clock.timers = Clock.timers.filter((t) => t.at > Clock.now);
  due.forEach((t) => t.fn());
  Clock.tweens = Clock.tweens.filter((t) => {
    const p = Math.min(1, (Clock.now - t.start) / t.ms);
    t.on(t.ease(p));
    if (p >= 1) t.resolve();
    return p < 1;
  });
  Clock.updates.forEach((fn) => fn(dt));
}

const $ = (selector) => document.querySelector(selector);
const stage = $("#stage");
let fit = 1;
function applyFit() {
  fit = Math.min(innerWidth / 1920, innerHeight / 1080);
  stage.style.transform = `translate(${(innerWidth - 1920 * fit) / 2}px, ${(innerHeight - 1080 * fit) / 2}px) scale(${fit})`;
}

// In stage pixels.
const Cursor = { x: 1340, y: 640, el: $("#cursor"), held: $("#held"), hovered: [], shown: true };
function stageOrigin() { const r = stage.getBoundingClientRect(); return [r.left, r.top]; }
function placeCursor() {
  Cursor.el.style.transform = `translate(${Cursor.x}px, ${Cursor.y}px) scale(${Cursor.down ? 0.9 : 1})`;
  Cursor.el.style.display = Cursor.shown ? "" : "none";
  Cursor.held.style.left = `${Cursor.x - 8}px`;
  Cursor.held.style.top = `${Cursor.y - 8}px`;
}
function elementAtCursor() {
  const [ox, oy] = stageOrigin();
  return document.elementFromPoint(ox + Cursor.x * fit, oy + Cursor.y * fit);
}
// Marks what's under the cursor .hover, and shows its tooltip.
function refreshHover() {
  placeCursor();
  const el = elementAtCursor();
  const chain = [];
  for (let node = el; node && node !== stage; node = node.parentElement) {
    if (node.hasAttribute("data-hover")) chain.push(node);
  }
  Cursor.hovered.forEach((node) => { if (!chain.includes(node)) node.classList.remove("hover"); });
  chain.forEach((node) => node.classList.add("hover"));
  Cursor.hovered = chain;
  const tipped = chain.find((node) => node.dataset.tip);
  UI.tooltip(tipped);
}
function actionUnderCursor() {
  for (let node = elementAtCursor(); node && node !== stage; node = node.parentElement) {
    if (node.dataset.act) return node.dataset.act;
  }
  return null;
}
function press() {
  const action = actionUnderCursor();
  UI.closeMenuUnless(action);
  if (action) UI.act(action);
  refreshHover();
}

function centreOf(target) {
  if (Array.isArray(target)) return target;
  const el = typeof target === "string" ? $(target) : target;
  if (!el) throw new Error(`Nothing to point at: ${target}`);
  const r = el.getBoundingClientRect();
  const [ox, oy] = stageOrigin();
  return [(r.left - ox + r.width / 2) / fit, (r.top - oy + r.height / 2) / fit];
}
async function moveTo(target, ms) {
  const [x, y] = centreOf(target);
  const [fromX, fromY] = [Cursor.x, Cursor.y];
  const distance = Math.hypot(x - fromX, y - fromY);
  // A slight bow, as a hand moves, not a ruler.
  const bow = Math.min(40, distance * 0.08);
  const duration = ms || Math.max(320, Math.min(950, 260 + distance * 0.6));
  await tween(duration, (t) => {
    Cursor.x = fromX + (x - fromX) * t;
    Cursor.y = fromY + (y - fromY) * t - Math.sin(t * Math.PI) * bow;
    refreshHover();
  }, easeInOut);
}
async function click(target, ms) {
  if (target) await moveTo(target, ms);
  await wait(130);
  Cursor.down = true; placeCursor();
  await wait(80);
  press();
  Cursor.down = false; placeCursor();
  await wait(120);
}
function holdItem(src) {
  Cursor.held.src = src;
  Cursor.held.hidden = !src;
  placeCursor();
}
async function fadeFrom(ms) { await tween(ms, (t) => { $("#fade").style.opacity = 1 - t; }); }

// Live: real time and the real mouse. Capture: capture.mjs calls __step().
const params = new URLSearchParams(location.search);
const capturing = params.has("capture");
function live() {
  let last = performance.now();
  const frame = (now) => {
    tick(Math.min(50, now - last));
    last = now;
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
  addEventListener("pointermove", (event) => {
    const [ox, oy] = stageOrigin();
    Cursor.x = (event.clientX - ox) / fit;
    Cursor.y = (event.clientY - oy) / fit;
    refreshHover();
  });
  addEventListener("pointerdown", press);
  addEventListener("resize", applyFit);
}
window.__step = async (dt) => {
  tick(dt);
  await new Promise((resolve) => setTimeout(resolve, 0));
  return window.__done === true;
};
