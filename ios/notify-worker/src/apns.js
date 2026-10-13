// Apple Push Notification service (APNs) over HTTP/2, authenticated with a .p8 key.
// Uses only Web Crypto and fetch, so it runs in a Cloudflare Worker.

const enc = new TextEncoder();

function b64url(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem) {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

/** The short-lived signed token APNs asks for in the `authorization` header (ES256). */
export async function makeProviderToken({ p8, keyId, teamId, now = Math.floor(Date.now() / 1000) }) {
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(p8), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: teamId, iat: now })));
  const input = `${header}.${claims}`;
  // Web Crypto returns the raw r||s signature, which is the format JWT wants.
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(input)));
  return `${input}.${b64url(sig)}`;
}

/** Send one alert. Returns the HTTP status and Apple's reason when it refused. */
export async function sendPush({ token, sandbox, payload, topic, jwt, fetchImpl = fetch }) {
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetchImpl(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  let reason = null;
  if (res.status !== 200) {
    reason = (await res.json().catch(() => ({}))).reason ?? `HTTP ${res.status}`;
  }
  return { status: res.status, reason };
}
