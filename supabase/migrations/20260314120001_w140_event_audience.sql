-- ============================================================
-- W140 BLOCO 2: Per-event audience rules
-- Defines WHO should attend (mandatory/optional/observer)
-- all_active_operational = is_active AND (tribe_id IS NOT NULL OR role IN (manager, deputy_manager))
-- ============================================================

CREATE TABLE public.event_audience_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  attendance_type text NOT NULL DEFAULT 'mandatory',
  target_type text NOT NULL,
    -- 'all_active_operational': active + (tribe OR GP/DM)
    -- 'tribe': specific tribe
    -- 'role': specific operational_role
    -- 'specific_members': only invited members
  target_value text,
  created_at timestamptz DEFAULT now()
);

-- Use a partial unique index instead of UNIQUE constraint with COALESCE
CREATE UNIQUE INDEX idx_event_audience_unique
  ON public.event_audience_rules (event_id, attendance_type, target_type, target_value)
  WHERE target_value IS NOT NULL;
CREATE UNIQUE INDEX idx_event_audience_unique_null
  ON public.event_audience_rules (event_id, attendance_type, target_type)
  WHERE target_value IS NULL;

CREATE TABLE public.event_invited_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.members(id),
  attendance_type text NOT NULL DEFAULT 'mandatory',
  notes text,
  created_at timestamptz DEFAULT now(),
  UNIQUE(event_id, member_id)
);

CREATE INDEX idx_event_audience_event ON public.event_audience_rules(event_id);
CREATE INDEX idx_event_invited_event ON public.event_invited_members(event_id);
CREATE INDEX idx_event_invited_member ON public.event_invited_members(member_id);

ALTER TABLE public.event_audience_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_invited_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view audience rules" ON public.event_audience_rules
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Members can view invited members" ON public.event_invited_members
  FOR SELECT TO authenticated USING (true);

-- Write policies
CREATE POLICY "Managers can manage audience rules" ON public.event_audience_rules
  FOR ALL TO authenticated USING (true);
CREATE POLICY "Managers can manage invited members" ON public.event_invited_members
  FOR ALL TO authenticated USING (true);

GRANT ALL ON public.event_audience_rules TO authenticated;
GRANT ALL ON public.event_invited_members TO authenticated;

COMMENT ON TABLE public.event_audience_rules IS 'W140: Group-level audience rules. all_active_operational excludes sponsors/liaisons from mandatory.';
COMMENT ON TABLE public.event_invited_members IS 'W140: Individual member invites per event.';
