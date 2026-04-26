-- INCIDENT p64 — revert Sarah's accidental signoff on Adendo IP
--
-- Context: 2026-04-26, hotfix incident (auth_org/can_by_member REVOKE) caused
-- /governance/ip-agreement to render "(conteúdo indisponível)" instead of
-- document content. Sarah Faria (member 19b7ff75-bcb1-4a15-a8e1-006fc6822069,
-- curator) clicked the sign button trying to make the document load — this
-- registered an unintended signoff at 23:04:10 UTC on chain 47362201
-- (Adendo de Propriedade Intelectual aos Acordos de Cooperação, gate=curator).
--
-- Per CC Art. 138 (vício de consentimento por erro) the act was induced by
-- a system bug rather than expressed intent. Per LGPD Art. 9 (informação
-- adequada) the data subject was not properly informed of what she was
-- signing because the document body did not render.
--
-- PM ratified Opção A (Vitor 2026-04-26): DELETE the approval_signoffs row
-- so Sarah can re-sign after reading the actual content. The original
-- audit_log entry (admin_audit_log id e3022999-...) is preserved as evidence
-- of the incident; this migration adds a new audit_log entry documenting
-- the revert with full context.
--
-- Effect:
--   * approval_signoffs row e3022999-8e9a-4b4d-a23f-7774e905cf43 → DELETED
--   * No certificate was issued (gate=curator, not member_ratification)
--   * No member_document_signatures row was created (only created for
--     member_ratification or volunteers_in_role_active gates)
--   * Chain status remains 'review' (was already 'review', threshold 'all'
--     for curator gate not yet satisfied — only 1 of N curator signatures)
--   * admin_audit_log entry added documenting the revert + reason

DO $$
DECLARE
  v_existed boolean;
  v_chain_id uuid := '47362201-23e0-4e2d-96c5-4019b936331e';
  v_signoff_id uuid := 'e3022999-8e9a-4b4d-a23f-7774e905cf43';
  v_member_id uuid := '19b7ff75-bcb1-4a15-a8e1-006fc6822069';
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.approval_signoffs WHERE id = v_signoff_id) INTO v_existed;
  IF NOT v_existed THEN
    RAISE NOTICE 'Signoff % already removed; recording audit only', v_signoff_id;
  ELSE
    DELETE FROM public.approval_signoffs WHERE id = v_signoff_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    NULL,
    'ip_ratification_signoff_reverted',
    'approval_signoff',
    v_signoff_id,
    jsonb_build_object(
      'chain_id', v_chain_id,
      'gate_kind', 'curator',
      'document_id', '41de16e2-4f2e-4eac-b63e-8f0b45b22629',
      'document_title', 'Adendo de Propriedade Intelectual aos Acordos de Cooperação',
      'reverted_member_id', v_member_id,
      'reverted_member_name', 'Sarah Faria Alcantara Macedo Rodovalho',
      'original_signed_at', '2026-04-26 23:04:10.521347+00',
      'original_audit_log_id', 'e3022999-8e9a-4b4d-a23f-7774e905cf43',
      'revert_reason', 'incident_p64_doc_did_not_render',
      'incident_summary',
      'auth_org/can_by_member EXECUTE was REVOKE''d from authenticated by Track Q-D batch 3b migration 20260426145632 at 14:56 UTC. RLS policies could not evaluate, all PostgREST authenticated table reads failed silently. /governance/ip-agreement document_versions read returned null → page rendered "(conteúdo indisponível)". Member tried to load doc by clicking, accidentally triggered signoff. Hotfix migrations 20260426232108 + 20260426232200 restored grants. PM ratified revert per CC Art. 138 (vício de consentimento por erro) + LGPD Art. 9 (informação adequada).',
      'pm_ratify', 'Vitor Maia Rodovalho 2026-04-26',
      'restoration_path', 'Sarah may re-sign at /governance/ip-agreement?chain_id=47362201-23e0-4e2d-96c5-4019b936331e&gate_kind=curator after reviewing document content'
    )
  );
END $$;
