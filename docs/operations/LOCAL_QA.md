# Local QA Workflow — Núcleo IA & GP

**Owner:** Vitor Maia Rodovalho (GP)
**Status:** Adopted (p202, 2026-05-19) — issue #164 close
**Audit ref:** `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #39

---

## TL;DR

- **Primary QA workflow = remote-linked.** Run smoke / contract tests against the live Supabase project (`ldrfrvwhxsmgaabwmaik`) via env vars `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`. This is the default expected path and what CI uses.
- **Local Supabase stack is OPTIONAL.** Requires a one-time bootstrap (`supabase db pull --linked`) to capture the schema before `supabase start` works. Useful for Edge Function debug with `supabase functions serve`.
- Without remote env vars, DB-aware tests **skip silently** (the offline baseline still passes). For CI to run the DB-aware suite, configure the two secrets in GitHub repo settings.

---

## Workflow A — Remote-linked (recommended default)

This is the path used by every parallel-agent session in p201/p202 and by CI.

### Prerequisites

- Repo cloned + `npm install` ran.
- `.env.local` (or shell env) populated with at least:
  ```bash
  export SUPABASE_URL=https://ldrfrvwhxsmgaabwmaik.supabase.co
  export SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi…  # ask GP — never commit
  ```
- For Cloudflare-side debugging: `wrangler` CLI authenticated against the `vitormr.dev` zone.

### Day-to-day commands

```bash
# Run unit + contract tests against remote DB
npm test

# Build + smoke routes
npm run build
npm run smoke:routes

# Apply migrations directly via Supabase MCP (when CLI push is blocked by drift)
# In an MCP-enabled client: mcp__supabase__apply_migration

# Mark a migration as applied (after manual apply via MCP or dashboard)
supabase migration repair --status applied <timestamp>

# Reload PostgREST schema cache (after RPC signature changes)
# In MCP: execute_sql with NOTIFY pgrst, 'reload schema';
```

### When to use this path

- Authoring new RPCs, RLS policies, migrations.
- Running contract tests + DB-aware unit tests.
- Reproducing production-only bugs.
- Verifying Edge Function behaviour against real auth/RLS.

### Limitations

- Edge Function debugging requires `supabase functions serve` which needs the local stack (Workflow B). For most QA, deploy to the linked project (`supabase functions deploy <name>`) and read logs.
- No offline development — needs internet + valid service-role key.

---

## Workflow B — Local Supabase stack (optional)

Useful when you want to test an Edge Function locally before deploying, or
when network is unreliable. Requires more setup.

### Prerequisites

1. Docker installed + running.
2. Supabase CLI installed (`brew install supabase/tap/supabase` or equivalent).
3. Authenticated to Supabase: `supabase login`.
4. Linked to the project: `supabase link --project-ref ldrfrvwhxsmgaabwmaik`.
5. **Deno installed** if you want to use `supabase functions serve` (Edge Function local debug).
   ```bash
   curl -fsSL https://deno.land/install.sh | sh
   export PATH="$HOME/.deno/bin:$PATH"   # persist in your shell rc
   deno --version                         # verify
   ```

### One-time bootstrap (critical step)

Before `supabase start` can succeed, the local stack must have a baseline schema. The repo's `supabase/migrations/` folder does **not** contain a "create members table" migration — the schema was set up directly in production before the migration history was repo-tracked. You must pull it from the linked project first:

```bash
# Pull the current schema from the linked project into a new local baseline migration
supabase db pull --linked
# This creates a file in supabase/migrations/ named like
# 20260101000000_remote_schema.sql with the full schema.

# Optionally inspect the generated file before committing:
git diff supabase/migrations/

# If satisfied, commit it (one-time addition to the repo):
# (do not commit if you only want a local-only bootstrap)
```

If you don't want to commit the pulled schema (because the production schema may include local-policy edits that should stay environment-specific), keep the pulled migration locally (gitignored) and re-pull whenever you destroy your local stack.

### Daily commands

```bash
# Start the local stack (Docker)
supabase start

