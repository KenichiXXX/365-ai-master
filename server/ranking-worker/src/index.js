import { base64url, createSubscriptionHandler, licenseResponse, signLicense } from "./subscriptions.js";

const handleSubscription = createSubscriptionHandler();

const dimensionKeys = ["routing", "timing", "context", "leverage"];
const exactKeys = (value, keys) => value !== null && typeof value === "object"
  && !Array.isArray(value) && Object.keys(value).length === keys.length
  && keys.every((key) => Object.hasOwn(value, key));
const scoreValid = (score) => Number.isInteger(score) && score >= 0 && score <= 100;

async function readJSON(request) {
  // Bound the actual bytes, including chunked requests without Content-Length.
  const reader = request.body?.getReader();
  if (!reader) throw new Error("invalid");
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 1024) { await reader.cancel(); throw new Error("invalid"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

async function readPayload(request) {
  const body = await readJSON(request);
  if (!exactKeys(body, ["device_token", "score", "dims", "app_version"])
    || typeof body.device_token !== "string" || !/^[A-Za-z0-9-]{8,64}$/.test(body.device_token)
    || !scoreValid(body.score) || !exactKeys(body.dims, dimensionKeys)
    || !dimensionKeys.every((key) => scoreValid(body.dims[key]))
    || typeof body.app_version !== "string" || body.app_version.length > 20) throw new Error("invalid");
  return body;
}

async function issueLicense(request, env) {
  if (!env.ADMIN_TOKEN || request.headers.get("Authorization") !== `Bearer ${env.ADMIN_TOKEN}`) {
    return licenseResponse({ error: "unauthorized" }, 401);
  }
  let body;
  try {
    body = await readJSON(request);
    if (!exactKeys(body, ["order_ref", "days"]) || typeof body.order_ref !== "string"
      || body.order_ref.trim().length === 0 || body.order_ref.length > 64 || body.days !== 365) throw new Error("invalid");
  } catch { return licenseResponse({ error: "invalid" }, 422); }
  const now = new Date();
  const payload = { v: 1, lic: base64url(crypto.getRandomValues(new Uint8Array(12))), plan: "pro",
    iat: now.toISOString().slice(0, 10), exp: new Date(now.getTime() + body.days * 86400000).toISOString().slice(0, 10) };
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO licenses (lic, plan, iat, exp, order_ref, created_at)
      SELECT ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM manual_orders WHERE order_ref = ?)`)
      .bind(payload.lic, payload.plan, payload.iat, payload.exp, body.order_ref, now.toISOString(), body.order_ref),
    env.DB.prepare(`INSERT OR IGNORE INTO manual_orders(order_ref, lic)
      SELECT order_ref, lic FROM licenses WHERE lic = ?`).bind(payload.lic),
  ]);
  const stored = await env.DB.prepare(`SELECT l.* FROM licenses l JOIN manual_orders m ON m.lic = l.lic
    WHERE m.order_ref = ?`).bind(body.order_ref).first();
  const key = await signLicense(env, { v: 1, lic: stored.lic, plan: stored.plan, iat: stored.iat, exp: stored.exp });
  await env.DB.prepare(`INSERT OR IGNORE INTO license_keys(lic, period_ref, exp, key) VALUES (?, ?, ?, ?)`)
    .bind(stored.lic, `manual:${body.order_ref}`, stored.exp, key).run();
  const issued = await env.DB.prepare("SELECT key FROM license_keys WHERE lic = ? AND period_ref = ?")
    .bind(stored.lic, `manual:${body.order_ref}`).first();
  return licenseResponse({ key: issued.key });
}

// Only this evaluable arithmetic is currently shipped. Future versions must be
// explicitly reviewed here; app_version never determines score comparability.
const knownScoreVersions = new Set(["1"]);

// Separate from public routing so tests can prove isolation using a synthetic
// second version without advertising an unsupported production scoring model.
export async function handleScore(request, env, scoreVersion = null) {
  if (scoreVersion !== null && !/^[A-Za-z0-9.-]{1,32}$/.test(scoreVersion)) {
    return Response.json({ error: "invalid" }, { status: 422 });
  }
  const versioned = scoreVersion !== null;
  const literal = versioned ? `'${scoreVersion}'` : "";
  const scope = versioned ? `score_version = ${literal} AND ` : "";
  const versionColumn = versioned ? "score_version, " : "";
  const versionValue = versioned ? `${literal}, ` : "";
  const versionJoin = versioned ? `AND c.score_version = ${literal} AND d.score_version = ${literal}` : "";
  const prepare = (sql) => env.DB.prepare(versioned
    ? sql.replace(/\b(devices|score_counts|dim_counts)\b/g, "cohort_$1") : sql);
  const seedStatements = versioned ? [
    env.DB.prepare(`WITH RECURSIVE scores(score) AS (
      SELECT 0 UNION ALL SELECT score + 1 FROM scores WHERE score < 100)
      INSERT OR IGNORE INTO cohort_score_counts(score_version, score, n)
      SELECT ?, score, 0 FROM scores`).bind(scoreVersion),
    env.DB.prepare(`WITH RECURSIVE scores(score) AS (
      SELECT 0 UNION ALL SELECT score + 1 FROM scores WHERE score < 100),
      dims(dim) AS (SELECT 'routing' UNION ALL SELECT 'timing' UNION ALL SELECT 'context' UNION ALL SELECT 'leverage')
      INSERT OR IGNORE INTO cohort_dim_counts(score_version, dim, score, n)
      SELECT ?, dim, score, 0 FROM dims CROSS JOIN scores`).bind(scoreVersion),
  ] : [];
  let body;
  try { body = await readPayload(request); }
  catch { return Response.json({ error: "invalid" }, { status: 422 }); }
  const { device_token: token, score, dims, app_version: version } = body;
  const now = new Date();
  const cutoff = new Date(now.getTime() - 3600000).toISOString();
  // Each statement checks the current device inside the same atomic batch.
  // Concurrent submissions cannot race a read performed outside the transaction.
  await env.DB.batch([
    ...seedStatements,
    prepare(`UPDATE score_counts SET n = n - 1 WHERE ${scope}score = (
      SELECT score FROM devices WHERE ${scope}device_token = ? AND score <> ? AND updated_at <= ?
    )`).bind(token, score, cutoff),
    prepare(`UPDATE score_counts SET n = n + 1 WHERE ${scope}score = ? AND (
      NOT EXISTS (SELECT 1 FROM devices WHERE ${scope}device_token = ?) OR
      EXISTS (SELECT 1 FROM devices WHERE ${scope}device_token = ? AND score <> ? AND updated_at <= ?)
    )`).bind(score, token, token, score, cutoff),
    ...dimensionKeys.flatMap((dim) => [
      prepare(`UPDATE dim_counts SET n = n - 1 WHERE ${scope}dim = ? AND score = (
        SELECT ${dim} FROM devices WHERE ${scope}device_token = ? AND ${dim} <> ? AND updated_at <= ?
      )`).bind(dim, token, dims[dim], cutoff),
      prepare(`UPDATE dim_counts SET n = n + 1 WHERE ${scope}dim = ? AND score = ? AND (
        NOT EXISTS (SELECT 1 FROM devices WHERE ${scope}device_token = ?) OR
        EXISTS (SELECT 1 FROM devices WHERE ${scope}device_token = ? AND ${dim} <> ? AND updated_at <= ?)
      )`).bind(dim, dims[dim], token, token, dims[dim], cutoff),
    ]),
    prepare(`INSERT INTO devices
      (${versionColumn}device_token, score, routing, timing, context, leverage, app_version, updated_at)
      VALUES (${versionValue}?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(${versionColumn}device_token) DO UPDATE SET score = excluded.score,
      routing = excluded.routing, timing = excluded.timing, context = excluded.context,
      leverage = excluded.leverage, app_version = excluded.app_version, updated_at = excluded.updated_at
      WHERE devices.updated_at <= ?`).bind(token, score, dims.routing, dims.timing,
        dims.context, dims.leverage, version, now.toISOString(), cutoff),
  ]);
  const counts = await prepare(`SELECT SUM(n) AS total,
    SUM(CASE WHEN score < (SELECT score FROM devices WHERE ${scope}device_token = ?) THEN n ELSE 0 END) AS beaten,
    SUM(CASE WHEN score > (SELECT score FROM devices WHERE ${scope}device_token = ?) THEN n ELSE 0 END) AS higher FROM score_counts WHERE ${scope}1=1`)
    .bind(token, token).first();
  const total = counts.total;
  const dimRanks = await prepare(`SELECT c.dim,
    SUM(CASE WHEN c.score > CASE c.dim WHEN 'routing' THEN d.routing WHEN 'timing' THEN d.timing
      WHEN 'context' THEN d.context WHEN 'leverage' THEN d.leverage END THEN c.n ELSE 0 END) + 1 AS rank,
    SUM(CASE WHEN c.score < CASE c.dim WHEN 'routing' THEN d.routing WHEN 'timing' THEN d.timing
      WHEN 'context' THEN d.context WHEN 'leverage' THEN d.leverage END THEN c.n ELSE 0 END) AS beaten
    FROM dim_counts c JOIN devices d ON d.device_token = ? ${versionJoin} GROUP BY c.dim`).bind(token).all();
  return Response.json({ ...(scoreVersion === null ? {} : { score_version: scoreVersion }), total, dims: Object.fromEntries(dimRanks.results.map(({ dim, rank, beaten }) =>
    [dim, { rank, percentile: total >= 20 ? Math.round(100 * beaten / (total - 1)) : null }])), rank: counts.higher + 1,
    percentile: total >= 20 ? Math.round(100 * counts.beaten / (total - 1)) : null,
    small_sample: total < 20 });
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === "/v1/waffo/webhook" || path === "/v1/license/refresh") return handleSubscription(request, env);
    if (request.method === "POST" && path === "/v1/license/issue") {
      if (new URL(request.url).search) return licenseResponse({ error: "invalid" }, 422);
      try { return await issueLicense(request, env); }
      catch { return licenseResponse({ status: "unavailable" }, 503); }
    }
    if (request.method !== "POST") return new Response(null, { status: 404 });
    if (path === "/v1/score") return handleScore(request, env);
    const scoreVersion = path.match(/^\/v1\/score\/([^/]+)$/)?.[1];
    if (!knownScoreVersions.has(scoreVersion)) return new Response(null, { status: 404 });
    return handleScore(request, env, scoreVersion);
  },
};
