import { beforeEach, expect, test, vi } from "vitest";
import { env, applyD1Migrations } from "cloudflare:test";
import worker from "../src/index.js";
import { createSubscriptionHandler, inclusiveExpiry } from "../src/subscriptions.js";
import { FakePaymentProvider } from "./fakes/payment-provider.js";

let bindings, provider, handle, publicKey;
const now = () => new Date("2026-10-21T12:00:00Z");
const event = (overrides = {}) => ({ eventId: "event-1", subscriptionRef: "sub-1", orderRef: "order-1",
  revision: 1, periodStart: "2026-10-21T00:00:00Z", paidThrough: "2027-10-21T00:00:00Z",
  status: "paid", autoRenew: true, managementURL: null, ...overrides });
const request = (path, body) => new Request(`https://test.local${path}`, { method: "POST", body });
const webhook = (value) => handle(request("/v1/waffo/webhook", provider.add(value)), bindings);
const refresh = (lic, key, extra = {}) => handle(request("/v1/license/refresh", JSON.stringify({ lic, key, ...extra })), bindings);
const decode = (s) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
const payload = (key) => JSON.parse(new TextDecoder().decode(decode(key.split(".")[1])));
async function currentKey() {
  const row = await env.DB.prepare("SELECT key FROM license_keys ORDER BY exp DESC LIMIT 1").first();
  return row.key;
}
beforeEach(async () => {
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
  for (const table of ["one_time_events", "one_time_orders", "license_keys", "license_refresh_limits", "subscription_events", "subscription_periods", "subscriptions", "manual_orders", "licenses"]) {
    await env.DB.prepare(`DELETE FROM ${table}`).run();
  }
  const pair = await crypto.subtle.generateKey("Ed25519", true, ["sign", "verify"]);
  publicKey = pair.publicKey;
  bindings = { ...env, LICENSE_PRIVATE_KEY: btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey)))) };
  provider = new FakePaymentProvider();
  handle = createSubscriptionHandler(provider, now);
});

test("verified payment persists one signed key, concurrent duplicates never inflate expiry", async () => {
  const responses = await Promise.all([webhook(event()), webhook(event()), webhook(event())]);
  expect(responses.map(r => r.status)).toEqual([200, 200, 200]);
  const key = await currentKey();
  const data = payload(key);
  expect(data).toEqual({ v: 1, lic: expect.stringMatching(/^[A-Za-z0-9_-]{16}$/), plan: "pro", iat: "2026-10-21", exp: "2027-10-20" });
  expect(await crypto.subtle.verify("Ed25519", publicKey, decode(key.split(".")[2]), decode(key.split(".")[1]))).toBe(true);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_events").first()).n).toBe(1);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(1);
  const results = await Promise.all([refresh(data.lic, key), refresh(data.lic, key)]);
  for (const response of results) {
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(await response.json()).toEqual({ status: "active", key, auto_renew: true, paid_through: "2027-10-21T00:00:00.000Z" });
  }
});

test("renewal before and after expiry keeps lic and uses verified calendar boundary", async () => {
  await webhook(event());
  const old = await currentKey();
  await webhook(event({ eventId: "renewal", orderRef: "order-2", revision: 2,
    periodStart: "2027-10-21T00:00:00Z", paidThrough: "2028-10-21T00:00:00Z" }));
  for (const date of [now(), new Date("2027-11-01T12:00:00Z")]) {
    const response = await createSubscriptionHandler(provider, () => date)(request("/v1/license/refresh", JSON.stringify({ lic: payload(old).lic, key: old })), bindings);
    const result = await response.json();
    expect(result.status).toBe("active");
    expect(payload(result.key).lic).toBe(payload(old).lic);
    expect(payload(result.key).exp).toBe("2028-10-20");
    expect(payload(result.key).iat).toBe("2026-10-21");
  }
});

test("cancel preserves paid period; pending and failed renewal do not extend it", async () => {
  await webhook(event());
  const key = await currentKey();
  for (const [i, status] of ["pending", "failed", "cancelled"].entries()) {
    await webhook(event({ eventId: status, orderRef: "not-paid", revision: i + 2, status, autoRenew: false,
      paidThrough: "2030-01-01T00:00:00Z" }));
    const result = await (await refresh(payload(key).lic, key)).json();
    expect(result.key).toBe(key);
    expect(result.auto_renew).toBe(false);
    expect(result.paid_through).toBe("2027-10-21T00:00:00.000Z");
  }
  const expired = createSubscriptionHandler(provider, () => new Date("2027-10-21T00:00:00Z"));
  expect(await (await expired(request("/v1/license/refresh", JSON.stringify({ lic: payload(key).lic, key })), bindings)).json()).toEqual({ status: "expired" });
});

