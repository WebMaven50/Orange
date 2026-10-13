import { test } from "node:test";
import assert from "node:assert/strict";
import { isValidToken, safeEqual, percentChange, priceAlert, buildPayload, checkMessage, clampThreshold } from "../src/logic.js";

test("tokens must be 64 lowercase hex characters", () => {
  assert.ok(isValidToken("a".repeat(64)));
  assert.ok(!isValidToken("A".repeat(64)));
  assert.ok(!isValidToken("a".repeat(63)));
  assert.ok(!isValidToken(undefined));
});

test("admin password comparison", () => {
  assert.ok(safeEqual("secret", "secret"));
  assert.ok(!safeEqual("secret", "secreT"));
  assert.ok(!safeEqual("secret", "secret2"));
  assert.ok(!safeEqual(undefined, "x"));
});

test("price alerts only past the threshold", () => {
  assert.equal(percentChange(105, 100), 5);
  assert.equal(priceAlert(4.9), null);
  assert.equal(priceAlert(-4.9), null);
  assert.match(priceAlert(5.2).title, /up \+5\.2% today/);
  assert.match(priceAlert(-6).title, /down −6\.0% today/);
  assert.equal(percentChange(0, 100), null);
});

test("payload carries the link only when given", () => {
  assert.deepEqual(buildPayload({ title: "t", body: "b" }).aps.alert, { title: "t", body: "b" });
  assert.equal(buildPayload({ title: "t", body: "b", url: "https://example.com" }).url, "https://example.com");
  assert.equal(buildPayload({ title: "t", body: "b" }).url, undefined);
});

test("admin messages are checked before sending", () => {
  assert.equal(checkMessage({ title: "Hi", body: "There" }), null);
  assert.ok(checkMessage({ title: "", body: "x" }));
  assert.ok(checkMessage({ title: "x", body: "" }));
  assert.ok(checkMessage({ title: "x".repeat(81), body: "x" }));
  assert.ok(checkMessage({ title: "x", body: "x", url: "http://insecure.example" }));
  assert.ok(checkMessage({ title: "x", body: "x", url: "not a url" }));
  assert.equal(checkMessage({ title: "x", body: "x", url: "https://example.com/podcast" }), null);
});

test("each phone's threshold is kept in 1-20%, defaulting to 5", () => {
  assert.equal(clampThreshold(undefined), 5);
  assert.equal(clampThreshold(3), 3);
  assert.equal(clampThreshold(0), 5);
  assert.equal(clampThreshold(50), 5);
  assert.equal(clampThreshold("abc"), 5);
});

test("a per-phone threshold changes which moves alert", () => {
  assert.notEqual(priceAlert(2.5, 2), null);
  assert.equal(priceAlert(2.5, 3), null);
  assert.match(priceAlert(-2.5, 2).title, /down/);
});
