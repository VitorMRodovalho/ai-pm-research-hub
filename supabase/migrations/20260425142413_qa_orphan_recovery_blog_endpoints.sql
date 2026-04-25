-- Track Q-A Batch B — orphan recovery: blog public endpoints (4 fns)
--
-- Captures live bodies as-of 2026-04-25 for blog public-facing reader/like
-- surface (4 SECDEF functions). All four are reachable via Astro pages and
-- public APIs (post listing + per-post like state + view increment + toggle).
-- Bodies preserved verbatim from `pg_get_functiondef` — no behavior change.
--
-- Notes:
-- - All four are SECURITY DEFINER (own/touch blog_likes + blog_posts denorm
--   counters). Guarded by auth.uid()-derived members lookup; anon visitors
--   read but cannot like/toggle.
-- - increment_blog_view is fire-and-forget (called from page render).
-- - get_blog_likes_batch is the batch reader used by listing pages.
-- - toggle_blog_like both mutates blog_likes AND syncs the denorm counter on
--   blog_posts; preserved here as-is.

CREATE OR REPLACE FUNCTION public.get_blog_likes_batch(p_post_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result jsonb := '{}'::jsonb;
  v_post record;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();

  FOR v_post IN
    SELECT bp.id, bp.like_count,
      CASE WHEN v_member_id IS NOT NULL
        THEN EXISTS (SELECT 1 FROM blog_likes bl WHERE bl.post_id = bp.id AND bl.member_id = v_member_id)
        ELSE false END as liked
    FROM blog_posts bp
    WHERE bp.id = ANY(p_post_ids)
  LOOP
    v_result := v_result || jsonb_build_object(
      v_post.id::text, jsonb_build_object('liked', v_post.liked, 'like_count', coalesce(v_post.like_count, 0))
    );
  END LOOP;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_blog_post_likes(p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_liked boolean := false;
  v_count integer;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();

  IF v_member_id IS NOT NULL THEN
    v_liked := EXISTS (SELECT 1 FROM blog_likes WHERE post_id = p_post_id AND member_id = v_member_id);
  END IF;

  SELECT like_count INTO v_count FROM blog_posts WHERE id = p_post_id;

  RETURN jsonb_build_object(
    'liked', v_liked,
    'like_count', coalesce(v_count, 0)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.increment_blog_view(p_slug text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE blog_posts SET view_count = view_count + 1
  WHERE slug = p_slug AND status = 'published';
END;
$function$;

CREATE OR REPLACE FUNCTION public.toggle_blog_like(p_post_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_existed boolean;
  v_new_count integer;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  -- Check if already liked
  IF EXISTS (SELECT 1 FROM blog_likes WHERE post_id = p_post_id AND member_id = v_member_id) THEN
    -- Unlike
    DELETE FROM blog_likes WHERE post_id = p_post_id AND member_id = v_member_id;
    v_existed := true;
  ELSE
    -- Like
    INSERT INTO blog_likes (post_id, member_id) VALUES (p_post_id, v_member_id);
    v_existed := false;
  END IF;

  -- Update denormalized counter
  SELECT count(*) INTO v_new_count FROM blog_likes WHERE post_id = p_post_id;
  UPDATE blog_posts SET like_count = v_new_count WHERE id = p_post_id;

  RETURN jsonb_build_object(
    'liked', NOT v_existed,
    'like_count', v_new_count
  );
END;
$function$;
