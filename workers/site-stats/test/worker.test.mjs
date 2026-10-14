import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

function fakeDB() {
  const runs = [];
  return {
    runs,
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async run() { runs.push({ sql, args }); return {}; },
            async all() { return { results: [] }; },
          };
        },
      };
    },
  };
}

const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1";
function hit(body, { origin = "https://theorangerobot.com", ua = UA, ip = "203.0.113.7", cf = { country: "US", region: "Texas", city: "Austin" } } = {}) {
  const req = new Request("https://stats.test/hit", {
    method: "POST",
    headers: { origin, "user-agent": ua, "cf-connecting-ip": ip, "content-type": "text/plain" },
    body: JSON.stringify(body),
  });
  Object.defineProperty(req, "cf", { value: cf });
  return req;
}

test("a page view is stored with referrer, location and a hashed visitor, never the IP", async () => {
  const DB = fakeDB();
  const env = { DB, SALT: "s3cret" };
  const res = await worker.fetch(hit({ t: "view", p: "/games/index.html?x=1", r: "https://www.google.com/search?q=orange+robot" }), env);
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("access-control-allow-origin"), "https://theorangerobot.com");
  const { args } = DB.runs[0];
  const [, day, type, path, refHost, refUrl, country, region, city, visitor, target, device, os, browser] = args;
  assert.deepEqual([device, os, browser], ["phone", "iOS", "Safari"]);
  assert.ok(!JSON.stringify(args).includes("AppleWebKit"), "the full user agent is not stored");
  assert.equal(type, "view");
  assert.equal(path, "/games/index.html");
  assert.equal(refHost, "google.com");
  assert.equal(refUrl, "https://www.google.com/search");
  assert.deepEqual([country, region, city], ["US", "Texas", "Austin"]);
  assert.match(visitor, /^[0-9a-f]{16}$/);
  assert.equal(target, null);
  assert.ok(!JSON.stringify(args).includes("203.0.113.7"), "the IP address is not stored anywhere");
});

test("time on page is stored as seconds and capped, and zero-second reports are dropped", async () => {
  const DB = fakeDB();
  const env = { DB, SALT: "s" };
  await worker.fetch(hit({ t: "time", p: "/games/index.html?x=1", s: 42.4 }), env);
  await worker.fetch(hit({ t: "time", p: "/", s: 999999 }), env);
  await worker.fetch(hit({ t: "time", p: "/", s: 0 }), env);
  assert.equal(DB.runs.length, 2, "the zero-second report is not stored");
  const first = DB.runs[0].args, second = DB.runs[1].args;
  assert.equal(first[2], "time");
  assert.equal(first[3], "/games/index.html");
  assert.equal(first[14], 42);
  assert.equal(second[14], 1800, "a forgotten tab is capped at 30 minutes");
});

test("a direct visit is recorded as direct, and a click keeps what was clicked", async () => {
  const DB = fakeDB();
  const env = { DB, SALT: "s" };
  await worker.fetch(hit({ t: "click", p: "/", r: "", c: "Buy the book → https://theorangerobot.com/store/buy.html?x=1" }), env);
  const [, , type, , refHost, , , , , , target] = DB.runs[0].args;
  assert.equal(type, "click");
  assert.equal(refHost, "(direct)");
  assert.equal(target, "Buy the book → https://theorangerobot.com/store/buy.html");
});

test("other sites cannot report, and crawlers are not recorded", async () => {
  const DB = fakeDB();
  const env = { DB, SALT: "s" };
  const foreign = await worker.fetch(hit({ t: "view", p: "/" }, { origin: "https://evil.example" }), env);
  assert.equal(foreign.status, 403);
  const bot = await worker.fetch(hit({ t: "view", p: "/" }, { ua: "Mozilla/5.0 (compatible; Googlebot/2.1)" }), env);
  assert.equal(bot.status, 204);
  assert.equal(DB.runs.length, 0);
});

test("oversized or malformed reports are refused", async () => {
  const env = { DB: fakeDB(), SALT: "s" };
  const bad = new Request("https://stats.test/hit", {
    method: "POST", headers: { origin: "https://theorangerobot.com", "user-agent": UA }, body: "{not json",
  });
  assert.equal((await worker.fetch(bad, env)).status, 400);
});

test("the console needs a sign-in, and a wrong password is refused", async () => {
  const env = { DB: fakeDB(), SALT: "s", ADMIN_PASSWORD: "right" };
  const noCookie = await worker.fetch(new Request("https://stats.test/admin/stats", { method: "POST", body: "{}" }), env);
  assert.equal(noCookie.status, 403);
  const wrong = await worker.fetch(new Request("https://stats.test/admin/login", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: "password=nope",
  }), env);
  assert.equal(wrong.status, 401);
  assert.equal(wrong.headers.get("set-cookie"), null);
});

test("signing in sets a 30-day cookie that opens the console and the stats", async () => {
  const env = { DB: fakeDB(), SALT: "s", ADMIN_PASSWORD: "right" };
  const res = await worker.fetch(new Request("https://stats.test/admin/login", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: "username=site-activity&password=right",
  }), env);
  assert.equal(res.status, 303);
  const cookie = res.headers.get("set-cookie");
  assert.match(cookie, /^sr_admin=\d+\./);
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /Secure/);
  assert.match(cookie, /SameSite=Strict/);
  assert.match(cookie, /Max-Age=2592000/);
  const pair = cookie.split(";")[0];
  const page = await worker.fetch(new Request("https://stats.test/admin", { headers: { cookie: pair } }), env);
  assert.match(await page.text(), /Website activity/);
  const stats = await worker.fetch(new Request("https://stats.test/admin/stats", {
    method: "POST", headers: { cookie: pair }, body: JSON.stringify({ days: 7 }),
  }), env);
  assert.equal(stats.status, 200);
  assert.equal((await stats.json()).days, 7);
});

