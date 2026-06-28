# publish-linkedin — deploy steps

Order matters. Apply the DB change via `apply_migration` (NOT `db push` — squashed history),
then deploy the function, then dry-run, then enqueue.

## 1. DB: widen `comms_scheduled_posts.media_type` check (apply_migration)

The scheduler queue was Instagram-only (`media_type in IMAGE/CAROUSEL/REELS/STORIES`).
LinkedIn rows (TEXT/VIDEO/ARTICLE/IMAGE) must satisfy the check too. `channel` has no check.

This is NOT committed under `supabase/migrations/` here on purpose: the ADR-0097 orphan-local
drift gate (`tests/contracts/rpc-migration-coverage.test.mjs`) fails any migration file not yet
applied to the remote DB. Apply via MCP first, then write the local file in the SAME change and
`migration repair` (GC-097 ritual, `.claude/rules/database.md`):

```sql
-- 20260805000274_comms_scheduled_posts_multichannel_media_types.sql
alter table public.comms_scheduled_posts
  drop constraint if exists comms_scheduled_posts_media_type_check;

alter table public.comms_scheduled_posts
  add constraint comms_scheduled_posts_media_type_check
  check (media_type in (
    'IMAGE', 'CAROUSEL', 'REELS', 'STORIES',          -- Instagram
    'TEXT', 'VIDEO', 'ARTICLE', 'LINK'                -- LinkedIn (organization share)
  ));
```

Steps: `apply_migration` → `Write` the file under `supabase/migrations/<ts>_*.sql` (ts >
current head) → `supabase migration repair --status applied <ts>`. NOTIFY not needed
(no PostgREST surface change).

> ⚠️ Pick the timestamp from the LIVE head, not `ls | tail`. As of 2026-06-28 the prod
> `schema_migrations` already tracks `20260805000274/275/276` with no committed files
> (uncommitted drift — see the hub drift issue), so the repo's apparent head (`...273`)
> is stale. Query `SELECT version FROM supabase_migrations.schema_migrations ORDER BY
> version DESC LIMIT 1` and use a greater value (≥ `...277`). Do NOT reuse `274`.

## 2. Secret + scope (owner action)

- Add `w_organization_social` to the LinkedIn app + 3-legged re-auth; store the new token via
  `/admin/comms` (`admin_manage_comms_channel`). The `linkedin` row in `comms_channel_config`
  must carry `organization_urn` (already set for metrics).
- Manual-invoke secret: reuses `INSTAGRAM_PUBLISH_SECRET` (shared comms-publish secret) OR a
  service-role token (the cron path).

## 3. Deploy the function

```bash
supabase functions deploy publish-linkedin --no-verify-jwt
```

## 4. Dry-run, then first real post

```bash
# dry_run validates config + payload, no post
curl -X POST "$SUPABASE_URL/functions/v1/publish-linkedin" \
  -H "Authorization: Bearer $INSTAGRAM_PUBLISH_SECRET" -H 'Content-Type: application/json' \
  -d '{"dry_run":true,"post_type":"TEXT","text":"hello"}'

# first real post (e.g. webinar 30/jun recap) — TEXT with a clickable URL in the body
```

## 5. Enqueue scheduled LinkedIn posts

Insert into `comms_scheduled_posts` with `channel='linkedin'`, a valid `media_type`
(TEXT/IMAGE/VIDEO/ARTICLE), `scheduled_at`, and `payload` = the publish-linkedin body. The
`publish-scheduled` cron routes by `channel`.
