-- Widen comms_scheduled_posts.media_type check for multi-channel (LinkedIn org share).
-- IG types kept; LinkedIn types added (TEXT/VIDEO/ARTICLE/LINK). channel has no check.
alter table public.comms_scheduled_posts
  drop constraint if exists comms_scheduled_posts_media_type_check;

alter table public.comms_scheduled_posts
  add constraint comms_scheduled_posts_media_type_check
  check (media_type in (
    'IMAGE', 'CAROUSEL', 'REELS', 'STORIES',          -- Instagram
    'TEXT', 'VIDEO', 'ARTICLE', 'LINK'                -- LinkedIn (organization share)
  ));
