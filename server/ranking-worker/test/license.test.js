import { beforeEach, expect, test } from "vitest";
import { env, applyD1Migrations } from "cloudflare:test";
import worker from "../src/index.js";

let bindings, publicKey;
beforeEach(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
  for (const table of ["license_keys", "license_refresh_limits", "subscription_events", "subscription_periods", "subscriptions", "manual_orders", "licenses"]) {
    await env.DB.prepare(`DELETE FROM ${table}`).run();
  }
  const pair = await crypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]);
  publicKey = pair.publicKey;
  bindings = { ...env, ADMIN_TOKEN: "test-admin",
    LICENSE_PRIVATE_KEY: btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey)))) };
});
const issue = (body, token = "test-admin", config = bindings) => worker.fetch(new Request("https://test.local/v1/license/issue", {
  method: "POST", headers: token === null ? {} : { Authorization: `Bearer ${token}` },
  body: JSON.stringify(body),
}), config);
const decode = (part) => Uint8Array.from(atob(part.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));

test("only an authenticated admin can issue, with no unset-secret bypass", async () => {
  for (const token of [null, "wrong"]) expect((await issue({ order_ref: "order-1", days: 365 }, token)).status).toBe(401);
  expect((await issue({ order_ref: "order-1", days: 365 }, "undefined", { ...bindings, ADMIN_TOKEN: undefined })).status).toBe(401);
});

test("issues a verifiable one-year key and stores only license metadata", async () => {
  const response = await issue({ order_ref: "founder-1", days: 365 });
  expect(response.status).toBe(200);
  const { key } = await response.json();
  const [prefix, encoded, signature] = key.split(".");
  expect(prefix).toBe("AIM1");
  expect(encoded + signature).toMatch(/^[A-Za-z0-9_-]+$/);
  expect(await crypto.subtle.verify("Ed25519", publicKey, decode(signature), decode(encoded))).toBe(true);
  const payload = JSON.parse(new TextDecoder().decode(decode(encoded)));
  expect(payload).toEqual({ v: 1, lic: expect.stringMatching(/^[A-Za-z0-9_-]{16}$/), plan: "pro",
    iat: new Date().toISOString().slice(0, 10), exp: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/) });
  expect((Date.parse(payload.exp) - Date.parse(payload.iat)) / 86400000).toBe(365);
  expect(await env.DB.prepare("SELECT * FROM licenses WHERE lic = ?").bind(payload.lic).first()).toEqual({
    lic: payload.lic, plan: "pro", iat: payload.iat, exp: payload.exp, order_ref: "founder-1", created_at: expect.any(String),
  });
  const second = await (await issue({ order_ref: "founder-2", days: 365 })).json();
  expect(second.key).not.toBe(key);
});

test("rejects invalid issuance bodies", async () => {
  for (const body of [null, {}, { order_ref: "", days: 365 }, { order_ref: "x".repeat(65), days: 365 },
    { order_ref: 42, days: 365 }, { order_ref: "x", days: 0 }, { order_ref: "x", days: 1.5 },
    { order_ref: "x", days: "365" }, { order_ref: "x", days: 366 }, { order_ref: "x", days: 365, email: "private" }]) {
    expect((await issue(body)).status).toBe(422);
  }
  const malformed = await worker.fetch(new Request("https://test.local/v1/license/issue", {
    method: "POST", headers: { Authorization: "Bearer test-admin" }, body: "{",
  }), bindings);
  expect(malformed.status).toBe(422);
});

test("listing and reserved Waffo webhook stay unavailable", async () => {
  for (const [method, path] of [["GET", "/v1/license/issue"], ["GET", "/v1/licenses"], ["GET", "/v1/waffo/webhook"]]) {
    expect((await worker.fetch(new Request(`https://test.local${path}`, { method }), bindings)).status).toBe(404);
  }
});


test("concurrent admin retries return one persisted key per order and manual keys stay manual", async () => {
  const responses = await Promise.all(Array.from({ length: 4 }, () => issue({ order_ref: "retry-order", days: 365 })));
  const keys = await Promise.all(responses.map(async response => {
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(response.status).toBe(200);
    return (await response.json()).key;
  }));
  expect(new Set(keys).size).toBe(1);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM licenses WHERE order_ref = ?").bind("retry-order").first()).n).toBe(1);
  const payload = JSON.parse(new TextDecoder().decode(decode(keys[0].split(".")[1])));
  const response = await worker.fetch(new Request("https://test.local/v1/license/refresh", {
    method: "POST", body: JSON.stringify({ lic: payload.lic, key: keys[0] }),
  }), bindings);
  expect(await response.json()).toEqual({ status: "manual" });
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscriptions").first()).n).toBe(0);
});


test("pre-subscription manual issuance metadata authorizes only its original signed proof", async () => {
  const { signLicense } = await import("../src/subscriptions.js");
  const p = { v: 1, lic: "legacyManualKey1", plan: "pro", iat: "2024-01-01", exp: "2025-01-01" };
  await env.DB.prepare("INSERT INTO licenses VALUES (?, ?, ?, ?, ?, ?)")
    .bind(p.lic, p.plan, p.iat, p.exp, "legacy-order", "2024-01-01T00:00:00Z").run();
  const response = await worker.fetch(new Request("https://test.local/v1/license/refresh", {
    method: "POST", body: JSON.stringify({ lic: p.lic, key: await signLicense(bindings, p) }),
  }), bindings);
  expect(await response.json()).toEqual({ status: "manual" });
});


test("phase4 license endpoints reject score, source and private practice fields", async () => {
  for (const extra of [{ device_token: "private-token-p4", score: 80 },
                        { course_source: "synthetic", prompt: "private-prompt-p4" },
                        { path: "/private/project-p4", arguments: "private-argument-p4" }]) {
    expect((await issue({ order_ref: "isolated", days: 365, ...extra })).status).toBe(422);
    const response = await worker.fetch(new Request("https://test.local/v1/license/refresh", {
      method: "POST", body: JSON.stringify({ lic: "abcdefghijklmnop", key: "AIM1.fake.proof", ...extra }),
    }), bindings);
    expect(response.status).toBe(422);
    expect(await response.text()).not.toContain("private-");
  }
  expect((await env.DB.prepare("SELECT count(*) AS n FROM licenses").first()).n).toBe(0);
});