test.each(["refunded", "revoked"])("%s is terminal and stale active cannot restore it", async (status) => {
  await webhook(event());
  const key = await currentKey();
  await webhook(event({ eventId: "terminal", revision: 3, status }));
  await webhook(event({ eventId: "stale", revision: 2 }));
  expect(await (await refresh(payload(key).lic, key)).json()).toEqual({ status: "revoked" });
  await webhook(event({ eventId: "later", revision: 4 }));
  expect(await (await refresh(payload(key).lic, key)).json()).toEqual({ status: "revoked" });
});

test("unordered events reconcile or fail closed; provider outage cannot grant time", async () => {
  const unordered = event({ revision: null });
  provider.add(unordered);
  expect((await handle(request("/v1/waffo/webhook", unordered.eventId), bindings)).status).toBe(503);
  provider.subscriptions.set("sub-1", event({ revision: 2 }));
  expect((await handle(request("/v1/waffo/webhook", unordered.eventId), bindings)).status).toBe(200);
  const key = await currentKey();
  provider.available = false;
  expect(await (await refresh(payload(key).lic, key)).json()).toEqual({ status: "unavailable" });
});

test("exact bounded proof rejects guessed IDs, tamper, unknown issuance and extra fields", async () => {
  await webhook(event());
  const key = await currentKey();
  const lic = payload(key).lic;
  for (const [id, proof, extra] of [["a".repeat(16), key, {}], [lic, key.slice(0, -5) + "AAAAA", {}], [lic, key, { device_token: "private" }], [lic, "x".repeat(2000), {}]]) {
    const response = await refresh(id, proof, extra);
    expect([401, 422]).toContain(response.status);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(JSON.stringify(await response.json())).not.toContain(key);
  }
  const missing = await handle(request("/v1/license/refresh", JSON.stringify({ lic })), bindings);
  expect(missing.status).toBe(422);
  await env.DB.prepare("DELETE FROM license_keys").run();
  expect((await refresh(lic, key)).status).toBe(401);
});

test("refresh is rate limited per known license, with a bounded retry window", async () => {
  await webhook(event());
  const key = await currentKey();
  const results = await Promise.all(Array.from({ length: 12 }, () => refresh(payload(key).lic, key)));
  expect(results.filter(r => r.status === 429).length).toBe(2);
  const later = createSubscriptionHandler(provider, () => new Date(now().getTime() + 61000));
  expect((await later(request("/v1/license/refresh", JSON.stringify({ lic: payload(key).lic, key })), bindings)).status).toBe(200);
});

test("default provider is unavailable and cannot be replaced by request or env flags; logs redact proof", async () => {
  const log = vi.spyOn(console, "log");
  const error = vi.spyOn(console, "error");
  const response = await worker.fetch(request("/v1/waffo/webhook?provider=fake", "private-sentinel"), { ...bindings, PAYMENT_PROVIDER: provider, USE_FAKE_PAYMENTS: true });
  expect(response.status).toBe(503);
  expect(response.headers.get("Cache-Control")).toBe("no-store");
  expect(await response.json()).toEqual({ status: "unavailable" });
  expect(log).not.toHaveBeenCalled();
  expect(error).not.toHaveBeenCalled();
  log.mockRestore(); error.mockRestore();
});

test("inclusive expiry uses only complete UTC days, including leap years and partial days", () => {
  expect(inclusiveExpiry("2028-03-01T00:00:00Z")).toBe("2028-02-29");
  expect(inclusiveExpiry("2028-03-01T15:00:00Z")).toBe("2028-02-29");
});


test.each(["pending", "failed"])("initial %s cannot issue or refresh a key", async (status) => {
  expect((await webhook(event({ status }))).status).toBe(200);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(0);
  const lic = (await env.DB.prepare("SELECT lic FROM subscriptions").first()).lic;
  expect((await refresh(lic, "AIM1.guessed.proof")).status).toBe(401);
});

test("order and period replays under different events cannot manufacture additional entitlement", async () => {
  await webhook(event());
  const key = await currentKey();
  await webhook(event({ eventId: "same-order", revision: 2, paidThrough: "2030-01-01T00:00:00Z" }));
  await webhook(event({ eventId: "same-period", orderRef: "other-order", revision: 3, paidThrough: "2031-01-01T00:00:00Z" }));
  expect((await env.DB.prepare("SELECT paid_through FROM subscriptions").first()).paid_through).toBe("2027-10-21T00:00:00.000Z");
  expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(1);
  expect(await currentKey()).toBe(key);
});

