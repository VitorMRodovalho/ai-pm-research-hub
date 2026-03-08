-- ═══════════════════════════════════════════════════════════════
-- Migration: cycles table — single source of truth for cycle config
-- Replaces hardcoded CYCLE_META, CYCLE_ORDER, dates map in admin,
--   profile, cycle-history, and constants files.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cycles (
  cycle_code  TEXT PRIMARY KEY,
  cycle_label TEXT NOT NULL,
  cycle_abbr  TEXT NOT NULL,
  cycle_start DATE NOT NULL,
  cycle_end   DATE,
  cycle_color TEXT NOT NULL DEFAULT '#94A3B8',
  sort_order  INT NOT NULL DEFAULT 0,
  is_current  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.cycles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cycles_read_all" ON public.cycles
  FOR SELECT USING (true);

CREATE POLICY "cycles_admin_write" ON public.cycles
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.members WHERE auth_id = auth.uid() AND is_superadmin = true)
  );

-- Seed with existing cycle data (matches current CYCLE_META)
INSERT INTO public.cycles (cycle_code, cycle_label, cycle_abbr, cycle_start, cycle_end, cycle_color, sort_order, is_current) VALUES
  ('pilot',   'Piloto 2024',          'P24',  '2024-03-01', '2024-12-31', '#F59E0B', 1, false),
  ('cycle_1', 'Ciclo 1 (2025/1)',     'C1',   '2025-01-01', '2025-06-30', '#3B82F6', 2, false),
  ('cycle_2', 'Ciclo 2 (2025/2)',     'C2',   '2025-07-01', '2025-12-31', '#8B5CF6', 3, false),
  ('cycle_3', 'Ciclo 3 (2026/1)',     'C3',   '2026-01-01', NULL,         '#10B981', 4, true)
ON CONFLICT (cycle_code) DO NOTHING;

-- Helper RPC to get current cycle
CREATE OR REPLACE FUNCTION public.get_current_cycle()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT to_jsonb(c.*) FROM public.cycles c WHERE c.is_current = true LIMIT 1;
$$;

-- Helper RPC to list all cycles ordered
CREATE OR REPLACE FUNCTION public.list_cycles()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.sort_order), '[]'::jsonb)
  FROM public.cycles c;
$$;

GRANT EXECUTE ON FUNCTION public.get_current_cycle() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_cycles() TO anon, authenticated;
