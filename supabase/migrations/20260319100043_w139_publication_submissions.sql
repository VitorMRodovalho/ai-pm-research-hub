-- W139 Item 2: Publication submission tracking schema
-- Fixes: publication_submission_events table was archived to z_archive but still referenced by frontend + RPCs
-- Adds: Full publication_submissions infrastructure for Cycle 3 deliverable tracking

-- ============================================================
-- PART A: Recreate publication_submission_events in public schema
-- (matches z_archive.publication_submission_events structure)
-- ============================================================

-- Drop existing RPCs first (they return z_archive type which we're replacing)
DROP FUNCTION IF EXISTS public.upsert_publication_submission_event(uuid, text, timestamptz, text, text);
DROP FUNCTION IF EXISTS public.upsert_publication_submission_event(uuid, text, timestamptz, text, text, text, timestamptz);

CREATE TABLE IF NOT EXISTS public.publication_submission_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  board_item_id uuid NOT NULL REFERENCES public.board_items(id) ON DELETE CASCADE,
  channel text NOT NULL DEFAULT 'projectmanagement_com',
  submitted_at timestamptz,
  outcome text NOT NULL DEFAULT 'pending',
  notes text,
  updated_by uuid NOT NULL REFERENCES public.members(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  external_link text,
  published_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_pub_sub_events_board_item ON public.publication_submission_events(board_item_id);
CREATE INDEX IF NOT EXISTS idx_pub_sub_events_outcome ON public.publication_submission_events(outcome);

-- RLS
ALTER TABLE public.publication_submission_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view submission events" ON public.publication_submission_events
  FOR SELECT TO authenticated USING (true);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION public.update_pub_sub_event_timestamp()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_pub_sub_event_updated
  BEFORE UPDATE ON public.publication_submission_events
  FOR EACH ROW
  EXECUTE FUNCTION public.update_pub_sub_event_timestamp();

GRANT SELECT ON public.publication_submission_events TO authenticated;
GRANT SELECT ON public.publication_submission_events TO anon;

-- Fix existing RPCs to return correct type (public schema, not z_archive)
CREATE OR REPLACE FUNCTION public.upsert_publication_submission_event(
  p_board_item_id uuid,
  p_channel text DEFAULT 'projectmanagement_com',
  p_submitted_at timestamptz DEFAULT NULL,
  p_outcome text DEFAULT 'pending',
  p_notes text DEFAULT NULL
)
RETURNS public.publication_submission_events
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_row public.publication_submission_events%rowtype;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'Auth required'; end if;

  select * into v_member from public.members
  where auth_id = v_actor and is_active = true limit 1;

  if v_member.id is null then raise exception 'Member not found'; end if;

  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'communicator')
    or exists (
      select 1 from unnest(coalesce(v_member.designations, array[]::text[])) d
      where d in ('curator', 'co_gp', 'comms_leader', 'comms_member')
    )
  ) then
    raise exception 'Publication workflow access required';
  end if;

  insert into public.publication_submission_events (
    board_item_id, channel, submitted_at, outcome, notes, updated_by
  ) values (
    p_board_item_id,
    coalesce(nullif(trim(p_channel), ''), 'projectmanagement_com'),
    p_submitted_at, p_outcome, nullif(trim(p_notes), ''), v_member.id
  )
  returning * into v_row;
  return v_row;
end;
$function$;

-- Overload with external_link and published_at
CREATE OR REPLACE FUNCTION public.upsert_publication_submission_event(
  p_board_item_id uuid,
  p_channel text DEFAULT 'projectmanagement_com',
  p_submitted_at timestamptz DEFAULT NULL,
  p_outcome text DEFAULT 'pending',
  p_notes text DEFAULT NULL,
  p_external_link text DEFAULT NULL,
  p_published_at timestamptz DEFAULT NULL
)
RETURNS public.publication_submission_events
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_actor uuid;
  v_member public.members%rowtype;
  v_row public.publication_submission_events%rowtype;
begin
  v_actor := auth.uid();
  if v_actor is null then raise exception 'Auth required'; end if;

  select * into v_member from public.members
  where auth_id = v_actor and is_active = true limit 1;

  if v_member.id is null then raise exception 'Member not found'; end if;

  if not (
    coalesce(v_member.is_superadmin, false)
    or v_member.operational_role in ('manager', 'deputy_manager', 'communicator')
    or exists (
      select 1 from unnest(coalesce(v_member.designations, array[]::text[])) d
      where d in ('curator', 'co_gp', 'comms_leader', 'comms_member')
    )
  ) then
    raise exception 'Publication workflow access required';
  end if;

  insert into public.publication_submission_events (
    board_item_id, channel, submitted_at, outcome, notes, external_link, published_at, updated_by
  ) values (
    p_board_item_id,
    coalesce(nullif(trim(p_channel), ''), 'projectmanagement_com'),
    p_submitted_at, p_outcome, nullif(trim(p_notes), ''),
    nullif(trim(p_external_link), ''), p_published_at, v_member.id
  )
  returning * into v_row;
  return v_row;
end;
$function$;

-- ============================================================
-- PART B: New publication_submissions infrastructure
-- Structured tracking of article/paper submissions to PMI conferences and journals
-- ============================================================

