-- p95 #94 W2 — publication_ideas pipeline (per ADR-0020 Accepted + Amendment 1)
-- PM Decisions 2A+2B+2C+2D shipped p95 (2026-05-05) unblocked W2:
--   D2: PT-BR primary, EN obrigatório p/ Frontiers, jsonb i18n bilingual
--   D3: text[] proposed_channels (no enum) — PMI.org + PM.com + blog + newsletter + linkedin + medium + dev_to + youtube + podcast
--   D4: polymorphic FK pattern (source_type text + source_id uuid, no FK constraint, indexed)
--
-- Stage state machine (9 stages):
--   draft → proposed → researching → writing → review → curation → approved → published → archived
-- review_sub_stage (text, nullable): tribe_review | leader_review (during stage='review')
--
-- Authority:
-- - propose: any active member
-- - advance to non-approval stages: proposer OR comitê (manage_event)
-- - advance to approved/published: comitê only
-- - archive: proposer OR comitê
-- - link to series: comitê (manage_event)
-- - fork to channel: proposer OR comitê (just records intent in W2; W3 orchestrator does row creation)
-- - list: any active member sees own; comitê sees all
--
-- Rollback:
--   ALTER TABLE public.public_publications DROP COLUMN IF EXISTS source_idea_id;
--   ALTER TABLE public.campaign_sends DROP COLUMN IF EXISTS source_idea_id;
--   ALTER TABLE public.publication_submissions DROP COLUMN IF EXISTS source_idea_id;
--   ALTER TABLE public.blog_posts DROP COLUMN IF EXISTS source_idea_id;
--   DROP TABLE IF EXISTS public.publication_ideas CASCADE;
--   DROP FUNCTION IF EXISTS public.propose_publication_idea(text,text,text,uuid,integer,uuid,uuid[],text[],uuid,smallint,text[],jsonb);
--   DROP FUNCTION IF EXISTS public.advance_idea_stage(uuid,text,text,text);
--   DROP FUNCTION IF EXISTS public.fork_idea_to_channel(uuid,text,jsonb);
--   DROP FUNCTION IF EXISTS public.link_idea_to_series(uuid,uuid,smallint);
--   DROP FUNCTION IF EXISTS public.get_idea_pipeline(integer,text,uuid);

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.publication_ideas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_type text CHECK (source_type IS NULL OR source_type IN
    ('meeting_action','hub_resource','wiki_page','external_research','experiment','partnership','webinar','ata_decision','other')),
  source_id uuid,
  title text NOT NULL,
  summary text,
  tribe_id integer,
  initiative_id uuid REFERENCES public.initiatives(id),
  proposer_member_id uuid NOT NULL REFERENCES public.members(id),
  author_ids uuid[] DEFAULT '{}'::uuid[],
  proposed_channels text[] DEFAULT '{}'::text[],
  stage text NOT NULL DEFAULT 'draft'
    CHECK (stage IN ('draft','proposed','researching','writing','review','curation','approved','published','archived')),
  review_sub_stage text
    CHECK (review_sub_stage IS NULL OR review_sub_stage IN ('tribe_review','leader_review')),
  series_id uuid REFERENCES public.publication_series(id),
  series_position smallint,
  target_languages text[] NOT NULL DEFAULT ARRAY['pt-BR']::text[],
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  rejection_reason text,
  archived_reason text,
  approved_by uuid REFERENCES public.members(id),
  approved_at timestamptz,
  published_at timestamptz,
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid REFERENCES public.organizations(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT publication_ideas_source_pair_consistent CHECK ((source_type IS NULL) = (source_id IS NULL))
);

