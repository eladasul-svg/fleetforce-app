import { chromium } from 'playwright';
import fs from 'fs';
const [loginUrl, outDir] = [process.argv[2], process.argv[3]];
const REF3 = 'a0JWm000000HNgVMAW', REF1 = 'a0JWm000000HNgBMAW';
fs.rmSync(outDir, { recursive: true, force: true }); fs.mkdirSync(outDir, { recursive: true });

const OVERLAY = () => {
  const ensure = () => {
    if (document.getElementById('__rec_cap')) return;
    const st = document.createElement('style');
    st.textContent = `
#__rec_cap{position:fixed;left:0;right:0;bottom:0;height:76px;z-index:2147483646;background:rgba(15,30,51,.94);
 display:flex;align-items:center;gap:22px;padding:0 40px;font:500 27px/1.2 -apple-system,"Segoe UI",Helvetica,Arial,sans-serif;color:#fff;pointer-events:none}
#__rec_cap .pill{flex:none;font-size:17px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;padding:7px 14px;border-radius:6px;background:#f5b941;color:#0f1e33}
#__rec_cap .txt{transition:opacity .35s}
#__rec_cur{position:fixed;left:0;top:0;width:28px;height:28px;z-index:2147483647;pointer-events:none;transform:translate(-100px,-100px)}
#__rec_ring{position:fixed;width:44px;height:44px;margin:-22px 0 0 -22px;border-radius:50%;border:3px solid rgba(1,118,211,.9);z-index:2147483646;pointer-events:none;opacity:0}
#__rec_end{position:fixed;inset:0;z-index:2147483645;background:#0f1e33;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:26px;
 font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;opacity:0;transition:opacity .8s;pointer-events:none}
#__rec_end .t{font-size:84px;font-weight:700;letter-spacing:-.01em}
#__rec_end .t span{color:#f5b941;font-weight:500}
#__rec_end .u{font-size:38px;color:#cbd5e1}`;
    document.documentElement.appendChild(st);
    const cap = document.createElement('div'); cap.id = '__rec_cap';
    cap.innerHTML = '<span class="pill">Sample data</span><span class="txt"></span>';
    const cur = document.createElement('div'); cur.id = '__rec_cur';
    cur.innerHTML = '<svg viewBox="0 0 28 28" width="28" height="28"><path d="M4 2 L4 22 L9.5 17 L13 25 L16.5 23.5 L13 15.8 L20.5 15.5 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
    const ring = document.createElement('div'); ring.id = '__rec_ring';
    const end = document.createElement('div'); end.id = '__rec_end';
    end.innerHTML = '<div class="t">FleetForce <span>· sample data</span></div><div class="u">fleetforce.info</div>';
    document.documentElement.append(cap, cur, ring, end);
    window.__rec = window.__rec || { x: -100, y: -100 };
    const s = window.__rec; cur.style.transform = `translate(${s.x}px,${s.y}px)`;
    if (s.caption) cap.querySelector('.txt').textContent = s.caption;
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ensure); else ensure();
  setInterval(ensure, 300);
};

const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1, locale: 'en-US' });
await ctx.addInitScript(OVERLAY);
const p = await ctx.newPage();
await p.goto(loginUrl); await p.waitForURL(/lightning/, { timeout: 90000 });
const base = new URL(p.url()).origin;

// ---------- frame capture ----------
const cdp = await ctx.newCDPSession(p);
const frames = []; let rec = false, pausedAt = 0, offset = 0, t0 = null, n = 0;
const now = () => performance.now() / 1000;
const vt = () => now() - t0 - offset;              // video time
cdp.on('Page.screencastFrame', async ({ data, sessionId }) => {
  cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
  if (!rec) return;
  const f = `f${String(n++).padStart(5, '0')}.jpg`;
  fs.writeFileSync(`${outDir}/${f}`, Buffer.from(data, 'base64')); frames.push({ f, t: vt() });
});
const snap = async () => {                          // force a frame (screencast only sends on change)
  const f = `f${String(n++).padStart(5, '0')}.jpg`;
  fs.writeFileSync(`${outDir}/${f}`, await p.screenshot({ type: 'jpeg', quality: 92 })); frames.push({ f, t: vt() });
};
const start = async () => { await cdp.send('Page.startScreencast', { format: 'jpeg', quality: 92, maxWidth: 1920, maxHeight: 1080, everyNthFrame: 1 }); t0 = now(); rec = true; await snap(); };
const pause = () => { rec = false; pausedAt = now(); };
const resume = async () => { offset += now() - pausedAt; rec = true; await snap(); };
const wait = (ms) => p.waitForTimeout(ms);

