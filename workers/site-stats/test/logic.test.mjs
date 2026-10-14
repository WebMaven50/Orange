import { test } from "node:test";
import assert from "node:assert/strict";
import {
  hostOf, classifyReferrer, cleanPath, cleanReferrerUrl, cleanClickTarget, isBot, visitorHash, safeEqual, allowedOrigin, parseDevice,
} from "../src/logic.js";

test("referrers are classified as direct, internal, or the outside host", () => {
  const site = "theorangerobot.com";
  assert.equal(classifyReferrer("", site), "(direct)");
  assert.equal(classifyReferrer("not a url", site), "(direct)");
  assert.equal(classifyReferrer("https://www.theorangerobot.com/games/", site), "(internal)");
  assert.equal(classifyReferrer("https://www.google.com/search?q=x", site), "google.com");
  assert.equal(classifyReferrer("https://t.co/abc", site), "t.co");
  assert.equal(hostOf("https://WWW.Example.com/x"), "example.com");
});

test("paths and referrers never keep query strings or fragments", () => {
  assert.equal(cleanPath("/store/order-status.html?order=SECRET#top"), "/store/order-status.html");
  assert.equal(cleanPath("games/x.html"), "/games/x.html");
  assert.equal(cleanPath(undefined), "/");
  assert.equal(cleanReferrerUrl("https://news.example.com/story?utm=1&id=9#c"), "https://news.example.com/story");
  assert.equal(cleanReferrerUrl("junk"), "");
  assert.equal(cleanClickTarget("Buy the book → https://x.com/buy?token=abc"), "Buy the book → https://x.com/buy");
});

test("crawlers and scripts are skipped, ordinary browsers are not", () => {
  assert.ok(isBot("Mozilla/5.0 (compatible; Googlebot/2.1)"));
  assert.ok(isBot(""));
  assert.ok(isBot("curl/8.1"));
  assert.ok(!isBot("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1"));
});

test("the visitor hash is stable within a day, differs across days and people, and hides the IP", async () => {
  const a = await visitorHash("salt", "2026-10-13", "203.0.113.7", "UA1");
  assert.equal(a, await visitorHash("salt", "2026-10-13", "203.0.113.7", "UA1"));
  assert.notEqual(a, await visitorHash("salt", "2026-10-14", "203.0.113.7", "UA1"));
  assert.notEqual(a, await visitorHash("salt", "2026-10-13", "203.0.113.8", "UA1"));
  assert.notEqual(a, await visitorHash("other", "2026-10-13", "203.0.113.7", "UA1"));
  assert.match(a, /^[0-9a-f]{16}$/);
  assert.ok(!a.includes("203"), "no trace of the address");
});

test("only the site's own origins may report", () => {
  assert.ok(allowedOrigin("https://theorangerobot.com"));
  assert.ok(allowedOrigin("https://www.theorangerobot.com"));
  assert.ok(!allowedOrigin("https://evil.example"));
  assert.ok(!allowedOrigin(undefined));
});

test("admin password comparison", () => {
  assert.ok(safeEqual("pw", "pw"));
  assert.ok(!safeEqual("pw", "pW"));
  assert.ok(!safeEqual(undefined, "pw"));
});

test("devices are reduced to broad categories", () => {
  const iphone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
  assert.deepEqual(parseDevice(iphone), { device: "phone", os: "iOS", browser: "Safari" });
  const ipad = "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
  assert.deepEqual(parseDevice(ipad), { device: "tablet", os: "iOS", browser: "Safari" });
  const chromeWin = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";
  assert.deepEqual(parseDevice(chromeWin), { device: "desktop", os: "Windows", browser: "Chrome" });
  const edge = chromeWin + " Edg/130.0.0.0";
  assert.equal(parseDevice(edge).browser, "Edge");
  const androidPhone = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36";
  assert.deepEqual(parseDevice(androidPhone), { device: "phone", os: "Android", browser: "Chrome" });
  const macSafari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";
  assert.deepEqual(parseDevice(macSafari), { device: "desktop", os: "macOS", browser: "Safari" });
  const firefox = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";
  assert.deepEqual(parseDevice(firefox), { device: "desktop", os: "Linux", browser: "Firefox" });
  assert.deepEqual(parseDevice(undefined), { device: "desktop", os: "Other", browser: "Other" });
});
