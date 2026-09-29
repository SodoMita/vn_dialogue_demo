#!/usr/bin/env node
// Web export smoke test: does the exported game really boot on a host that
// sends NO COOP/COEP headers (GitHub Pages, itch)?
//
//   node tests/web_smoke.mjs build/web [screenshot.jpg]
//
// Needs Playwright with a Chromium install; point PLAYWRIGHT_DIR at the
// folder where `npm i playwright && npx playwright install chromium` ran
// (defaults to the current directory).
//
// Checks (exit 1 on any failure):
//   1. the page ends up cross-origin isolated with SharedArrayBuffer, i.e.
//      coi-serviceworker.js registered and reloaded the page;
//   2. Godot starts as a multi-threaded build and hides its loading screen;
//   3. no uncaught page error, no script error and no "sample from a stream
//      that cannot be sampled" warning (the web default playback type must
//      stay Stream so the procedural music generator can play).
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const dir = process.argv[2] ?? 'build/web';
const shot = process.argv[3];
const require = createRequire(join(process.env.PLAYWRIGHT_DIR ?? process.cwd(), '/'));
const { chromium } = require('playwright');

const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream', '.json': 'application/json', '.png': 'image/png',
};

// Plain static server on purpose: no COOP/COEP, like GitHub Pages.
const server = createServer(async (req, res) => {
  try {
    const rel = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^(\.\.[/\\])+/, '');
    let file = join(dir, rel === '/' ? 'index.html' : rel);
    if ((await stat(file)).isDirectory()) file = join(file, 'index.html');
    const body = await readFile(file);
    res.writeHead(200, { 'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream', 'Content-Length': body.length });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const url = `http://127.0.0.1:${server.address().port}/index.html`;

const failures = [];
const expect = (cond, what) => {
  console.log(`${cond ? '[PASS]' : '[FAIL]'} ${what}`);
  if (!cond) failures.push(what);
};

const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
});
const page = await (await browser.newContext({ viewport: { width: 1280, height: 720 } })).newPage();
const logs = [];
page.on('console', (m) => logs.push(`${m.text()}`));
page.on('pageerror', (e) => logs.push(`PAGEERROR ${e}`));

await page.goto(url);
// First load: the service worker registers, then reloads the page once.
let isolated = false;
for (let i = 0; i < 30 && !isolated; i++) {
  await page.waitForTimeout(1000);
  isolated = await page.evaluate(() => self.crossOriginIsolated === true && typeof SharedArrayBuffer !== 'undefined').catch(() => false);
}
expect(isolated, 'page is cross-origin isolated with SharedArrayBuffer (service worker works)');

let booted = false;
for (let i = 0; i < 60 && !booted; i++) {
  await page.waitForTimeout(1000);
  booted = logs.some((l) => l.includes('multi-threaded')) &&
    await page.evaluate(() => { const s = document.querySelector('#status'); return !!document.querySelector('canvas') && (!s || getComputedStyle(s).display === 'none'); }).catch(() => false);
}
expect(booted, 'Godot booted as a multi-threaded build and hid its loading screen');
await page.waitForTimeout(4000); // let the first line and the music start

const reloadAt = logs.findIndex((l) => l.includes('Reloading page'));
const afterReload = logs.slice(Math.max(0, reloadAt));
expect(!logs.some((l) => l.startsWith('PAGEERROR')), 'no uncaught page errors');
expect(!afterReload.some((l) => l.includes('cannot be sampled')), 'no "stream that cannot be sampled" warning (Stream playback on web)');
expect(!afterReload.some((l) => /SCRIPT ERROR|Parse Error/.test(l)), 'no script errors in the console');

if (shot) await page.screenshot({ path: shot, type: 'jpeg', quality: 70 });
await browser.close();
server.close();
if (failures.length) {
  console.log('\nconsole tail:\n' + logs.slice(-12).map((l) => '  ' + l.slice(0, 200)).join('\n'));
  process.exit(1);
}
console.log('web smoke test passed');
