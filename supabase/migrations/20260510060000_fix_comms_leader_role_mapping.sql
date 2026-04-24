-- =============================================================================
-- Fix comms_leader role mapping drift (ADR-0023)
-- =============================================================================
-- Issue: latent drift surfaced durante elaboração de ADR-0023
--   sync_operational_role_cache()  : volunteer × comms_leader → 'comms_leader'
--   check_schema_invariants().A3   : volunteer × comms_leader → 'tribe_leader'
--
-- Impact: 0 rows atualmente (nenhum auth_engagements com role=comms_leader
-- e is_authoritative=true em prod). Time-bomb: próximo INSERT com esse role
-- dispararia violation A3.
--
-- Decisão ADR-0023 (Appendix A): tribe_leader é canonical. comms_leader é
-- um sub-tipo de tribe leader (lidera Tribo 1 / Hub de Comunicação) —
-- separar no cache quebra buscas que pedem "todos os tribe leaders".
--
-- Este patch alinha sync_operational_role_cache() com invariant A3.
-- Rollback: re-CREATE com 'comms_leader' retorno literal.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sync_operational_role_cache()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_member_id uuid;
  v_new_role text;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE person_id = COALESCE(NEW.person_id, OLD.person_id);
  IF v_member_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  SELECT CASE
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'leader')         THEN 'tribe_leader'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'comms_leader')   THEN 'tribe_leader'  -- ADR-0023: canonical (was 'comms_leader', drift with invariant A3)
      WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('researcher', 'facilitator', 'communicator', 'curator')) THEN 'researcher'
      WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
      WHEN bool_or(ae.kind = 'observer') THEN 'observer'
      WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
      WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
      WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
      WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
      ELSE 'guest'
    END INTO v_new_role
  FROM public.auth_engagements ae
  WHERE ae.person_id = COALESCE(NEW.person_id, OLD.person_id) AND ae.is_authoritative = true;

  UPDATE public.members SET operational_role = COALESCE(v_new_role, 'guest'), updated_at = now()
    WHERE id = v_member_id AND operational_role IS DISTINCT FROM COALESCE(v_new_role, 'guest');

  RETURN COALESCE(NEW, OLD);
END;
$fn$;

COMMENT ON FUNCTION public.sync_operational_role_cache() IS
  'Trigger function: reconciles members.operational_role from auth_engagements. '
  'ADR-0023 defines the canonical priority ladder. ADR-0011 Amendment A references this cache for fast-path. '
  'Invariant parity rule: any change to the CASE MUST be replicated in check_schema_invariants().A3 in same commit.';

NOTIFY pgrst, 'reload schema';
