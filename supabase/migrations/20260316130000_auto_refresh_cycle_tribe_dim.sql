-- Auto-refresh cycle_tribe_dim when base tables change
-- Triggers on: tribes, members (leader changes), member_cycle_history,
--              legacy_tribes, tribe_lineage, project_memberships
-- Date: 2026-03-16
-- ============================================================================

CREATE OR REPLACE FUNCTION public.trigger_refresh_cycle_tribe_dim()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.refresh_cycle_tribe_dim();
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- Tribes: new tribe, rename, activate/deactivate
DROP TRIGGER IF EXISTS trg_refresh_dim_on_tribes ON public.tribes;
CREATE TRIGGER trg_refresh_dim_on_tribes
  AFTER INSERT OR UPDATE OR DELETE ON public.tribes
  FOR EACH STATEMENT EXECUTE FUNCTION public.trigger_refresh_cycle_tribe_dim();

-- Members: leader assignment, tribe change
DROP TRIGGER IF EXISTS trg_refresh_dim_on_members ON public.members;
CREATE TRIGGER trg_refresh_dim_on_members
  AFTER UPDATE OF operational_role, tribe_id, is_active, photo_url ON public.members
  FOR EACH STATEMENT EXECUTE FUNCTION public.trigger_refresh_cycle_tribe_dim();

-- Member cycle history: historical data corrections
DROP TRIGGER IF EXISTS trg_refresh_dim_on_history ON public.member_cycle_history;
CREATE TRIGGER trg_refresh_dim_on_history
  AFTER INSERT OR UPDATE OR DELETE ON public.member_cycle_history
  FOR EACH STATEMENT EXECUTE FUNCTION public.trigger_refresh_cycle_tribe_dim();

-- Legacy tribes: curated legacy records
DROP TRIGGER IF EXISTS trg_refresh_dim_on_legacy_tribes ON public.legacy_tribes;
CREATE TRIGGER trg_refresh_dim_on_legacy_tribes
  AFTER INSERT OR UPDATE OR DELETE ON public.legacy_tribes
  FOR EACH STATEMENT EXECUTE FUNCTION public.trigger_refresh_cycle_tribe_dim();

-- Tribe lineage: parent relationships
DROP TRIGGER IF EXISTS trg_refresh_dim_on_lineage ON public.tribe_lineage;
CREATE TRIGGER trg_refresh_dim_on_lineage
  AFTER INSERT OR UPDATE OR DELETE ON public.tribe_lineage
  FOR EACH STATEMENT EXECUTE FUNCTION public.trigger_refresh_cycle_tribe_dim();
