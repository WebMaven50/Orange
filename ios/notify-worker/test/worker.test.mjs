import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

function memoryKV() {
  const m = new Map();
  return {
    m,
    async put(k, v) { m.set(k, v); },
    async get(k) { return m.has(k) ? m.get(k) : null; },
    async delete(k) { m.delete(k); },
    async list({ prefix = "" } = {}) {
      return { keys: [...m.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })), list_complete: true };
    },
  };
}

const req = (path, body, method = "POST") => new Request(`https://x.test${path}`, {
  method, headers: { "content-type": "application/json" },
  body: body === undefined ? undefined : JSON.stringify(body),
});

test("registering stores only the token, sandbox flag and alert choice", async () => {
  const env = { DEVICES: memoryKV() };
  const token = "b".repeat(64);
  const res = await worker.fetch(req("/device", { token, sandbox: true, messages: true, alerts: false, extra: "nope" }), env);
  assert.equal(res.status, 200);
  const stored = JSON.parse(env.DEVICES.m.get(`d:${token}`));
  assert.deepEqual(Object.keys(stored).sort(), ["added", "alerts", "messages", "sandbox", "threshold"]);
  assert.equal(stored.threshold, 5, "defaults to 5%");
  assert.equal(stored.alerts, false);
});

test("admin messages go only to devices that opted in to messages", async () => {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  const p8 = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
  const env = { DEVICES: memoryKV(), ADMIN_PASSWORD: "right", APNS_TOPIC: "com.test.app", APNS_KEY_P8: p8, APNS_KEY_ID: "KEYID12345", APNS_TEAM_ID: "TEAMID1234" };
  const optedIn = "1".repeat(64), alertsOnly = "2".repeat(64);
  await worker.fetch(req("/device", { token: optedIn, messages: true }), env);
  await worker.fetch(req("/device", { token: alertsOnly, messages: false, alerts: true }), env);
  const realFetch = globalThis.fetch;
  const contacted = [];
  globalThis.fetch = async (url, init) => { contacted.push({ url, init }); return new Response("{}", { status: 200 }); };
  try {
    const res = await worker.fetch(req("/admin/send", { password: "right", title: "Hi", body: "There" }), env);
    const out = await res.json();
    assert.equal(res.status, 200);
    assert.equal(out.sent, 1);
    assert.equal(contacted.length, 1, "only the opted-in device is contacted");
    assert.ok(contacted[0].url.endsWith("/3/device/" + optedIn));
    assert.match(contacted[0].init.headers.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    assert.equal(JSON.parse(contacted[0].init.body).aps.alert.title, "Hi");
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("bad tokens are refused and nothing is stored", async () => {
  const env = { DEVICES: memoryKV() };
  const res = await worker.fetch(req("/device", { token: "not-a-token" }), env);
  assert.equal(res.status, 400);
  assert.equal(env.DEVICES.m.size, 0);
});

test("turning notifications off removes the token", async () => {
  const env = { DEVICES: memoryKV() };
  const token = "c".repeat(64);
  await worker.fetch(req("/device", { token }), env);
  await worker.fetch(req("/device/remove", { token }), env);
  assert.equal(env.DEVICES.m.size, 0);
});

test("the admin send refuses a wrong password and sends nothing", async () => {
  const env = { DEVICES: memoryKV(), ADMIN_PASSWORD: "right" };
  await worker.fetch(req("/device", { token: "d".repeat(64) }), env);
  const res = await worker.fetch(req("/admin/send", { password: "wrong", title: "t", body: "b" }), env);
  assert.equal(res.status, 403);
});

test("sends are checked for a valid message", async () => {
  const env = { DEVICES: memoryKV(), ADMIN_PASSWORD: "right" };
  const bad = await worker.fetch(req("/admin/send", { password: "right", title: "t", body: "b", url: "http://insecure" }), env);
  assert.equal(bad.status, 400);
});

const formPost = (path, body, cookie) => new Request(`https://x.test${path}`, {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded", ...(cookie ? { cookie } : {}) },
  body,
});

test("the message page needs a sign-in, and the sign-in page works with password managers", async () => {
  const env = { DEVICES: memoryKV(), ADMIN_PASSWORD: "right" };
  const page = await worker.fetch(new Request("https://x.test/admin"), env);
  const html = await page.text();
  assert.match(html, /autocomplete="username"/);
  assert.match(html, /autocomplete="current-password"/);
  assert.ok(!/Send to everyone who opted in/.test(html), "the send form is not shown when signed out");
  const wrong = await worker.fetch(formPost("/admin/login", "password=nope"), env);
  assert.equal(wrong.status, 401);
  assert.equal(wrong.headers.get("set-cookie"), null);
});

test("signing in sets a 30-day cookie that opens the page and allows sending", async () => {
  const env = { DEVICES: memoryKV(), ADMIN_PASSWORD: "right" };
  const res = await worker.fetch(formPost("/admin/login", "username=game-messages&password=right"), env);
  assert.equal(res.status, 303);
  const cookie = res.headers.get("set-cookie");
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /Secure/);
  assert.match(cookie, /SameSite=Strict/);
  assert.match(cookie, /Max-Age=2592000/);
  const pair = cookie.split(";")[0];
  const page = await worker.fetch(new Request("https://x.test/admin", { headers: { cookie: pair } }), env);
  assert.match(await page.text(), /Send to everyone who opted in/);
  // A valid session lets a message through the checks (this one fails only on its bad link).
  const send = await worker.fetch(new Request("https://x.test/admin/send", {
    method: "POST", headers: { cookie: pair, "content-type": "application/json" },
    body: JSON.stringify({ title: "t", body: "b", url: "http://insecure" }),
  }), env);
  assert.equal(send.status, 400);
  const noSession = await worker.fetch(new Request("https://x.test/admin/send", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ title: "t", body: "b" }),
  }), env);
  assert.equal(noSession.status, 403);
});

test("a changed password or a forged cookie does not open the message page", async () => {
  const env = { DEVICES: memoryKV(), ADMIN_PASSWORD: "right" };
  const login = await worker.fetch(formPost("/admin/login", "password=right"), env);
  const pair = login.headers.get("set-cookie").split(";")[0];
  const changed = await worker.fetch(new Request("https://x.test/admin", { headers: { cookie: pair } }), { ...env, ADMIN_PASSWORD: "new" });
  assert.match(await changed.text(), /Sign in/);
  const forged = await worker.fetch(new Request("https://x.test/admin", { headers: { cookie: "sr_notify_admin=9999999999.AAAA" } }), env);
  assert.match(await forged.text(), /Sign in/);
  const out = await worker.fetch(formPost("/admin/logout", ""), env);
  assert.match(out.headers.get("set-cookie"), /Max-Age=0/);
});


test("unknown paths are not found", async () => {
  const res = await worker.fetch(new Request("https://x.test/nope"), { DEVICES: memoryKV() });
  assert.equal(res.status, 404);
});
