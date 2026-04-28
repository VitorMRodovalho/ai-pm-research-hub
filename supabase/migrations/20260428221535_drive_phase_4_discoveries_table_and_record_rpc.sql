-- Drive Phase 4 — auto-discovery atas via cron.
-- Schema: drive_file_discoveries (idempotency cache + audit + auto-match attempt).
-- Heuristic: filename date pattern → match against events.date ±7 days same initiative.
-- If matched event has empty minutes_url → auto-promote to event.minutes_url.

CREATE TABLE IF NOT EXISTS public.drive_file_discoveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  initiative_drive_link_id uuid NOT NULL REFERENCES public.initiative_drive_links(id) ON DELETE CASCADE,
  drive_file_id text NOT NULL UNIQUE,
  drive_file_url text NOT NULL,
  filename text NOT NULL,
  mime_type text,
  size_bytes bigint,
  drive_modified_at timestamptz,
  discovered_at timestamptz NOT NULL DEFAULT now(),
  matched_event_id uuid REFERENCES public.events(id) ON DELETE SET NULL,
  match_strategy text NOT NULL DEFAULT 'unmatched' CHECK (match_strategy IN ('unmatched', 'filename_date', 'manual')),
  match_confidence text NOT NULL DEFAULT 'none' CHECK (match_confidence IN ('none', 'low', 'medium', 'high')),
  promoted_to_minutes_url boolean NOT NULL DEFAULT false,
  promoted_at timestamptz,
  promoted_by uuid REFERENCES public.members(id) ON DELETE SET NULL  -- NULL when auto-promoted by cron
);

CREATE INDEX IF NOT EXISTS idx_drive_discoveries_link ON public.drive_file_discoveries(initiative_drive_link_id);
CREATE INDEX IF NOT EXISTS idx_drive_discoveries_unmatched ON public.drive_file_discoveries(initiative_drive_link_id) WHERE matched_event_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_drive_discoveries_event ON public.drive_file_discoveries(matched_event_id) WHERE matched_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_drive_discoveries_promoted_by ON public.drive_file_discoveries(promoted_by) WHERE promoted_by IS NOT NULL;

ALTER TABLE public.drive_file_discoveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY drive_file_discoveries_read_authenticated ON public.drive_file_discoveries
  FOR SELECT TO authenticated
  USING (rls_is_member());

COMMENT ON TABLE public.drive_file_discoveries IS
'ADR-0065 Drive Phase 4: idempotency cache + audit trail for cron auto-discovery of Drive files in initiatives'' minutes folders. drive_file_id is UNIQUE for ON CONFLICT DO NOTHING idempotency.';

