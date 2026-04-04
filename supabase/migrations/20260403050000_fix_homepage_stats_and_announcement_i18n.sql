-- Fix get_homepage_stats: align member count with get_public_platform_stats (current_cycle_active)
-- Add localized title columns to announcements for banner i18n

BEGIN;

-- 1. Fix member count to use current_cycle_active (was member_status='active', off by 1)
CREATE OR REPLACE FUNCTION get_homepage_stats()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM members WHERE is_active AND current_cycle_active),
    'observers', (SELECT count(*) FROM members WHERE member_status = 'observer'),
    'alumni', (SELECT count(*) FROM members WHERE member_status = 'alumni'),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'chapters', (SELECT COUNT(DISTINCT chapter) FROM members WHERE is_active = true AND chapter IS NOT NULL),
    'impact_hours', (
      SELECT COALESCE(round(sum(
        COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
        * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)
      ) / 60), 0)
      FROM events e
      WHERE e.date >= '2026-01-01' AND e.date <= CURRENT_DATE
    )
  );
END;
$$;

-- 2. Add localized title columns to announcements
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS title_en text;
ALTER TABLE announcements ADD COLUMN IF NOT EXISTS title_es text;

NOTIFY pgrst, 'reload schema';

COMMIT;
