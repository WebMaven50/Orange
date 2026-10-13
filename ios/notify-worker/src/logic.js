// Pure helpers for the notify Worker. No network or storage here, so they can be tested directly.

const TOKEN_RE = /^[0-9a-f]{64}$/;

/** A push token is 32 bytes as lowercase hex. Anything else is rejected. */
export function isValidToken(token) {
  return typeof token === "string" && TOKEN_RE.test(token);
}

/** Constant-time string comparison, so the admin password can't be guessed by timing. */
export function safeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const enc = new TextEncoder();
  const x = enc.encode(a), y = enc.encode(b);
  let diff = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** A phone's alert threshold, in percent. Anything missing or out of range falls back to 5. */
export function clampThreshold(v) {
  const n = Number(v);
  return Number.isFinite(n) && n >= 1 && n <= 20 ? n : 5;
}

/** Percent change of `price` against `open`. Null when there is no usable open. */
export function percentChange(price, open) {
  if (!(price > 0) || !(open > 0)) return null;
  return ((price - open) / open) * 100;
}

/** The price-move alert, or null while the move is still inside the threshold. */
export function priceAlert(changePercent, threshold = 5) {
  if (changePercent == null || Math.abs(changePercent) < threshold) return null;
  const dir = changePercent > 0 ? "up" : "down";
  const sign = changePercent > 0 ? "+" : "−";
  return {
    dir,
    title: `Bitcoin is ${dir} ${sign}${Math.abs(changePercent).toFixed(1)}% today`,
    body: "Open The Orange Robot Trader to see what the market is doing.",
  };
}

/** The APNs payload for a message. `url` opens when the notification is tapped. */
export function buildPayload({ title, body, url }) {
  const payload = { aps: { alert: { title, body }, sound: "default" } };
  if (url) payload.url = url;
  return payload;
}

/** Validates an admin message. Returns an error string, or null when it is fine. */
export function checkMessage({ title, body, url }) {
  if (typeof title !== "string" || title.trim().length === 0) return "A title is needed.";
  if (title.length > 80) return "Keep the title under 80 characters.";
  if (typeof body !== "string" || body.trim().length === 0) return "A message is needed.";
  if (body.length > 240) return "Keep the message under 240 characters.";
  if (url) {
    let parsed;
    try { parsed = new URL(url); } catch { return "The link isn't a valid web address."; }
    if (parsed.protocol !== "https:") return "The link must start with https://.";
  }
  return null;
}