-- Helper: extract date from filename (heuristic, 3 patterns)
CREATE OR REPLACE FUNCTION public._extract_date_from_filename(p_filename text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_match text[];
BEGIN
  -- Pattern 1: YYYY-MM-DD or YYYY_MM_DD or YYYY/MM/DD
  v_match := regexp_match(p_filename, '(\d{4})[-_/](\d{2})[-_/](\d{2})');
  IF v_match IS NOT NULL THEN
    BEGIN
      RETURN make_date(v_match[1]::int, v_match[2]::int, v_match[3]::int);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  -- Pattern 2: DD-MM-YYYY or DD_MM_YYYY or DD/MM/YYYY (Brazilian convention)
  v_match := regexp_match(p_filename, '(\d{2})[-_/](\d{2})[-_/](\d{4})');
  IF v_match IS NOT NULL THEN
    BEGIN
      RETURN make_date(v_match[3]::int, v_match[2]::int, v_match[1]::int);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  -- Pattern 3: YYYYMMDD (compact)
  v_match := regexp_match(p_filename, '(20\d{2})(\d{2})(\d{2})');
  IF v_match IS NOT NULL THEN
    BEGIN
      RETURN make_date(v_match[1]::int, v_match[2]::int, v_match[3]::int);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public._extract_date_from_filename(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._extract_date_from_filename(text) TO authenticated, service_role;

-- RPC: record_drive_discovery — idempotent insert + auto-match attempt
CREATE OR REPLACE FUNCTION public.record_drive_discovery(
  p_initiative_drive_link_id uuid,
  p_drive_file_id text,
  p_drive_file_url text,
  p_filename text,
  p_mime_type text DEFAULT NULL,
  p_size_bytes bigint DEFAULT NULL,
  p_drive_modified_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_initiative_id uuid;
  v_existing_id uuid;
  v_new_id uuid;
  v_filename_date date;
  v_matched_event_id uuid;
  v_match_strategy text := 'unmatched';
  v_match_confidence text := 'none';
  v_event_minutes_url text;
  v_event_date date;
  v_auto_promoted boolean := false;
BEGIN
  -- Caller authorization: service_role only (cron) OR view_internal_analytics
  IF current_user NOT IN ('service_role', 'postgres', 'supabase_admin') THEN
    DECLARE
      v_caller_id uuid;
    BEGIN
      SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
      IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
        RETURN jsonb_build_object('error', 'Unauthorized: requires service_role or view_internal_analytics');
      END IF;
    END;
  END IF;

  -- Idempotent: skip if already discovered
  SELECT id INTO v_existing_id FROM public.drive_file_discoveries
  WHERE drive_file_id = p_drive_file_id;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('is_new', false, 'discovery_id', v_existing_id);
  END IF;

  -- Resolve initiative
  SELECT initiative_id INTO v_initiative_id
  FROM public.initiative_drive_links
  WHERE id = p_initiative_drive_link_id AND unlinked_at IS NULL;
  IF v_initiative_id IS NULL THEN
    RETURN jsonb_build_object('error', 'initiative_drive_link not found or unlinked');
  END IF;

  -- Try filename date heuristic
  v_filename_date := public._extract_date_from_filename(p_filename);
  IF v_filename_date IS NOT NULL THEN
    SELECT e.id, e.minutes_url, e.date
      INTO v_matched_event_id, v_event_minutes_url, v_event_date
    FROM public.events e
    WHERE e.initiative_id = v_initiative_id
      AND e.date BETWEEN v_filename_date - INTERVAL '7 days' AND v_filename_date + INTERVAL '7 days'
    ORDER BY ABS(e.date - v_filename_date)
    LIMIT 1;

    IF v_matched_event_id IS NOT NULL THEN
      v_match_strategy := 'filename_date';
      v_match_confidence := CASE
        WHEN v_filename_date = v_event_date THEN 'high'
        WHEN ABS(v_filename_date - v_event_date) <= 1 THEN 'medium'
        ELSE 'low'
      END;
      -- Auto-promote: only if event has no minutes_url yet
      IF v_event_minutes_url IS NULL THEN
        UPDATE public.events
        SET minutes_url = p_drive_file_url,
            minutes_posted_at = COALESCE(p_drive_modified_at, now()),
            updated_at = now()
        WHERE id = v_matched_event_id;
        v_auto_promoted := true;
      END IF;
    END IF;
  END IF;

  -- INSERT discovery
  INSERT INTO public.drive_file_discoveries (
    initiative_drive_link_id, drive_file_id, drive_file_url, filename,
    mime_type, size_bytes, drive_modified_at,
    matched_event_id, match_strategy, match_confidence,
    promoted_to_minutes_url, promoted_at, promoted_by
  ) VALUES (
    p_initiative_drive_link_id, p_drive_file_id, p_drive_file_url, p_filename,
    p_mime_type, p_size_bytes, p_drive_modified_at,
    v_matched_event_id, v_match_strategy, v_match_confidence,
    v_auto_promoted, CASE WHEN v_auto_promoted THEN now() ELSE NULL END, NULL
  )
  RETURNING id INTO v_new_id;

  RETURN jsonb_build_object(
    'is_new', true,
    'discovery_id', v_new_id,
    'matched_event_id', v_matched_event_id,
    'match_strategy', v_match_strategy,
    'match_confidence', v_match_confidence,
    'auto_promoted', v_auto_promoted
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_drive_discovery(uuid, text, text, text, text, bigint, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_drive_discovery(uuid, text, text, text, text, bigint, timestamptz) TO authenticated, service_role;

COMMENT ON FUNCTION public.record_drive_discovery(uuid, text, text, text, text, bigint, timestamptz) IS
'ADR-0065 Drive Phase 4: idempotent insert into drive_file_discoveries + auto-match heuristic (filename date → events.date ±7d) + auto-promote (event.minutes_url IS NULL → fill). Caller: service_role (cron) OR view_internal_analytics.';

NOTIFY pgrst, 'reload schema';
