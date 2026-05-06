-- p95 #94 W3.3 (Opção B) — fork_idea_to_channel record social brief em publication_ideas.metadata
-- Lightweight no-architectural-change path. Opção A (nova tabela comms_briefs) ainda na mesa para V2.
--
-- Para channel IN ('social','linkedin','instagram','twitter','youtube','tiktok','facebook','medium','dev_to'):
-- Merge brief jsonb em idea.metadata.briefs[channel] = {channel, scaffolded_at, scaffolded_by,
--   proposed_caption_pt, hashtags, payload_hint, note}.
--
-- Idempotente: re-fork sobrescreve o brief mais recente para esse canal (não duplica histórico).
-- Multi-channel: same idea pode ter briefs.linkedin + briefs.instagram + briefs.twitter coexistentes.
--
-- Implementação: usa || merge (jsonb concat) em vez de jsonb_set.
-- Razão: jsonb_set não auto-cria intermediate paths quando 'briefs' key inicial não existe.
-- Pattern: COALESCE(metadata,'{}') || jsonb_build_object('briefs', COALESCE(metadata->'briefs','{}') || jsonb_build_object(channel, brief))
--
-- Trade-off conhecido: payload denormalizado (não-relational). Aceitável para V1; V2 (Opção A com
-- nova tabela comms_briefs) pode migrar lendo idea.metadata.briefs e escrevendo na tabela dedicada.
--
-- W3.1 (blog) + W3.2 (newsletter) handlers retidos verbatim.
--
-- Rollback: revert fork_idea_to_channel para versão W3.2 (20260516680000)

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
  v_brief_recorded boolean := false;
  v_brief_jsonb jsonb;
  v_normalized_channel text;
  v_social_channels text[] := ARRAY['social','linkedin','instagram','twitter','youtube','tiktok','facebook','medium','dev_to']::text[];
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

  IF v_normalized_channel = ANY(v_social_channels) AND v_idea.stage IN ('approved','published') THEN
    v_brief_jsonb := jsonb_build_object(
      'channel', v_normalized_channel,
      'scaffolded_at', now(),
      'scaffolded_by', v_caller_id,
      'proposed_caption_pt', COALESCE(NULLIF(v_idea_summary, ''), v_idea_title),
      'hashtags', COALESCE(v_idea.themes, '{}'::text[]),
      'payload_hint', p_payload_hint,
      'note', 'V1 brief stored in metadata.briefs. V2 (Opção A) pode migrar para tabela comms_briefs dedicada.'
    );

    UPDATE public.publication_ideas
       SET metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
         'briefs',
         COALESCE(metadata->'briefs', '{}'::jsonb) || jsonb_build_object(v_normalized_channel, v_brief_jsonb)
       )
     WHERE id = p_idea_id;

    v_brief_recorded := true;
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
      'campaign_template_id', v_existing_template_id,
      'brief_recorded', v_brief_recorded
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W3.3-OpcaoB')
  );

  RETURN jsonb_build_object(
    'success', true,
    'idea_id', p_idea_id,
    'channel', p_channel,
    'blog_post_id', v_existing_blog_id,
    'blog_post_created', v_blog_created,
    'campaign_template_id', v_existing_template_id,
    'template_created', v_template_created,
    'brief_recorded', v_brief_recorded,
    'note', CASE
      WHEN v_blog_created THEN 'Auto-scaffold: blog_posts draft created. Edit body_html via existing tools.'
      WHEN v_template_created THEN 'Auto-scaffold: campaign_templates draft created (newsletter). Edit subject/body_html before sending.'
      WHEN v_brief_recorded THEN 'Brief social registrado em idea.metadata.briefs.' || v_normalized_channel || '. V2 (Opção A) pode migrar para tabela dedicada.'
      WHEN v_existing_blog_id IS NOT NULL THEN 'Existing blog_posts row found (idempotent return).'
      WHEN v_existing_template_id IS NOT NULL THEN 'Existing campaign_template row found (idempotent return).'
      ELSE 'Fork intent recorded para canal não-orchestrated.'
    END
  );
END; $function$;
