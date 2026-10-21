import { beforeEach, expect, test } from "vitest";
import { env, SELF, applyD1Migrations } from "cloudflare:test";

beforeEach(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM devices"),
    env.DB.prepare("UPDATE score_counts SET n = 0"),
  ]);
});
const payload = (token = "device-0001", score = 70) => ({
  device_token: token, score,
  dims: { routing: 60, timing: 70, context: 80, leverage: 90 }, app_version: "1.0",
});
const post = (body) => SELF.fetch("https://test.local/v1/score", {
  method: "POST", body: JSON.stringify(body),
});

test("rejects extra, missing, malformed, oversized, and out-of-range fields", async () => {
  const missing = payload(); delete missing.dims.context;
  const extraDim = payload(); extraDim.dims.extra = 1;
  for (const body of [{ ...payload(), private: "secret" }, missing, extraDim,
    { ...payload(), score: 101 }, { ...payload(), score: true },
    { ...payload(), score: 2.5 }, { ...payload(), dims: null },
    { ...payload(), device_token: "bad_token" }, { ...payload(), app_version: "x".repeat(21) },
    { ...payload(), padding: "x".repeat(1024) }, null, []]) {
    const response = await post(body);
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid" });
  }
  const malformed = await SELF.fetch("https://test.local/v1/score", { method: "POST", body: "{" });
  expect(malformed.status).toBe(422);
  expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM devices").first()).n).toBe(0);
});

test("first device and throttle, then moves bucket atomically after one hour", async () => {
  const response = await post(payload());
  expect(response.status).toBe(200);
  expect(response.headers.get("access-control-allow-origin")).toBeNull();
  expect(await response.json()).toEqual({ total: 1, rank: 1, percentile: null, small_sample: true });
  await post(payload("device-0001", 80));
  expect((await env.DB.prepare("SELECT score FROM devices").first()).score).toBe(70);
  await env.DB.prepare("UPDATE devices SET updated_at = ?").bind("2000-01-01T00:00:00.000Z").run();
  expect((await (await post(payload("device-0001", 80))).json()).total).toBe(1);
  expect((await env.DB.prepare("SELECT n FROM score_counts WHERE score = 70").first()).n).toBe(0);
  expect((await env.DB.prepare("SELECT n FROM score_counts WHERE score = 80").first()).n).toBe(1);
  await env.DB.prepare("UPDATE devices SET updated_at = ?").bind("2000-01-01T00:00:00.000Z").run();
  await post(payload("device-0001", 80));
  expect((await env.DB.prepare("SELECT SUM(n) AS n FROM score_counts").first()).n).toBe(1);
});

test("25 devices, ties, and percentile use lower and higher score buckets", async () => {
  for (let i = 0; i < 25; i++) await post(payload(`device-${String(i).padStart(4, "0")}`, i * 4));
  expect(await (await post(payload("device-0012", 48))).json()).toEqual({
    total: 25, rank: 13, percentile: 50, small_sample: false,
  });
  expect(await (await post(payload("device-tied", 48))).json()).toEqual({
    total: 26, rank: 13, percentile: 48, small_sample: false,
  });
  expect((await (await post(payload("device-0024", 96))).json()).percentile).toBe(100);
});

test("other paths and methods return 404", async () => {
  for (const [method, path] of [["GET", "/v1/score"], ["OPTIONS", "/v1/score"], ["POST", "/other"]]) {
    expect((await SELF.fetch(`https://test.local${path}`, { method })).status).toBe(404);
  }
});

test("enforces the byte limit even for otherwise valid JSON", async () => {
  const json = JSON.stringify(payload());
  for (const [size, expected] of [[1025, 422], [1024, 200]]) {
    const response = await SELF.fetch("https://test.local/v1/score", {
      method: "POST", body: json.padEnd(size, " "),
    });
    expect(response.status).toBe(expected);
  }
});

test("simultaneous submissions for one device leave exactly one bucket entry", async () => {
  await Promise.all([0, 25, 50, 75, 100].map((score) => post(payload("concurrent-device", score))));
  const stored = await env.DB.prepare("SELECT score FROM devices").first();
  const buckets = await env.DB.prepare("SELECT score, n FROM score_counts WHERE n <> 0").all();
  expect(buckets.results).toEqual([{ score: stored.score, n: 1 }]);
  expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM devices").first()).n).toBe(1);
});
