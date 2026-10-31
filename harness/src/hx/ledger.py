"""The ledger: one DuckDB file all clients normalise into (DESIGN.md §2).

The ledger is *derived*: raw source copies under data/raw/ are the record, and
`hx ingest --rebuild` recreates every table from them. That makes schema changes
a rebuild rather than a migration.
"""

from __future__ import annotations

from pathlib import Path

import duckdb

from hx.paths import data_dir

SCHEMA_VERSION = 3  # bump on any table change; a mismatch triggers a full rebuild from raw

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE IF NOT EXISTS session (
    session_id TEXT PRIMARY KEY,
    client TEXT, project TEXT, cwd TEXT, git_branch TEXT,
    title TEXT, entrypoint TEXT, client_version TEXT
);

-- One row per model response (deduped by provider message id).
CREATE TABLE IF NOT EXISTS call (
    call_id TEXT PRIMARY KEY,
    session_id TEXT, agent_id TEXT, client TEXT,
    provider TEXT, model TEXT, ts TIMESTAMP,
    input_tokens BIGINT, output_tokens BIGINT,
    cache_read_tokens BIGINT, cache_write_5m_tokens BIGINT, cache_write_1h_tokens BIGINT,
    thinking_tokens BIGINT, stop_reason TEXT,
    est_usd DOUBLE,
    source TEXT
);

CREATE TABLE IF NOT EXISTS tool_use (
    tool_use_id TEXT PRIMARY KEY,
    call_id TEXT, session_id TEXT, agent_id TEXT, ts TIMESTAMP,
    tool TEXT, input_chars BIGINT, command TEXT
);

CREATE TABLE IF NOT EXISTS tool_result (
    tool_use_id TEXT PRIMARY KEY,
    session_id TEXT, ts TIMESTAMP,
    result_chars BIGINT, is_error BOOLEAN, denied TEXT
);

-- Point events: prompt, interrupt, api_error, turn (value = ms), compaction, ...
CREATE TABLE IF NOT EXISTS event (
    event_id TEXT PRIMARY KEY,
    session_id TEXT, agent_id TEXT, ts TIMESTAMP,
    kind TEXT, value DOUBLE, detail TEXT
);

-- Links between sessions and tracker tasks (DESIGN.md §2, Q3).
CREATE TABLE IF NOT EXISTS session_task (
    session_id TEXT, task_id TEXT, ts TIMESTAMP, source TEXT,
    PRIMARY KEY (session_id, task_id, source)
);

-- Subscription/provider quota windows over time (from data/raw/quota/*.jsonl).
CREATE TABLE IF NOT EXISTS quota_snapshot (
    provider TEXT, window_name TEXT, ts TIMESTAMP, used_pct DOUBLE, resets_at TIMESTAMP, session_id TEXT,
    PRIMARY KEY (provider, window_name, ts)
);

CREATE TABLE IF NOT EXISTS import_state (
    raw_path TEXT PRIMARY KEY, size BIGINT, mtime_ns BIGINT, imported_at TIMESTAMP
);

CREATE OR REPLACE VIEW session_summary AS
SELECT s.*,
       c.first_ts, c.last_ts, c.calls, c.models,
       c.input_tokens, c.output_tokens, c.cache_read_tokens, c.cache_write_tokens, c.est_usd,
       (SELECT count(*) FROM tool_use t WHERE t.session_id = s.session_id) AS tool_uses,
       (SELECT string_agg(DISTINCT task_id, ',') FROM session_task st WHERE st.session_id = s.session_id) AS tasks
FROM session s
LEFT JOIN (
    SELECT session_id, min(ts) AS first_ts, max(ts) AS last_ts, count(*) AS calls,
           string_agg(DISTINCT model, ',') AS models,
           sum(input_tokens) AS input_tokens, sum(output_tokens) AS output_tokens,
           sum(cache_read_tokens) AS cache_read_tokens,
           sum(cache_write_5m_tokens + cache_write_1h_tokens) AS cache_write_tokens,
           sum(est_usd) AS est_usd
    FROM call GROUP BY session_id
) c USING (session_id);
"""

TABLES = ["session", "call", "tool_use", "tool_result", "event", "session_task", "quota_snapshot",
          "import_state", "meta"]


def path() -> Path:
    return data_dir() / "ledger.duckdb"


def connect(db: Path | None = None, rebuild: bool = False) -> duckdb.DuckDBPyConnection:
    db = db or path()
    db.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(db))
    if rebuild or _version(con) not in (None, SCHEMA_VERSION):
        con.execute("DROP VIEW IF EXISTS session_summary")
        for t in TABLES:
            con.execute(f"DROP TABLE IF EXISTS {t}")
    con.execute(SCHEMA)
    con.execute("INSERT OR REPLACE INTO meta VALUES ('schema_version', ?)", [str(SCHEMA_VERSION)])
    return con


def _version(con) -> int | None:
    try:
        row = con.execute("SELECT value FROM meta WHERE key = 'schema_version'").fetchone()
        return int(row[0]) if row else None
    except duckdb.CatalogException:
        return None


def upsert(con, table: str, rows: list[dict]) -> None:
    if not rows:
        return
    cols = list(rows[0])
    sql = f"INSERT OR REPLACE INTO {table} ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})"
    con.executemany(sql, [[r[c] for c in cols] for r in rows])