CREATE INDEX IF NOT EXISTS publication_ideas_stage_idx ON public.publication_ideas(stage);
CREATE INDEX IF NOT EXISTS publication_ideas_proposer_idx ON public.publication_ideas(proposer_member_id);
CREATE INDEX IF NOT EXISTS publication_ideas_series_idx ON public.publication_ideas(series_id) WHERE series_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS publication_ideas_source_idx ON public.publication_ideas(source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS publication_ideas_tribe_idx ON public.publication_ideas(tribe_id) WHERE tribe_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS publication_ideas_initiative_idx ON public.publication_ideas(initiative_id) WHERE initiative_id IS NOT NULL;

COMMENT ON TABLE public.publication_ideas IS
  'Pipeline unificado de publicação (#94 W2 / ADR-0020). Primitivo idea que flui por N canais. PM decisions 2A+2B+2C+2D ratified.';

-- ============================================================
-- TRIGGERS
-- ============================================================
CREATE OR REPLACE FUNCTION public.publication_ideas_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS publication_ideas_updated_at_trg ON public.publication_ideas;
CREATE TRIGGER publication_ideas_updated_at_trg
BEFORE UPDATE ON public.publication_ideas
FOR EACH ROW EXECUTE FUNCTION public.publication_ideas_set_updated_at();

-- ============================================================
-- RLS — deny-all; SECDEF RPCs gate access
-- ============================================================
ALTER TABLE public.publication_ideas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS publication_ideas_deny_all ON public.publication_ideas;
CREATE POLICY publication_ideas_deny_all ON public.publication_ideas
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- ============================================================
-- BACK-LINK FK additions on output tables (W1 already added series_id to blog_posts)
-- ============================================================
ALTER TABLE public.blog_posts
  ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);
CREATE INDEX IF NOT EXISTS blog_posts_source_idea_idx ON public.blog_posts(source_idea_id) WHERE source_idea_id IS NOT NULL;

ALTER TABLE public.publication_submissions
  ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);
CREATE INDEX IF NOT EXISTS publication_submissions_source_idea_idx ON public.publication_submissions(source_idea_id) WHERE source_idea_id IS NOT NULL;

ALTER TABLE public.campaign_sends
  ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);
CREATE INDEX IF NOT EXISTS campaign_sends_source_idea_idx ON public.campaign_sends(source_idea_id) WHERE source_idea_id IS NOT NULL;

ALTER TABLE public.public_publications
  ADD COLUMN IF NOT EXISTS source_idea_id uuid REFERENCES public.publication_ideas(id);
CREATE INDEX IF NOT EXISTS public_publications_source_idea_idx ON public.public_publications(source_idea_id) WHERE source_idea_id IS NOT NULL;

-- ============================================================
-- propose_publication_idea — any active member
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
  p_metadata jsonb DEFAULT NULL
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
    target_languages, metadata, stage
  )
  VALUES (
    trim(p_title), p_summary, p_source_type, p_source_id, p_tribe_id, p_initiative_id,
    v_caller_id,
    COALESCE(p_author_ids, ARRAY[v_caller_id]::uuid[]),
    COALESCE(p_proposed_channels, '{}'::text[]),
    p_series_id, p_series_position,
    COALESCE(p_target_languages, ARRAY['pt-BR']::text[]),
    COALESCE(p_metadata, '{}'::jsonb),
    'draft'
  )
  RETURNING id INTO v_idea_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'propose_publication_idea', 'publication_idea', v_idea_id,
    jsonb_build_object(
      'title', p_title, 'tribe_id', p_tribe_id, 'series_id', p_series_id,
      'channels', p_proposed_channels, 'source_type', p_source_type
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W2')
  );

  RETURN jsonb_build_object('success', true, 'idea_id', v_idea_id, 'stage', 'draft');
END; $function$;

GRANT EXECUTE ON FUNCTION public.propose_publication_idea(text,text,text,uuid,integer,uuid,uuid[],text[],uuid,smallint,text[],jsonb) TO authenticated;

