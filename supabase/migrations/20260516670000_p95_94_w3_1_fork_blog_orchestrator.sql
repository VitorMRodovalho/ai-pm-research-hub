-- p95 #94 W3.1 — fork_idea_to_channel auto-scaffold blog_posts draft
-- W3 multi-channel orchestrator (subset 3.1: blog channel only).
-- W3.2 (newsletter campaign_template) + W3.3 (comms_media_items canva brief) deferred.
--
-- Bonus fixes bundled (caught during W3.1 smoke):
-- - W2 missing themes column on publication_ideas (param p_themes was declared on propose but column never added)
-- - propose_publication_idea signature change (add p_themes param + persist into INSERT)
--
-- When fork_idea_to_channel(channel='blog'|'blog_post') is called for stage IN (approved, published):
--   - Create blog_posts draft (status='draft', category='deep-dive') with source_idea_id linked
--   - Title/excerpt jsonb i18n with pt-BR key (idea title/summary)
--   - Tags from idea.themes
--   - Slug: ASCII-folded + dashed + collision-disambiguated via idea_id suffix
--   - Idempotent: returns existing if a blog_post already exists for this source_idea_id
-- Other channels: fork intent recorded only (no row creation in W3.1)
--
-- Rollback:
--   ALTER TABLE public.publication_ideas DROP COLUMN IF EXISTS themes;
--   DROP FUNCTION IF EXISTS public.propose_publication_idea(text,text,text,uuid,integer,uuid,uuid[],text[],uuid,smallint,text[],jsonb,text[]);
--   DROP FUNCTION IF EXISTS public.fork_idea_to_channel(uuid,text,jsonb);
--   -- then re-apply W2 versions from 20260516650000

ALTER TABLE public.publication_ideas
  ADD COLUMN IF NOT EXISTS themes text[] DEFAULT '{}'::text[];

CREATE INDEX IF NOT EXISTS publication_ideas_themes_idx ON public.publication_ideas USING GIN (themes);

DROP FUNCTION IF EXISTS public.propose_publication_idea(text,text,text,uuid,integer,uuid,uuid[],text[],uuid,smallint,text[],jsonb);
DROP FUNCTION IF EXISTS public.fork_idea_to_channel(uuid,text,jsonb);

