import { WaffoPaymentProvider } from "./payment-provider.js";

const DAY = 86400000;
const encoder = new TextEncoder();
const statuses = new Set(["paid", "pending", "failed", "cancelled", "refunded", "revoked"]);
const exact = (value, fields) => value && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).length === fields.length && fields.every(f => Object.hasOwn(value, f));
const ref = value => typeof value === "string" && /^[A-Za-z0-9_.:-]{1,128}$/.test(value);
export const base64url = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const decode = value => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
export const licenseResponse = (body, status = 200, headers = {}) => Response.json(body,
  { status, headers: { "Cache-Control": "no-store", ...headers } });

async function signingKey(env) {
  return crypto.subtle.importKey("pkcs8", decode(env.LICENSE_PRIVATE_KEY), "Ed25519", true, ["sign"]);
}
export async function signLicense(env, payload) {
  const bytes = encoder.encode(JSON.stringify(payload));
  const signature = await crypto.subtle.sign("Ed25519", await signingKey(env), bytes);
  return `AIM1.${base64url(bytes)}.${base64url(signature)}`;
}
export async function readBytes(request, limit) {
  const reader = request.body?.getReader();
  if (!reader) throw new Error("invalid");
  let size = 0;
  const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new Error("invalid"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength; }
  return result;
}

// exp is inclusive. Only complete UTC calendar days fit an exclusive instant.
export function inclusiveExpiry(paidThrough) {
  const end = Date.parse(paidThrough);
  if (!Number.isFinite(end)) throw new Error("invalid");
  return new Date(Math.floor(end / DAY) * DAY - DAY).toISOString().slice(0, 10);
}
function normalize(value) {
  if (!value || ![value.eventId, value.subscriptionRef, value.orderRef].every(ref)
    || !Number.isSafeInteger(value.revision) || value.revision < 0 || !statuses.has(value.status)
    || typeof value.autoRenew !== "boolean") throw new Error("unavailable");
  const dates = [value.periodStart, value.paidThrough].map(date => {
    if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}T.*Z$/.test(date)
      || !Number.isFinite(Date.parse(date))) throw new Error("unavailable");
    return new Date(date).toISOString();
  });
  if (dates[1] <= dates[0]) throw new Error("unavailable");
  let managementURL = null;
  if (value.managementURL !== null) {
    const url = new URL(value.managementURL);
    if (url.protocol !== "https:" || url.username || url.password || url.hash
      || url.href.length > 2048) throw new Error("unavailable");
    managementURL = url.href;
  }
  return { eventId: value.eventId, subscriptionRef: value.subscriptionRef, orderRef: value.orderRef,
    revision: value.revision, periodStart: dates[0], paidThrough: dates[1], status: value.status,
    autoRenew: value.autoRenew, managementURL };
}
async function ordered(provider, value) {
  if (value && value.revision == null) {
    if (!ref(value.subscriptionRef)) throw new Error("unavailable");
    const reconciled = await provider.getSubscription(value.subscriptionRef);
    if (reconciled?.subscriptionRef !== value.subscriptionRef) throw new Error("unavailable");
    return normalize({ ...reconciled, eventId: value.eventId });
  }
  return normalize(value);
}