test("colliding verified event identity and invalid normalized data fail closed", async () => {
  await webhook(event());
  expect((await webhook(event({ subscriptionRef: "other-sub", orderRef: "other-order" }))).status).toBe(503);
  for (const changes of [{ revision: -1 }, { revision: 1.2 }, { status: "guessed-provider-status" },
    { paidThrough: "bad" }, { periodStart: "2030-01-01T00:00:00Z" },
    { managementURL: "http://not-secure.example/manage" }, { managementURL: "https://user:secret@example.com/manage" }]) {
    expect((await webhook(event({ eventId: "invalid", ...changes }))).status).toBe(503);
  }
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscriptions").first()).n).toBe(1);
});

test("refresh rejects a correctly signed but unissued proof and malformed JSON", async () => {
  await webhook(event());
  const key = await currentKey();
  const p = { ...payload(key), exp: "2035-01-01" };
  const { signLicense } = await import("../src/subscriptions.js");
  expect((await refresh(p.lic, await signLicense(bindings, p))).status).toBe(401);
  for (const body of ["{", " ".repeat(1025), "null", "[]"]) {
    expect((await handle(request("/v1/license/refresh", body), bindings)).status).toBe(422);
  }
});

test("production webhook always fails closed, even with a fake-shaped body and env binding", async () => {
  for (const body of [JSON.stringify(event()), "event-1"]) {
    const response = await worker.fetch(request("/v1/waffo/webhook", body), { ...bindings, PAYMENT_PROVIDER: provider });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ status: "unavailable" });
  }
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_events").first()).n).toBe(0);
});

test("prepaid initial future period does not activate early", async () => {
  await webhook(event({ periodStart: "2027-01-01T00:00:00Z", paidThrough: "2028-01-01T00:00:00Z" }));
  const key = await currentKey();
  expect(await (await refresh(payload(key).lic, key)).json()).toEqual({ status: "pending" });
});

test("unverified callbacks and oversized raw webhook bodies never reach D1", async () => {
  for (const body of ["forged", "x".repeat(65537)]) {
    expect((await handle(request("/v1/waffo/webhook", body), bindings)).status).toBe(503);
  }
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_events").first()).n).toBe(0);
});


test("conflicting same-revision status cannot silently authorize refresh", async () => {
  await webhook(event());
  const key = await currentKey();
  expect((await webhook(event({ eventId: "ambiguous-refund", status: "refunded" }))).status).toBe(503);
  expect(await (await refresh(payload(key).lic, key)).json()).toEqual({ status: "unavailable" });
});

test("a future paid period separated by a gap cannot extend the current key", async () => {
  await webhook(event());
  const old = await currentKey();
  await webhook(event({ eventId: "future-gap", orderRef: "gap-order", revision: 2,
    periodStart: "2028-01-01T00:00:00Z", paidThrough: "2029-01-01T00:00:00Z" }));
  const result = await (await refresh(payload(old).lic, old)).json();
  expect(result.key).toBe(old);
  expect(result.paid_through).toBe("2027-10-21T00:00:00.000Z");
});


test("D1 failure rolls back event, period and entitlement together; retry completes one key", async () => {
  const failing = { ...bindings, DB: {
    prepare: sql => env.DB.prepare(sql),
    batch: statements => env.DB.batch([...statements, env.DB.prepare("INSERT INTO missing_table VALUES (1)")]),
  } };
  const body = provider.add(event());
  expect((await handle(request("/v1/waffo/webhook", body), failing)).status).toBe(503);
  for (const table of ["subscription_events", "subscription_periods", "subscriptions", "license_keys"]) {
    expect((await env.DB.prepare(`SELECT count(*) AS n FROM ${table}`).first()).n).toBe(0);
  }
  expect((await handle(request("/v1/waffo/webhook", body), bindings)).status).toBe(200);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(1);
});

test("signing outage retries the verified period without another year or license", async () => {
  const body = provider.add(event());
  expect((await handle(request("/v1/waffo/webhook", body), { ...bindings, LICENSE_PRIVATE_KEY: "unset" })).status).toBe(503);
  const sub = await env.DB.prepare("SELECT lic, paid_through FROM subscriptions").first();
  expect((await handle(request("/v1/waffo/webhook", body), bindings)).status).toBe(200);
  expect(payload(await currentKey()).lic).toBe(sub.lic);
  expect(payload(await currentKey()).exp).toBe("2027-10-20");
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_periods").first()).n).toBe(1);
});

test("only authenticated management metadata is stored, separate from responses and rankings", async () => {
  const managementURL = "https://verified-provider.example/manage/opaque-reference";
  await webhook(event({ managementURL }));
  const key = await currentKey();
  const result = await (await refresh(payload(key).lic, key)).json();
  expect(JSON.stringify(result)).not.toContain(managementURL);
  expect((await env.DB.prepare("SELECT management_url FROM subscriptions").first()).management_url).toBe(managementURL);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM cohort_devices").first()).n).toBe(0);
});