# Run migrations in order (00000000 deprecated marker → schema → after_schema RPCs → other)
supabase db reset   # destructive: wipes local data + reapplies migrations from zero

# Serve an Edge Function locally (e.g., nucleo-mcp)
supabase functions serve nucleo-mcp --no-verify-jwt --env-file ./supabase/.env.local

# Open Supabase Studio locally
# http://localhost:54323

# Stop the stack
supabase stop
```

### Common drift troubleshooting

#### `supabase db push` blocked by remote-only migration history

Symptom: `supabase db push` reports migrations in the remote `schema_migrations` table that don't exist as files in `supabase/migrations/`.

This happens when DDL was applied directly via `mcp__supabase__apply_migration` (the canonical path post-Track Q-C, see `.claude/rules/database.md`). Resolution:

```bash
# 1. List orphan migrations recorded in remote schema_migrations but missing from FS:
# (use MCP execute_sql or psql against linked project)
SELECT version FROM supabase_migrations.schema_migrations
WHERE version NOT IN ('list of FS timestamps');

# 2. For each missing file, recover from the linked project's history:
# Option a) Capture body via mcp__supabase__execute_sql:
#   SELECT statements FROM supabase_migrations.schema_migrations WHERE version='<ts>';
# Option b) Re-derive from pg_get_functiondef if it was an RPC change.

# 3. Write the file locally:
# supabase/migrations/<ts>_<descriptive_name>.sql

# 4. Mark as applied (since production already has it):
supabase migration repair --status applied <ts>

# Verify FS count matches remote count:
ls supabase/migrations/*.sql | wc -l
# vs (via MCP execute_sql):
# SELECT count(*) FROM supabase_migrations.schema_migrations;
```

This pattern was used multiple times during p199-b/p199-c recovery — see `feedback_drop_function_audit_wrappers.md` and `handoff_p200_post_p199_close.md` in memory.

#### `supabase start` ERROR: type does not exist

If you see `ERROR: type "public.X" does not exist (SQLSTATE 42704)` from a migration, it means the migration references a table/type that hasn't been created yet by an earlier migration. Two paths:

1. **Reorder** (modify history — risky): change the migration's timestamp prefix to a later value. Only do this if production hasn't applied the migration yet.
2. **Split** (preferred — additive): move the failing statements to a new migration with a later timestamp. The original migration becomes a marker. This is what p202 did for `00000000_baseline_rpcs.sql` → `20260723000000_baseline_rpcs_after_schema.sql` (issue #164).

---

## When to use which workflow

| Task | Use |
|---|---|
| Author new RPC / migration | Workflow A (remote-linked) |
| Run contract tests | Workflow A |
| Run smoke routes | Workflow A |
| Reproduce production-only bug | Workflow A |
| Debug Edge Function logic locally | Workflow B (needs Deno + db pull) |
| Test against destroyable data | Workflow B |
| CI | Workflow A (configure secrets in repo settings) |

---

## CI configuration

DB-aware tests require these GitHub repo secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

CI workflow `.github/workflows/ci.yml` references them as `${{ secrets.SUPABASE_URL }}` + `${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}` (set up in p174). Without these, the DB-aware suite skips silently — the offline baseline still passes (1449/0/46 last pinned).

A sentinel test in `tests/contracts/rpc-migration-coverage.test.mjs` hard-fails CI when env is absent (added p177 to prevent silent skip drift).

---

## See also

- `.claude/rules/deploy.md` — pre-deploy checklist + canonical test baselines
- `.claude/rules/database.md` — DDL via `apply_migration` (never `execute_sql`)
- `.claude/rules/mcp.md` — MCP pre-deploy + smoke (incl. matrix drift gate)
- `docs/RUNBOOK.md` — broader operations runbook
- `docs/audit/P162_GAP_OPPORTUNITY_LOG.md` item #39 — original gap report
- Issue #164 — adoption decision (path C: split baseline + remote-linked default)
