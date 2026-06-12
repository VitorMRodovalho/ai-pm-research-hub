-- 20260805000153_pending_ratifications_sequential_gating.sql
--
-- GC-097 RECOVERY (#656) — local-file capture of DDL already applied to prod.
--
-- This version was registered in supabase_migrations.schema_migrations
-- (name: pending_ratifications_sequential_gating) by the #648/#653 volunteer-
-- term-immutability work via apply_migration MCP WITHOUT the GC-097 manual
-- file sync. Result: two CI drift gates on main went red —
--   (1) ADR-0097 missing-file: version 153 tracked but no local .sql.
--   (2) Phase C body-hash: latest CREATE FUNCTION capture of
--       get_pending_ratifications was the pre-sequential 908-char body
--       (20260684000000_p178…) vs the live 2360-char sequential-gating body.
--
-- The body below is verbatim pg_get_functiondef() from the live DB (prod),
-- so re-running this migration is an idempotent no-op against production.
-- It exists to make the local migration history match deployed state.
--
-- What the sequential-gating logic adds vs the prior body: a per-candidate-gate
-- prior-gate-satisfaction guard (the inner `NOT EXISTS … gp WHERE order < …`
-- block) so a gate is only "eligible" once all earlier-ordered gates have met
-- their threshold ('all' = every eligible signer; numeric = N signoffs).

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
$function$
;