// ---------- helpers ----------
const caption = (text) => p.evaluate((t) => {
  window.__rec = window.__rec || {}; window.__rec.caption = t;
  const el = document.querySelector('#__rec_cap .txt'); if (!el) return;
  el.style.opacity = 0; setTimeout(() => { el.textContent = t; el.style.opacity = 1; }, 350);
}, text);
const moveTo = (x, y, ms = 900) => p.evaluate(([x, y, ms]) => new Promise((res) => {
  const s = window.__rec, cur = document.getElementById('__rec_cur'), x0 = s.x < 0 ? 960 : s.x, y0 = s.y < 0 ? 700 : s.y, st = performance.now();
  const ease = (k) => k < .5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
  const step = (tm) => { const k = Math.min(1, (tm - st) / ms), e = ease(k); s.x = x0 + (x - x0) * e; s.y = y0 + (y - y0) * e;
    cur.style.transform = `translate(${s.x}px,${s.y}px)`; k < 1 ? requestAnimationFrame(step) : res(); };
  requestAnimationFrame(step);
}), [x, y, ms]);
const ripple = () => p.evaluate(() => { const s = window.__rec, r = document.getElementById('__rec_ring');
  r.style.left = (s.x + 4) + 'px'; r.style.top = (s.y + 3) + 'px';
  r.animate([{ opacity: 1, transform: 'scale(.4)' }, { opacity: 0, transform: 'scale(1.3)' }], { duration: 550, easing: 'ease-out' }); });
const center = async (loc) => { await loc.scrollIntoViewIfNeeded(); const bb = await loc.boundingBox(); return [bb.x + Math.min(bb.width / 2, 60), bb.y + bb.height / 2]; };
const clickOn = async (loc, { ms = 900, before = 350 } = {}) => {
  const [x, y] = await center(loc); await moveTo(x, y, ms); await p.mouse.move(x, y); await wait(before); await ripple(); await wait(120); await p.mouse.click(x, y);
};
const hover = async (loc, ms = 800) => { const [x, y] = await center(loc); await moveTo(x, y, ms); await p.mouse.move(x, y); };
const smoothScroll = (dy, ms = 1400) => p.evaluate(([dy, ms]) => new Promise((res) => {
  const y0 = window.scrollY, st = performance.now(), ease = (k) => k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
  const step = (tm) => { const k = Math.min(1, (tm - st) / ms); window.scrollTo(0, y0 + dy * ease(k)); k < 1 ? requestAnimationFrame(step) : res(); };
  requestAnimationFrame(step);
}), [dy, ms]);
const settle = async (ms = 7000) => { await p.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {}); await wait(ms); };
const scrollTop = () => p.evaluate(() => window.scrollTo(0, 0));

// ---------- prep (not recorded): close stray workspace tabs, warm caches ----------
for (const path of [`/lightning/r/fleetforce__Fleet_Asset__c/${REF1}/view`, `/lightning/r/fleetforce__Fleet_Asset__c/${REF3}/view`, '/lightning/page/home']) { await p.goto(base + path); await settle(5000); }
for (let i = 0; i < 10; i++) { const x = p.locator('button[title^="Close "]').filter({ hasNotText: 'Assistant' }); const c = await x.count(); if (!c) break; await x.filter({ visible: true }).first().click().catch(() => {}); await wait(1200); }
await p.goto(base + '/lightning/page/home'); await settle(8000); await scrollTop();
await p.evaluate(() => { window.__rec.x = 1500; window.__rec.y = 760; });

// ---------- Beat 1 (0-10): Home -> Fleet Exposure ----------
await caption('One view of fleet data health');
await start();
await wait(2500);
await clickOn(p.getByRole('tab', { name: 'Fleet Exposure' }).filter({ visible: true }).first(), { ms: 1300 });
await wait(1200);
await hover(p.getByText('Fleet exposure', { exact: true }).filter({ visible: true }).first(), 900);
await wait(Math.max(0, (10 - vt()) * 1000));