-- ============================================================
-- advance_idea_stage — state machine transitions
-- ============================================================
CREATE OR REPLACE FUNCTION public.advance_idea_stage(
  p_idea_id uuid,
  p_new_stage text,
  p_review_sub_stage text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_proposer uuid;
  v_current_stage text;
  v_is_committee boolean;
  v_stages_order text[] := ARRAY['draft','proposed','researching','writing','review','curation','approved','published','archived']::text[];
  v_current_idx int;
  v_new_idx int;
  v_requires_committee boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_new_stage NOT IN ('draft','proposed','researching','writing','review','curation','approved','published','archived') THEN
    RAISE EXCEPTION 'invalid new_stage %', p_new_stage;
  END IF;
  IF p_review_sub_stage IS NOT NULL AND p_review_sub_stage NOT IN ('tribe_review','leader_review') THEN
    RAISE EXCEPTION 'invalid review_sub_stage %', p_review_sub_stage;
  END IF;

  SELECT proposer_member_id, stage INTO v_proposer, v_current_stage
  FROM public.publication_ideas WHERE id = p_idea_id;
  IF v_proposer IS NULL THEN RAISE EXCEPTION 'Idea not found: %', p_idea_id; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');

  v_requires_committee := p_new_stage IN ('approved','published');
  IF v_requires_committee AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: stage % requires manage_event (comitê)', p_new_stage;
  END IF;

  IF v_caller_id <> v_proposer AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: only proposer or comitê can advance stage';
  END IF;

  v_current_idx := array_position(v_stages_order, v_current_stage);
  v_new_idx := array_position(v_stages_order, p_new_stage);

  IF p_new_stage <> 'archived'
     AND NOT (v_current_stage IN ('review','curation') AND p_new_stage = 'writing')
     AND v_new_idx <= v_current_idx THEN
    RAISE EXCEPTION 'Cannot move stage backwards from % to %', v_current_stage, p_new_stage;
  END IF;

  IF v_current_stage IN ('published','archived') THEN
    RAISE EXCEPTION 'Cannot move idea out of terminal stage %', v_current_stage;
  END IF;

  UPDATE public.publication_ideas
     SET stage = p_new_stage,
         review_sub_stage = CASE
           WHEN p_new_stage = 'review' THEN p_review_sub_stage
           ELSE NULL
         END,
         approved_by = CASE WHEN p_new_stage = 'approved' THEN v_caller_id ELSE approved_by END,
         approved_at = CASE WHEN p_new_stage = 'approved' THEN now() ELSE approved_at END,
         published_at = CASE WHEN p_new_stage = 'published' THEN now() ELSE published_at END,
         archived_reason = CASE WHEN p_new_stage = 'archived' THEN COALESCE(p_notes, archived_reason) ELSE archived_reason END
   WHERE id = p_idea_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'advance_idea_stage', 'publication_idea', p_idea_id,
    jsonb_build_object(
      'from_stage', v_current_stage, 'to_stage', p_new_stage,
      'sub_stage', p_review_sub_stage, 'notes', p_notes
    ),
    jsonb_build_object('source','mcp','issue','#94','wave','W2','as_committee', v_is_committee AND v_caller_id <> v_proposer)
  );

  RETURN jsonb_build_object(
    'success', true, 'idea_id', p_idea_id,
    'from_stage', v_current_stage, 'to_stage', p_new_stage
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.advance_idea_stage(uuid,text,text,text) TO authenticated;

-- ============================================================
-- fork_idea_to_channel — record intent + bump proposed_channels[] (W2 stub; W3 orchestrator does row creation)
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
  v_proposer uuid;
  v_stage text;
  v_channels text[];
  v_is_committee boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF p_channel IS NULL OR length(trim(p_channel)) = 0 THEN
    RAISE EXCEPTION 'channel is required';
  END IF;

  SELECT proposer_member_id, stage, proposed_channels INTO v_proposer, v_stage, v_channels
  FROM public.publication_ideas WHERE id = p_idea_id;
  IF v_proposer IS NULL THEN RAISE EXCEPTION 'Idea not found: %', p_idea_id; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');
  IF v_caller_id <> v_proposer AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: only proposer or comitê can fork to channel';
  END IF;

  IF v_stage IN ('archived') THEN
    RAISE EXCEPTION 'Cannot fork from archived idea';
  END IF;

  IF NOT (v_channels @> ARRAY[p_channel]::text[]) THEN
    UPDATE public.publication_ideas
       SET proposed_channels = array_append(COALESCE(proposed_channels, '{}'::text[]), p_channel)
     WHERE id = p_idea_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'fork_idea_to_channel', 'publication_idea', p_idea_id,
    jsonb_build_object('channel', p_channel, 'payload_hint', p_payload_hint, 'stage_at_fork', v_stage),
    jsonb_build_object('source','mcp','issue','#94','wave','W2','note','W3 orchestrator does downstream row creation')
  );

  RETURN jsonb_build_object(
    'success', true,
    'idea_id', p_idea_id,
    'channel', p_channel,
    'note', 'Fork intent recorded. Use create_blog_post / create_publication_submission / etc and link via source_idea_id (W3 will automate).'
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.fork_idea_to_channel(uuid,text,jsonb) TO authenticated;

-- ============================================================
-- link_idea_to_series — attach idea to a publication_series with optional position
-- ============================================================
CREATE OR REPLACE FUNCTION public.link_idea_to_series(
  p_idea_id uuid,
  p_series_id uuid,
  p_position smallint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_proposer uuid;
  v_series_active boolean;
  v_is_committee boolean;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT proposer_member_id INTO v_proposer FROM public.publication_ideas WHERE id = p_idea_id;
  IF v_proposer IS NULL THEN RAISE EXCEPTION 'Idea not found: %', p_idea_id; END IF;

  SELECT is_active INTO v_series_active FROM public.publication_series WHERE id = p_series_id;
  IF v_series_active IS NULL THEN RAISE EXCEPTION 'Series not found: %', p_series_id; END IF;
  IF NOT v_series_active THEN RAISE EXCEPTION 'Series is not active'; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');
  IF v_caller_id <> v_proposer AND NOT v_is_committee THEN
    RAISE EXCEPTION 'Unauthorized: only proposer or comitê can link to series';
  END IF;

  UPDATE public.publication_ideas
     SET series_id = p_series_id, series_position = p_position
   WHERE id = p_idea_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller_id, 'link_idea_to_series', 'publication_idea', p_idea_id,
    jsonb_build_object('series_id', p_series_id, 'position', p_position),
    jsonb_build_object('source','mcp','issue','#94','wave','W2')
  );

  RETURN jsonb_build_object('success', true, 'idea_id', p_idea_id, 'series_id', p_series_id, 'position', p_position);
END; $function$;

GRANT EXECUTE ON FUNCTION public.link_idea_to_series(uuid,uuid,smallint) TO authenticated;

-- ============================================================
-- get_idea_pipeline — read view (proposer sees own; comitê sees all)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_idea_pipeline(
  p_tribe_id integer DEFAULT NULL,
  p_stage_filter text DEFAULT NULL,
  p_series_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_is_committee boolean;
  v_result jsonb;
  v_summary jsonb;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  v_is_committee := public.can_by_member(v_caller_id, 'manage_event')
                 OR public.can_by_member(v_caller_id, 'manage_member');

  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      pi.id,
      pi.title,
      pi.summary,
      pi.stage,
      pi.review_sub_stage,
      pi.tribe_id,
      pi.initiative_id,
      pi.proposer_member_id,
      mp.name AS proposer_name,
      pi.author_ids,
      pi.proposed_channels,
      pi.target_languages,
      pi.source_type,
      pi.source_id,
      pi.series_id,
      COALESCE(ps.title_i18n->>'pt-BR', ps.slug) AS series_title,
      ps.slug AS series_slug,
      pi.series_position,
      pi.metadata,
      pi.rejection_reason,
      pi.archived_reason,
      pi.approved_by,
      ma.name AS approved_by_name,
      pi.approved_at,
      pi.published_at,
      pi.created_at,
      pi.updated_at
    FROM public.publication_ideas pi
    LEFT JOIN public.members mp ON mp.id = pi.proposer_member_id
    LEFT JOIN public.members ma ON ma.id = pi.approved_by
    LEFT JOIN public.publication_series ps ON ps.id = pi.series_id
    WHERE (p_stage_filter IS NULL OR pi.stage = p_stage_filter)
      AND (p_tribe_id IS NULL OR pi.tribe_id = p_tribe_id)
      AND (p_series_id IS NULL OR pi.series_id = p_series_id)
      AND (v_is_committee OR pi.proposer_member_id = v_caller_id)
    ORDER BY pi.created_at DESC
  ) r;

  SELECT jsonb_object_agg(stage, cnt) INTO v_summary
  FROM (
    SELECT stage, COUNT(*) AS cnt
    FROM public.publication_ideas pi
    WHERE (v_is_committee OR pi.proposer_member_id = v_caller_id)
      AND (p_tribe_id IS NULL OR pi.tribe_id = p_tribe_id)
      AND (p_series_id IS NULL OR pi.series_id = p_series_id)
    GROUP BY stage
  ) s;

  RETURN jsonb_build_object(
    'ideas', v_result,
    'count', jsonb_array_length(v_result),
    'is_committee', v_is_committee,
    'by_stage', COALESCE(v_summary, '{}'::jsonb)
  );
END; $function$;

GRANT EXECUTE ON FUNCTION public.get_idea_pipeline(integer,text,uuid) TO authenticated;
