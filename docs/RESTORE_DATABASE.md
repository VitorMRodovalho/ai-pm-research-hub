# Database Restore Procedure

## When to use
- Accidental data deletion
- Supabase incident
- Migration rollback needed

## Steps

### 1. Download backup
- Go to: GitHub > Actions > Weekly Database Backup > latest successful run
- Download the artifact (db-backup-YYYYMMDD_HHMMSS.zip)
- Unzip → backup_YYYYMMDD_HHMMSS.sql.gz
- Decompress: `gunzip backup_YYYYMMDD_HHMMSS.sql.gz`

### 2. Review before restoring
- Open the .sql file and verify it contains expected tables
- Check the timestamp matches the desired restore point

### 3. Restore to Supabase
**⚠️ WARNING: This will DROP and recreate all public schema objects**

```bash
# Option A: Via psql (direct connection)
psql "$SUPABASE_DB_URL" < backup_YYYYMMDD_HHMMSS.sql

# Option B: Via Supabase SQL Editor
# Copy sections of the .sql file and execute in order:
# 1. DROP + CREATE tables
# 2. INSERT data
# 3. CREATE views + functions
```

### 4. Verify
- Check member count: `SELECT COUNT(*) FROM members;`
- Check gamification: `SELECT COUNT(*) FROM gamification_points;`
- Check recent data: `SELECT MAX(updated_at) FROM members;`

### 5. Post-restore
- Clear any application caches
- Verify the site loads correctly
- Check Edge Functions still work (Credly sync, etc.)

## What is backed up
All `public` schema tables, views, functions, triggers, RLS policies, indexes.

## What is NOT backed up
| Schema | Why excluded |
|--------|-------------|
| auth | Managed by Supabase Auth — contains passwords, tokens. Restoring would break auth. |
| storage | Managed by Supabase Storage — files in buckets. Not in pg_dump scope. |
| supabase_functions | Edge Function metadata — managed by Supabase. |
| extensions | PostgreSQL extensions — recreated by Supabase. |
| graphql / graphql_public | GraphQL introspection — auto-generated. |
| realtime | Realtime subscriptions — transient. |
| pgsodium / vault | Encryption keys — managed by Supabase. |
| supabase_migrations | Migration history — in repo, not needed in dump. |

## Schedule
- Weekly: Sunday 23:00 UTC (20:00 BRT)
- Retention: 8 most recent backups (~2 months)
- Location: GitHub Actions artifacts