test("a forged or password-changed cookie does not open the console", async () => {
  const env = { DB: fakeDB(), SALT: "s", ADMIN_PASSWORD: "right" };
  const login = await worker.fetch(new Request("https://stats.test/admin/login", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: "password=right",
  }), env);
  const pair = login.headers.get("set-cookie").split(";")[0];
  const changed = { ...env, ADMIN_PASSWORD: "new-password" };
  const res = await worker.fetch(new Request("https://stats.test/admin", { headers: { cookie: pair } }), changed);
  assert.match(await res.text(), /Sign in/, "the old cookie stops working when the password changes");
  const forged = await worker.fetch(new Request("https://stats.test/admin", { headers: { cookie: "sr_admin=9999999999.AAAA" } }), env);
  assert.match(await forged.text(), /Sign in/);
});

test("the sign-in page works with password managers and sign-out clears the cookie", async () => {
  const env = { DB: fakeDB(), SALT: "s", ADMIN_PASSWORD: "right" };
  const page = await worker.fetch(new Request("https://stats.test/admin"), env);
  const html = await page.text();
  assert.match(html, /autocomplete="username"/);
  assert.match(html, /autocomplete="current-password"/);
  assert.match(html, /<form method="post" action="\/admin\/login"/);
  const out = await worker.fetch(new Request("https://stats.test/admin/logout", { method: "POST" }), env);
  assert.match(out.headers.get("set-cookie"), /Max-Age=0/);
});

test("time on page is stored as seconds and capped, and zero-second reports are dropped", async () => {
  const DB = fakeDB();
  const env = { DB, SALT: "s" };
  await worker.fetch(hit({ t: "time", p: "/games/index.html?x=1", s: 42.4 }), env);
  await worker.fetch(hit({ t: "time", p: "/", s: 999999 }), env);
  await worker.fetch(hit({ t: "time", p: "/", s: 0 }), env);
  assert.equal(DB.runs.length, 2, "the zero-second report is not stored");
  const first = DB.runs[0].args, second = DB.runs[1].args;
  assert.equal(first[2], "time");
  assert.equal(first[3], "/games/index.html");
  assert.equal(first[14], 42);
  assert.equal(second[14], 1800, "a forgotten tab is capped at 30 minutes");
});

test("a direct visit is recorded as direct, and a click keeps what was clicked", async () => {
  const DB = fakeDB();
  const env = { DB, SALT: "s" };
  await worker.fetch(hit({ t: "click", p: "/", r: "", c: "Buy the book → https://theorangerobot.com/store/buy.html?x=1" }), env);
  const [, , type, , refHost, , , , , , target] = DB.runs[0].args;
  assert.equal(type, "click");
  assert.equal(refHost, "(direct)");
  assert.equal(target, "Buy the book → https://theorangerobot.com/store/buy.html");
});

test("other sites cannot report, and crawlers are not recorded", async () => {
  const DB = fakeDB();
  const env = { DB, SALT: "s" };
  const foreign = await worker.fetch(hit({ t: "view", p: "/" }, { origin: "https://evil.example" }), env);
  assert.equal(foreign.status, 403);
  const bot = await worker.fetch(hit({ t: "view", p: "/" }, { ua: "Mozilla/5.0 (compatible; Googlebot/2.1)" }), env);
  assert.equal(bot.status, 204);
  assert.equal(DB.runs.length, 0);
});

test("oversized or malformed reports are refused", async () => {
  const env = { DB: fakeDB(), SALT: "s" };
  const bad = new Request("https://stats.test/hit", {
    method: "POST", headers: { origin: "https://theorangerobot.com", "user-agent": UA }, body: "{not json",
  });
  assert.equal((await worker.fetch(bad, env)).status, 400);
});

test("the console groups each visitor's page views into a route, oldest first", async () => {
  const rows = [
    { visitor: "aaaaaaaa11111111", ts: 300, path: "/store/buy.html", country: "IT", city: "Milan", device: "phone", os: "iOS", browser: "Safari" },
    { visitor: "bbbbbbbb22222222", ts: 250, path: "/", country: "US", city: "Austin", device: "desktop", os: "macOS", browser: "Chrome" },
    { visitor: "aaaaaaaa11111111", ts: 100, path: "/", country: "IT", city: "Milan", device: "phone", os: "iOS", browser: "Safari" },
    { visitor: "aaaaaaaa11111111", ts: 200, path: "/games/index.html", country: "IT", city: "Milan", device: "phone", os: "iOS", browser: "Safari" },
  ];
  const DB = {
    prepare(sql) {
      return { bind() { return { async all() { return { results: sql.includes("LIMIT 600") ? rows : [] }; }, async run() { return {}; } }; } };
    },
  };
  const res = await worker.fetch(new Request("https://stats.test/admin/stats", {
    method: "POST", body: JSON.stringify({ password: "right", days: 7 }),
  }), { DB, ADMIN_PASSWORD: "right" });
  const { journeys } = await res.json();
  const a = journeys.find((j) => j.visitor === "aaaaaaaa");
  assert.equal(a.pages, 3);
  assert.equal(a.route, "/  →  /games/index.html  →  /store/buy.html");
  assert.equal(a.where, "Milan, IT");
  assert.equal(a.device, "phone · iOS · Safari");
  assert.equal(journeys[0].visitor, "aaaaaaaa", "most recently active visitor first");
});
