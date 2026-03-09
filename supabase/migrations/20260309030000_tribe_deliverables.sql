-- ═══════════════════════════════════════════════════════════════
-- Migration: tribe_deliverables — per-tribe deliverable tracking
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.tribe_deliverables (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tribe_id           INT NOT NULL REFERENCES public.tribes(id),
  cycle_code         TEXT NOT NULL REFERENCES public.cycles(cycle_code),
  title              TEXT NOT NULL,
  description        TEXT,
  status             TEXT NOT NULL DEFAULT 'planned'
                     CHECK (status IN ('planned', 'in_progress', 'completed', 'cancelled')),
  assigned_member_id UUID REFERENCES public.members(id),
  artifact_id        UUID REFERENCES public.artifacts(id),
  due_date           DATE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tribe_deliverables_tribe_cycle
  ON public.tribe_deliverables (tribe_id, cycle_code);

ALTER TABLE public.tribe_deliverables ENABLE ROW LEVEL SECURITY;

-- Read: any authenticated user
CREATE POLICY "tribe_deliverables_read" ON public.tribe_deliverables
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Write: superadmin OR tribe_leader of that tribe
CREATE POLICY "tribe_deliverables_write" ON public.tribe_deliverables
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid()
        AND (
          is_superadmin = true
          OR (
            operational_role = 'tribe_leader'
            AND tribe_id = tribe_deliverables.tribe_id
          )
        )
    )
  );

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.tribe_deliverables_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tribe_deliverables_updated_at
  BEFORE UPDATE ON public.tribe_deliverables
  FOR EACH ROW
  EXECUTE FUNCTION public.tribe_deliverables_set_updated_at();

-- RPC: list deliverables for a tribe+cycle
CREATE OR REPLACE FUNCTION public.list_tribe_deliverables(
  p_tribe_id INT,
  p_cycle_code TEXT
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    jsonb_agg(
      to_jsonb(td.*) ORDER BY td.due_date NULLS LAST, td.created_at
    ),
    '[]'::jsonb
  )
  FROM public.tribe_deliverables td
  WHERE td.tribe_id = p_tribe_id
    AND td.cycle_code = p_cycle_code;
$$;

GRANT EXECUTE ON FUNCTION public.list_tribe_deliverables(INT, TEXT) TO authenticated;