// ---------- Beat 2 (10-20): KPI tiles ----------
await caption('Where is the data late, missing or conflicting?');
await wait(1000);
for (const label of ['Open data gaps', 'Open recall alerts', 'Vehicles at risk', 'Average fleet data health']) {
  await hover(p.getByText(label, { exact: true }).filter({ visible: true }).first(), 900); await wait(1100);
}
await wait(Math.max(0, (20 - vt()) * 1000));

// ---------- Beat 3 (20-40): vehicle at risk ----------
await caption('Each score says why');
await clickOn(p.getByText('rear axle bolt may loosen', { exact: false }).filter({ visible: true }).first(), { ms: 900 });
await wait(1500);
const ref3Link = p.locator(`a[href="/${REF3}"]`).filter({ visible: true }).first();
await ref3Link.waitFor({ timeout: 15000 });
{ const bb = await ref3Link.boundingBox(); await smoothScroll(Math.max(0, bb.y - 640), 1300); }
await wait(700);
await clickOn(ref3Link, { ms: 900 });
pause(); await settle(6000);
const dhTab = () => p.getByRole('tab', { name: 'Data Health' }).filter({ visible: true }).first();
await dhTab().scrollIntoViewIfNeeded(); await scrollTop();
await resume();
await wait(600);
await clickOn(dhTab(), { ms: 900 });
await wait(1200);
{ const g = p.getByText('Data health', { exact: true }).filter({ visible: true }).first(); const bb = await g.boundingBox(); await smoothScroll(Math.max(0, bb.y - 160), 1300); }
await hover(p.getByText('Freshness', { exact: false }).filter({ visible: true }).first(), 800); await wait(1200);
{ const s = p.getByText('Data streams', { exact: true }).filter({ visible: true }).first(); const bb = await s.boundingBox(); await smoothScroll(Math.max(0, bb.y - 220), 1300); }
await hover(p.getByText('9 days ago', { exact: true }).filter({ visible: true }).first(), 800); await wait(1200);
await hover(p.getByText('Possible recall', { exact: false }).filter({ visible: true }).first(), 900); await wait(1100);
const vendor = p.locator('a[data-id]', { hasText: 'Webfleet' }).filter({ visible: true }).first();
await clickOn(vendor, { ms: 900 });
pause(); await p.waitForURL(/\/Account\//, { timeout: 20000 }); await settle(5000);
await scrollTop(); await p.evaluate(() => { window.__rec.x = 700; window.__rec.y = 420; });
await resume();
await hover(p.getByText('Technology Partner', { exact: true }).filter({ visible: true }).first(), 900);
await wait(Math.max(1500, (41 - vt()) * 1000));

// ---------- Beat 4 (40-50): contrast and close ----------
await caption('Same check, healthy vehicle: 100');
pause();
await p.goto(base + `/lightning/r/fleetforce__Fleet_Asset__c/${REF1}/view`); await settle(6000);
await dhTab().click(); await wait(2500);
{ const g = p.getByText('Data health', { exact: true }).filter({ visible: true }).first(); const bb = await g.boundingBox(); await p.evaluate((y) => window.scrollTo(0, y), Math.max(0, bb.y - 160)); }
await p.evaluate(() => { window.__rec.x = 1500; window.__rec.y = 820; });
await caption('Same check, healthy vehicle: 100');
await wait(1000);
await resume();
await hover(p.getByText('Healthy', { exact: true }).filter({ visible: true }).first(), 1000);
await wait(2400);
await caption('');
await p.evaluate(() => { document.getElementById('__rec_end').style.opacity = 1; document.getElementById('__rec_cur').style.opacity = 0; });
await wait(Math.max(4000, (50 - vt()) * 1000));
await snap();
rec = false; await cdp.send('Page.stopScreencast');
fs.writeFileSync(`${outDir}/manifest.json`, JSON.stringify({ duration: vt(), frames }));
console.log('duration', vt().toFixed(2), 'frames', frames.length, 'url', p.url());
await b.close();
