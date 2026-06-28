-- comms_scheduled_posts: widen media_type to admit LinkedIn post types.
--
-- The queue was Instagram-only (media_type in IMAGE/CAROUSEL/REELS/STORIES). The
-- publish-scheduled dispatcher now routes by channel (instagram -> publish-instagram,
-- linkedin -> publish-linkedin), so LinkedIn rows (TEXT / ARTICLE / VIDEO / IMAGE)
-- must satisfy the check too. The `channel` column has no check constraint, so only
-- media_type needs widening. Existing IG values are preserved.
--
-- Apply order (GC-097): apply this via apply_migration (remote) FIRST, then deploy
-- publish-linkedin + dry-run, then enqueue linkedin rows. `supabase db push` is
-- unusable here (squashed history) — use apply_migration + migration repair.

begin;

alter table public.comms_scheduled_posts
  drop constraint if exists comms_scheduled_posts_media_type_check;

alter table public.comms_scheduled_posts
  add constraint comms_scheduled_posts_media_type_check
  check (media_type in (
    -- Instagram
    'IMAGE', 'CAROUSEL', 'REELS', 'STORIES',
    -- LinkedIn (organization share)
    'TEXT', 'VIDEO', 'ARTICLE', 'LINK'
  ));

comment on constraint comms_scheduled_posts_media_type_check
  on public.comms_scheduled_posts is
  'Multi-channel post types: IG (IMAGE/CAROUSEL/REELS/STORIES) + LinkedIn (TEXT/VIDEO/ARTICLE/LINK). Behaviour is driven by payload in the per-channel publish EF; this column gates the queue + carries the human-facing type.';

commit;
