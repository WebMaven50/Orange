import { test } from "node:test";
import assert from "node:assert/strict";
import { makeProviderToken, sendPush } from "../src/apns.js";

async function keyPair() {
  const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", kp.privateKey));
  const b64 = btoa(String.fromCharCode(...der));
  const p8 = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----`;
  return { p8, publicKey: kp.publicKey };
}

test("provider token is a valid ES256 JWT with the right header and claims", async () => {
  const { p8, publicKey } = await keyPair();
  const jwt = await makeProviderToken({ p8, keyId: "KEYID12345", teamId: "TEAMID1234", now: 1_700_000_000 });
  const [h, c, s] = jwt.split(".");
  const dec = (x) => JSON.parse(Buffer.from(x, "base64url").toString("utf8"));
  assert.deepEqual(dec(h), { alg: "ES256", kid: "KEYID12345" });
  assert.deepEqual(dec(c), { iss: "TEAMID1234", iat: 1_700_000_000 });
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey,
    Buffer.from(s, "base64url"), new TextEncoder().encode(`${h}.${c}`));
  assert.ok(ok, "signature verifies against the public key");
});

test("sends to the production or sandbox host with the right headers", async () => {
  const seen = [];
  const fake = async (url, init) => {
    seen.push({ url, init });
    return new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 });
  };
  const payload = { aps: { alert: { title: "t", body: "b" } } };
  const r = await sendPush({ token: "a".repeat(64), sandbox: true, payload, topic: "com.theorangerobot.trader", jwt: "x.y.z", fetchImpl: fake });
  assert.equal(seen[0].url, `https://api.sandbox.push.apple.com/3/device/${"a".repeat(64)}`);
  assert.equal(seen[0].init.headers["apns-topic"], "com.theorangerobot.trader");
  assert.equal(seen[0].init.headers["apns-push-type"], "alert");
  assert.equal(r.status, 400);
  assert.equal(r.reason, "BadDeviceToken");
  await sendPush({ token: "a".repeat(64), sandbox: false, payload, topic: "t", jwt: "x", fetchImpl: fake });
  assert.equal(seen[1].url.startsWith("https://api.push.apple.com/3/device/"), true);
});
