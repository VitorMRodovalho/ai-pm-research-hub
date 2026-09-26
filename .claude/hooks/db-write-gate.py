#!/usr/bin/env python3
"""PreToolUse gate: only the designated ORCHESTRATOR session writes to the shared database.

WHY (2026-09-25, #2477): two migrations went to production from a session that was NOT the
orchestrator. It ran in the primary clone (not in a lane worktree), had opened its own lane, and
followed a prompt written by a third session that told it to apply DDL "when the queue is empty".
The old hook only ASKED, and only with a busy queue. A first version of this gate decided by
directory (lane worktree = deny) and would NOT have caught it: that session's cwd was the primary
clone. The discriminator that works is the SESSION, so this gate asks "is this the designated
orchestrator?", wherever the session runs.

Scope: writes to THIS project's database only.
  * mcp__supabase__*            -> the project-level server in .mcp.json; barred unless the nearest
                                   .mcp.json above cwd names ANOTHER project_ref (the user-level copy of
                                   this gate runs in every project of the portfolio)
  * mcp__claude_ai_Supabase__*  -> only when tool_input.project_id is this project
Decisions for apply_migration, and for execute_sql carrying a write/DDL statement:
  * designated orchestrator -> apply_migration asks when PRs are open or DB jobs are in flight
                               (the old queue check), else allow; execute_sql allow
  * any other session       -> deny, naming the orchestrator and how the GP re-designates
  * no orchestrator on file -> deny (fail-closed)
Read-only execute_sql always passes.

The designation lives OUTSIDE the repo (public): ORCH_FILE below, first token = session_id. The GP
designates; `scripts/lane-registry.sh orquestrador <session_id> "<nota>"` writes it.

Bash (2026-09-25, decisao do GP, pacote A): the MCP is not the only path. The account-wide
management token (SQL of any kind through api.supabase.com, or the linked Supabase CLI) and psql
also write. For a session that is NOT the orchestrator, a Bash command is denied when it matches
BASH_RISK_RE AND it concerns THIS project: the command names PROJECT_REF, or the cwd is a clone or
worktree of this repository (git remote). Sessions in other repos of the portfolio keep their own
CLI. The token lives in ~/.config/supabase-mgmt/token, outside every repo, and `with-supabase-token
<cmd>` loads it for one command; reading it is one of the denied forms. The service_role key in the
lanes' .env is NOT covered: it reaches DML only, and the lanes' DB-aware tests need it.

Known limits: a SELECT that calls a writing function (`select some_rpc()`) is not detected as a
write, and a quoted identifier spelled like a keyword (`select 1 as "update"`) is taken as one. The
first is a gap the rule in CLAUDE.md still covers; the second is a conservative false positive, and
it is the probe used to exercise this gate live without writing anything. This is a
guardrail against ACCIDENTS between sessions of the same user, not a security boundary.

Env (tests): DB_GATE_SKIP_QUEUE=1 skips the `gh` queue check; LANE_ORCH_FILE overrides ORCH_FILE.
"""
import json
import os
import re
import subprocess
import sys

PROJECT_REF = "ldrfrvwhxsmgaabwmaik"
ORCH_FILE = os.environ.get(
    "LANE_ORCH_FILE",
    os.path.expanduser("~/projects/_pmo/lanes/ai-pm-research-hub.orquestrador"),
)

WRITE_RE = re.compile(
    r"\b(INSERT|UPDATE|DELETE|MERGE|UPSERT|TRUNCATE|CREATE|ALTER|DROP|GRANT|REVOKE|"
    r"COMMENT\s+ON|REFRESH\s+MATERIALIZED|VACUUM|REINDEX|CLUSTER|CALL|DO|SECURITY\s+LABEL|"
    r"COPY|LOCK|NOTIFY)\b",
    re.IGNORECASE,
)


BASH_RISK_RE = re.compile(
    r"api\.supabase\.com"
    r"|\bsupabase\s+(?:db|migration|functions|gen|link|secrets|sql|inspect|projects|branches|storage)\b"
    r"|\bnpx\s+supabase\b"
    r"|\b(?:psql|pg_dump|pg_restore)\b"
    r"|\bdb:types\b|check_advisors"
    r"|with-supabase-token|supabase-mgmt|\.supabase/access-token|SUPABASE_ACCESS_TOKEN",
)
REPO_RE = re.compile(r"[/:]ai-pm-research-hub(?:\.git)?/?$")


