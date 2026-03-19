# Claude Code — Project Rules

## GC-097: Pre-Commit Validation (MANDATORY)

Before committing ANY change, verify:

### If you touched SQL/RPC:
1. Check FK constraints: `SELECT constraint_name, pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'TABLE'::regclass AND contype = 'f';`
2. Verify `auth.uid()` vs `members.id` — events.created_by FK → auth.users(id), NOT members(id)
3. Test the RPC with real data via MCP execute_sql
4. Check for column name mismatches: members uses `name` (not `full_name`), `credly_url` (not `credly_username`), publication_submissions uses `submission_date` (not `submitted_at`)
5. Check array types: members.designations is `text[]` (not jsonb), members.cycles is `text[]` (not jsonb). Use `&&` not `?|`, use `array_length()` not `jsonb_array_length()`

### If you touched i18n:
1. Every new key MUST exist in ALL 3 dictionaries (pt-BR.ts, en-US.ts, es-LATAM.ts)
2. Grep for raw keys in components: any `t('key.name')` must have a corresponding entry
3. Check the key name matches exactly (e.g., `modal.advanced` vs `modal.advancedFields`)

### If you created/modified routes:
1. If a PT-BR page exists, /en/ and /es/ redirect pages must also exist
2. Check: `ls src/pages/en/X.astro src/pages/es/X.astro`

### If you modified an RPC signature:
1. Use DROP + CREATE (not CREATE OR REPLACE) when changing parameter types or count
2. Check for overloaded functions: `SELECT count(*) FROM pg_proc WHERE proname = 'X' AND pronamespace = 'public'::regnamespace`
3. After applying to DB, ALWAYS run: `NOTIFY pgrst, 'reload schema'`
4. Mark migration as applied: `supabase migration repair --status applied TIMESTAMP`

### ALWAYS:
1. Run `npx astro build` — must pass with 0 new errors
2. Read the HAR file if the user provides one — the PostgREST error body is the truth
