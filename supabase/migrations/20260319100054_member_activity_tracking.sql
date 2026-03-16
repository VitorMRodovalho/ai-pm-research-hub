-- Member Activity Tracking (GC-070)
-- Lightweight activity tracking for admin adoption dashboard.
-- LGPD: legítimo interesse (Art. 7, IX). Dados mínimos. Admin-only.

-- 1. Activity columns on members
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS total_sessions integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_active_pages text[] DEFAULT '{}';

COMMENT ON COLUMN public.members.last_seen_at IS 'Last time member loaded any authenticated page.';
COMMENT ON COLUMN public.members.total_sessions IS 'Total distinct login sessions.';
COMMENT ON COLUMN public.members.last_active_pages IS 'Last 5 pages visited (rolling). Admin adoption dashboard only.';

-- 2. Activity sessions table (daily granularity)
CREATE TABLE IF NOT EXISTS public.member_activity_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  session_date date NOT NULL DEFAULT CURRENT_DATE,
  pages_visited integer DEFAULT 1,
  first_page text,
  last_page text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(member_id, session_date)
);

ALTER TABLE public.member_activity_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Superadmin can view all sessions" ON public.member_activity_sessions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid()
      AND (is_superadmin = true OR operational_role = 'manager')
    )
  );

CREATE POLICY "Members can insert own sessions" ON public.member_activity_sessions
  FOR INSERT TO authenticated
  WITH CHECK (
    member_id = (SELECT id FROM public.members WHERE auth_id = auth.uid())
  );

CREATE INDEX IF NOT EXISTS idx_activity_sessions_member ON public.member_activity_sessions(member_id, session_date DESC);
CREATE INDEX IF NOT EXISTS idx_activity_sessions_date ON public.member_activity_sessions(session_date DESC);

COMMENT ON TABLE public.member_activity_sessions IS 'Daily activity sessions per member. Max 1 row per member per day. Admin-only read access.';

-- 3. RPC: record_member_activity (called on every pageview, throttled client-side)
CREATE OR REPLACE FUNCTION public.record_member_activity(
  p_page text DEFAULT '/'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member_id uuid;
  v_today date := CURRENT_DATE;
BEGIN
  SELECT id INTO v_member_id
  FROM public.members
  WHERE auth_id = auth.uid() AND is_active = true;

  IF v_member_id IS NULL THEN RETURN; END IF;

  UPDATE public.members SET
    last_seen_at = now(),
    last_active_pages = (
      SELECT array_agg(p) FROM (
        SELECT unnest(
          ARRAY[p_page] || COALESCE(last_active_pages, '{}')
        ) AS p LIMIT 5
      ) sub
    )
  WHERE id = v_member_id;

  INSERT INTO public.member_activity_sessions (member_id, session_date, pages_visited, first_page, last_page)
  VALUES (v_member_id, v_today, 1, p_page, p_page)
  ON CONFLICT (member_id, session_date) DO UPDATE SET
    pages_visited = member_activity_sessions.pages_visited + 1,
    last_page = p_page,
    updated_at = now();

  UPDATE public.members SET
    total_sessions = (
      SELECT count(DISTINCT session_date)
      FROM public.member_activity_sessions
      WHERE member_id = v_member_id
    )
  WHERE id = v_member_id;
END;
$$;

COMMENT ON FUNCTION public.record_member_activity IS 'Records member pageview. Updates last_seen_at, rolling pages, daily session.';

-- 4. RPC: get_adoption_dashboard (admin-only)
CREATE OR REPLACE FUNCTION public.get_adoption_dashboard()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role = 'manager')
  ) THEN
    RAISE EXCEPTION 'Admin only';
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'summary', jsonb_build_object(
      'total_active', (SELECT count(*) FROM members WHERE is_active = true),
      'ever_logged_in', (SELECT count(*) FROM members WHERE is_active = true AND auth_id IS NOT NULL),
      'seen_last_7d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '7 days'),
      'seen_last_30d', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at > now() - interval '30 days'),
      'never_seen', (SELECT count(*) FROM members WHERE is_active = true AND last_seen_at IS NULL),
      'adoption_pct_7d', (
        SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '7 days')::numeric
          / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members
      ),
      'adoption_pct_30d', (
        SELECT ROUND(count(*) FILTER (WHERE last_seen_at > now() - interval '30 days')::numeric
          / NULLIF(count(*) FILTER (WHERE is_active = true), 0) * 100, 1) FROM members
      ),
      'avg_sessions_per_member', (
        SELECT ROUND(AVG(total_sessions)::numeric, 1)
        FROM members WHERE is_active = true AND total_sessions > 0
      )
    ),
    'by_tier', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'tier', operational_role,
        'total', count(*),
        'seen_7d', count(*) FILTER (WHERE last_seen_at > now() - interval '7 days'),
        'seen_30d', count(*) FILTER (WHERE last_seen_at > now() - interval '30 days'),
        'never', count(*) FILTER (WHERE last_seen_at IS NULL),
        'avg_sessions', ROUND(AVG(total_sessions)::numeric, 1)
      )), '[]'::jsonb)
      FROM members WHERE is_active = true GROUP BY operational_role
    ),
    'by_tribe', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'tribe_id', t.id, 'tribe_name', t.name,
        'total', count(m.id),
        'seen_7d', count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '7 days'),
        'seen_30d', count(m.id) FILTER (WHERE m.last_seen_at > now() - interval '30 days'),
        'never', count(m.id) FILTER (WHERE m.last_seen_at IS NULL),
        'avg_sessions', ROUND(AVG(m.total_sessions)::numeric, 1)
      ) ORDER BY t.id), '[]'::jsonb)
      FROM tribes t LEFT JOIN members m ON m.tribe_id = t.id AND m.is_active = true
      GROUP BY t.id, t.name
    ),
    'daily_activity', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'date', d.dt::text,
        'unique_members', COALESCE(s.cnt, 0),
        'total_pageviews', COALESCE(s.pvs, 0)
      ) ORDER BY d.dt), '[]'::jsonb)
      FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE, '1 day') d(dt)
      LEFT JOIN (
        SELECT session_date, count(DISTINCT member_id) as cnt, sum(pages_visited) as pvs
        FROM member_activity_sessions WHERE session_date > CURRENT_DATE - 30
        GROUP BY session_date
      ) s ON s.session_date = d.dt
    ),
    'members', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', m.id, 'name', m.name, 'tier', m.operational_role,
        'tribe_id', m.tribe_id, 'tribe_name', t.name,
        'has_auth', m.auth_id IS NOT NULL, 'last_seen', m.last_seen_at,
        'total_sessions', m.total_sessions, 'last_pages', m.last_active_pages,
        'status', CASE
          WHEN m.last_seen_at IS NULL THEN 'never'
          WHEN m.last_seen_at > now() - interval '7 days' THEN 'active'
          WHEN m.last_seen_at > now() - interval '30 days' THEN 'inactive'
          ELSE 'dormant'
        END
      ) ORDER BY m.last_seen_at DESC NULLS LAST), '[]'::jsonb)
      FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id
      WHERE m.is_active = true
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_adoption_dashboard IS 'Admin adoption dashboard: last_seen, sessions, by tier/tribe, daily activity chart.';

-- 5. Bump governance_entries
UPDATE public.governance_entries
SET total_entries = 70
WHERE id = (SELECT id FROM public.governance_entries ORDER BY created_at DESC LIMIT 1);
