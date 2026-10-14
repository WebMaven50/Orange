// The Orange Robot website activity monitor.
//
// Records page views and clicks reported by /site-stats.js: the page, where the visitor came
// from, approximate location (country, region, city from Cloudflare), and what they clicked.
// IP addresses are never stored. They are used once, to build a one-way daily hash that lets
// the console count unique visitors.

import {
  classifyReferrer, cleanPath, cleanReferrerUrl, cleanClickTarget, clip, isBot, visitorHash, safeEqual, allowedOrigin, parseDevice,
  signSession, verifySession, getCookie,
} from "./logic.js";

const COOKIE = "sr_admin";
const SESSION_DAYS = 30;
const sessionSecret = (env) => `${env.ADMIN_PASSWORD}|${env.SALT}`;
async function signedIn(request, env) {
  return verifySession(sessionSecret(env), getCookie(request.headers.get("cookie"), COOKIE), Math.floor(Date.now() / 1000));
}

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
  let body = {};
  try { body = JSON.parse((await request.text()) || "{}"); } catch { return json({ error: "bad request" }, 400); }
  const allowed = (await signedIn(request, env)) || safeEqual(body.password, env.ADMIN_PASSWORD);
  if (!allowed) return json({ error: "signed out" }, 403);

  const days = Math.min(Math.max(parseInt(body.days, 10) || 7, 1), 90);
  const since = new Date(Date.now() - (days - 1) * 86400000).toISOString().slice(0, 10);
  const q = async (sql) => (await env.DB.prepare(sql).bind(since).all()).results;

  const [totals, byDay, referrers, countries, cities, pages, clicks, recent, devices, systems, browsers, timeOnPage, steps] = await Promise.all([
    q("SELECT COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1"),
    q("SELECT day, COUNT(*) AS views, COUNT(DISTINCT visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY day ORDER BY day DESC"),
    q("SELECT ref_host AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY ref_host ORDER BY views DESC LIMIT 20"),
    q("SELECT country AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY country ORDER BY visitors DESC LIMIT 20"),
    q("SELECT city || ', ' || region || ' ' || country AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 AND city != '' GROUP BY city, region, country ORDER BY visitors DESC LIMIT 20"),
    q("SELECT path AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY path ORDER BY views DESC LIMIT 20"),
    q("SELECT target AS name, path, COUNT(*) AS clicks FROM hits WHERE type='click' AND day >= ?1 GROUP BY target, path ORDER BY clicks DESC LIMIT 25"),
    q("SELECT ts, type, visitor, path, ref_host, country, region, city, target, device, os, browser, seconds FROM hits WHERE day >= ?1 ORDER BY ts DESC LIMIT 60"),
    q("SELECT COALESCE(device, 'unknown') AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY device ORDER BY visitors DESC"),
    q("SELECT COALESCE(os, 'unknown') AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY os ORDER BY visitors DESC"),
    q("SELECT COALESCE(browser, 'unknown') AS name, COUNT(*) AS views, COUNT(DISTINCT day || visitor) AS visitors FROM hits WHERE type='view' AND day >= ?1 GROUP BY browser ORDER BY visitors DESC"),
    q("SELECT path AS name, COUNT(*) AS reports, SUM(seconds) AS seconds FROM hits " +
      "WHERE type='time' AND day >= ?1 GROUP BY path ORDER BY seconds DESC LIMIT 20"),
    q("SELECT visitor, ts, path, country, city, device, os, browser FROM hits WHERE type='view' AND day >= ?1 ORDER BY ts DESC LIMIT 600"),
  ]);
  // Group page views by visitor code so each visitor's route through the site reads in order.
  const byVisitor = new Map();
  for (const r of steps) {
    if (!byVisitor.has(r.visitor)) byVisitor.set(r.visitor, []);
    byVisitor.get(r.visitor).push(r);
  }
  const journeys = [...byVisitor.entries()].map(([visitor, rows]) => {
    rows.sort((x, y) => x.ts - y.ts);
    const first = rows[0], last = rows[rows.length - 1];
    return {
      visitor: visitor.slice(0, 8), first: first.ts, last: last.ts, pages: rows.length,
      route: rows.map((r) => r.path).join("  →  "),
      where: [first.city, first.country].filter(Boolean).join(", "),
      device: [first.device, first.os, first.browser].filter(Boolean).join(" · "),
    };
  }).sort((x, y) => y.last - x.last).slice(0, 40);
  // Average over the visits that reported a time (quick bounces and blocked browsers don't report).
  const timed = timeOnPage.map((r) => ({
    name: r.name, views: r.reports, avg: r.reports > 0 ? Math.round(r.seconds / r.reports) : 0,
  }));
  return json({ days, since, totals: totals[0] ?? { views: 0, visitors: 0 }, byDay, referrers, countries, cities, pages, clicks, recent, devices, systems, browsers, timed, journeys });
}

