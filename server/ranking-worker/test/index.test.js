import { beforeEach, expect, test } from "vitest";
import { env, SELF, applyD1Migrations } from "cloudflare:test";

beforeEach(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM devices"),
    env.DB.prepare("DELETE FROM cohort_devices"),
    env.DB.prepare("DELETE FROM cohort_score_counts"),
    env.DB.prepare("DELETE FROM cohort_dim_counts"),
    env.DB.prepare("UPDATE score_counts SET n = 0"),
    env.DB.prepare("UPDATE dim_counts SET n = 0"),
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
  expect(await response.json()).toEqual({ total: 1, rank: 1, percentile: null, small_sample: true, dims: Object.fromEntries(
    Object.keys(payload().dims).map(dim => [dim, { rank: 1, percentile: null }])) });
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
    dims: Object.fromEntries(Object.keys(payload().dims).map(dim => [dim, { rank: 1, percentile: 0 }])),
  });
  expect(await (await post(payload("device-tied", 48))).json()).toEqual({
    total: 26, rank: 13, percentile: 48, small_sample: false,
    dims: Object.fromEntries(Object.keys(payload().dims).map(dim => [dim, { rank: 1, percentile: 0 }])),
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
  await Promise.all([0, 25, 50, 75, 100].map((score) => post({ ...payload("concurrent-device", score),
    dims: { routing: score, timing: 100 - score, context: score, leverage: 100 - score } })));
  const stored = await env.DB.prepare("SELECT * FROM devices").first();
  const buckets = await env.DB.prepare("SELECT score, n FROM score_counts WHERE n <> 0").all();
  expect(buckets.results).toEqual([{ score: stored.score, n: 1 }]);
  expect(await dimBuckets()).toEqual(Object.keys(payload().dims).sort().map(dim => ({ dim, score: stored[dim], n: 1 })));
  expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM devices").first()).n).toBe(1);
});

const dimBuckets = async () => (await env.DB.prepare(
  "SELECT dim, score, n FROM dim_counts WHERE n <> 0 ORDER BY dim, score").all()).results;

test("dimension buckets obey throttle and move even when overall is unchanged", async () => {
  const first = payload();
  const original = await (await post(first)).json();
  const before = await dimBuckets();
  const changed = { ...first, dims: { routing: 0, timing: 100, context: 80, leverage: 50 } };
  expect((await (await post(changed)).json()).dims).toEqual(original.dims);
  expect(await dimBuckets()).toEqual(before);
  await env.DB.prepare("UPDATE devices SET updated_at = '2000-01-01T00:00:00.000Z'").run();
  await post(changed);
  expect(await dimBuckets()).toEqual(Object.entries(changed.dims).sort().map(([dim, score]) => ({ dim, score, n: 1 })));
  expect((await env.DB.prepare("SELECT SUM(n) AS n FROM score_counts").first()).n).toBe(1);
  await env.DB.prepare("UPDATE devices SET updated_at = '2000-01-01T00:00:00.000Z'").run();
  await post(changed);
  expect(await dimBuckets()).toEqual(Object.entries(changed.dims).sort().map(([dim, score]) => ({ dim, score, n: 1 })));
});

test("each dimension ranks independently with ties and the 20-device boundary", async () => {
  for (let i = 0; i < 19; i++) {
    await post({ ...payload(`ranked-${String(i).padStart(4, "0")}`, 50),
      dims: { routing: i * 5, timing: 100 - i * 5, context: 50, leverage: 0 } });
  }
  const subject = { ...payload("ranked-subject", 50), dims: { routing: 50, timing: 50, context: 50, leverage: 100 } };
  const early = await (await post({ ...subject, device_token: "ranked-0000" })).json();
  expect(Object.values(early.dims).every(d => d.percentile === null)).toBe(true);
  const result = await (await post(subject)).json();
  expect(result.dims).toEqual({ routing: { rank: 9, percentile: 53 }, timing: { rank: 11, percentile: 42 },
    context: { rank: 1, percentile: 0 }, leverage: { rank: 1, percentile: 100 } });
});

