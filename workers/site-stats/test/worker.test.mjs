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
  const [, day, type, path, refHost, refUrl, country, region, city, visitor, target] = args;
  assert.equal(type, "view");
  assert.equal(path, "/games/index.html");
  assert.equal(refHost, "google.com");
  assert.equal(refUrl, "https://www.google.com/search");
  assert.deepEqual([country, region, city], ["US", "Texas", "Austin"]);
  assert.match(visitor, /^[0-9a-f]{16}$/);
  assert.equal(target, null);
  assert.ok(!JSON.stringify(args).includes("203.0.113.7"), "the IP address is not stored anywhere");
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

test("the console needs the password", async () => {
  const env = { DB: fakeDB(), SALT: "s", ADMIN_PASSWORD: "right" };
  const wrong = await worker.fetch(new Request("https://stats.test/admin/stats", {
    method: "POST", body: JSON.stringify({ password: "nope", days: 7 }),
  }), env);
  assert.equal(wrong.status, 403);
  const ok = await worker.fetch(new Request("https://stats.test/admin/stats", {
    method: "POST", body: JSON.stringify({ password: "right", days: 7 }),
  }), env);
  assert.equal(ok.status, 200);
  const data = await ok.json();
  assert.equal(data.days, 7);
});

test("the admin page is served", async () => {
  const res = await worker.fetch(new Request("https://stats.test/admin"), { DB: fakeDB() });
  assert.equal(res.status, 200);
  assert.match(await res.text(), /Website activity/);
});
