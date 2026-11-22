// Turns the frames recorded by record_test.dart into GIFs.
//
// Each frame is drawn as HTML, screenshotted with headless Chrome, and the
// screenshots are joined with ffmpeg (one shared palette per GIF).
//
//   node tool/demos/render.mjs [demo ...]
//
// Needs google-chrome (or $CHROME) and ffmpeg on PATH.
import { execFile } from 'node:child_process';
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const run = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));
const framesDir = join(here, 'frames');
const outDir = join(here, '..', '..', 'website', 'public', 'demos');
const chrome = process.env.CHROME ?? 'google-chrome';
// The tour is also the package's screenshot on pub.dev.
const screenshot = join(here, '..', '..', 'doc', 'screenshots', 'gui-tour.gif');

const FONT_SIZE = 15;
const LINE = 18;
const CHAR = FONT_SIZE * 0.6021; // DejaVu Sans Mono advance width
const PAD = 14;
const BAR = 30;

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function html(demo, frame) {
  const rows = frame.rows
    .map((runs) =>
      runs
        .map(([text, fg, bg, bold]) =>
          `<span style="color:${fg};background:${bg}${bold ? ';font-weight:bold' : ''}">${esc(text)}</span>`)
        .join(''))
    .join('\n');
  return `<!doctype html><meta charset="utf-8"><style>
html,body{margin:0;background:#0d0d10;overflow:hidden}
.win{margin:0;background:${demo.background};border-radius:10px;overflow:hidden;
  width:${Math.ceil(demo.cols * CHAR) + PAD * 2}px}
.bar{height:${BAR}px;background:#2a2a31;display:flex;align-items:center;gap:8px;padding:0 12px;
  font:12px 'DejaVu Sans',sans-serif;color:#9a9aa5}
.dot{width:12px;height:12px;border-radius:50%}
.title{flex:1;text-align:center;margin-right:60px}
pre{margin:0;padding:${PAD}px;font:${FONT_SIZE}px/${LINE}px 'DejaVu Sans Mono',monospace;
  font-variant-ligatures:none}
</style><div class="win"><div class="bar"><span class="dot" style="background:#ff5f57"></span>
<span class="dot" style="background:#febc2e"></span><span class="dot" style="background:#28c840"></span>
<span class="title">shop_app — dart run modular_l10n_generator gui</span></div><pre>${rows}</pre></div>`;
}

async function pool(items, size, fn) {
  let next = 0;
  await Promise.all(Array.from({ length: size }, async () => {
    while (next < items.length) {
      const i = next++;
      await fn(items[i], i);
    }
  }));
}

async function render(name) {
  const demo = JSON.parse(readFileSync(join(framesDir, `${name}.json`), 'utf8'));
  const work = mkdtempSync(join(tmpdir(), `ml10n-${name}-`));
  const width = Math.ceil(demo.cols * CHAR) + PAD * 2;
  const height = demo.rows * LINE + PAD * 2 + BAR;

  await pool(demo.frames, 6, async (frame, i) => {
    const page = join(work, `f${String(i).padStart(4, '0')}.html`);
    writeFileSync(page, html(demo, frame));
    await run(chrome, [
      '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
      `--user-data-dir=${join(work, `profile${i}`)}`,
      '--force-device-scale-factor=1', `--window-size=${width},${height}`,
      `--screenshot=${page.replace(/\.html$/, '.png')}`, `file://${page}`,
    ]);
    rmSync(join(work, `profile${i}`), { recursive: true, force: true });
  });

  const list = demo.frames
    .map((f, i) => `file 'f${String(i).padStart(4, '0')}.png'\nduration ${(f.ms / 1000).toFixed(3)}`)
    .join('\n');
  // The concat demuxer ignores the last duration unless the file repeats.
  writeFileSync(join(work, 'list.txt'),
    `${list}\nfile 'f${String(demo.frames.length - 1).padStart(4, '0')}.png'\n`);

  mkdirSync(outDir, { recursive: true });
  const gif = join(outDir, `${name}.gif`);
  await run('ffmpeg', [
    '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', join(work, 'list.txt'),
    '-vf', 'fps=15,split[a][b];[a]palettegen=max_colors=64:stats_mode=full[p];[b][p]paletteuse=dither=none',
    '-loop', '0', gif,
  ]);
  // A still of the most informative moment, for pages that prefer a PNG.
  copyFileSync(join(work, `f${String(demo.frames.length - 2).padStart(4, '0')}.png`),
    join(outDir, `${name}.png`));
  rmSync(work, { recursive: true, force: true });
  if (name === 'tour') {
    mkdirSync(dirname(screenshot), { recursive: true });
    copyFileSync(gif, screenshot);
  }
  console.log(`${name}: ${demo.frames.length} frames → ${gif}`);
}

const names = process.argv.slice(2).length
  ? process.argv.slice(2)
  : readdirSync(framesDir).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5));
for (const name of names) await render(name);