const ADMIN_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Site activity</title>
<style>
 body{font:15px -apple-system,system-ui,sans-serif;background:#0b0b0b;color:#eee;margin:0;padding:20px;max-width:1200px}
 h1{font-size:20px;color:#f7821a;margin:0 0 4px} h2{font-size:15px;color:#f7821a;margin:28px 0 8px}
 .note{color:#888;font-size:13px} .row{display:flex;gap:10px;margin:14px 0;flex-wrap:wrap}
 input,select{padding:10px;border-radius:8px;border:1px solid #333;background:#171717;color:#eee;font:inherit}
 button{padding:10px 18px;border:0;border-radius:8px;background:#f7821a;color:#000;font:inherit;font-weight:800}
 .scroll{overflow-x:auto;border:1px solid #1d1d1d;border-radius:10px}
 table{width:100%;border-collapse:collapse;font-size:13px}
 th,td{text-align:left;padding:9px 14px;border-bottom:1px solid #1d1d1d;white-space:nowrap;vertical-align:top}
 th{color:#999;font-weight:600;background:#101010}
 td.n,th.n{text-align:right;color:#f7821a}
 td.w{white-space:normal;min-width:240px;max-width:520px;word-break:break-word}
 td.m{font-family:ui-monospace,Menlo,monospace;color:#9ad}
 .cards{display:flex;gap:12px;flex-wrap:wrap} .card{background:#171717;border-radius:10px;padding:12px 18px;min-width:140px}
 .card b{display:block;font-size:24px;color:#f7821a}
</style></head><body>
<h1>Website activity</h1>
<p class="note">Page views, referrers, approximate location, devices and clicks. IP addresses are not stored. The visitor code is a one-way hash that changes every day and when someone's network changes.</p>
<div class="row">
 <form method="post" action="/admin/logout" style="margin:0"><button type="submit" style="background:#222;color:#ccc">Sign out</button></form>
 <select id="days"><option value="1">Today</option><option value="7" selected>Last 7 days</option><option value="30">Last 30 days</option><option value="90">Last 90 days</option></select>
 <button id="go">Show</button>
</div>
<div id="msg" class="note"></div>
<div id="out"></div>
<script>
const out = document.getElementById('out'), msg = document.getElementById('msg');
function el(tag, text, cls) { const e = document.createElement(tag); if (text !== undefined) e.textContent = text; if (cls) e.className = cls; return e; }
function when(ts) { return new Date(ts * 1000).toISOString().replace('T', ' ').slice(0, 19); }
function table(title, cols, rows) {
  const wrap = document.createElement('div'); wrap.append(el('h2', title));
  const box = el('div', undefined, 'scroll');
  const t = document.createElement('table'); const hr = document.createElement('tr');
  cols.forEach(c => hr.append(el('th', c.h, c.n ? 'n' : '')));
  t.append(hr);
  if (!rows.length) { const r = document.createElement('tr'); r.append(el('td', 'Nothing yet')); t.append(r); }
  rows.forEach(row => { const r = document.createElement('tr');
    cols.forEach(c => r.append(el('td', String(row[c.k] ?? ''), (c.n ? 'n ' : '') + (c.w ? 'w ' : '') + (c.m ? 'm' : ''))));
    t.append(r); });
  box.append(t); wrap.append(box); return wrap;
}
document.getElementById('go').addEventListener('click', async () => {
  msg.textContent = 'Loading…'; out.textContent = '';
  const res = await fetch('/admin/stats', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ days: document.getElementById('days').value }) });
  const d = await res.json().catch(() => ({}));
  if (res.status === 403) { location.href = '/admin'; return; }
  if (!res.ok) { msg.textContent = d.error || 'Something went wrong.'; return; }
  msg.textContent = 'Since ' + d.since + ' (UTC)';
  const cards = el('div', undefined, 'cards');
  [['Page views', d.totals.views], ['Visitors', d.totals.visitors]].forEach(([l, v]) => { const c = el('div', undefined, 'card'); c.append(el('b', v), el('span', l)); cards.append(c); });
  out.append(cards);
  out.append(table('Visitor journeys (pages in the order each visitor opened them)', [
    {h:'Visitor',k:'visitor',m:1},{h:'First seen (UTC)',k:'firstText'},{h:'Last seen (UTC)',k:'lastText'},{h:'Pages',k:'pages',n:1},
    {h:'Route',k:'route',w:1},{h:'Where',k:'where'},{h:'Device',k:'device'}],
    d.journeys.map(j => ({ ...j, firstText: when(j.first), lastText: when(j.last) }))));
  out.append(table('By day', [{h:'Day',k:'day'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.byDay));
  out.append(table('Where visitors came from', [{h:'Referrer',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.referrers));
  out.append(table('Countries', [{h:'Country',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.countries));
  out.append(table('Cities', [{h:'City',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.cities));
  out.append(table('Device type', [{h:'Device',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.devices));
  out.append(table('Operating system', [{h:'System',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.systems));
  out.append(table('Browser', [{h:'Browser',k:'name'},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.browsers));
  out.append(table('Average time on page (visits that reported a time)', [{h:'Page',k:'name',w:1},{h:'Visits',k:'views',n:1},{h:'Average',k:'avgText',n:1}],
    d.timed.map(r => ({ name: r.name, views: r.views, avgText: Math.floor(r.avg / 60) + 'm ' + String(r.avg % 60).padStart(2, '0') + 's' }))));
  out.append(table('Pages', [{h:'Page',k:'name',w:1},{h:'Views',k:'views',n:1},{h:'Visitors',k:'visitors',n:1}], d.pages));
  out.append(table('What they clicked', [{h:'Click',k:'name',w:1},{h:'On page',k:'path'},{h:'Times',k:'clicks',n:1}], d.clicks));
  out.append(table('Recent activity', [
    {h:'Time (UTC)',k:'when'},{h:'Type',k:'type'},{h:'Visitor',k:'who',m:1},{h:'Page',k:'path',w:1},{h:'From',k:'ref_host'},
    {h:'Country',k:'country'},{h:'City',k:'city'},{h:'Device',k:'device'},{h:'Click / seconds',k:'detail',w:1}],
    d.recent.map(r => ({ ...r, when: when(r.ts), who: (r.visitor || '').slice(0, 8),
      ref_host: r.type === 'view' ? r.ref_host : '',
      detail: r.type === 'time' ? r.seconds + 's on page' : (r.target || '') }))));
});
</script></body></html>`;

function loginPage(error) {
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sign in</title>
<style>
 body{font:16px -apple-system,system-ui,sans-serif;background:#0b0b0b;color:#eee;margin:0;padding:28px;max-width:380px}
 h1{font-size:20px;color:#f7821a;margin:0 0 6px} p{color:#888;font-size:13px;margin:0 0 18px}
 input{width:100%;box-sizing:border-box;padding:12px;margin:0 0 12px;border-radius:8px;border:1px solid #333;background:#171717;color:#eee;font:inherit}
 button{width:100%;padding:13px;border:0;border-radius:8px;background:#f7821a;color:#000;font:inherit;font-weight:800}
 .err{color:#ff6b5e;font-size:14px;margin:0 0 12px}
</style></head><body>
<h1>Website activity</h1>
<p>Sign in to see the console. Your device can remember you for ${SESSION_DAYS} days.</p>
${error ? '<div class="err">That password isn\'t right.</div>' : ''}
<form method="post" action="/admin/login" autocomplete="on">
 <input type="text" name="username" value="site-activity" autocomplete="username" readonly>
 <input type="password" name="password" autocomplete="current-password" placeholder="Password" required autofocus>
 <button type="submit">Sign in</button>
</form>
</body></html>`;
  return new Response(html, { status: error ? 401 : 200, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
}

function cookieHeader(value, maxAge) {
  return `${COOKIE}=${value}; Path=/; Max-Age=${maxAge}; HttpOnly; Secure; SameSite=Strict`;
}

async function login(request, env) {
  let password = "";
  try {
    const form = new URLSearchParams(await request.text());
    password = form.get("password") || "";
  } catch { /* falls through to the error page */ }
  if (!safeEqual(password, env.ADMIN_PASSWORD)) return loginPage(true);
  const exp = Math.floor(Date.now() / 1000) + SESSION_DAYS * 86400;
  const token = await signSession(sessionSecret(env), exp);
  return new Response(null, {
    status: 303,
    headers: { location: "/admin", "set-cookie": cookieHeader(token, SESSION_DAYS * 86400), "cache-control": "no-store" },
  });
}

function logout() {
  return new Response(null, { status: 303, headers: { location: "/admin", "set-cookie": cookieHeader("", 0) } });
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (request.method === "OPTIONS" && pathname === "/hit") {
      const origin = request.headers.get("origin");
      return allowedOrigin(origin) ? new Response(null, { status: 204, headers: cors(origin) }) : new Response(null, { status: 403 });
    }
    if (request.method === "POST" && pathname === "/hit") return recordHit(request, env);
    if (request.method === "POST" && pathname === "/admin/stats") return stats(request, env);
    if (request.method === "POST" && pathname === "/admin/login") return login(request, env);
    if (request.method === "POST" && pathname === "/admin/logout") return logout();
    if (request.method === "GET" && pathname === "/admin") {
      if (!(await signedIn(request, env))) return loginPage(false);
      return new Response(ADMIN_HTML, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
    }
    return json({ error: "not found" }, 404);
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(env.DB.prepare("DELETE FROM hits WHERE day < date('now', '-90 day')").run());
  },
};
