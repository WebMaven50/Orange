// The Orange Robot notify Worker.
//
// Stores only what it needs to deliver a push: the device's push token (as a key),
// whether it is sandbox, and whether it wants price alerts. No accounts, no IP
// addresses, no logs of tokens. Turning notifications off deletes the token.

import { isValidToken, safeEqual, percentChange, priceAlert, buildPayload, checkMessage } from "./logic.js";
import { makeProviderToken, sendPush } from "./apns.js";

const JSON_HEADERS = { "content-type": "application/json", "cache-control": "no-store" };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });

// The APNs provider token is valid for up to an hour; reuse it for 50 minutes.
let cachedJwt = { value: null, expires: 0 };
async function providerJwt(env) {
  const now = Date.now();
  if (cachedJwt.value && now < cachedJwt.expires) return cachedJwt.value;
  const value = await makeProviderToken({
    p8: env.APNS_KEY_P8, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID,
    now: Math.floor(now / 1000),
  });
  cachedJwt = { value, expires: now + 50 * 60 * 1000 };
  return value;
}

async function readJson(request, maxBytes = 2048) {
  const text = await request.text();
  if (text.length > maxBytes) throw new Error("too large");
  return JSON.parse(text);
}

async function registerDevice(request, env) {
  let body;
  try { body = await readJson(request); } catch { return json({ error: "bad request" }, 400); }
  if (!isValidToken(body.token)) return json({ error: "bad token" }, 400);
  await env.DEVICES.put(`d:${body.token}`, JSON.stringify({
    sandbox: body.sandbox === true,
    messages: body.messages === true,
    alerts: body.alerts === true,
    added: new Date().toISOString().slice(0, 10),
  }));
  return json({ ok: true });
}

async function removeDevice(request, env) {
  let body;
  try { body = await readJson(request); } catch { return json({ error: "bad request" }, 400); }
  if (!isValidToken(body.token)) return json({ error: "bad token" }, 400);
  await env.DEVICES.delete(`d:${body.token}`);
  return json({ ok: true });
}

/** Sends to every stored device that passes `wants`. Removes tokens Apple says are gone. */
async function sendToAll(env, payload, wants = () => true) {
  const jwt = await providerJwt(env);
  const tally = { sent: 0, failed: 0, removed: 0 };
  let cursor;
  do {
    const page = await env.DEVICES.list({ prefix: "d:", cursor });
    cursor = page.list_complete ? undefined : page.cursor;
    const keys = page.keys.map((k) => k.name);
    for (let i = 0; i < keys.length; i += 25) {
      await Promise.all(keys.slice(i, i + 25).map(async (name) => {
        const device = JSON.parse((await env.DEVICES.get(name)) ?? "null");
        if (!device || !wants(device)) return;
        const token = name.slice(2);
        const r = await sendPush({
          token, sandbox: device.sandbox, payload, topic: env.APNS_TOPIC, jwt,
        });
        if (r.status === 200) { tally.sent++; return; }
        if (r.status === 410 || r.reason === "BadDeviceToken" || r.reason === "Unregistered") {
          await env.DEVICES.delete(name);
          tally.removed++;
        } else {
          tally.failed++;
        }
      }));
    }
  } while (cursor);
  return tally;
}

async function adminSend(request, env) {
  let body;
  try { body = await readJson(request, 4096); } catch { return json({ error: "bad request" }, 400); }
  if (!safeEqual(body.password, env.ADMIN_PASSWORD)) return json({ error: "wrong password" }, 403);
  const message = { title: body.title, body: body.body, url: body.url || undefined };
  const problem = checkMessage(message);
  if (problem) return json({ error: problem }, 400);
  const tally = await sendToAll(env, buildPayload(message), (d) => d.messages);
  return json({ ok: true, ...tally });
}

/** Once a day at most: if Bitcoin is far enough from its UTC open, tell the price-alert devices. */
async function checkPriceMoves(env) {
  const [ticker, daily] = await Promise.all([
    fetch("https://api.kraken.com/0/public/Ticker?pair=XBTUSD").then((r) => r.json()),
    fetch("https://api.kraken.com/0/public/OHLC?pair=XBTUSD&interval=1440").then((r) => r.json()),
  ]);
  const tickerKey = Object.keys(ticker.result ?? {})[0];
  const price = Number(ticker.result?.[tickerKey]?.c?.[0]);
  const rows = daily.result?.[Object.keys(daily.result ?? {}).find((k) => k !== "last")] ?? [];
  const today = rows[rows.length - 1];
  const open = Number(today?.[1]);
  const alert = priceAlert(percentChange(price, open));
  if (!alert) return;
  const day = new Date().toISOString().slice(0, 10);
  const marker = `alerted:${day}:${alert.dir}`;
  if (await env.DEVICES.get(marker)) return;
  await env.DEVICES.put(marker, "1", { expirationTtl: 2 * 24 * 3600 });
  await sendToAll(env, buildPayload({ title: alert.title, body: alert.body }), (d) => d.alerts);
}

const ADMIN_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Game messages</title>
<style>
 body{font:16px -apple-system,system-ui,sans-serif;background:#0b0b0b;color:#eee;margin:0;padding:20px;max-width:560px}
 h1{font-size:20px;color:#f7821a} label{display:block;margin:14px 0 4px;font-size:13px;color:#aaa}
 input,textarea{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #333;background:#171717;color:#eee;font:inherit}
 textarea{min-height:90px} button{margin-top:18px;width:100%;padding:14px;border:0;border-radius:10px;background:#f7821a;color:#000;font-weight:800;font-size:16px}
 #out{margin-top:16px;font-size:14px;color:#ccc;white-space:pre-wrap}
 p.note{font-size:13px;color:#888}
</style></head><body>
<h1>Send a message to players</h1>
<p class="note">Goes to everyone who turned notifications on in the game. Nothing is sent automatically. Check the text before you send.</p>
<label for="pw">Admin password</label><input id="pw" type="password" autocomplete="off">
<label for="t">Title (under 80 characters)</label><input id="t" maxlength="80">
<label for="b">Message (under 240 characters)</label><textarea id="b" maxlength="240"></textarea>
<label for="u">Optional link (https only)</label><input id="u" type="url" placeholder="https://">
<button id="send">Send to everyone who opted in</button>
<div id="out"></div>
<script>
document.getElementById('send').addEventListener('click', async () => {
  const out = document.getElementById('out');
  if (!confirm('Send this message to all opted-in players now?')) return;
  out.textContent = 'Sending…';
  const res = await fetch('/admin/send', {
    method: 'POST', headers: {'content-type': 'application/json'},
    body: JSON.stringify({
      password: document.getElementById('pw').value,
      title: document.getElementById('t').value,
      body: document.getElementById('b').value,
      url: document.getElementById('u').value,
    }),
  });
  const data = await res.json().catch(() => ({}));
  out.textContent = res.ok
    ? 'Sent: ' + data.sent + ' · failed: ' + data.failed + ' · removed (no longer valid): ' + data.removed
    : (data.error || 'Something went wrong.');
});
</script></body></html>`;

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (request.method === "POST" && pathname === "/device") return registerDevice(request, env);
    if (request.method === "POST" && pathname === "/device/remove") return removeDevice(request, env);
    if (request.method === "POST" && pathname === "/admin/send") return adminSend(request, env);
    if (request.method === "GET" && pathname === "/admin") {
      return new Response(ADMIN_HTML, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
    }
    return json({ error: "not found" }, 404);
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(checkPriceMoves(env));
  },
};
