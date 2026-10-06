#!/usr/bin/env python3
"""Elicitation hook: the orchestrator answers the Supabase MCP confirmation box for apply_migration.

Since mcp-server-supabase 0.13.0 (2026-09-17), the hosted Supabase MCP asks the client to confirm any SQL
its classifier calls destructive: a statement starting with DROP, DELETE or TRUNCATE, ALTER TABLE ... DROP
COLUMN, or UPDATE without WHERE. The classifier splits on ';' without respecting function bodies, so a DELETE
inside a plpgsql body also raises the box. The request expires after a while, and here migrations are
approved by the GP in the chat before the call. Decision of the GP, 2026-10-06: the orchestrator answers the
box, except when the migration itself deletes data; then the box stays for a person.

Accepts ONLY when all of these hold. Otherwise it prints nothing and the normal box appears:
  1. the server is "supabase" and the tool is apply_migration (execute_sql keeps the box);
  2. the message names this project ("Apply the migration to project ldrfrvwhxsmgaabwmaik?");
  3. the box asks for no field (action-only form);
  4. the session is the designated orchestrator (same file db-write-gate.py reads);
  5. the migration SQL, read from this session's transcript by tool_use_id, deletes no data at top level:
     no DELETE, TRUNCATE, UPDATE without WHERE, DROP TABLE, DROP SCHEMA, DROP DATABASE or
     ALTER TABLE ... DROP COLUMN, and no DO block doing one of those. Function bodies are definitions, not
     execution, so a DELETE inside CREATE FUNCTION does not count.

It never exits non-zero: exit 2 would decline the box. Every decision is appended to LOG_FILE.
"""
import json
import os
import re
import sys
import time

PROJECT_REF = "ldrfrvwhxsmgaabwmaik"
SERVER = "supabase"
ORCH_FILE = os.environ.get(
    "LANE_ORCH_FILE",
    os.path.expanduser("~/projects/_pmo/lanes/ai-pm-research-hub.orquestrador"),
)
LOG_FILE = os.environ.get(
    "SUPABASE_CONFIRM_GATE_LOG",
    os.path.expanduser("~/.claude/logs/supabase-confirm-gate.log"),
)
TAIL_BYTES = 16 * 1024 * 1024

DOLLAR_BODY = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$.*?\$\1\$", re.S)
DO_BLOCK = re.compile(r"\bdo\s+(?:language\s+\w+\s+)?(\$([A-Za-z_][A-Za-z0-9_]*)?\$)(.*?)\1", re.S | re.I)
SQ_STRING = re.compile(r"'(?:[^']|'')*'")
DATA_LOSS = [
    re.compile(r"^(delete|truncate)\b", re.I),
    re.compile(r"^drop\s+(table|schema|database)\b", re.I),
    re.compile(
        r"^alter\s+table\b.*\bdrop\s+(?!constraint\b|default\b|not\s+null\b|identity\b|expression\b)",
        re.I | re.S,
    ),
]


def orchestrator_id() -> str:
    try:
        with open(ORCH_FILE, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    return line.split()[0]
    except OSError:
        pass
    return ""


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    return re.sub(r"--[^\n]*", " ", sql)


def statement_loses_data(stmt: str) -> bool:
    s = stmt.strip()
    if not s:
        return False
    if any(p.search(s) for p in DATA_LOSS):
        return True
    return bool(re.match(r"^update\b", s, re.I)) and not re.search(r"\bwhere\b", s, re.I)


def do_block_loses_data(body: str) -> str:
    """A DO block runs on apply. Statements there start after BEGIN, THEN, ELSE or LOOP, and dynamic SQL
    runs from the string given to EXECUTE."""
    for dyn in re.finditer(r"\bexecute\s+(?:format\s*\(\s*)?'((?:[^']|'')*)'", body, re.I):
        for stmt in dyn.group(1).replace("''", "'").split(";"):
            if statement_loses_data(stmt):
                return "EXECUTE " + stmt.strip()[:52]
    plain = SQ_STRING.sub("''", body)
    for stmt in re.split(r";|\b(?:begin|then|else|loop|declare)\b", plain, flags=re.I):
        if statement_loses_data(stmt):
            return stmt.strip()[:60]
    return ""


def loses_data(sql: str) -> str:
    """Returns the reason the migration deletes data, or '' when it does not."""
    sql = strip_comments(sql)
    for block in DO_BLOCK.finditer(sql):
        reason = do_block_loses_data(block.group(3))
        if reason:
            return "DO block: " + reason
    top = SQ_STRING.sub("''", DOLLAR_BODY.sub(" ", sql))
    for stmt in top.split(";"):
        if statement_loses_data(stmt):
            return "statement: " + stmt.strip()[:60]
    return ""


def migration_sql(transcript_path: str, tool_use_id: str):
    """Returns (name, query) of the tool call in the transcript, or (None, None) when not found."""
    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as fh:
            if size > TAIL_BYTES:
                fh.seek(size - TAIL_BYTES)
                fh.readline()
            lines = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None, None
    for line in reversed(lines):
        if tool_use_id not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        content = (entry.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for part in content:
            if isinstance(part, dict) and part.get("type") == "tool_use" and part.get("id") == tool_use_id:
                args = part.get("input") or {}
                return args.get("name"), args.get("query")
    return None, None


def log(event: dict, decision: str, reason: str, name=None) -> None:
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "session": (event.get("session_id") or "")[:8],
                "tool_use_id": event.get("tool_use_id"),
                "migration": name,
                "decision": decision,
                "reason": reason,
            }, ensure_ascii=False) + "\n")
    except OSError:
        pass


def decide(event: dict):
    """Returns (accept, reason, migration name)."""
    if event.get("hook_event_name") not in (None, "Elicitation"):
        return False, "not an Elicitation event", None
    if event.get("mcp_server_name") != SERVER:
        return False, "server is not supabase", None
    if not str(event.get("tool_name") or "").endswith("apply_migration"):
        return False, "tool is not apply_migration", None
    if f"Apply the migration to project {PROJECT_REF}?" not in str(event.get("message") or ""):
        return False, "message does not name this project", None
    schema = event.get("requested_schema") or {}
    if schema.get("properties") or schema.get("required"):
        return False, "the box asks for fields", None
    orch = orchestrator_id()
    if not orch or event.get("session_id") != orch:
        return False, "session is not the designated orchestrator", None
    name, query = migration_sql(str(event.get("transcript_path") or ""), str(event.get("tool_use_id") or ""))
    if not query:
        return False, "migration SQL not found in the transcript", name
    reason = loses_data(query)
    if reason:
        return False, "migration deletes data (" + reason + ")", name
    return True, "orchestrator, this project, no data deleted at top level", name


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(event, dict):
        return
    try:
        accept, reason, name = decide(event)
    except Exception as exc:  # any surprise falls back to the person
        accept, reason, name = False, "hook error: " + type(exc).__name__, None
    log(event, "accept" if accept else "ask", reason, name)
    if accept:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "Elicitation", "action": "accept", "content": {}}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
