-- W135: Homepage stats RPC + site_config for general meeting
-- Lightweight public RPC for homepage counters (no auth required)

CREATE OR REPLACE FUNCTION get_homepage_stats()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN jsonb_build_object(
    'members', (SELECT count(*) FROM members WHERE is_active),
    'tribes', (SELECT count(*) FROM tribes WHERE is_active),
    'chapters', 5,
    'impact_hours', (
      SELECT COALESCE(round(sum(
        COALESCE(e.duration_actual, e.duration_minutes, 60)::numeric
        * (SELECT count(*) FROM attendance a WHERE a.event_id = e.id AND a.present)
      ) / 60), 0)
      FROM events e WHERE e.date >= '2025-02-01'
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_homepage_stats() TO anon, authenticated;

-- General meeting config
INSERT INTO site_config (key, value) VALUES
  ('general_meeting_link', '"https://meet.google.com/dzo-phoj-tid"'),
  ('general_meeting_day', '3'),
  ('general_meeting_time', '"20:00"')
ON CONFLICT (key) DO NOTHING;

-- Active announcement for Ciclo 3
INSERT INTO announcements (title, message, type, link_url, link_text, starts_at, ends_at, is_active)
SELECT
  'Ciclo 3 em Andamento',
  'O Ciclo 3 (2026/1) do Núcleo IA & GP começou! Reuniões gerais toda quarta-feira às 20h.',
  'info',
  'https://meet.google.com/dzo-phoj-tid',
  'Entrar na Reunião Geral',
  '2026-03-05T00:00:00Z'::timestamptz,
  '2026-08-31T23:59:59Z'::timestamptz,
  true
WHERE NOT EXISTS (SELECT 1 FROM announcements WHERE title = 'Ciclo 3 em Andamento');