test("dimension migration backfills existing devices and seeds every bucket", async () => {
  const migration = env.TEST_MIGRATIONS.find(m => m.name.includes("0003"));
  expect(migration).toBeDefined();
  await env.DB.prepare("DROP TABLE dim_counts").run();
  for (const token of ["legacy-one", "legacy-two"]) {
    await env.DB.prepare(`INSERT INTO devices (device_token, score, routing, timing, context, leverage, updated_at)
      VALUES (?, 70, 0, 100, 50, 75, '2000-01-01')`).bind(token).run();
  }
  await env.DB.batch(migration.queries.map(query => env.DB.prepare(query)));
  expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM dim_counts").first()).n).toBe(404);
  expect(await dimBuckets()).toEqual([
    { dim: "context", score: 50, n: 2 }, { dim: "leverage", score: 75, n: 2 },
    { dim: "routing", score: 0, n: 2 }, { dim: "timing", score: 100, n: 2 }]);
  await post(payload("legacy-one", 90));
  expect((await env.DB.prepare("SELECT n FROM dim_counts WHERE dim = 'routing' AND score = 0").first()).n).toBe(1);
});

const versionedPost = (body, version = "1") => SELF.fetch(`https://test.local/v1/score/${version}`, {
  method: "POST", body: JSON.stringify(body),
});

test("throttled overall ranking uses the accepted stored score just like dimensions", async () => {
  await post(payload("low-device", 10));
  await post(payload("mid-device", 50));
  const accepted = await (await post(payload("high-device", 90))).json();
  expect(await (await post({ ...payload("high-device", 0), dims: { routing: 0, timing: 0, context: 0, leverage: 0 } })).json()).toEqual(accepted);
});

test("known version endpoint echoes version and excludes legacy without inferring app version", async () => {
  await post(payload("same-device", 100));
  const response = await versionedPost(payload("same-device", 10));
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ score_version: "1", total: 1, rank: 1, small_sample: true });
  expect((await versionedPost(payload(), "unknown")).status).toBe(404);
  expect((await versionedPost({ ...payload(), score_version: "1" })).status).toBe(422);
  expect((await (await post(payload("same-device", 100))).json()).total).toBe(1);
});

test("versioned cohorts isolate UUIDs, totals, ties and 19/20 boundary", async () => {
  const { handleScore } = await import("../src/index.js");
  expect(handleScore).toBeTypeOf("function");
  const syntheticPost = (body) => handleScore(new Request("https://test.local/v1/score/test-v2", {
    method: "POST", body: JSON.stringify(body),
  }), env, "test-v2");
  for (let i = 0; i < 19; i++) await versionedPost(payload(`cohort-${String(i).padStart(4, "0")}`, i * 5));
  const early = await (await versionedPost(payload("cohort-0010", 50))).json();
  expect(early).toMatchObject({ total: 19, rank: 9, percentile: null, small_sample: true });
  expect(Object.values(early.dims).every(dim => dim.percentile === null)).toBe(true);
  const ranked = await (await versionedPost(payload("cohort-tied", 50))).json();
  expect(ranked).toMatchObject({ total: 20, rank: 9, percentile: 53, small_sample: false });
  expect(Object.values(ranked.dims).every(dim => dim.percentile === 0)).toBe(true);
  expect(await (await syntheticPost(payload("cohort-tied", 100))).json()).toMatchObject({
    score_version: "test-v2", total: 1, rank: 1, percentile: null,
  });
  expect(await (await versionedPost(payload("cohort-tied", 0))).json()).toEqual(ranked);
  expect((await (await syntheticPost(payload("cohort-tied", 0))).json()).total).toBe(1);
});

test("versioned atomic buckets survive concurrent requests and dimension-only updates", async () => {
  await Promise.all([0, 25, 50, 75, 100].map(score => versionedPost({ ...payload("cohort-concurrent", score),
    dims: { routing: score, timing: 100 - score, context: score, leverage: 100 - score } })));
  const stored = await env.DB.prepare("SELECT * FROM cohort_devices WHERE score_version = '1'").first();
  expect((await env.DB.prepare("SELECT score, n FROM cohort_score_counts WHERE score_version = '1' AND n <> 0").all()).results)
    .toEqual([{ score: stored.score, n: 1 }]);
  const original = await (await versionedPost(payload("cohort-concurrent", 100 - stored.score))).json();
  expect(original.rank).toBe(1);
  await env.DB.prepare("UPDATE cohort_devices SET updated_at = '2000-01-01T00:00:00.000Z'").run();
  const changed = { ...payload("cohort-concurrent", stored.score), dims: { routing: 11, timing: 22, context: 33, leverage: 44 } };
  await versionedPost(changed);
  const buckets = await env.DB.prepare("SELECT dim, score, n FROM cohort_dim_counts WHERE score_version = '1' AND n <> 0 ORDER BY dim").all();
  expect(buckets.results).toEqual(Object.entries(changed.dims).sort().map(([dim, score]) => ({ dim, score, n: 1 })));
  expect((await env.DB.prepare("SELECT SUM(n) AS n FROM cohort_score_counts WHERE score_version = '1'").first()).n).toBe(1);
});


