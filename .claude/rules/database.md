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

## LGPD Compliance (GC-162)
- All new tables MUST have RLS enabled
- No anon access to PII (members.email, phone, pmi_id, auth_id)
- Ghost users (authenticated without member record) get NOTHING from PII tables
- Public data via SECURITY DEFINER RPCs only (get_public_leaderboard, get_public_platform_stats)
