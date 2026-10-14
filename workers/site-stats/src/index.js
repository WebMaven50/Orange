// The Orange Robot website activity monitor.
//
// Records page views and clicks reported by /site-stats.js: the page, where the visitor came
// from, approximate location (country, region, city from Cloudflare), and what they clicked.
// IP addresses are never stored. They are used once, to build a one-way daily hash that lets
// the console count unique visitors.

import {
  classifyReferrer, cleanPath, cleanReferrerUrl, cleanClickTarget, clip, isBot, visitorHash, safeEqual, allowedOrigin, parseDevice,
} from "./logic.js";

const SITE_HOST = "theorangerobot.com";
const JSON_HEADERS = { "content-type": "application/json", "cache-control": "no-store" };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });

function cors(origin) {
  return {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "content-type",
    vary: "origin",
  };
}

async function recordHit(request, env) {
  const origin = request.headers.get("origin");
  if (!allowedOrigin(origin)) return new Response(null, { status: 403 });
  const ua = request.headers.get("user-agent") || "";
  if (isBot(ua)) return new Response(null, { status: 204, headers: cors(origin) });

  let body;
  try {
    const text = await request.text();
    if (text.length > 2048) throw new Error("too large");
    body = JSON.parse(text);
  } catch {
    return new Response(null, { status: 400, headers: cors(origin) });
  }

  const now = new Date();
  const day = now.toISOString().slice(0, 10);
  const type = body.t === "click" ? "click" : body.t === "time" ? "time" : "view";
  // Time on page: whole seconds the page was visible, capped so a forgotten tab can't skew averages.
  const seconds = type === "time" ? Math.min(Math.max(Math.round(Number(body.s)) || 0, 0), 1800) : null;
  if (type === "time" && seconds === 0) return new Response(null, { status: 204, headers: cors(origin) });
  const ip = request.headers.get("cf-connecting-ip") || "";
  const visitor = await visitorHash(env.SALT, day, ip, ua);   // the IP is not kept
  const geo = request.cf || {};
  const { device, os, browser } = parseDevice(ua);   // broad categories only; the user agent is not kept

  await env.DB.prepare(
    "INSERT INTO hits (ts, day, type, path, ref_host, ref_url, country, region, city, visitor, target, device, os, browser, seconds) " +
    "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)"
  ).bind(
    Math.floor(now.getTime() / 1000), day, type, cleanPath(body.p),
    classifyReferrer(body.r, SITE_HOST), cleanReferrerUrl(body.r),
    clip(geo.country, 2), clip(geo.region, 80), clip(geo.city, 80),
    visitor, type === "click" ? cleanClickTarget(body.c) : null,
    device, os, browser, seconds,
  ).run();

  return new Response(null, { status: 204, headers: cors(origin) });
}

async function stats(request, env) {
  let body;
  try { body = JSON.parse(await request.text()); } catch { return json({ error: "bad request" }, 400); }
  if (!safeEqual(body.password, env.ADMIN_PASSWORD)) return json({ error: "wrong password" }, 403);

  const days = Math.min(Math.max(parseInt(body.days, 10) || 7, 1), 90);
  const since = new Date(Date.now() - (days - 1) * 86400000).toISOString().slice(0, 10);
  const q = async (sql) => (await env.DB.prepare(sql).bind(since).all()).results;

  const [totals, byDay, referrers, countries, cities, pages, clicks, recent, devices, systems, browsers, timeOnPage] = await Promise.all([
    q("SELECT COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1"),
    q("SELECT day, COUNT(*) AS views, COUNT(DISTINCT visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY day ORDER BY day DESC"),
    q("SELECT ref_host AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY ref_host ORDER BY views DESC LIMIT 20"),
    q("SELECT country AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY country ORDER BY visitors DESC LIMIT 20"),
    q("SELECT city || ', ' || region || ' ' || country AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 AND city != '' GROUP BY city, region, country ORDER BY visitors DESC LIMIT 20"),
    q("SELECT path AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY path ORDER BY views DESC LIMIT 20"),
    q("SELECT target AS name, path, COUNT(*) AS clicks FROM hits WHERE type='click' AND day >= ?1 GROUP BY target, path ORDER BY clicks DESC LIMIT 25"),
    q("SELECT ts, type, path, ref_host, country, region, city, target, device, os, browser, seconds FROM hits WHERE day >= ?1 ORDER BY ts DESC LIMIT 50"),
    q("SELECT COALESCE(device, 'unknown') AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY device ORDER BY visitors DESC"),
    q("SELECT COALESCE(os, 'unknown') AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY os ORDER BY visitors DESC"),
    q("SELECT COALESCE(browser, 'unknown') AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY browser ORDER BY visitors DESC"),
    q("SELECT t.path AS name, SUM(t.seconds) AS seconds, " +
      "(SELECT COUNT(*) FROM hits v WHERE v.type='view' AND v.day >= ?1 AND v.path = t.path) AS views " +
      "FROM hits t WHERE t.type='time' AND t.day >= ?1 GROUP BY t.path ORDER BY seconds DESC LIMIT 20"),
  ]);
  // Average time per page view, from the reported visible time.
  const timed = timeOnPage.map((r) => ({
    name: r.name, views: r.views, avg: r.views > 0 ? Math.round(r.seconds / r.views) : Math.round(r.seconds),
  }));
  return json({ days, since, totals: totals[0] ?? { views: 0, visitors: 0 }, byDay, referrers, countries, cities, pages, clicks, recent, devices, systems, browsers, timed });
}