-- Submission status lifecycle
DO $$ BEGIN
  CREATE TYPE public.submission_status AS ENUM (
    'draft', 'submitted', 'under_review', 'revision_requested',
    'accepted', 'rejected', 'published', 'presented'
  );
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- Submission target type
DO $$ BEGIN
  CREATE TYPE public.submission_target_type AS ENUM (
    'pmi_global_conference', 'pmi_chapter_event', 'academic_journal',
    'academic_conference', 'webinar', 'blog_post', 'other'
  );
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- Main submissions table
CREATE TABLE public.publication_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  board_item_id uuid REFERENCES public.board_items(id) ON DELETE SET NULL,
  title text NOT NULL,
  abstract text,
  target_type submission_target_type NOT NULL,
  target_name text NOT NULL,
  target_url text,
  status submission_status NOT NULL DEFAULT 'draft',
  submission_date date,
  review_deadline date,
  acceptance_date date,
  presentation_date date,
  primary_author_id uuid NOT NULL REFERENCES public.members(id),
  estimated_cost_brl numeric(10,2) DEFAULT 0,
  actual_cost_brl numeric(10,2),
  cost_paid_by text,
  reviewer_feedback text,
  doi_or_url text,
  tribe_id integer REFERENCES public.tribes(id),
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Co-authors junction table
CREATE TABLE public.publication_submission_authors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES public.publication_submissions(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.members(id),
  author_order integer NOT NULL DEFAULT 1,
  is_corresponding boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(submission_id, member_id)
);

-- Indexes
CREATE INDEX idx_pub_submissions_status ON public.publication_submissions(status);
CREATE INDEX idx_pub_submissions_author ON public.publication_submissions(primary_author_id);
CREATE INDEX idx_pub_submissions_tribe ON public.publication_submissions(tribe_id);
CREATE INDEX idx_pub_submissions_board_item ON public.publication_submissions(board_item_id);
CREATE INDEX idx_pub_sub_authors_sub ON public.publication_submission_authors(submission_id);

-- Updated_at trigger for submissions
CREATE TRIGGER trg_publication_submission_updated
  BEFORE UPDATE ON public.publication_submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_pub_sub_event_timestamp();

-- RLS
ALTER TABLE public.publication_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.publication_submission_authors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view submissions" ON public.publication_submissions
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Members can view submission authors" ON public.publication_submission_authors
  FOR SELECT TO authenticated USING (true);

GRANT SELECT ON public.publication_submissions TO authenticated;
GRANT SELECT ON public.publication_submission_authors TO authenticated;

-- SECURITY DEFINER RPC: Create submission
CREATE OR REPLACE FUNCTION public.create_publication_submission(
  p_title text,
  p_target_type submission_target_type,
  p_target_name text,
  p_primary_author_id uuid,
  p_tribe_id integer DEFAULT NULL,
  p_board_item_id uuid DEFAULT NULL,
  p_abstract text DEFAULT NULL,
  p_target_url text DEFAULT NULL,
  p_estimated_cost_brl numeric DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_submission_id uuid;
  v_caller_id uuid;
  v_member_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id AND is_active = true LIMIT 1;
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not an active member'; END IF;

  INSERT INTO public.publication_submissions (
    title, target_type, target_name, primary_author_id,
    tribe_id, board_item_id, abstract, target_url, estimated_cost_brl, created_by
  ) VALUES (
    p_title, p_target_type, p_target_name, p_primary_author_id,
    p_tribe_id, p_board_item_id, p_abstract, p_target_url, p_estimated_cost_brl, v_member_id
  )
  RETURNING id INTO v_submission_id;

  -- Add primary author to authors table
  INSERT INTO public.publication_submission_authors (submission_id, member_id, author_order, is_corresponding)
  VALUES (v_submission_id, p_primary_author_id, 1, true);

  RETURN v_submission_id;
END;
$$;

-- SECURITY DEFINER RPC: Update submission status
CREATE OR REPLACE FUNCTION public.update_publication_submission_status(
  p_submission_id uuid,
  p_new_status submission_status,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_caller_id uuid;
  v_member_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT id INTO v_member_id FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  UPDATE public.publication_submissions
  SET status = p_new_status
  WHERE id = p_submission_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Submission not found'; END IF;
END;
$$;

-- SECURITY DEFINER RPC: Get submissions with authors
CREATE OR REPLACE FUNCTION public.get_publication_submissions(
  p_status submission_status DEFAULT NULL,
  p_tribe_id integer DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  title text,
  abstract text,
  target_type submission_target_type,
  target_name text,
  status submission_status,
  submission_date date,
  presentation_date date,
  primary_author_name text,
  tribe_name text,
  estimated_cost_brl numeric,
  actual_cost_brl numeric,
  created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ps.id, ps.title, ps.abstract, ps.target_type, ps.target_name,
    ps.status, ps.submission_date, ps.presentation_date,
    m.name AS primary_author_name,
    t.name AS tribe_name,
    ps.estimated_cost_brl, ps.actual_cost_brl, ps.created_at
  FROM public.publication_submissions ps
  LEFT JOIN public.members m ON m.id = ps.primary_author_id
  LEFT JOIN public.tribes t ON t.id = ps.tribe_id
  WHERE (p_status IS NULL OR ps.status = p_status)
    AND (p_tribe_id IS NULL OR ps.tribe_id = p_tribe_id)
  ORDER BY ps.created_at DESC;
END;
$$;

COMMENT ON TABLE public.publication_submission_events IS 'W139: Board-level submission event tracking (external links, outcomes, dates).';
COMMENT ON TABLE public.publication_submissions IS 'W139: Structured tracking of article/paper submissions to PMI conferences, journals, and events.';
COMMENT ON TABLE public.publication_submission_authors IS 'W139: Co-authors junction for publication submissions.';