test("versioned overall and dimension comparisons use accepted values under throttle", async () => {
  await versionedPost({ ...payload("accepted-low", 10), dims: { routing: 10, timing: 90, context: 50, leverage: 30 } });
  await versionedPost({ ...payload("accepted-mid", 50), dims: { routing: 50, timing: 50, context: 50, leverage: 30 } });
  const subject = { ...payload("accepted-high", 90), dims: { routing: 90, timing: 10, context: 50, leverage: 70 } };
  const accepted = await (await versionedPost(subject)).json();
  expect(accepted).toMatchObject({ rank: 1, dims: { routing: { rank: 1 }, timing: { rank: 3 }, context: { rank: 1 }, leverage: { rank: 1 } } });
  expect(await (await versionedPost({ ...subject, score: 0, dims: { routing: 0, timing: 100, context: 0, leverage: 0 } })).json()).toEqual(accepted);
});


test("dimension ranks remain isolated from a second cohort with opposing scores", async () => {
  const { handleScore } = await import("../src/index.js");
  const syntheticPost = (body) => handleScore(new Request("https://test.local/v1/score/test-v2", {
    method: "POST", body: JSON.stringify(body),
  }), env, "test-v2");
  const subject = { ...payload("isolated-subject", 50), dims: { routing: 50, timing: 50, context: 50, leverage: 50 } };
  await versionedPost({ ...payload("isolated-peer", 90), dims: { routing: 90, timing: 10, context: 90, leverage: 10 } });
  const first = await (await versionedPost(subject)).json();
  expect(first).toMatchObject({ total: 2, rank: 2, dims: {
    routing: { rank: 2 }, timing: { rank: 1 }, context: { rank: 2 }, leverage: { rank: 1 },
  } });
  await syntheticPost({ ...payload("isolated-peer", 10), dims: { routing: 10, timing: 90, context: 10, leverage: 90 } });
  const second = await (await syntheticPost(subject)).json();
  expect(second).toMatchObject({ score_version: "test-v2", total: 2, rank: 1, dims: {
    routing: { rank: 1 }, timing: { rank: 2 }, context: { rank: 1 }, leverage: { rank: 2 },
  } });
  expect(await (await versionedPost(subject)).json()).toEqual(first);
  expect(await (await syntheticPost(subject)).json()).toEqual(second);
});

test("versioned overall buckets move after one hour and repeated accepted values stay idempotent", async () => {
  await versionedPost(payload("moving-peer", 50));
  await versionedPost(payload("moving-subject", 10));
  await env.DB.prepare("UPDATE cohort_devices SET updated_at = '2000-01-01T00:00:00.000Z' WHERE device_token = 'moving-subject'").run();
  const accepted = await (await versionedPost(payload("moving-subject", 90))).json();
  expect(accepted).toMatchObject({ total: 2, rank: 1 });
  const buckets = async () => (await env.DB.prepare(
    "SELECT score, n FROM cohort_score_counts WHERE score_version = '1' AND n <> 0 ORDER BY score").all()).results;
  expect(await buckets()).toEqual([{ score: 50, n: 1 }, { score: 90, n: 1 }]);
  expect(await (await versionedPost(payload("moving-subject", 90))).json()).toEqual(accepted);
  await env.DB.prepare("UPDATE cohort_devices SET updated_at = '2000-01-01T00:00:00.000Z' WHERE device_token = 'moving-subject'").run();
  expect(await (await versionedPost(payload("moving-subject", 90))).json()).toEqual(accepted);
  expect(await buckets()).toEqual([{ score: 50, n: 1 }, { score: 90, n: 1 }]);
  expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM cohort_devices WHERE score_version = '1'").first()).n).toBe(2);
});


test("phase4 ranking never accepts license or practice payload fields", async () => {
  for (const extra of [{ lic: "abcdefghijklmnop", key: "AIM1.private-token-p4.proof" },
                        { prompt: "private-prompt-p4", path: "/private/project-p4" },
                        { arguments: "private-argument-p4", trial_start: true }]) {
    const response = await versionedPost({ ...payload(), ...extra });
    expect(response.status).toBe(422);
    const body = await response.text();
    expect(body).toBe('{"error":"invalid"}');
    expect(body).not.toContain("private-");
  }
  expect((await env.DB.prepare("SELECT count(*) AS n FROM cohort_devices").first()).n).toBe(0);
});