-- ============================================================
-- propose_publication_idea (re-created with p_themes parameter)
-- ============================================================
CREATE OR REPLACE FUNCTION public.propose_publication_idea(
  p_title text,
  p_summary text DEFAULT NULL,
  p_source_type text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL,
  p_initiative_id uuid DEFAULT NULL,
  p_author_ids uuid[] DEFAULT NULL,
  p_proposed_channels text[] DEFAULT NULL,
  p_series_id uuid DEFAULT NULL,
  p_series_position smallint DEFAULT NULL,
  p_target_languages text[] DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL,
  p_themes text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_idea_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_title IS NULL OR length(trim(p_title)) = 0 THEN
    RAISE EXCEPTION 'title is required';
  END IF;
  IF (p_source_type IS NULL) <> (p_source_id IS NULL) THEN
    RAISE EXCEPTION 'source_type and source_id must be both set or both NULL';
  END IF;

  INSERT INTO public.publication_ideas (
    title, summary, source_type, source_id, tribe_id, initiative_id,
    proposer_member_id, author_ids, proposed_channels, series_id, series_position,
    target_languages, metadata, stage, themes
  )
  VALUES (
    trim(p_title), p_summary, p_source_type, p_source_id, p_tribe_id, p_initiative_id,
    v_caller_id,
    COALESCE(p_author_ids, ARRAY[v_caller_id]::uuid[]),
    COALESCE(p_proposed_channels, '{}'::text[]),
    p_series_id, p_series_position,
    COALESCE(p_target_languages, ARRAY['pt-BR']::text[]),
    COALESCE(p_metadata, '{}'::jsonb),
    'draft',
    COALESCE(p_themes, '{}'::text[])
  )
  RETURNING id INTO v_idea_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'propose_publication_idea', 'publication_idea', v_idea_id,
    jsonb_build_object(
      'title', p_title, 'tribe_id', p_tribe_id, 'series_id', p_series_id,
      'channels', p_proposed_channels, 'source_type', p_source_type,
      'themes', p_themes
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W2')
  );

  RETURN jsonb_build_object('success', true, 'idea_id', v_idea_id, 'stage', 'draft');
END; $function$;

GRANT EXECUTE ON FUNCTION public.propose_publication_idea(text,text,text,uuid,integer,uuid,uuid[],text[],uuid,smallint,text[],jsonb,text[]) TO authenticated;

-- ============================================================
-- fork_idea_to_channel (W3.1 auto-scaffold blog draft)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fork_idea_to_channel(
  p_idea_id uuid,
  p_channel text,
  p_payload_hint jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_idea public.publication_ideas%ROWTYPE;
  v_is_committee boolean;
  v_existing_blog_id uuid;
  v_new_blog_id uuid;
  v_blog_slug text;
  v_existing_slug_count int;
  v_idea_title text;
  v_blog_created boolean := false;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_channel IS NULL OR length(trim(p_channel)) = 0 THEN
    RAISE EXCEPTION 'channel is required';
  END IF;

  SELECT * INTO v_idea FROM public.publication_ideas WHERE id = p_idea_id;
  IF v_idea.id IS NULL THEN RAISE EXCEPTION 'Idea not found: %', p_idea_id; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');
  IF v_caller_id <> v_idea.proposer_member_id AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: only proposer or comitê can fork to channel';
  END IF;

  IF v_idea.stage IN ('archived') THEN
    RAISE EXCEPTION 'Cannot fork from archived idea';
  END IF;

  IF NOT (v_idea.proposed_channels @> ARRAY[p_channel]::text[]) THEN
    UPDATE public.publication_ideas
       SET proposed_channels = array_append(COALESCE(proposed_channels, '{}'::text[]), p_channel)
     WHERE id = p_idea_id;
  END IF;

  IF lower(trim(p_channel)) IN ('blog','blog_post') AND v_idea.stage IN ('approved','published') THEN
    SELECT id INTO v_existing_blog_id
    FROM public.blog_posts
    WHERE source_idea_id = p_idea_id
    LIMIT 1;

    IF v_existing_blog_id IS NULL THEN
      v_idea_title := COALESCE(v_idea.title, 'untitled');
      v_blog_slug := lower(regexp_replace(
        regexp_replace(
          translate(v_idea_title,
            'áàâãäåçéèêëíìîïñóòôõöúùûüýÿÁÀÂÃÄÅÇÉÈÊËÍÌÎÏÑÓÒÔÕÖÚÙÛÜÝŸ',
            'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY'
          ),
          '[^a-zA-Z0-9\s-]+', '', 'g'
        ),
        '\s+', '-', 'g'
      ));
      v_blog_slug := substring(v_blog_slug from 1 for 80);
      v_blog_slug := trim(both '-' from v_blog_slug);
      IF length(v_blog_slug) = 0 THEN v_blog_slug := 'untitled-' || substring(p_idea_id::text from 1 for 8); END IF;

      SELECT count(*) INTO v_existing_slug_count FROM public.blog_posts WHERE slug = v_blog_slug;
      IF v_existing_slug_count > 0 THEN
        v_blog_slug := v_blog_slug || '-' || substring(p_idea_id::text from 1 for 6);
      END IF;

      INSERT INTO public.blog_posts (
        slug, title, excerpt, body_html,
        author_member_id, category, status, tags,
        series_id, series_position, source_idea_id, organization_id
      )
      VALUES (
        v_blog_slug,
        jsonb_build_object('pt-BR', v_idea_title),
        jsonb_build_object('pt-BR', COALESCE(v_idea.summary, '')),
        jsonb_build_object('pt-BR', '<p>' || COALESCE(v_idea.summary, '<i>Rascunho criado a partir de publication_idea ' || p_idea_id || '. Edite o body_html.</i>') || '</p>'),
        v_idea.proposer_member_id,
        'deep-dive',
        'draft',
        COALESCE(v_idea.themes, '{}'::text[]),
        v_idea.series_id,
        v_idea.series_position,
        p_idea_id,
        v_idea.organization_id
      )
      RETURNING id INTO v_new_blog_id;

      v_blog_created := true;
      v_existing_blog_id := v_new_blog_id;
    END IF;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'fork_idea_to_channel', 'publication_idea', p_idea_id,
    jsonb_build_object(
      'channel', p_channel,
      'payload_hint', p_payload_hint,
      'stage_at_fork', v_idea.stage,
      'blog_post_created', v_blog_created,
      'blog_post_id', v_existing_blog_id
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W3.1')
  );

  RETURN jsonb_build_object(
    'success', true,
    'idea_id', p_idea_id,
    'channel', p_channel,
    'blog_post_id', v_existing_blog_id,
    'blog_post_created', v_blog_created,
    'note', CASE
      WHEN v_blog_created THEN 'Auto-scaffold: blog_posts draft created. Edit body_html via existing tools.'
      WHEN v_existing_blog_id IS NOT NULL THEN 'Existing blog_posts row found (idempotent return).'
      ELSE 'Fork intent recorded (W3.2/W3.3 will automate other channels).'
    END
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.fork_idea_to_channel(uuid,text,jsonb) TO authenticated;
