// Pure helpers for the site-stats Worker. No network or storage, so they can be tested directly.

/** Host of a URL, lowercased, without a leading "www.". Empty string when it isn't a URL. */
export function hostOf(url) {
  try {
    return new URL(url).hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return "";
  }
}

/** Where a visit came from: "(direct)", "(internal)" (a link within the site), or the referring host. */
export function classifyReferrer(referrer, siteHost) {
  if (!referrer) return "(direct)";
  const host = hostOf(referrer);
  if (!host) return "(direct)";
  return host === siteHost.replace(/^www\./, "") ? "(internal)" : host;
}

/** Cut a string to `n` characters, tolerating missing values. */
export function clip(value, n) {
  return typeof value === "string" ? value.slice(0, n) : "";
}

/** The page path only: no query string and no fragment, so tokens in URLs are never stored. */
export function cleanPath(p) {
  if (typeof p !== "string") return "/";
  const path = p.split("?")[0].split("#")[0].trim();
  return clip(path.startsWith("/") ? path : "/" + path, 200);
}

/** Referrer URL stripped of its query string and fragment, shortened. */
export function cleanReferrerUrl(r) {
  if (typeof r !== "string" || !r) return "";
  try {
    const u = new URL(r);
    return clip(`${u.protocol}//${u.host}${u.pathname}`, 300);
  } catch {
    return "";
  }
}

/** A click label with any query string removed from URLs inside it. */
export function cleanClickTarget(t) {
  if (typeof t !== "string") return "";
  return clip(t.replace(/\?[^\s]*/g, "").trim(), 200);
}

const BOT_RE = /bot|crawl|spider|slurp|facebookexternalhit|preview|headless|lighthouse|monitor|curl|wget|python-requests/i;
/** Obvious crawlers and scripts, which would only add noise. */
export function isBot(userAgent) {
  return !userAgent || BOT_RE.test(userAgent);
}

/**
 * A one-way visitor identifier that changes every day.
 * The IP address and user agent go in, only 16 hex characters of a SHA-256 come out, and the
 * input is never stored. It can count unique visitors within a day, but it can't be reversed,
 * and it can't follow someone from one day to the next.
 */
export async function visitorHash(secret, day, ip, userAgent) {
  const data = new TextEncoder().encode(`${secret}|${day}|${ip}|${userAgent}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].slice(0, 8).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Constant-time string comparison for the admin password. */
export function safeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const enc = new TextEncoder();
  const x = enc.encode(a), y = enc.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** Only these origins may send hits. */
export function allowedOrigin(origin) {
  return origin === "https://theorangerobot.com" || origin === "https://www.theorangerobot.com";
}
