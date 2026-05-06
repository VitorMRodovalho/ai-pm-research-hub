-- p95 #94 W3.2 — fork_idea_to_channel auto-scaffold campaign_templates draft (newsletter)
-- Extends W3.1 (blog) with newsletter channel handling.
-- W3.3 (comms_media_items canva brief) deferred.
--
-- When fork_idea_to_channel(channel IN ('newsletter','email')) is called for stage IN (approved, published):
--   - Create campaign_templates draft (category='newsletter') with source_idea_id linked
--   - Subject jsonb i18n (pt-BR), body_html / body_text jsonb i18n
--   - Slug snake_case ('idea_*' prefix); collision-disambiguated via idea_id suffix
--   - target_audience: empty placeholder (admin edits before send)
--   - Idempotent: returns existing if a campaign_template already linked to this idea
-- W3.1 blog handler retained verbatim. Multi-channel scaffold from same idea supported (independent rows).
--
-- Rollback:
--   ALTER TABLE public.campaign_templates DROP COLUMN IF EXISTS source_idea_id;
--   DROP FUNCTION IF EXISTS public.fork_idea_to_channel(uuid,text,jsonb);
--   -- then re-apply W3.1 (20260516670000)

ALTER TABLE public.campaign_templates
  ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);

CREATE INDEX IF NOT EXISTS campaign_templates_source_idea_idx
  ON public.campaign_templates(source_idea_id) WHERE source_idea_id IS NOT NULL;

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
  v_existing_template_id uuid;
  v_new_template_id uuid;
  v_template_slug text;
  v_existing_slug_count int;
  v_idea_title text;
  v_idea_summary text;
  v_blog_created boolean := false;
  v_template_created boolean := false;
  v_normalized_channel text;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_channel IS NULL OR length(trim(p_channel)) = 0 THEN
    RAISE EXCEPTION 'channel is required';
  END IF;

  v_normalized_channel := lower(trim(p_channel));

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

  v_idea_title := COALESCE(v_idea.title, 'untitled');
  v_idea_summary := COALESCE(v_idea.summary, '');

  IF v_normalized_channel IN ('blog','blog_post') AND v_idea.stage IN ('approved','published') THEN
    SELECT id INTO v_existing_blog_id
    FROM public.blog_posts
    WHERE source_idea_id = p_idea_id
    LIMIT 1;

    IF v_existing_blog_id IS NULL THEN
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
        jsonb_build_object('pt-BR', v_idea_summary),
        jsonb_build_object('pt-BR', '<p>' || COALESCE(NULLIF(v_idea_summary, ''), '<i>Rascunho criado a partir de publication_idea ' || p_idea_id || '. Edite o body_html.</i>') || '</p>'),
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

  IF v_normalized_channel IN ('newsletter','email') AND v_idea.stage IN ('approved','published') THEN
    SELECT id INTO v_existing_template_id
    FROM public.campaign_templates
    WHERE source_idea_id = p_idea_id
    LIMIT 1;

    IF v_existing_template_id IS NULL THEN
      v_template_slug := lower(regexp_replace(
        regexp_replace(
          translate(v_idea_title,
            'áàâãäåçéèêëíìîïñóòôõöúùûüýÿÁÀÂÃÄÅÇÉÈÊËÍÌÎÏÑÓÒÔÕÖÚÙÛÜÝŸ',
            'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY'
          ),
          '[^a-zA-Z0-9\s_-]+', '', 'g'
        ),
        '[\s-]+', '_', 'g'
      ));
      v_template_slug := substring(v_template_slug from 1 for 80);
      v_template_slug := trim(both '_' from v_template_slug);
      IF length(v_template_slug) = 0 THEN v_template_slug := 'idea_' || substring(p_idea_id::text from 1 for 8); END IF;
      v_template_slug := 'idea_' || v_template_slug;

      SELECT count(*) INTO v_existing_slug_count FROM public.campaign_templates WHERE slug = v_template_slug;
      IF v_existing_slug_count > 0 THEN
        v_template_slug := v_template_slug || '_' || substring(p_idea_id::text from 1 for 6);
      END IF;

      INSERT INTO public.campaign_templates (
        slug, name, subject, body_html, body_text, category,
        target_audience, variables, source_idea_id, created_by
      )
      VALUES (
        v_template_slug,
        substring(v_idea_title from 1 for 200),
        jsonb_build_object('pt-BR', v_idea_title),
        jsonb_build_object('pt-BR', '<p>' || COALESCE(NULLIF(v_idea_summary, ''), '<i>Newsletter draft scaffolded from publication_idea ' || p_idea_id || '. Edit body_html before sending.</i>') || '</p>'),
        jsonb_build_object('pt-BR', COALESCE(NULLIF(v_idea_summary, ''), 'Newsletter draft from idea ' || p_idea_id)),
        'newsletter',
        '{"all": false, "roles": [], "chapters": [], "designations": []}'::jsonb,
        '["member.name", "member.tribe", "member.chapter", "platform.url", "unsubscribe_url"]'::jsonb,
        p_idea_id,
        v_caller_id
      )
      RETURNING id INTO v_new_template_id;

      v_template_created := true;
      v_existing_template_id := v_new_template_id;
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
      'blog_post_id', v_existing_blog_id,
      'template_created', v_template_created,
      'campaign_template_id', v_existing_template_id
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W3.2')
  );

  RETURN jsonb_build_object(
    'success', true,
    'idea_id', p_idea_id,
    'channel', p_channel,
    'blog_post_id', v_existing_blog_id,
    'blog_post_created', v_blog_created,
    'campaign_template_id', v_existing_template_id,
    'template_created', v_template_created,
    'note', CASE
      WHEN v_blog_created THEN 'Auto-scaffold: blog_posts draft created. Edit body_html via existing tools.'
      WHEN v_template_created THEN 'Auto-scaffold: campaign_templates draft created (newsletter). Edit subject/body_html before sending.'
      WHEN v_existing_blog_id IS NOT NULL THEN 'Existing blog_posts row found (idempotent return).'
      WHEN v_existing_template_id IS NOT NULL THEN 'Existing campaign_template row found (idempotent return).'
      ELSE 'Fork intent recorded (W3.3 will automate canva brief for social/comms_media channels).'
    END
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.fork_idea_to_channel(uuid,text,jsonb) TO authenticated;
