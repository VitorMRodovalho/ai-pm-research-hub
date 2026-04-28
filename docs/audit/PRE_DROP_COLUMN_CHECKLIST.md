# Pre-DROP-COLUMN Audit Checklist

Issue #81 #3 closure. Codifies the methodology that should have caught the
gaps in #79/#80 (members.tribe_id Phase 3d drop left 5 RPCs + 7 worker
references stale; list_boards silently broken for 6 days).

## When to use

Run the FULL checklist before any migration that contains:
- `ALTER TABLE ... DROP COLUMN`
- `DROP TABLE`
- `RENAME COLUMN` (semantically equivalent for callers)
- `RENAME TABLE`

Skip for purely additive changes (ADD COLUMN, ADD CONSTRAINT) — those don't
break callers.

## Why "UPDATE SET" alone is insufficient

The Phase 3e Batch B audit hit only `UPDATE ... SET` references and missed:
- `SELECT col FROM table` and `SELECT INTO col`
- `WHERE col = ...` predicates
- `ORDER BY col` clauses
- Embedded `.select()` projections in TS callers
- RLS policies referencing the column
- Triggers reading `NEW.col` / `OLD.col`
- Views in `pg_views.definition`

Each pattern needs its own scan. The checklist below is the union.

---

## Checklist (run all 8 dimensions)

### 1. pg_proc bodies — function source code

```sql
SELECT proname, pg_get_function_arguments(oid)
FROM pg_proc
WHERE prosrc ~ '\m<table>\.<column>\M'
  AND pronamespace = 'public'::regnamespace;
```

Word-boundary regex (`\m`/`\M`) avoids substring false-positives.

**Optional:** strip line + block comments first (see
`check_code_schema_drift()` v3) — `-- ADR doc references` will otherwise
appear as false positives.

### 2. pg_views — view definitions

```sql
SELECT viewname FROM pg_views
WHERE schemaname='public'
  AND definition ~ '\m<table>\.<column>\M';
```

Views with stale references throw `relation does not exist` at query time.

### 3. pg_policy — RLS policies

```sql
SELECT
  pol.polname,
  c.relname AS table_name,
  pg_get_expr(pol.polqual, pol.polrelid) AS qual,
  pg_get_expr(pol.polwithcheck, pol.polrelid) AS with_check
FROM pg_policy pol
JOIN pg_class c ON c.oid = pol.polrelid
WHERE coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') ~ '\m<table>\.<column>\M'
   OR coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') ~ '\m<table>\.<column>\M';
```

A stale policy makes the entire row inaccessible (or worse, opens a hole if
the predicate silently became `false`).

### 4. Triggers (NEW.col / OLD.col reads)

```sql
SELECT proname FROM pg_proc p
JOIN pg_trigger t ON t.tgfoid = p.oid
WHERE p.prosrc ~ '\m(NEW|OLD)\.<column>\M';
```

Trigger functions silently no-op or crash on the row's UPDATE/DELETE path.

### 5. TypeScript / edge functions

```bash
# Supabase JS client patterns
grep -rE "\.select\(.*['\"]<column>['\"]" supabase/functions/ src/
grep -rE "\.from\(['\"]<table>['\"]\)" supabase/functions/ src/ | grep "<column>"
grep -rE "\.eq\(['\"]<column>['\"]" supabase/functions/ src/
grep -rE "!inner\(<column>" supabase/functions/ src/
```

Includes embedded selects, foreign-table joins, equality filters.

### 6. SQL strings in code (raw queries)

```bash
grep -rE "<table>\.<column>|FROM <table>.*<column>" supabase/functions/ src/
```

Catches dynamic SQL string concatenation.

### 7. Cron jobs

```sql
SELECT jobid, jobname, command FROM cron.job
WHERE command ~ '\m<column>\M' OR command ~ '\m<table>\.<column>\M';
```

Cron-driven SQL silently fails — no user surface, hidden until log review.

### 8. RUNBOOK and ADR docs

```bash
grep -rE "<table>\.<column>" docs/ CLAUDE.md
```

Stale doc isn't a runtime bug but lures future engineers into wrong models.
At minimum, replace with `(dropped in <ADR>; derive via …)` comment.

---

## Automation

### Live drift detector (post-deploy)

`public.check_code_schema_drift()` (Issue #81 #4) wraps dimensions 1-3 above.
Run after any DROP COLUMN deploy:

```sql
SELECT * FROM public.check_code_schema_drift();
```

Returns `(object_type, object_name, schema_name, pattern_matched, …)` for
human triage. Strips comments. Auto-filters via `information_schema`.

### Pre-commit drift gate (TS code)

The pre-commit hook (`.githooks/pre-commit` Issue #81 #6) refuses commits
that introduce `const { data } = await sb.from(...)` without destructuring
`error`. That pattern was the root cause of the 6-day silent fail in #80.

---

## Process integration

When creating a migration with `DROP COLUMN`:

1. **Header comment** must include:
   ```sql
   -- DROP COLUMN <table>.<column>
   -- Pre-drop audit: ran PRE_DROP_COLUMN_CHECKLIST.md (8 dimensions). Findings:
   --   - pg_proc:  N functions
   --   - pg_views: M views
   --   - pg_policy: P policies
   --   - TS:        Q files
   --   - cron:      R jobs
   -- All updated in companion migrations / commits referenced below.
   ```

2. **PR description** must list all updated callers with commit hashes.

3. **Post-deploy verification** must include
   `SELECT count(*) FROM public.check_code_schema_drift()` returning 0
   before the migration is considered "merged".

---

## History

- 2026-04-21 #79: 5 RPCs broke (`update_event_instance` family) when
  `events.tribe_id` was dropped Phase 3e. Audit only caught `UPDATE SET`.
- 2026-04-21 #80: `list_boards` silently returned "No board found" for 6
  days because `project_boards.tribe_id` was dropped in Phase 3d. Worker
  destructured `data` without `error`, masking the real PostgREST 400.
- 2026-04-28 #81: this checklist + drift detector + silent-error gate
  ratified to prevent recurrence.

---

Assisted-By: Claude (Anthropic)