async function persistEvent(env, value) {
  const e = value;
  const fingerprint = base64url(await crypto.subtle.digest("SHA-256", encoder.encode(JSON.stringify(e))));
  const { eventId: _eventId, ...snapshot } = e;
  const snapshotHash = base64url(await crypto.subtle.digest("SHA-256", encoder.encode(JSON.stringify(snapshot))));
  const lic = base64url(crypto.getRandomValues(new Uint8Array(12)));
  const verified = `EXISTS (SELECT 1 FROM subscription_events WHERE event_id = ? AND fingerprint = ?)`;
  const fresh = `NOT EXISTS (SELECT 1 FROM subscriptions WHERE provider_ref = ?
    AND (revision >= ? OR terminal_revision IS NOT NULL))`;
  const paid = e.status === "paid";
  const terminal = ["refunded", "revoked"].includes(e.status);
  await env.DB.batch([
    env.DB.prepare(`INSERT OR IGNORE INTO subscription_events(event_id, provider_ref, revision, fingerprint)
      VALUES (?, ?, ?, ?)`).bind(e.eventId, e.subscriptionRef, e.revision, fingerprint),
    env.DB.prepare(`INSERT OR IGNORE INTO subscription_periods(order_ref, provider_ref, period_start, paid_through)
      SELECT ?, ?, ?, ? WHERE ? AND ${verified} AND ${fresh}`)
      .bind(e.orderRef, e.subscriptionRef, e.periodStart, e.paidThrough, paid ? 1 : 0,
        e.eventId, fingerprint, e.subscriptionRef, e.revision),
    env.DB.prepare(`INSERT INTO subscriptions(provider_ref, lic, revision, status, snapshot_hash, paid_through,
      auto_renew, terminal_revision, management_url)
      SELECT ?, ?, ?, ?, ?, CASE WHEN ? THEN ? ELSE NULL END, ?, ?, ?
      WHERE ${verified} AND (? = 0 OR EXISTS (SELECT 1 FROM subscription_periods
        WHERE order_ref = ? AND provider_ref = ? AND period_start = ? AND paid_through = ?))
      ON CONFLICT(provider_ref) DO UPDATE SET revision = excluded.revision, status = excluded.status,
        snapshot_hash = excluded.snapshot_hash,
        paid_through = CASE WHEN excluded.paid_through > COALESCE(subscriptions.paid_through, '')
          THEN excluded.paid_through ELSE subscriptions.paid_through END,
        auto_renew = excluded.auto_renew, terminal_revision = excluded.terminal_revision,
        management_url = excluded.management_url
      WHERE subscriptions.revision < excluded.revision AND subscriptions.terminal_revision IS NULL`)
      .bind(e.subscriptionRef, lic, e.revision, e.status, snapshotHash, paid ? 1 : 0, e.paidThrough,
        e.autoRenew ? 1 : 0, terminal ? e.revision : null, e.managementURL, e.eventId, fingerprint,
        paid ? 1 : 0, e.orderRef, e.subscriptionRef, e.periodStart, e.paidThrough),
  ]);
  const stored = await env.DB.prepare("SELECT fingerprint FROM subscription_events WHERE event_id = ?").bind(e.eventId).first();
  if (stored.fingerprint !== fingerprint) throw new Error("unavailable");
  const sub = await env.DB.prepare("SELECT * FROM subscriptions WHERE provider_ref = ?").bind(e.subscriptionRef).first();
  if (!sub || sub.revision < e.revision
    || (sub.revision === e.revision && sub.snapshot_hash !== snapshotHash)) throw new Error("unavailable");
  return sub;
}

async function paidKey(env, sub) {
  const period = await env.DB.prepare(`SELECT * FROM subscription_periods
    WHERE provider_ref = ? AND paid_through = ? ORDER BY period_start LIMIT 1`)
    .bind(sub.provider_ref, sub.paid_through).first();
  if (!period) return null;
  const first = await env.DB.prepare("SELECT MIN(period_start) AS start FROM subscription_periods WHERE provider_ref = ?")
    .bind(sub.provider_ref).first();
  const payload = { v: 1, lic: sub.lic, plan: "pro", iat: first.start.slice(0, 10), exp: inclusiveExpiry(period.paid_through) };
  if (payload.exp < payload.iat) return null;
  const key = await signLicense(env, payload);
  await env.DB.prepare(`INSERT OR IGNORE INTO license_keys(lic, period_ref, exp, key) VALUES (?, ?, ?, ?)`)
    .bind(sub.lic, period.order_ref, payload.exp, key).run();
  return (await env.DB.prepare("SELECT key FROM license_keys WHERE lic = ? AND period_ref = ?")
    .bind(sub.lic, period.order_ref).first()).key;
}

async function verifyProof(env, key, lic) {
  try {
    const parts = key.split(".");
    if (parts.length !== 3 || parts[0] !== "AIM1" || !parts.slice(1).every(p => /^[A-Za-z0-9_-]+$/.test(p))) return false;
    const bytes = decode(parts[1]);
    const signature = decode(parts[2]);
    if (base64url(bytes) !== parts[1] || base64url(signature) !== parts[2]) return false;
    const jwk = await crypto.subtle.exportKey("jwk", await signingKey(env));
    const publicKey = await crypto.subtle.importKey("jwk", { kty: jwk.kty, crv: jwk.crv, x: jwk.x }, "Ed25519", false, ["verify"]);
    if (!await crypto.subtle.verify("Ed25519", publicKey, signature, bytes)) return false;
    const p = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    const date = value => typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
      && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
    if (!exact(p, ["v", "lic", "plan", "iat", "exp"]) || p.v !== 1 || p.plan !== "pro" || p.lic !== lic
      || !date(p.iat) || !date(p.exp) || p.exp < p.iat) return false;
    const known = await env.DB.prepare("SELECT 1 FROM license_keys WHERE lic = ? AND key = ?").bind(lic, key).first();
    if (known) return true;
    // Pre-migration manual keys are recognized by their original signed metadata.
    return Boolean(await env.DB.prepare("SELECT 1 FROM licenses WHERE lic = ? AND plan = ? AND iat = ? AND exp = ?")
      .bind(lic, p.plan, p.iat, p.exp).first());
  } catch { return false; }
}
async function allowRefresh(env, lic, now) {
  const start = Math.floor(now.getTime() / 60000);
  const result = await env.DB.prepare(`INSERT INTO license_refresh_limits(lic, window_start, attempts) VALUES (?, ?, 1)
    ON CONFLICT(lic) DO UPDATE SET window_start = excluded.window_start,
      attempts = CASE WHEN license_refresh_limits.window_start = excluded.window_start
        THEN license_refresh_limits.attempts + 1 ELSE 1 END
    WHERE license_refresh_limits.window_start <> excluded.window_start OR license_refresh_limits.attempts < 10
    RETURNING attempts`).bind(lic, start).first();
  return Boolean(result);
}

