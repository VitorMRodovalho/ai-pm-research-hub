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
Decisions for apply_migration, for execute_sql carrying a write/DDL statement, and for the
MUTATING_TOOLS below (#2504):
  * designated orchestrator -> apply_migration and merge_branch ask when PRs are open or DB jobs are
                               in flight (the old queue check), else allow; the rest allow
  * any other session       -> deny, naming the orchestrator and how the GP re-designates
  * no orchestrator on file -> deny (fail-closed)
Read-only execute_sql always passes, and so do the MCP tools that only read (list_*, get_*).

MUTATING_TOOLS (#2504, 27/09/2026): tools that change THIS project with no SQL to classify, so every
call counts as a write. Until then the matcher and decide() knew only apply_migration and execute_sql,
and an Edge Function deploy (orchestrator-only by the project rules) passed from any session.
merge_branch applies the branch's migrations to production, so it gets the apply_migration queue check.
The branch tools that take branch_id carry no project_id: the gate cannot tell the project and treats
the call as this one (fail-closed).

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

Main (2026-10-06, decisao do GP): lanes must not push to main in parallel with the orchestrator's work.
For a session that is NOT the orchestrator, in a clone or worktree of this repo or in a command naming it,
the gate also denies what reaches main: merging a PR (gh pr merge, the merge API,
mcp__github__merge_pull_request), a push that lands on main (a refspec to main, a push with no refspec
while on main, --all, --mirror), a forced push, --admin, and writing a file straight to main through the
GitHub MCP. Pushing one's own branch and opening a PR stay free. See main_write().

Known limits: a SELECT that calls a writing function (`select some_rpc()`) is not detected as a
write, and a quoted identifier spelled like a keyword (`select 1 as "update"`) is taken as one. The
first is a gap the rule in CLAUDE.md still covers; the second is a conservative false positive, and
it is the probe used to exercise this gate live without writing anything. This is a
guardrail against ACCIDENTS between sessions of the same user, not a security boundary.

When the gate itself fails (2026-10-09, decisao do GP, opcao do meio): until then every failure let the call
through. Unreadable stdin returned 0, an exception inside decide() made Python exit 1, and Claude Code treats
exit 1 as a NON-blocking error (code.claude.com/docs/en/hooks: "If your hook is meant to enforce a policy, use
exit 2"). Now:
  * a call on a WRITE path fails CLOSED: exit 2 with the reason on stderr (exit 2 blocks whatever the JSON says).
    Write path = apply_migration, execute_sql (before classification there is no way to tell a read), the
    MUTATING_TOOLS, the GitHub MCP tools in GITHUB_MAIN_TOOLS, and a Bash command the gate already treats as a
    write path (BASH_RISK_RE, git push, gh pr merge, the merge API, --admin);
  * any other call (ordinary Bash, other tools) fails OPEN with a loud stderr warning: the hook runs on every Bash
    call of the machine, and a gate bug must not stop every session;
  * unreadable stdin cannot be attributed to a tool, so the RAW TEXT decides: it fails closed when the text names a
    write tool or matches a Bash write pattern, and open (with the warning) otherwise.

Env (tests): DB_GATE_SKIP_QUEUE=1 skips the `gh` queue check; DB_GATE_QUEUE="<prs>,<jobs>" replaces
it with fixed counts (to exercise the busy branch offline); LANE_ORCH_FILE overrides ORCH_FILE;
DB_GATE_INJECT_ERROR=1 raises inside decide(), to exercise the failure policy above.
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

# The .claude/settings.json matcher lists each of these under both server prefixes.
MUTATING_TOOLS = (
    "deploy_edge_function",
    "create_branch", "delete_branch", "merge_branch", "reset_branch", "rebase_branch",
    "pause_project", "restore_project",
)
QUEUED_TOOLS = ("apply_migration", "merge_branch")


BASH_RISK_RE = re.compile(
    r"api\.supabase\.com"
    r"|\bsupabase\s+(?:db|migration|functions|gen|link|secrets|sql|inspect|projects|branches|storage)\b"
    r"|\bnpx\s+supabase\b"
    r"|\b(?:psql|pg_dump|pg_restore)\b"
    r"|\bdb:types\b|check_advisors"
    r"|with-supabase-token|supabase-mgmt|\.supabase/access-token|SUPABASE_ACCESS_TOKEN",
)
REPO_RE = re.compile(r"[/:]ai-pm-research-hub(?:\.git)?/?$")

# Main so pela orquestradora (06/10/2026, decisao do GP): lane nenhuma sobe nada para a main em paralelo
# ao trabalho da orquestradora. Para quem NAO e a orquestradora, o gate nega o que chega a main deste
# repositorio: mergear PR (gh pr merge, a API REST de merge ou a mutation GraphQL), --admin, push forcado e
# push que chega a main (refspec para main, push sem refspec ou de HEAD estando na main, --all, --mirror).
# Cada acao e medida no diretorio em que roda: o cwd, depois de cada `cd` anterior a ela e do `git -C`. O
# gh vale tambem quando o comando cita este repositorio (-R, GH_REPO, caminho da API). Pelo MCP do GitHub:
# merge de PR e gravar arquivo direto na main. Push da branch propria e abrir PR continuam livres: e assim
# que a lane entrega.
REPO_SLUG = "ai-pm-research-hub"
GH_MERGE_RE = re.compile(r"\bgh\s+pr\s+merge\b|\bgh\s+api\b[^\n;&|]*?/(?:pulls/\d+/merge|merges)\b")
GH_GRAPHQL_MERGE_RE = re.compile(
    r"\bgh\s+api\b[^\n;&|]*?\bgraphql\b[\s\S]*\b(?:mergePullRequest|enablePullRequestAutoMerge)\b"
)
GH_ADMIN_RE = re.compile(r"\bgh\b[^\n;&|]*?\s--admin\b")
GIT_PUSH_RE = re.compile(r"\bgit((?:\s+-[cC]\s+\S+)*)\s+push\b([^\n;&|]*)")
MAIN_REFSPEC_RE = re.compile(r"^(?:[^:]*:)?(?:refs/heads/)?main$")
PUSH_ALL_FLAGS = ("--all", "--mirror")
GITHUB_MAIN_TOOLS = ("merge_pull_request", "push_files", "create_or_update_file", "delete_file")


def repo_is_this(cwd: str) -> bool:
    if not cwd or not os.path.isdir(cwd):
        return False
    out = subprocess.run(
        ["git", "-C", cwd, "config", "--get", "remote.origin.url"],
        capture_output=True, text=True, timeout=10,
    )
    return out.returncode == 0 and bool(REPO_RE.search(out.stdout.strip()))


def current_branch(path: str) -> str:
    out = subprocess.run(
        ["git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True, text=True, timeout=10,
    )
    return out.stdout.strip() if out.returncode == 0 else ""


def resolve_dir(base: str, d: str) -> str:
    d = os.path.expandvars(os.path.expanduser(d.strip("'\"")))
    return d if os.path.isabs(d) else os.path.join(base, d)


def dir_at(cmd: str, pos: int, cwd: str) -> str:
    """Onde roda o trecho que comeca em `pos`: o cwd, depois de cada `cd <dir>` anterior a ele. Um `cd`
    para diretorio que nao existe falharia no shell, e quase sempre e texto citado: fica de fora."""
    base = cwd
    for d in re.findall(r"\bcd\s+([^\s;&|]+)", cmd[:pos]):
        nxt = resolve_dir(base, d)
        if os.path.isdir(nxt):
            base = nxt
    return base


def main_write(cmd: str, cwd: str) -> str:
    """O que o comando faz com a main deste repositorio; vazio quando nao chega a ela."""
    for rx, what in ((GH_MERGE_RE, "mergear uma PR"), (GH_GRAPHQL_MERGE_RE, "mergear uma PR"),
                     (GH_ADMIN_RE, "usar --admin")):
        m = rx.search(cmd)
        if m and (REPO_SLUG in cmd or repo_is_this(dir_at(cmd, m.start(), cwd))):
            return what
    for m in GIT_PUSH_RE.finditer(cmd):
        path = dir_at(cmd, m.start(), cwd)
        dirs = re.findall(r"-C\s+(\S+)", m.group(1))
        if dirs:
            path = resolve_dir(path, dirs[-1])
        if not (repo_is_this(path) or REPO_SLUG in m.group(2)):
            continue
        args = m.group(2).split()
        flags = [a for a in args if a.startswith("-")]
        refspecs = [a for a in args if not a.startswith("-")][1:]
        if any(f in ("-f",) or f.startswith("--force") for f in flags):
            return "fazer push forcado"
        if any(f in PUSH_ALL_FLAGS for f in flags):
            return "fazer push de todas as branches, a main inclusive"
        if any(r.startswith("+") for r in refspecs):
            return "fazer push forcado"
        if any(MAIN_REFSPEC_RE.match(r) for r in refspecs):
            return "fazer push para a main"
        pushes_head = not refspecs or any(r.split(":")[-1] in ("HEAD", "@") for r in refspecs)
        if pushes_head and current_branch(path) == "main":
            return "fazer push estando na main"
    return ""


def github_main_write(tool: str, tool_input: dict) -> str:
    """Pelo MCP do GitHub: merge de PR, ou arquivo gravado direto na main, neste repositorio."""
    if not tool.startswith("mcp__github__"):
        return ""
    name = tool[len("mcp__github__"):]
    if name not in GITHUB_MAIN_TOOLS or (tool_input.get("repo") or "") != REPO_SLUG:
        return ""
    if name == "merge_pull_request":
        return "mergear uma PR"
    if (tool_input.get("branch") or "main") == "main":
        return "gravar arquivo direto na main"
    return ""


def main_deny_reason(session_id: str, orch: str, cwd: str, what: str) -> str:
    who = f"a sessao orquestradora designada e {orch[:8]}" if orch else "NENHUMA sessao orquestradora esta designada"
    return (
        f"SO A ORQUESTRADORA MERGEIA E SOBE PARA A MAIN NESTE PROJETO (decisao do GP, 06/10/2026). Esta sessao "
        f"({session_id[:8] or '?'}) NAO e a orquestradora e roda {where(cwd)} ({cwd}); {who}. O comando tenta "
        f"{what}. Termine o trabalho na PR aberta e avise a orquestradora: merge, migration, deploy de EF e "
        "escrita no banco sao dela. Push da sua branch e abrir PR continuam livres. Um comando que so cite "
        "esses comandos (grep, echo, texto de commit) tambem e barrado; reformule."
    )


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


# Leitura de quem NAO e a orquestradora roda numa transacao somente leitura. O texto do SQL nao diz o
# que a execucao faz: um SELECT que chama uma funcao que grava nao tem nenhuma palavra de escrita, e so o
# Postgres sabe que a funcao grava. Com o prefixo, quem recusa e o banco (25006), inclusive dentro de
# funcao SECURITY DEFINER, pg_net e pg_cron. Medido em 29/09/2026 pelo execute_sql do MCP: o prefixo vale
# para os comandos seguintes da mesma chamada, e o mesmo UPDATE sem ele roda (controle).
READ_ONLY_PREFIX = "SET TRANSACTION READ ONLY;\n"
# O que tira a chamada da transacao somente leitura, e por isso e negado a quem nao e a orquestradora.
# Medido em 29/09/2026: COMMIT e START TRANSACTION READ WRITE no meio da chamada escapam. Ligar o modo
# escrita por set_config('transaction_read_only', ...) passa por aqui (o nome esta entre aspas, e o texto
# entre aspas e ignorado), e quem recusa e o Postgres (25001, medido); a mencao sem aspas (SET ...) e negada.
# Leitura nao precisa de nenhum deles.
TXN_ESCAPE_RE = re.compile(
    r"(?:^|;)\s*(?:COMMIT|ROLLBACK|ABORT|END|BEGIN|START|PREPARE"
    r"|SET\s+(?:LOCAL\s+|SESSION\s+)?TRANSACTION|SET\s+SESSION\s+CHARACTERISTICS)\b"
    r"|\b(?:default_)?transaction_read_only\b",
    re.IGNORECASE,
)


def strip_read_only_prefix(sql: str) -> str:
    """A outra copia do gate (hook de usuario) pode ter prefixado antes: o prefixo nao se acumula."""
    while sql.startswith(READ_ONLY_PREFIX):
        sql = sql[len(READ_ONLY_PREFIX):]
    return sql


def escapes_read_only(sql: str) -> bool:
    return bool(TXN_ESCAPE_RE.search(strip_sql_comments(sql or "").strip()))


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
        if "project_id" not in tool_input and tool_action(tool) in MUTATING_TOOLS:
            return True  # branch_id tools: project unknown, fail-closed
        return tool_input.get("project_id") == PROJECT_REF
    return False


def tool_action(tool: str) -> str:
    return tool.rsplit("__", 1)[-1]


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
    fixed = os.environ.get("DB_GATE_QUEUE")
    if fixed:
        prs, _, jobs = fixed.partition(",")
        return int(prs or 0), int(jobs or 0)

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


def deny_reason(session_id: str, orch: str, cwd: str, action: str = "") -> str:
    who = f"a sessao orquestradora designada e {orch[:8]}" if orch else "NENHUMA sessao orquestradora esta designada"
    head = (f"SO A ORQUESTRADORA ALTERA ESTE PROJETO PELO MCP ({action})" if action
            else "SO A ORQUESTRADORA ESCREVE NO BANCO COMPARTILHADO")
    return (
        f"{head}. Esta sessao ({session_id[:8] or '?'}) NAO e a "
        f"orquestradora e roda {where(cwd)} ({cwd}); {who}. Prepare o pacote (o .sql, a verificacao) e mande para ela, que aplica "
        "e commita no mesmo passo. Em 25/09/2026 uma sessao que nao era a orquestradora aplicou 2 "
        "migrations em producao. Trocar a orquestradora e decisao do GP: "
        "scripts/lane-registry.sh orquestrador <session_id> \"<nota>\"."
    )


def read_only_escape_reason(session_id: str, orch: str, cwd: str) -> str:
    who = f"a sessao orquestradora designada e {orch[:8]}" if orch else "NENHUMA sessao orquestradora esta designada"
    return (
        f"LEITURA DE QUEM NAO E A ORQUESTRADORA RODA SOMENTE LEITURA. Esta sessao ({session_id[:8] or '?'}) "
        f"roda {where(cwd)} ({cwd}); {who}. A consulta tem controle de transacao (COMMIT, ROLLBACK, BEGIN, "
        "START, END, SET TRANSACTION) ou mexe em transaction_read_only, o que tiraria a chamada da transacao "
        "somente leitura. Leitura nao precisa disso: tire o controle de transacao, ou mande o pacote para a "
        "orquestradora."
    )


def decide(event: dict):
    if os.environ.get("DB_GATE_INJECT_ERROR") == "1":
        raise RuntimeError("erro injetado (DB_GATE_INJECT_ERROR=1)")
    tool = event.get("tool_name", "")
    tool_input = event.get("tool_input") or {}
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        cwd = event.get("cwd") or os.getcwd()
        what = main_write(cmd, cwd)
        if what:
            session_id = event.get("session_id") or ""
            orch = orchestrator_id()
            if not orch or session_id != orch:
                return "deny", main_deny_reason(session_id, orch, cwd, what)
        if not BASH_RISK_RE.search(cmd):
            return None, None
        if PROJECT_REF not in cmd and not repo_is_this(cwd):
            return None, None
        session_id = event.get("session_id") or ""
        orch = orchestrator_id()
        if not orch or session_id != orch:
            return "deny", bash_deny_reason(session_id, orch, cwd)
        return None, None
    gh_what = github_main_write(tool, tool_input)
    if gh_what:
        session_id = event.get("session_id") or ""
        orch = orchestrator_id()
        if not orch or session_id != orch:
            return "deny", main_deny_reason(session_id, orch, event.get("cwd") or os.getcwd(), gh_what)
        return None, None
    action = tool_action(tool)
    is_sql = action == "execute_sql"
    is_mutating = action in MUTATING_TOOLS
    cwd = event.get("cwd") or os.getcwd()
    if not (action == "apply_migration" or is_sql or is_mutating) or not targets_this_db(tool, tool_input, cwd):
        return None, None
    session_id = event.get("session_id") or ""
    orch = orchestrator_id()
    if is_sql and not is_write(tool_input.get("query", "")):
        if orch and session_id == orch:
            return None, None
        body = strip_read_only_prefix(tool_input.get("query") or "")
        if escapes_read_only(body):
            return "deny", read_only_escape_reason(session_id, orch, cwd)
        return "allow", ("leitura de quem nao e a orquestradora: roda numa transacao somente leitura",
                         {**tool_input, "query": READ_ONLY_PREFIX + body})

    if not orch or session_id != orch:
        return "deny", deny_reason(session_id, orch, cwd, action if is_mutating else "")

    if action in QUEUED_TOOLS:
        prs, jobs = queue_busy()
        if prs > 0 or jobs > 0:
            return "ask", (
                f"BANCO OCUPADO: {prs} PR(s) aberta(s) e {jobs} job(s) de banco em voo. "
                f"{action} atinge o banco COMPARTILHADO na hora, e toda branch sem o .sql passa "
                "a acusar drift (PROD-AHEAD), inclusive a main. Fila de PRs vazia NAO e banco livre: "
                "mergear zera a fila e dispara CI Validate/Schema Invariants na main. Espere os dois "
                "numeros zerarem, ou confirme que a ordem ja foi combinada (#2340)."
            )
    return None, None


WRITE_TOOL_ACTIONS = ("apply_migration", "execute_sql") + MUTATING_TOOLS + GITHUB_MAIN_TOOLS


def bash_is_write_path(cmd: str) -> bool:
    return bool(BASH_RISK_RE.search(cmd) or GH_MERGE_RE.search(cmd) or GH_GRAPHQL_MERGE_RE.search(cmd)
                or GH_ADMIN_RE.search(cmd) or GIT_PUSH_RE.search(cmd))


def is_write_path(event: dict) -> bool:
    tool = event.get("tool_name", "") or ""
    if tool == "Bash":
        return bash_is_write_path((event.get("tool_input") or {}).get("command") or "")
    return tool_action(tool) in WRITE_TOOL_ACTIONS


def raw_is_write_path(raw: str) -> bool:
    return any(name in raw for name in WRITE_TOOL_ACTIONS) or bash_is_write_path(raw)


def gate_failed(write: bool, what: str) -> int:
    if write:
        print(f"DB-WRITE-GATE FALHOU NUM CAMINHO DE ESCRITA ({what}): a chamada foi BLOQUEADA por seguranca "
              "(falha fechada). Rode de novo; se repetir, o gate tem defeito e quem conserta e a orquestradora.",
              file=sys.stderr)
        return 2
    print(f"AVISO DB-WRITE-GATE: o gate falhou ({what}) numa chamada que nao e escrita; ela SEGUE, mas o gate "
          "precisa de conserto.", file=sys.stderr)
    return 0


def main():
    raw = sys.stdin.read()
    try:
        event = json.loads(raw)
        if not isinstance(event, dict):
            raise ValueError("entrada nao e um objeto JSON")
    except Exception as e:
        return gate_failed(raw_is_write_path(raw), f"entrada ilegivel: {type(e).__name__}")
    try:
        decision, reason = decide(event)
    except Exception as e:
        try:
            write = is_write_path(event)
        except Exception:
            write = raw_is_write_path(raw)
        return gate_failed(write, f"{type(e).__name__}: {e}")
    if decision:
        out = {"hookEventName": "PreToolUse", "permissionDecision": decision}
        # Quem devolve (motivo, entrada nova) reescreve a chamada: updatedInput SUBSTITUI a entrada inteira,
        # por isso leva todos os campos originais.
        if isinstance(reason, tuple):
            reason, out["updatedInput"] = reason
        out["permissionDecisionReason"] = reason
        print(json.dumps({"hookSpecificOutput": out}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
