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
  assert.deepEqual(Object.keys(stored).sort(), ["added", "alerts", "messages", "sandbox"]);
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

test("the admin page is served and sends are checked", async () => {
  const env = { DEVICES: memoryKV(), ADMIN_PASSWORD: "right" }; 
  const page = await worker.fetch(new Request("https://x.test/admin"), env);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /Send to everyone who opted in/);
  const bad = await worker.fetch(req("/admin/send", { password: "right", title: "t", body: "b", url: "http://insecure" }), env);
  assert.equal(bad.status, 400);
});

test("unknown paths are not found", async () => {
  const res = await worker.fetch(new Request("https://x.test/nope"), { DEVICES: memoryKV() });
  assert.equal(res.status, 404);
});
