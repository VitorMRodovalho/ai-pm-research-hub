-- ============================================================
-- p255 — Governance viewer hotfix: get_chain_workflow_detail returns content_html
-- ------------------------------------------------------------
-- WHAT: CREATE OR REPLACE public.get_chain_workflow_detail(p_chain_id uuid)
--   (same 1-arg signature, RETURNS jsonb, SECURITY DEFINER, search_path=public
--   preserved verbatim) — body extension:
--     1. v_chain SELECT INTO adds dv.content_html
--     2. RETURN jsonb_build_object gains 'content_html', v_chain.content_html
--   All other fields + body PRESERVED verbatim (chain id/status/gates/signers/
--   eligible_pending/days_open). Per-gate aggregate untouched.
--
-- WHY: Bug — Fernando Maquiaveli opening /governance/documents/<chainId>
--   (or external-reviewer path) sees "conteúdo indisponível" while export PDF
--   works. Console shows HTTP 406 on direct PostgREST SELECT to
--   document_versions.content_html. Cause: ReviewChainIsland.tsx fetches
--   chain detail via this RPC (OK) then does a SEPARATE client-side SELECT
--   on document_versions to fetch content_html — RLS denies the read for
--   users outside the document author / signer / SA roles. Export PDF path
--   uses a server-side route with elevated context, so it works.
--   PM-mandated fix path:
--     - Do NOT add allow-scripts to the viewer iframe (XSS risk).
--     - Do NOT broaden document_versions RLS generically (too coarse).
--     - Extend the existing SECDEF RPC. The auth model "anyone who can call
--       this RPC for this chain_id can also see the version content" is
--       consistent with the established pattern (get_previous_locked_version
--       and get_next_draft_version both already return content_html via
--       SECDEF).
--
-- SPEC DRIFT RESOLVED: none — bugfix.
--
-- ROLLBACK: re-apply the prior body from
--   supabase/migrations/20260684000000_p178_phase_b_drift_capture_1_touch_a_g_69fns.sql
--   Safe (same signature, additive field; payload omits content_html so UI
--   falls back to "(conteúdo indisponível)" placeholder).
--
-- INVARIANTS: 19/19=0 unchanged. No tables / FKs / RLS / triggers touched.
--   ACL preserved (CREATE OR REPLACE keeps EXECUTE grants intact).
--
-- SEDIMENT-246.B FOOTNOTE: body below matches live byte-for-byte
--   (post-apply_migration). Original draft had inline -- comments inside
--   the function body documenting "Submitter info" + "Per-gate aggregate"
--   sub-sections; apply_migration MCP silently strips inline -- inside
--   AS $$ ... $$. Replaced with live capture to keep Phase C body-drift
--   gate green. WHY documentation lives in this header instead.
--
-- CROSS-REF: HF2 of the p254 hotfix pair (same bundle PR).
--   HF1 (p254): boards initiative-leader gate (CPMAI/Fernando edit cards)
--   HF2 (this):  governance viewer content_html (CPMAI/Fernando read TAP)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_chain_workflow_detail(p_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_chain record;
  v_gates jsonb;
  v_signoffs jsonb;
  v_submitter jsonb;
BEGIN
  SELECT ac.id, ac.status, ac.gates, ac.document_id, ac.version_id, ac.opened_at, ac.opened_by,
         gd.title, gd.doc_type, dv.version_label, dv.locked_at, dv.content_html
  INTO v_chain
  FROM public.approval_chains ac
  JOIN public.governance_documents gd ON gd.id = ac.document_id
  LEFT JOIN public.document_versions dv ON dv.id = ac.version_id
  WHERE ac.id = p_chain_id;

  IF v_chain.id IS NULL THEN
    RETURN jsonb_build_object('error','chain_not_found');
  END IF;

  SELECT jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter, 'role', m.operational_role)
  INTO v_submitter
  FROM public.members m WHERE m.id = v_chain.opened_by;

  SELECT jsonb_agg(
    jsonb_build_object(
      'kind', g->>'kind',
      'order', (g->>'order')::int,
      'threshold', g->>'threshold',
      'signed_count', (
        SELECT COUNT(*) FROM public.approval_signoffs s
        WHERE s.approval_chain_id = v_chain.id
          AND s.gate_kind = g->>'kind'
          AND s.signoff_type IN ('approval','acknowledge')
      ),
      'signers', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'name', m.name,
          'chapter', m.chapter,
          'signed_at', s.signed_at,
          'signoff_type', s.signoff_type,
          'hash_short', SUBSTRING(s.signature_hash FROM 1 FOR 12)
        ) ORDER BY s.signed_at), '[]'::jsonb)
        FROM public.approval_signoffs s
        LEFT JOIN public.members m ON m.id = s.signer_id
        WHERE s.approval_chain_id = v_chain.id AND s.gate_kind = g->>'kind'
      ),
      'eligible_pending', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'chapter', m.chapter)
          ORDER BY m.name), '[]'::jsonb)
        FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, v_chain.id, g->>'kind')
          AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
            WHERE s.approval_chain_id = v_chain.id
              AND s.gate_kind = g->>'kind'
              AND s.signer_id = m.id)
      )
    ) ORDER BY (g->>'order')::int
  )
  INTO v_gates
  FROM jsonb_array_elements(v_chain.gates) g;

  RETURN jsonb_build_object(
    'chain_id', v_chain.id,
    'chain_status', v_chain.status,
    'document_id', v_chain.document_id,
    'document_title', v_chain.title,
    'doc_type', v_chain.doc_type,
    'version_id', v_chain.version_id,
    'version_label', v_chain.version_label,
    'locked_at', v_chain.locked_at,
    'content_html', v_chain.content_html,
    'opened_at', v_chain.opened_at,
    'submitter', v_submitter,
    'gates', COALESCE(v_gates, '[]'::jsonb),
    'days_open', CASE WHEN v_chain.opened_at IS NOT NULL
      THEN EXTRACT(EPOCH FROM (now() - v_chain.opened_at))/86400
      ELSE NULL END
  );
END;
$function$;

NOTIFY pgrst, 'reload schema';
