---
description: Rules for SQL migrations, RPCs, and database changes
globs: supabase/**/*.sql, src/lib/database.gen.ts
---

---
description: Database rules — GC-097 pre-commit validation, RPC signature changes, DDL via apply_migration (not execute_sql), LGPD/RLS, V4 authority audit
paths:
  - "supabase/migrations/**"
  - "supabase/functions/**"
  - "**/*.sql"
---

# Database Rules

> Path-scoped (2026-05-30): loads only when SQL/migration/EF files are in context. If it loads on every session
> anyway, the harness ignores `paths:` — verify with `/memory`. (See `reference_process_fix_and_context_hygiene_2026_05_30`.)

## Pre-Commit Validation (GC-097)
1. Check FK constraints: `SELECT constraint_name, pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'TABLE'::regclass AND contype = 'f';`
2. Verify `auth.uid()` vs `members.id` — events.created_by FK → auth.users(id), NOT members(id)
3. Test the RPC with real data via MCP execute_sql
4. Column names: members uses `name` (not `full_name`), `credly_url` (not `credly_username`)
5. Array types: members.designations is `text[]` (not jsonb). Use `&&` not `?|`

## RPC Signature Changes
1. Use DROP + CREATE (not CREATE OR REPLACE) when changing parameter types or count
2. Check overloaded functions: `SELECT count(*) FROM pg_proc WHERE proname = 'X'`
3. After applying to DB: `NOTIFY pgrst, 'reload schema'`
4. Mark migration as applied: `supabase migration repair --status applied TIMESTAMP`

## DDL must go through `apply_migration` — NEVER `execute_sql`
**Track Q-C (p50, ratified 2026-04-25):** the live `import_vep_applications` and `exec_portfolio_health` bodies drifted from every migration file because earlier sessions ran `CREATE OR REPLACE FUNCTION` via `execute_sql` (or the dashboard SQL editor). 92 functions ended up as orphans with no migration capture (see `docs/audit/RPC_BODY_DRIFT_AUDIT_P50.md`).

Rule:
- `mcp__claude_ai_Supabase__execute_sql` is for **read-only or DML** (SELECT, INSERT/UPDATE/DELETE on data, NOTIFY, EXPLAIN). Test calls during validation are fine.
- `mcp__claude_ai_Supabase__apply_migration` is for **all DDL** (CREATE/ALTER/DROP on tables, functions, types, policies, triggers, indexes, views; GRANT/REVOKE; COMMENT ON). Including `CREATE OR REPLACE FUNCTION`.
- **`apply_migration` via MCP applies DDL to remote DB only.** It does NOT (a) write a local migration file, NOR (b) register the version in `supabase_migrations.schema_migrations`. Caught 2x in p86 (Wave 5d shipping). Manual sync required:
  1. After `apply_migration` succeeds, `Write` a local file at `supabase/migrations/<timestamp>_<name>.sql` with the same SQL (timestamp = next-greater than current head; `SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 1` to find current).
  2. Run `supabase migration repair --status applied <timestamp>` to register in CLI tracking + sync to `schema_migrations` table.
  3. `NOTIFY pgrst, 'reload schema'` via `execute_sql` if the change affects PostgREST surface (RPC signatures, view shapes, policies on exposed tables).
- Without the manual sync, `tests/contracts/rpc-migration-coverage.test.mjs` will fail in CI when a new function appears in `pg_proc` without a `CREATE FUNCTION` block in any migration — catches accidental DDL via the wrong tool **and** the apply_migration MCP gap.
- **Contract test CI gate (p174 sediment)**: the Q-C orphan check requires `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` env vars; without them tests SKIP silently (offline baseline check still passes). Confirmed fix: `.github/workflows/ci.yml` `Run Unit Tests` step now uses `${{ secrets.SUPABASE_URL }}` + `${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}` (p174, 2026-05-17). Without those secrets configured in GH repo settings, the gate still silently skips — verify periodically that CI is actually running the DB-aware tests, not just the offline baseline.
- **Phase C body-hash drift gate (p175 extension)**: orphan check alone misses the case where a function IS captured by SOME migration but the live body has since diverged (the drift class that motivated p52/p174). Phase C compares `md5(regexp_replace(prosrc, '\s+', ' ', 'g'))` between live (via `_audit_list_public_function_bodies()` RPC) and the latest CREATE FUNCTION capture per `(name, normalized_args)` key. Baseline allowlist of currently-drifted keys lives at `docs/audit/RPC_BODY_DRIFT_ALLOWLIST_P175.txt` (225 entries at p175). Tests ratchet DOWN as drift is recovered via apply_migration. Shared parser at `tests/helpers/rpc-body-drift-parser.mjs` (consumed by both the test and `scripts/audit-rpc-body-drift.mjs`); SQL-side normalization must stay byte-equivalent to the helper's `normalizeBody()` — break it and EVERY function appears drifted.

## LGPD Compliance (GC-162)
- All new tables MUST have RLS enabled
- No anon access to PII (members.email, phone, pmi_id, auth_id)
- Ghost users (authenticated without member record) get NOTHING from PII tables
- Public data via SECURITY DEFINER RPCs only (get_public_leaderboard, get_public_platform_stats)

## V4 Authority audit — before proposing seed expansion
**Sediment p122e:** auditorias mecânicas de `engagement_kind_permissions` × actions produzem false positives recorrentes porque V4 tem três caminhos paralelos de autoridade (combos seedados + designation-based gates + RPC inline scoping). Antes de declarar gap ou propor `INSERT INTO engagement_kind_permissions ...`, executar o **procedimento de 4 etapas** em `docs/reference/V4_AUTHORITY_MODEL.md` (matriz capability→path + checklist).

Anti-pattern documentado: "seed expansion como atalho" em actions destrutivas (`manage_member`, `manage_platform`) cria privilege escalation que viola invariante "member lifecycle = GP-only" (LGPD Art. 18).
