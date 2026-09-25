#!/usr/bin/env python3
"""PreToolUse gate for writes to the SHARED database (apply_migration, execute_sql).

WHY (2026-09-25): a lane session, running in its own git worktree, applied two RLS migrations
straight to production. The previous hook only ASKED, and only when PRs were open or DB jobs were
running; with an empty queue it let the DDL through in silence, and nothing checked WHO was asking.
The rule was already written ("a lane prepara, a main aplica"); it was not mechanical.

Decisions:
  * lane (the session's cwd is a LINKED worktree: git-dir != git-common-dir):
      - apply_migration                        -> deny
      - execute_sql with a write/DDL statement -> deny
      - execute_sql read-only                  -> allow (no output)
  * main clone:
      - apply_migration -> ask when PRs are open or DB jobs are in flight (the old check), else allow
      - execute_sql     -> allow (the database rules in .claude/rules/ still apply)

Known limit: a SELECT that calls a writing function (`select some_rpc()`) is not detected as a
write. The gate catches the explicit forms; the rule in CLAUDE.md still covers the rest.

Env (tests only): DB_GATE_SKIP_QUEUE=1 skips the `gh` queue check.
"""
import json
import os
import re
import subprocess
import sys

LANE_REASON = (
    "LANE NAO ESCREVE NO BANCO COMPARTILHADO. Esta sessao roda num worktree de lane ({cwd}). "
    "A regra do projeto e: a lane PREPARA (o .sql, o pacote de verificacao) e AVISA a sessao "
    "principal, que aplica e commita no mesmo passo. Em 25/09/2026 uma lane aplicou 2 migrations "
    "de RLS direto em producao e a main ficou inconsistente com o banco. Mande o pacote para a main."
)

WRITE_RE = re.compile(
    r"\b(INSERT|UPDATE|DELETE|MERGE|UPSERT|TRUNCATE|CREATE|ALTER|DROP|GRANT|REVOKE|"
    r"COMMENT\s+ON|REFRESH\s+MATERIALIZED|VACUUM|REINDEX|CLUSTER|CALL|DO|SECURITY\s+LABEL|"
    r"COPY|LOCK|NOTIFY)\b",
    re.IGNORECASE,
)


def strip_sql_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    # String literals cannot trigger the keyword scan (a SELECT of 'DROP' is still a read).
    sql = re.sub(r"'(?:[^']|'')*'", "''", sql)
    return sql


def is_write(sql: str) -> bool:
    return bool(WRITE_RE.search(strip_sql_comments(sql or "")))


def git_path(cwd: str, flag: str) -> str:
    out = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--path-format=absolute", flag],
        capture_output=True, text=True, timeout=10,
    )
    return out.stdout.strip() if out.returncode == 0 else ""


def is_lane(cwd: str) -> bool:
    if not cwd or not os.path.isdir(cwd):
        return False
    git_dir = git_path(cwd, "--git-dir")
    common = git_path(cwd, "--git-common-dir")
    return bool(git_dir and common and os.path.realpath(git_dir) != os.path.realpath(common))


def queue_busy() -> tuple[int, int]:
    if os.environ.get("DB_GATE_SKIP_QUEUE") == "1":
        return 0, 0

    def count(args):
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=15)
            return int((r.stdout or "0").strip() or 0)
        except Exception:
            return 0

    prs = count(["gh", "pr", "list", "--state", "open", "--json", "number", "--jq", "length"])
    jobs = count([
        "gh", "run", "list", "--limit", "30", "--json", "name,status", "--jq",
        '[.[]|select(.status!="completed")|select(.name|test("Validate|Invariants|DB Types"))]|length',
    ])
    return prs, jobs


def decide(event: dict):
    tool = event.get("tool_name", "")
    cwd = event.get("cwd") or os.getcwd()
    tool_input = event.get("tool_input") or {}
    lane = is_lane(cwd)

    if tool.endswith("__apply_migration"):
        if lane:
            return "deny", LANE_REASON.format(cwd=cwd)
        prs, jobs = queue_busy()
        if prs > 0 or jobs > 0:
            return "ask", (
                f"BANCO OCUPADO: {prs} PR(s) aberta(s) e {jobs} job(s) de banco em voo. "
                "apply_migration atinge o banco COMPARTILHADO na hora, e toda branch sem o .sql passa "
                "a acusar drift (PROD-AHEAD), inclusive a main. Fila de PRs vazia NAO e banco livre: "
                "mergear zera a fila e dispara CI Validate/Schema Invariants na main. Espere os dois "
                "numeros zerarem, ou confirme que a ordem ja foi combinada (#2340)."
            )
        return None, None

    if tool.endswith("__execute_sql"):
        if lane and is_write(tool_input.get("query", "")):
            return "deny", LANE_REASON.format(cwd=cwd) + " (execute_sql com escrita ou DDL)"
        return None, None

    return None, None


def main():
    try:
        event = json.load(sys.stdin)
    except Exception:
        return 0
    decision, reason = decide(event)
    if decision:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