def repo_is_this(cwd: str) -> bool:
    if not cwd or not os.path.isdir(cwd):
        return False
    out = subprocess.run(
        ["git", "-C", cwd, "config", "--get", "remote.origin.url"],
        capture_output=True, text=True, timeout=10,
    )
    return out.returncode == 0 and bool(REPO_RE.search(out.stdout.strip()))


def bash_deny_reason(session_id: str, orch: str, cwd: str) -> str:
    who = f"a sessao orquestradora designada e {orch[:8]}" if orch else "NENHUMA sessao orquestradora esta designada"
    return (
        f"SO A ORQUESTRADORA USA O TOKEN DE GESTAO, A CLI DO SUPABASE OU O PSQL NESTE PROJETO. Esta sessao "
        f"({session_id[:8] or '?'}) NAO e a orquestradora e roda {where(cwd)} ({cwd}); {who}. O token da conta "
        "roda SQL de qualquer tipo em todos os projetos; a trava do MCP nao o cobre, esta cobre. Se precisa de "
        "deploy, db:types ou SQL, prepare o pacote e mande para a orquestradora. Ler codigo e testes continua "
        "livre; um grep que cite estes nomes tambem e barrado, entao reformule."
    )


def strip_sql_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    # String literals cannot trigger the keyword scan (a SELECT of 'DROP' is still a read).
    sql = re.sub(r"'(?:[^']|'')*'", "''", sql)
    return sql


def is_write(sql: str) -> bool:
    return bool(WRITE_RE.search(strip_sql_comments(sql or "")))


def mcp_json_ref(cwd: str) -> str:
    """project_ref named by the nearest .mcp.json at or above cwd; "" when none names one."""
    d = os.path.abspath(cwd or os.getcwd())
    while True:
        f = os.path.join(d, ".mcp.json")
        if os.path.isfile(f):
            try:
                m = re.search(r"project_ref=([a-z0-9]+)", open(f, encoding="utf-8").read())
                return m.group(1) if m else ""
            except OSError:
                return ""
        parent = os.path.dirname(d)
        if parent == d:
            return ""
        d = parent


def targets_this_db(tool: str, tool_input: dict, cwd: str) -> bool:
    if tool.startswith("mcp__supabase__"):
        ref = mcp_json_ref(cwd)
        return not ref or ref == PROJECT_REF
    if tool.startswith("mcp__claude_ai_Supabase__"):
        return tool_input.get("project_id") == PROJECT_REF
    return False


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


def queue_busy() -> tuple:
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


def where(cwd: str) -> str:
    if is_lane(cwd):
        return "num worktree de LANE"
    if cwd and os.path.isdir(cwd) and git_path(cwd, "--git-dir"):
        return "no clone principal"
    return "fora de um repositorio git"


def deny_reason(session_id: str, orch: str, cwd: str) -> str:
    who = f"a sessao orquestradora designada e {orch[:8]}" if orch else "NENHUMA sessao orquestradora esta designada"
    return (
        f"SO A ORQUESTRADORA ESCREVE NO BANCO COMPARTILHADO. Esta sessao ({session_id[:8] or '?'}) NAO e a "
        f"orquestradora e roda {where(cwd)} ({cwd}); {who}. Prepare o pacote (o .sql, a verificacao) e mande para ela, que aplica "
        "e commita no mesmo passo. Em 25/09/2026 uma sessao que nao era a orquestradora aplicou 2 "
        "migrations em producao. Trocar a orquestradora e decisao do GP: "
        "scripts/lane-registry.sh orquestrador <session_id> \"<nota>\"."
    )


def decide(event: dict):
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if not BASH_RISK_RE.search(cmd):
            return None, None
        cwd = event.get("cwd") or os.getcwd()
        if PROJECT_REF not in cmd and not repo_is_this(cwd):
            return None, None
        session_id = event.get("session_id") or ""
        orch = orchestrator_id()
        if not orch or session_id != orch:
            return "deny", bash_deny_reason(session_id, orch, cwd)
        return None, None
    is_apply = tool.endswith("__apply_migration")
    is_sql = tool.endswith("__execute_sql")
    cwd = event.get("cwd") or os.getcwd()
    if not (is_apply or is_sql) or not targets_this_db(tool, tool_input, cwd):
        return None, None
    if is_sql and not is_write(tool_input.get("query", "")):
        return None, None

    session_id = event.get("session_id") or ""
    orch = orchestrator_id()
    if not orch or session_id != orch:
        return "deny", deny_reason(session_id, orch, cwd)

    if is_apply:
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
