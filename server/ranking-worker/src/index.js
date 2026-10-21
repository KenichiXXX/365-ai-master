const dimensionKeys = ["routing", "timing", "context", "leverage"];
const exactKeys = (value, keys) => value !== null && typeof value === "object"
  && !Array.isArray(value) && Object.keys(value).length === keys.length
  && keys.every((key) => Object.hasOwn(value, key));
const scoreValid = (score) => Number.isInteger(score) && score >= 0 && score <= 100;

async function readPayload(request) {
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
  const body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  if (!exactKeys(body, ["device_token", "score", "dims", "app_version"])
    || typeof body.device_token !== "string" || !/^[A-Za-z0-9-]{8,64}$/.test(body.device_token)
    || !scoreValid(body.score) || !exactKeys(body.dims, dimensionKeys)
    || !dimensionKeys.every((key) => scoreValid(body.dims[key]))
    || typeof body.app_version !== "string" || body.app_version.length > 20) throw new Error("invalid");
  return body;
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/v1/score") {
      return new Response(null, { status: 404 });
    }
    let body;
    try { body = await readPayload(request); }
    catch { return Response.json({ error: "invalid" }, { status: 422 }); }
    const { device_token: token, score, dims, app_version: version } = body;
    const now = new Date();
    const cutoff = new Date(now.getTime() - 3600000).toISOString();
    // Each statement checks the current device inside the same atomic batch.
    // Concurrent submissions cannot race a read performed outside the transaction.
    await env.DB.batch([
      env.DB.prepare(`UPDATE score_counts SET n = n - 1 WHERE score = (
        SELECT score FROM devices WHERE device_token = ? AND score <> ? AND updated_at <= ?
      )`).bind(token, score, cutoff),
      env.DB.prepare(`UPDATE score_counts SET n = n + 1 WHERE score = ? AND (
        NOT EXISTS (SELECT 1 FROM devices WHERE device_token = ?) OR
        EXISTS (SELECT 1 FROM devices WHERE device_token = ? AND score <> ? AND updated_at <= ?)
      )`).bind(score, token, token, score, cutoff),
      env.DB.prepare(`INSERT INTO devices
        (device_token, score, routing, timing, context, leverage, app_version, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(device_token) DO UPDATE SET score = excluded.score,
        routing = excluded.routing, timing = excluded.timing, context = excluded.context,
        leverage = excluded.leverage, app_version = excluded.app_version, updated_at = excluded.updated_at
        WHERE devices.updated_at <= ?`).bind(token, score, dims.routing, dims.timing,
          dims.context, dims.leverage, version, now.toISOString(), cutoff),
    ]);
    const counts = await env.DB.prepare(`SELECT SUM(n) AS total,
      SUM(CASE WHEN score < ? THEN n ELSE 0 END) AS beaten,
      SUM(CASE WHEN score > ? THEN n ELSE 0 END) AS higher FROM score_counts`)
      .bind(score, score).first();
    const total = counts.total;
    return Response.json({ total, rank: counts.higher + 1,
      percentile: total >= 20 ? Math.round(100 * counts.beaten / (total - 1)) : null,
      small_sample: total < 20 });
  },
};
