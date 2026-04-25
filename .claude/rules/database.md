---
description: Rules for SQL migrations, RPCs, and database changes
globs: supabase/**/*.sql, src/lib/database.gen.ts
---

# Database Rules

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
- DDL via `apply_migration` auto-creates the migration file in `supabase/migrations/`. Always pair with `supabase migration repair --status applied <timestamp>` so local CLI state and remote agree.
- Followed by `NOTIFY pgrst, 'reload schema'` if the change affects PostgREST surface (RPC signatures, view shapes, policies on exposed tables).
- The contract test `tests/contracts/rpc-migration-coverage.test.mjs` will fail in CI when a new function appears in `pg_proc` without a `CREATE FUNCTION` block in any migration — catches accidental DDL via the wrong tool.

## LGPD Compliance (GC-162)
- All new tables MUST have RLS enabled
- No anon access to PII (members.email, phone, pmi_id, auth_id)
- Ghost users (authenticated without member record) get NOTHING from PII tables
- Public data via SECURITY DEFINER RPCs only (get_public_leaderboard, get_public_platform_stats)
