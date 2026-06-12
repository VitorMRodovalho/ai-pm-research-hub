-- get_pending_ratifications: sequential gate gating (display-only leak-fix)
--
-- Problem (live-diagnosed 2026-06-11): the volunteer-term chains expose gate 5
-- `volunteers_in_role_active` (threshold 'all') to every active volunteer. Because
-- gate `order` was declared but never enforced on the READ path, the term surfaced
-- as an actionable "Revisar e assinar" card to ~55 volunteers — including 25
-- pre-onboarding ciclo-4 guests whose filiação is unverified — while the upstream
-- gates submitter_acceptance (order 3) and president_go (order 4) were still unsigned
-- and the document was under governance review. (caso Flávio/Volvo + os outros 17.)
--
-- Fix (Option A, display-only, minimal blast radius): a gate is only included in
-- `eligible_gates` once ALL lower-`order` gates have met their threshold. Rows whose
-- eligible_gates collapses to empty are dropped (a "pending ratification" with no
-- currently-openable gate is not pending for that member). Threshold-met logic mirrors
-- `sign_ip_ratification` byte-for-byte (signoff_type IN ('approval','acknowledge');
-- 'all' = signoffs >= count of eligible signers; numeric = signoffs >= N; 0/other = met).
--
-- This does NOT touch `_can_sign_gate` or `sign_ip_ratification` — the WRITE path still
-- lacks ordering enforcement (a determined direct API call could still sign out of order
-- and mint a premature ratification certificate). That integrity hole is tracked as a
-- follow-up (Option B, requires security-engineer review since `_can_sign_gate` also gates
-- the cert_director_go chain shipped in ADR-0016 Amendment 4 / #650).

CREATE OR REPLACE FUNCTION public.get_pending_ratifications()
 RETURNS TABLE(chain_id uuid, document_id uuid, document_title text, doc_type text, version_id uuid, version_label text, version_locked_at timestamp with time zone, gates jsonb, opened_at timestamp with time zone, status text, eligible_gates text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
BEGIN
  SELECT m.id INTO v_member_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  WITH base AS (
    SELECT ac.id AS chain_id, gd.id AS document_id, gd.title AS document_title, gd.doc_type,
      dv.id AS version_id, dv.version_label, dv.locked_at AS version_locked_at,
      ac.gates, ac.opened_at, ac.status, ac.created_at AS created_at,
      (SELECT ARRAY_AGG(g->>'kind' ORDER BY (g->>'order')::int)
       FROM jsonb_array_elements(ac.gates) g
       WHERE public._can_sign_gate(v_member_id, ac.id, g->>'kind')
         AND NOT EXISTS (SELECT 1 FROM public.approval_signoffs s
           WHERE s.approval_chain_id = ac.id AND s.gate_kind = g->>'kind' AND s.signer_id = v_member_id)
         -- sequential gating: gate only openable once all lower-order gates met threshold
         AND NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(ac.gates) gp
           WHERE (gp->>'order')::int < (g->>'order')::int
             AND (
               ((gp->>'threshold') = 'all'
                 AND (SELECT count(*) FROM public.approval_signoffs s2
                      WHERE s2.approval_chain_id = ac.id AND s2.gate_kind = (gp->>'kind')
                        AND s2.signoff_type IN ('approval','acknowledge'))
                    < (SELECT count(*) FROM public.members m2
                       WHERE m2.is_active AND public._can_sign_gate(m2.id, ac.id, gp->>'kind')))
               OR
               ((gp->>'threshold') ~ '^[0-9]+$' AND (gp->>'threshold')::int > 0
                 AND (SELECT count(*) FROM public.approval_signoffs s2
                      WHERE s2.approval_chain_id = ac.id AND s2.gate_kind = (gp->>'kind')
                        AND s2.signoff_type IN ('approval','acknowledge'))
                    < (gp->>'threshold')::int)
             )
         )
      ) AS eligible_gates
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    JOIN public.document_versions dv ON dv.id = ac.version_id
    WHERE ac.status IN ('review','approved')
  )
  SELECT b.chain_id, b.document_id, b.document_title, b.doc_type, b.version_id, b.version_label,
    b.version_locked_at, b.gates, b.opened_at, b.status, b.eligible_gates
  FROM base b
  WHERE b.eligible_gates IS NOT NULL AND array_length(b.eligible_gates, 1) > 0
  ORDER BY b.opened_at DESC NULLS LAST, b.created_at DESC;
END;
$function$;
