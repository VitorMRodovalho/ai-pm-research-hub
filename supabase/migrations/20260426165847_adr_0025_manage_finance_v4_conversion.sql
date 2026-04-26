-- ADR-0025 (Accepted): manage_finance V4 action
-- Phase B'' V3→V4 conversion of 4 finance fns.
-- See docs/adr/ADR-0025-manage-finance-v4-action.md
--
-- PM ratified Q1-Q4 (2026-04-26 p59):
--   Q1 (sponsors com manage_finance?) — SIM
--   Q2 (chapter_liaison scope?) — NÃO agora (adiar até schema chapter_id)
--   Q3 (view_finance separada?) — NÃO (YAGNI; reads já protegidos via Q-D)
--   Q4 (timing?) — p59 mesmo (executar agora)
--
-- Privilege expansion safety check (verified pre-apply):
--   V3 grant: 2 members (Vitor, Fabricio — superadmin OR manager)
--   V4 grant proposed: 7 members (above + 5 sponsors)
--   Would gain: 5 sponsors (Ivan Lourenço, Márcio Silva dos Santos,
--     Matheus Frederico Rosa Rocha, Felipe Moraes Borges,
--     Francisca Jessica de Sousa de Alcântara) — INTENTIONAL per Q1
--   Would lose: 0 members

-- ============================================================
-- 1. Adicionar action manage_finance ao engagement_kind_permissions
-- ============================================================
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  ('volunteer', 'co_gp',          'manage_finance', 'organization'),
  ('volunteer', 'manager',        'manage_finance', 'organization'),
  ('volunteer', 'deputy_manager', 'manage_finance', 'organization'),
  ('sponsor',   'sponsor',        'manage_finance', 'organization')
ON CONFLICT (kind, role, action) DO NOTHING;

-- ============================================================
-- 2. Convert delete_cost_entry (DROP+CREATE per RPC sig change rule)
-- ============================================================
DROP FUNCTION IF EXISTS public.delete_cost_entry(uuid);
CREATE OR REPLACE FUNCTION public.delete_cost_entry(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to delete cost entries';
  END IF;

  DELETE FROM public.cost_entries WHERE id = p_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_cost_entry(uuid) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.delete_cost_entry(uuid) IS
  'Phase B'' V4 conversion (ADR-0025, p59): manage_finance gate via can_by_member. Was V3 (is_superadmin OR manager).';

-- ============================================================
-- 3. Convert delete_revenue_entry
-- ============================================================
DROP FUNCTION IF EXISTS public.delete_revenue_entry(uuid);
CREATE OR REPLACE FUNCTION public.delete_revenue_entry(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to delete revenue entries';
  END IF;

  DELETE FROM public.revenue_entries WHERE id = p_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.delete_revenue_entry(uuid) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.delete_revenue_entry(uuid) IS
  'Phase B'' V4 conversion (ADR-0025, p59): manage_finance gate via can_by_member. Was V3 (is_superadmin OR manager).';

-- ============================================================
-- 4. Convert update_kpi_target
-- ============================================================
DROP FUNCTION IF EXISTS public.update_kpi_target(uuid, numeric, numeric, text);
CREATE OR REPLACE FUNCTION public.update_kpi_target(
  p_kpi_id uuid,
  p_target_value numeric,
  p_current_value numeric,
  p_notes text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to update KPI targets';
  END IF;

  UPDATE public.annual_kpi_targets SET
    target_value = COALESCE(p_target_value, target_value),
    current_value = COALESCE(p_current_value, current_value),
    notes = COALESCE(p_notes, notes),
    updated_at = now()
  WHERE id = p_kpi_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_kpi_target(uuid, numeric, numeric, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.update_kpi_target(uuid, numeric, numeric, text) IS
  'Phase B'' V4 conversion (ADR-0025, p59): manage_finance gate via can_by_member. Was V3 (is_superadmin OR manager).';

-- ============================================================
-- 5. Convert update_sustainability_kpi
-- ============================================================
DROP FUNCTION IF EXISTS public.update_sustainability_kpi(uuid, numeric, numeric, text);
CREATE OR REPLACE FUNCTION public.update_sustainability_kpi(
  p_id uuid,
  p_target_value numeric,
  p_current_value numeric,
  p_notes text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_member_id uuid;
BEGIN
  SELECT m.id INTO v_caller_member_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();
  IF v_caller_member_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required';
  END IF;

  IF NOT public.can_by_member(v_caller_member_id, 'manage_finance') THEN
    RAISE EXCEPTION 'permission_denied: manage_finance required to update sustainability KPIs';
  END IF;

  UPDATE public.sustainability_kpi_targets SET
    target_value = COALESCE(p_target_value, target_value),
    current_value = COALESCE(p_current_value, current_value),
    notes = COALESCE(p_notes, notes),
    updated_at = now()
  WHERE id = p_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.update_sustainability_kpi(uuid, numeric, numeric, text) FROM PUBLIC, anon;
COMMENT ON FUNCTION public.update_sustainability_kpi(uuid, numeric, numeric, text) IS
  'Phase B'' V4 conversion (ADR-0025, p59): manage_finance gate via can_by_member. Was V3 (is_superadmin OR manager).';

NOTIFY pgrst, 'reload schema';
