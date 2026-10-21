import { beforeEach, expect, test } from "vitest";
import { env, applyD1Migrations } from "cloudflare:test";
import worker from "../src/index.js";

let bindings, publicKey;
beforeEach(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
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
  for (const [method, path] of [["GET", "/v1/license/issue"], ["GET", "/v1/licenses"], ["POST", "/v1/waffo/webhook"]]) {
    expect((await worker.fetch(new Request(`https://test.local${path}`, { method }), bindings)).status).toBe(404);
  }
});
