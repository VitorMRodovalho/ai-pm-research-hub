-- Phase B'' batch 18.1: link_attachment_to_governance V3 sa-only → V4 can_by_member('manage_platform')
-- V3: is_superadmin = true
-- V4: manage_platform (covers sa + manager/deputy_manager/co_gp)
-- Impact: V3=2, V4=2
CREATE OR REPLACE FUNCTION public.link_attachment_to_governance(p_attachment_id uuid, p_title text, p_signed_at timestamp with time zone DEFAULT now(), p_parties text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_member_id uuid; v_attachment record; v_doc_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL OR NOT public.can_by_member(v_member_id, 'manage_platform'::text) THEN
    RETURN jsonb_build_object('error', 'not_authorized');
  END IF;

  SELECT * INTO v_attachment FROM partner_attachments WHERE id = p_attachment_id;
  IF v_attachment IS NULL THEN RETURN jsonb_build_object('error', 'attachment_not_found'); END IF;

  INSERT INTO governance_documents (title, doc_type, status, pdf_url, partner_entity_id, signed_at, parties, valid_from)
  VALUES (p_title, 'cooperation_agreement', 'active', v_attachment.file_url,
    v_attachment.partner_entity_id, p_signed_at, p_parties, p_signed_at)
  RETURNING id INTO v_doc_id;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member_id, 'attachment_linked_to_governance', 'governance_document', v_doc_id,
    jsonb_build_object('attachment_id', p_attachment_id, 'title', p_title));

  RETURN jsonb_build_object('success', true, 'governance_document_id', v_doc_id);
END;
$function$;