const ADMIN_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Site activity</title>
<style>
 body{font:15px -apple-system,system-ui,sans-serif;background:#0b0b0b;color:#eee;margin:0;padding:20px;max-width:900px}
 h1{font-size:20px;color:#f7821a;margin:0 0 4px} h2{font-size:15px;color:#f7821a;margin:26px 0 6px}
 .note{color:#888;font-size:13px} .row{display:flex;gap:10px;margin:14px 0;flex-wrap:wrap}
 input,select{padding:10px;border-radius:8px;border:1px solid #333;background:#171717;color:#eee;font:inherit}
 button{padding:10px 18px;border:0;border-radius:8px;background:#f7821a;color:#000;font-weight:800;font:inherit;font-weight:800}
 table{width:100%;border-collapse:collapse;font-size:13px} th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #222;word-break:break-word}
 th{color:#999;font-weight:600} td.n{text-align:right;white-space:nowrap;color:#f7821a}
 .cards{display:flex;gap:12px;flex-wrap:wrap} .card{background:#171717;border-radius:10px;padding:12px 16px;min-width:130px}
 .card b{display:block;font-size:24px;color:#f7821a}
</style></head><body>
<h1>Website activity</h1>
<p class="note">Page views, referrers, approximate location and clicks. IP addresses are not stored: visitors are counted with a one-way daily hash.</p>
<div class="row">
 <input id="pw" type="password" placeholder="Admin password" autocomplete="off">
 <select id="days"><option value="1">Today</option><option value="7" selected>Last 7 days</option><option value="30">Last 30 days</option><option value="90">Last 90 days</option></select>
 <button id="go">Show</button>
</div>
<div id="msg" class="note"></div>
<div id="out"></div>
<script>
const out = document.getElementById('out'), msg = document.getElementById('msg');
function el(tag, text, cls) { const e = document.createElement(tag); if (text !== undefined) e.textContent = text; if (cls) e.className = cls; return e; }
function table(title, cols, rows) {
  const wrap = document.createElement('div'); wrap.append(el('h2', title));
  const t = document.createElement('table'); const hr = document.createElement('tr');
  cols.forEach(c => hr.append(el('th', c.h, c.n ? 'n' : '')));
  t.append(hr);
  if (!rows.length) { const r = document.createElement('tr'); r.append(el('td', 'Nothing yet')); t.append(r); }
  rows.forEach(row => { const r = document.createElement('tr'); cols.forEach(c => r.append(el('td', String(row[c.k] ?? ''), c.n ? 'n' : ''))); t.append(r); });
  wrap.append(t); return wrap;
}
document.getElementById('go').addEventListener('click', async () => {
  msg.textContent = 'Loading…'; out.textContent = '';
  const res = await fetch('/admin/stats', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ password: document.getElementById('pw').value, days: document.getElementById('days').value }) });
  const d = await res.json().catch(() => ({}));
  if (!res.ok) { msg.textContent = d.error || 'Something went wrong.'; return; }
  msg.textContent = 'Since ' + d.since + ' (UTC)';
  const cards = el('div', undefined, 'cards');
  [['Page views', d.totals.views], ['Visitors', d.totals.visitors]].forEach(([l, v]) => { const c = el('div', undefined, 'card'); c.append(el('b', v), el('span', l)); cards.append(c); });
  out.append(cards);
  out.append(table('By day', [{h:'Day',k:'day'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.byDay));
  out.append(table('Where visitors came from', [{h:'Referrer',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.referrers));
  out.append(table('Countries', [{h:'Country',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.countries));
  out.append(table('Cities', [{h:'City',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.cities));
  out.append(table('Device type', [{h:'Device',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.devices));
  out.append(table('Operating system', [{h:'System',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.systems));
  out.append(table('Browser', [{h:'Browser',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.browsers));
  out.append(table('Average time on page', [{h:'Page',k:'name'},{h:'Views',k:'views',n:1},{h:'Average',k:'avgText',n:1}],
    d.timed.map(r => ({ name: r.name, views: r.views, avgText: Math.floor(r.avg / 60) + 'm ' + String(r.avg % 60).padStart(2, '0') + 's' }))));
  out.append(table('Pages', [{h:'Page',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.pages));
  out.append(table('What they clicked', [{h:'Click',k:'name'},{h:'On page',k:'path'},{h:'Times',k:'clicks',n:1}], d.clicks));
  out.append(table('Recent activity', [{h:'Time (UTC)',k:'when'},{h:'Type',k:'type'},{h:'Page',k:'path'},{h:'From',k:'ref_host'},{h:'Country',k:'country'},{h:'City',k:'city'},{h:'Device',k:'device'},{h:'Click / seconds',k:'detail'}],
    d.recent.map(r => ({ ...r,
      when: new Date(r.ts * 1000).toISOString().replace('T', ' ').slice(0, 19),
      ref_host: r.type === 'view' ? r.ref_host : '',
      detail: r.type === 'time' ? r.seconds + 's on page' : (r.target || '') }))));
});
</script></body></html>`;

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (request.method === "OPTIONS" && pathname === "/hit") {
      const origin = request.headers.get("origin");
      return allowedOrigin(origin) ? new Response(null, { status: 204, headers: cors(origin) }) : new Response(null, { status: 403 });
    }
    if (request.method === "POST" && pathname === "/hit") return recordHit(request, env);
    if (request.method === "POST" && pathname === "/admin/stats") return stats(request, env);
    if (request.method === "GET" && pathname === "/admin") {
      return new Response(ADMIN_HTML, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
    }
    return json({ error: "not found" }, 404);
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(env.DB.prepare("DELETE FROM hits WHERE day < date('now', '-90 day')").run());
  },
};
