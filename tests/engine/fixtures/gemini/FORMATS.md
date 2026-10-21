# Task 5 format notes

Reference: pre-downloaded Tokei `usage.30s.py`, `test_gemini_usage.py`,
`test_opencode_sqlite.py`, `test_qwencode.py`, and `CALCULATION.md` in
`/tmp/tokei-ref/`. Consulted for data formats only; collector code and synthetic
fixtures are independently written. No reference implementation is vendored.

| Tool | Locations below supplied home | Record and identity | Model / timestamp | Token mapping |
| --- | --- | --- | --- | --- |
| Gemini CLI | `.gemini/tmp/**/session-*.json`, `session-*.jsonl`, nested `*/chats/**/*.jsonl`; also `.gemini/{antigravity-cli,antigravity,antigravity-ide,gemini-cli}/conversations` | JSON `sessionId`, `messages[]`; journal message `id`, `$set`, `$push`, `$rewindTo`; session + message ID | `model`, ISO `timestamp` | `tokens.input - tokens.cached`; cache = `cached`; output = `output + thoughts` |
| Gemini conversation DB | `*.db` under those roots, excluding `conversation_summaries.db` | `gen_metadata(idx, data BLOB)`; DB stem + row index + generation ordinal | protobuf generation field 19 model; field 9 -> 4 -> 1 epoch seconds, or row field 2 packed step references -> `steps(idx, metadata)` field 1 -> 1 | generation field 4: field 2 non-cached input, 5 cached input, 3 total output including thoughts; when field 10 reply output exists, add field 9 thoughts |
| OpenCode | `.local/share/opencode/opencode.db`, `storage/message/ses_*/msg_*.json` | SQLite `message(id, session_id, time_created, data)` with assistant JSON in `data`; message ID, DB preferred to legacy duplicate | `modelID` (fallback `model.id`), `time.created` epoch ms (fallback SQL `time_created`) | Independent `tokens.input`, `cache.read`, `cache.write`; output = `output + reasoning` |
| Qwen Code | `.qwen/usage_record.jsonl` | `version: 1`, `sessionId`, `models` map; latest cumulative snapshot replaces prior session; event identity session + model | model map key; `timestamp` or `startTime` epoch ms / ISO | `inputTokens - cachedTokens`; cache = `cachedTokens`; output = `outputTokens + thoughtsTokens` |

`CompactEvent` has no separate reasoning field. Independent thoughts/reasoning
are included once in output, preserving total usage and API-equivalent output
pricing. No activity, content, inventory, or project fields are collected.

Qwen's newer `usage/token-usage-*.jsonl` files are intentionally not read: the
plan's Global Constraints prohibit opening any `*token*` file. This means
request-only Qwen installations have no usage until a session summary exists.
Custom environment-based roots and settings discovery are outside this task.

JSON documents and Gemini journals can replace or rewind earlier messages;
changed files are rebuilt, unchanged signatures reuse cached compact events.
OpenCode stores `max_rowid` and `max_time` alongside events on the DB path,
but refreshes a changed DB instead of querying only newer rows: streaming can
update existing rows. Signatures include WAL metadata. Qwen uses the existing
complete-line incremental cursor. All database connections use escaped file
URIs with `mode=ro` and `query_only`; no immutable mode (which could miss WAL).
A private `_usage.py` helper centralizes validation, URI handling, and signatures.