// Injection is deliberately a module API, never an env binding or HTTP selector.
export function createSubscriptionHandler(provider = new WaffoPaymentProvider(), clock = () => new Date()) {
  return async (request, env) => {
    const url = new URL(request.url);
    if (request.method !== "POST" || !["/v1/waffo/webhook", "/v1/license/refresh"].includes(url.pathname)) {
      return licenseResponse({ status: "unavailable" }, 404);
    }
    if (url.search) return licenseResponse({ status: "unavailable" }, 503);
    try {
      if (url.pathname === "/v1/waffo/webhook") {
        const raw = await readBytes(request, 65536);
        const e = await ordered(provider, await provider.verifyWebhook(raw, request.headers));
        const sub = await persistEvent(env, e);
        if (sub.terminal_revision === null) await paidKey(env, sub);
        return licenseResponse({ status: "accepted" });
      }
      let body;
      try {
        body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(await readBytes(request, 1024)));
        if (!exact(body, ["lic", "key"]) || typeof body.lic !== "string" || !/^[A-Za-z0-9_-]{16}$/.test(body.lic)
          || typeof body.key !== "string" || body.key.length > 768) throw new Error("invalid");
      } catch { return licenseResponse({ status: "invalid" }, 422); }
      if (!await verifyProof(env, body.key, body.lic)) return licenseResponse({ status: "unauthorized" }, 401);
      const now = clock();
      if (!await allowRefresh(env, body.lic, now)) return licenseResponse({ status: "rate_limited" }, 429, { "Retry-After": "60" });
      let sub = await env.DB.prepare("SELECT * FROM subscriptions WHERE lic = ?").bind(body.lic).first();
      if (!sub) return licenseResponse({ status: "manual" });
      if (sub.terminal_revision !== null) return licenseResponse({ status: "revoked" });
      const latest = await ordered(provider, await provider.getSubscription(sub.provider_ref));
      if (latest.subscriptionRef !== sub.provider_ref) throw new Error("unavailable");
      sub = await persistEvent(env, latest);
      if (sub.terminal_revision !== null) return licenseResponse({ status: "revoked" });
      if (!sub.paid_through) return licenseResponse({ status: "pending" });
      if (Date.parse(sub.paid_through) <= now.getTime()) return licenseResponse({ status: "expired" });
      const periods = (await env.DB.prepare(`SELECT period_start, paid_through FROM subscription_periods
        WHERE provider_ref = ? ORDER BY period_start`).bind(sub.provider_ref).all()).results;
      let through = null;
      const instant = now.toISOString();
      for (const period of periods) {
        if ((period.period_start <= instant && period.paid_through > instant)
          || (through && period.period_start <= through)) {
          if (!through || period.paid_through > through) through = period.paid_through;
        }
      }
      if (!through) return licenseResponse({ status: "pending" });
      sub = { ...sub, paid_through: through };
      const key = await paidKey(env, sub);
      if (!key || inclusiveExpiry(sub.paid_through) < now.toISOString().slice(0, 10)) return licenseResponse({ status: "expired" });
      // Recheck terminal state after asynchronous signing to cover a concurrent refund.
      const final = await env.DB.prepare("SELECT terminal_revision FROM subscriptions WHERE lic = ?").bind(sub.lic).first();
      if (final.terminal_revision !== null) return licenseResponse({ status: "revoked" });
      return licenseResponse({ status: "active", key, auto_renew: Boolean(sub.auto_renew), paid_through: sub.paid_through });
    } catch { return licenseResponse({ status: "unavailable" }, 503); }
  };
}
