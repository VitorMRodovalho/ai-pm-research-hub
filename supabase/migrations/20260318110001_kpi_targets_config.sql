-- ═══════════════════════════════════════════════════════════════════════════
-- P3 Fix: Store KPI targets in site_config as kpi_targets_cycle_3
-- Sourced from hardcoded src/data/kpis.ts
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO public.site_config (key, value, updated_at)
VALUES (
  'kpi_targets_cycle_3',
  '{"chapters": "8", "articles": "+10", "webinars": "+6", "pilots": "3", "impact": "1.800h", "cert": "70%"}'::JSONB,
  now()
)
ON CONFLICT (key) DO UPDATE SET
  value = EXCLUDED.value,
  updated_at = now();

COMMIT;
