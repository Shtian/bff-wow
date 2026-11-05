// Records the scenes frame by frame on the virtual clock, so nothing stutters
// or drops. Writes out/<scene>.mp4 (1920x1080, 30fps), out/<scene>.gif (cropped
// to the action) and out/tour.mp4 (every scene, cut together).
//   npm run demo               everything
//   npm run demo -- away goals only those, no tour
//   npm run demo -- --still=away:9000   a PNG at that time, for checking
import { chromium } from "playwright";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, "out");
const FPS = 30, GIF_FPS = 15, GIF_WIDTH = 960, PARALLEL = 4;
const ORDER = ["away", "toasts", "roster", "goals", "spares", "when", "professions", "together"];

if (!existsSync(join(here, "assets", "backdrop.jpg"))) {
  console.error("No assets yet. Run: npm run demo:assets");
  process.exit(1);
}
mkdirSync(out, { recursive: true });
const args = process.argv.slice(2);
const still = args.find((a) => a.startsWith("--still="));
const chosen = args.filter((a) => !a.startsWith("--"));
const work = mkdtempSync(join(tmpdir(), "bff-demo-"));
const pageUrl = (scene) => `${pathToFileURL(join(here, "index.html")).href}?capture&scene=${scene}`;
const ffmpeg = (...a) => {
  const run = spawnSync("ffmpeg", ["-v", "error", "-y", ...a], { stdio: "inherit" });
  if (run.status !== 0) throw new Error(`ffmpeg failed: ${a.join(" ")}`);
};

async function open(browser, scene) {
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  page.on("pageerror", (error) => console.error(`[${scene}] ${error.message}`));
  await page.goto(pageUrl(scene));
  await page.waitForFunction(() => window.__ready === true);
  return page;
}

async function record(browser, scene) {
  const page = await open(browser, scene);
  const raw = join(work, `${scene}.mkv`);
  // Lossless first: a GIF made from a lossy video dithers its noise, and the
  // still backdrop stops compressing.
  const encoder = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "png", "-i", "-",
    "-c:v", "libx264", "-qp", "0", "-preset", "ultrafast", "-pix_fmt", "yuv444p", raw], { stdio: ["pipe", "inherit", "inherit"] });
  const finished = new Promise((resolve) => encoder.on("close", resolve));
  let frames = 0, done = false, tail = 0;
  while (tail < 2) {
    done = await page.evaluate((dt) => window.__step(dt), 1000 / FPS);
    const png = await page.screenshot({ type: "png" });
    if (!encoder.stdin.write(png)) await new Promise((resolve) => encoder.stdin.once("drain", resolve));
    frames += 1;
    if (done) tail += 1;
    if (frames > FPS * 120) throw new Error(`${scene} never finished`);
  }
  encoder.stdin.end();
  await finished;
  const crop = await page.evaluate((id) => window.__scenes[id].crop, scene);
  await page.close();
  ffmpeg("-i", raw, "-c:v", "libx264", "-crf", "16", "-preset", "slow", "-pix_fmt", "yuv420p", "-movflags", "+faststart", join(out, `${scene}.mp4`));
  if (crop) {
    const [x, y, w, h] = crop;
    const shape = `fps=${GIF_FPS},crop=${w}:${h}:${x}:${y},scale=${GIF_WIDTH}:-2:flags=lanczos`;
    ffmpeg("-i", raw, "-vf", `${shape},split[a][b];[a]palettegen=max_colors=192:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle`, join(out, `${scene}.gif`));
  }
  const mb = (file) => (existsSync(file) ? (statSync(file).size / 1e6).toFixed(1) : "-");
  console.log(`${scene}: ${(frames / FPS).toFixed(1)}s, mp4 ${mb(join(out, `${scene}.mp4`))}MB, gif ${mb(join(out, `${scene}.gif`))}MB`);
}

function tour() {
  const clips = ["card", ...ORDER];
  const inputs = clips.flatMap((c) => ["-i", join(work, `${c}.mkv`)]);
  const durations = clips.map((c) => Number(spawnSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", join(work, `${c}.mkv`)]).stdout.toString()));
  const faded = clips.map((_, i) => `[${i}:v]fade=t=in:st=0:d=0.35,fade=t=out:st=${(durations[i] - 0.35).toFixed(2)}:d=0.35,format=yuv420p[v${i}]`);
  const filter = `${faded.join(";")};${clips.map((_, i) => `[v${i}]`).join("")}concat=n=${clips.length}:v=1[out]`;
  ffmpeg(...inputs, "-filter_complex", filter, "-map", "[out]", "-c:v", "libx264", "-crf", "17", "-preset", "slow", "-movflags", "+faststart", join(out, "tour.mp4"));
  console.log(`tour: ${durations.reduce((a, b) => a + b, 0).toFixed(1)}s, ${(statSync(join(out, "tour.mp4")).size / 1e6).toFixed(1)}MB`);
}

const browser = await chromium.launch();
try {
  if (still) {
    const [scene, ...times] = still.slice("--still=".length).split(":");
    const page = await open(browser, scene);
    let now = 0;
    for (const time of times.flatMap((t) => t.split(",")).map(Number)) {
      while (now < time) { await page.evaluate((dt) => window.__step(dt), 1000 / FPS); now += 1000 / FPS; }
      await page.screenshot({ path: join(out, `still-${scene}-${time}.png`) });
    }
    console.log(`end ${await page.evaluate(() => window.__done === true)}`);
  } else {
    const scenes = chosen.length ? chosen : ["card", ...ORDER];
    const queue = [...scenes];
    await Promise.all(Array.from({ length: PARALLEL }, async () => {
      while (queue.length) await record(browser, queue.shift());
    }));
    if (!chosen.length) tour();
  }
} finally {
  await browser.close();
  rmSync(work, { recursive: true, force: true });
}