test("phase4 annual payment, cancel, renewal, outage and repeated callbacks preserve one license", async () => {
  const created = event();
  const cancelled = event({ eventId: "cancel-2", revision: 2, status: "cancelled", autoRenew: false });
  await webhook(created);
  const old = await currentKey();
  const original = payload(old);
  expect((await webhook(cancelled)).status).toBe(200);
  expect(await (await refresh(original.lic, old)).json()).toMatchObject({
    status: "active", key: old, auto_renew: false,
  });
  const renewal = event({ eventId: "renew-3", orderRef: "order-2", revision: 3,
    periodStart: "2027-10-21T00:00:00Z", paidThrough: "2028-10-21T00:00:00Z" });
  expect((await webhook(renewal)).status).toBe(200);
  const fresh = await currentKey();
  expect(payload(fresh)).toMatchObject({ lic: original.lic, exp: "2028-10-20" });
  for (let replay = 0; replay < 2; replay++) {
    for (const value of [created, cancelled, renewal]) expect((await webhook(value)).status).toBe(200);
    expect(await currentKey()).toBe(fresh);
    expect((await env.DB.prepare("SELECT count(*) AS n FROM subscriptions").first()).n).toBe(1);
    expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_periods").first()).n).toBe(2);
    expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_events").first()).n).toBe(3);
    expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(2);
  }
  // Restore the latest authoritative provider state after replaying historical callback envelopes.
  provider.add(renewal);
  expect(await (await refresh(original.lic, old)).json()).toMatchObject({ status: "active", key: fresh });
  expect(await crypto.subtle.verify("Ed25519", publicKey, decode(fresh.split(".")[2]), decode(fresh.split(".")[1]))).toBe(true);
  provider.available = false;
  expect(await (await refresh(original.lic, fresh)).json()).toEqual({ status: "unavailable" });
  expect(await currentKey()).toBe(fresh);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM cohort_devices").first()).n).toBe(0);
});


const oneTime = (overrides = {}) => ({ product: "one_time_annual", eventId: "wallet-paid",
  orderRef: "wallet-order", revision: 1, paidAt: "2026-10-21T00:00:00Z", status: "paid", ...overrides });

test("one-time annual order issues one 365-day signed licence per order, without renewal periods", async () => {
  const responses = await Promise.all([webhook(oneTime()), webhook(oneTime()),
    webhook(oneTime({ eventId: "wallet-retry" }))]);
  expect(responses.map(r => r.status)).toEqual([200, 200, 200]);
  const key = await currentKey();
  const data = payload(key);
  expect(data).toMatchObject({ product: "one_time_annual", iat: "2026-10-21", exp: "2027-10-20" });
  expect(await crypto.subtle.verify("Ed25519", publicKey, decode(key.split(".")[2]), decode(key.split(".")[1]))).toBe(true);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(1);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_periods").first()).n).toBe(0);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscriptions").first()).n).toBe(0);
  const result = await (await refresh(data.lic, key)).json();
  expect(result).toEqual({ status: "active", key, auto_renew: false, paid_through: "2027-10-21T00:00:00.000Z" });
});

test("one-time refund revokes and late paid events cannot resurrect or extend access", async () => {
  expect((await webhook(oneTime())).status).toBe(200);
  const key = await currentKey();
  expect((await webhook(oneTime({ eventId: "wallet-refund", revision: 2, status: "refunded" }))).status).toBe(200);
  await webhook(oneTime({ eventId: "late-paid", revision: 3 }));
  expect(await (await refresh(payload(key).lic, key)).json()).toEqual({ status: "revoked" });
  expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(1);
  expect((await env.DB.prepare("SELECT count(*) AS n FROM subscription_periods").first()).n).toBe(0);
});

test("unpaid or unauthenticated one-time orders never issue keys; conflicting paid date fails closed", async () => {
  for (const status of ["pending", "failed"]) await webhook(oneTime({ eventId: status, revision: status === "pending" ? 0 : 1, status }));
  expect((await env.DB.prepare("SELECT count(*) AS n FROM license_keys").first()).n).toBe(0);
  expect((await handle(request("/v1/waffo/webhook", "unverified"), bindings)).status).toBe(503);
  expect((await webhook(oneTime({ eventId: "paid", revision: 2 }))).status).toBe(200);
  const key = await currentKey();
  expect((await webhook(oneTime({ eventId: "changed-date", revision: 3, paidAt: "2030-01-01T00:00:00Z" }))).status).toBe(503);
  expect(await currentKey()).toBe(key);
});

test("one-time licence expires without any automatic renewal", async () => {
  await webhook(oneTime());
  const key = await currentKey();
  const handler = createSubscriptionHandler(provider, () => new Date("2027-10-21T00:00:00Z"));
  expect(await (await handler(request("/v1/license/refresh", JSON.stringify({ lic: payload(key).lic, key })), bindings)).json())
    .toEqual({ status: "expired" });
});
