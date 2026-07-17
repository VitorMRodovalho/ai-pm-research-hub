-- #1383 Wave 5 (governance/docs/certificates) — raw-side hardening.
--
-- (1) submit_change_request: the INSERT set change_requests.priority = p_impact_level, but the
--     priority CHECK is (high|medium|low) while impact_level CHECK is (low|medium|high|critical).
--     A CR with impact_level='critical' therefore ALWAYS failed with
--     "new row violates check constraint change_requests_priority_check" (proven live 2026-07-17,
--     rolled back). Clamp critical→high for the priority slot only; the impact_level column keeps
--     the true 'critical' value. Body otherwise byte-identical to the live definition.
--
-- (2) anon/PUBLIC EXECUTE drift on the governance/certificate WRITE RPCs. All of these resolve the
--     caller via `members WHERE auth_id = auth.uid()` and deny on NULL, so they are already
--     FAIL-CLOSED for anon (audited live 2026-07-17 — dead surface, not an exploit). REVOKE the
--     unnecessary anon/PUBLIC grants as defense-in-depth (#965 trap; W4 recalculate_cycle_rankings
--     precedent). `authenticated` + `service_role` keep their explicit grants, so the app/UI/EF
--     paths are unchanged.

CREATE OR REPLACE FUNCTION public.submit_change_request(p_title text, p_description text, p_cr_type text, p_manual_section_ids uuid[] DEFAULT NULL::uuid[], p_gc_references text[] DEFAULT NULL::text[], p_impact_level text DEFAULT 'medium'::text, p_impact_description text DEFAULT NULL::text, p_justification text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_caller record; v_mid uuid; v_crn text; v_nid uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  -- p200 ADR-0087: curator V3 designation → V4 can_by_member('curate_content')
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager','deputy_manager','tribe_leader')
    AND NOT public.can_by_member(v_mid, 'curate_content')
  THEN RETURN jsonb_build_object('error','Unauthorized'); END IF;
  IF p_cr_type NOT IN ('editorial','operational','structural','emergency') THEN
    RETURN jsonb_build_object('error','Invalid cr_type'); END IF;
  SELECT 'CR-'||LPAD((COALESCE(MAX(SUBSTRING(cr_number FROM 4)::int),0)+1)::text,3,'0')
    INTO v_crn FROM change_requests WHERE cr_number ~ '^CR-\d+$';
  INSERT INTO change_requests (
    cr_number,title,description,cr_type,status,priority,
    manual_section_ids,gc_references,impact_level,impact_description,justification,
    requested_by,requested_by_role,submitted_at,manual_version_from,created_at,updated_at
  ) VALUES (
    v_crn,p_title,p_description,p_cr_type,'submitted',CASE WHEN p_impact_level = 'critical' THEN 'high' ELSE p_impact_level END,
    p_manual_section_ids,p_gc_references,p_impact_level,p_impact_description,p_justification,
    v_mid,v_caller.operational_role,now(),'R2',now(),now()
  ) RETURNING id INTO v_nid;
  RETURN jsonb_build_object('success',true,'id',v_nid,'cr_number',v_crn);
END; $function$;

-- (2) REVOKE anon/PUBLIC EXECUTE on governance/certificate write RPCs (all fail-closed for anon).
REVOKE EXECUTE ON FUNCTION public.issue_certificate(jsonb) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_certificate(uuid, jsonb) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.counter_sign_certificate(uuid, text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_change_request(text, text, text, uuid[], text[], text, text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.upsert_document_version(uuid, text, text, text, uuid, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_document_version_draft(uuid) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lock_document_version(uuid, jsonb, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.recirculate_governance_doc(uuid, boolean, text[]) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sign_ip_ratification(uuid, text, text, jsonb, text, boolean) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cancel_manual_version_proposal(uuid, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirm_manual_version(uuid) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.propose_manual_version(text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.resolve_document_comment(uuid, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_document_comment(uuid, text, text, text, uuid) FROM anon, PUBLIC;

NOTIFY pgrst, 'reload schema';
