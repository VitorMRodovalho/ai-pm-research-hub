-- ============================================================================
-- GC-138: CR Approval Workflow — Sprint 2 "Autoridade"
-- cr_approvals table + 3 RPCs + notifications integration
-- ============================================================================

-- PART 1: cr_approvals table
CREATE TABLE IF NOT EXISTS cr_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cr_id uuid NOT NULL REFERENCES change_requests(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES members(id),
  action text NOT NULL CHECK (action IN ('approved', 'rejected', 'abstained')),
  comment text,
  signature_hash text NOT NULL,
  signed_ip inet,
  signed_user_agent text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(cr_id, member_id)
);

CREATE INDEX IF NOT EXISTS idx_cr_approvals_cr ON cr_approvals(cr_id);
CREATE INDEX IF NOT EXISTS idx_cr_approvals_member ON cr_approvals(member_id);

ALTER TABLE cr_approvals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cr_approvals_read_authenticated ON cr_approvals;
CREATE POLICY cr_approvals_read_authenticated ON cr_approvals
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS cr_approvals_insert_sponsors ON cr_approvals;
CREATE POLICY cr_approvals_insert_sponsors ON cr_approvals
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM members
      WHERE auth_id = auth.uid()
      AND (operational_role = 'sponsor' OR is_superadmin = true)
    )
  );

GRANT SELECT, INSERT ON cr_approvals TO authenticated;

-- PART 2: approve_change_request RPC
DROP FUNCTION IF EXISTS approve_change_request(uuid, text, text, inet, text);
CREATE OR REPLACE FUNCTION approve_change_request(
  p_cr_id uuid, p_action text, p_comment text DEFAULT NULL,
  p_ip inet DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid; v_member_name text; v_member_role text; v_is_superadmin boolean;
  v_cr record; v_hash text;
  v_total_sponsors int; v_total_approvals int; v_quorum_needed int; v_quorum_met boolean;
BEGIN
  SELECT id, name, operational_role, is_superadmin
  INTO v_member_id, v_member_name, v_member_role, v_is_superadmin
  FROM members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF v_member_role != 'sponsor' AND COALESCE(v_is_superadmin, false) != true THEN
    RETURN jsonb_build_object('error', 'not_authorized'); END IF;
  IF p_action NOT IN ('approved', 'rejected', 'abstained') THEN
    RETURN jsonb_build_object('error', 'invalid_action'); END IF;
  SELECT * INTO v_cr FROM change_requests WHERE id = p_cr_id;
  IF v_cr IS NULL THEN RETURN jsonb_build_object('error', 'cr_not_found'); END IF;
  IF v_cr.status NOT IN ('submitted', 'proposed', 'under_review', 'open', 'pending_review', 'in_review') THEN
    RETURN jsonb_build_object('error', 'cr_not_approvable', 'status', v_cr.status); END IF;

  v_hash := encode(sha256(convert_to(
    p_cr_id::text || v_member_id::text || p_action || now()::text || 'nucleo-ia-governance-salt', 'UTF8'
  )), 'hex');

  INSERT INTO cr_approvals (cr_id, member_id, action, comment, signature_hash, signed_ip, signed_user_agent)
  VALUES (p_cr_id, v_member_id, p_action, p_comment, v_hash, p_ip, p_user_agent)
  ON CONFLICT (cr_id, member_id)
  DO UPDATE SET action = EXCLUDED.action, comment = EXCLUDED.comment,
    signature_hash = EXCLUDED.signature_hash, signed_ip = EXCLUDED.signed_ip,
    signed_user_agent = EXCLUDED.signed_user_agent, created_at = now();

  UPDATE change_requests SET approved_by_members = (
    SELECT array_agg(DISTINCT member_id) FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved'
  ), status = CASE WHEN status IN ('submitted','open','pending_review') THEN 'under_review' ELSE status END
  WHERE id = p_cr_id;

  SELECT count(*) INTO v_total_sponsors FROM members WHERE operational_role = 'sponsor' AND is_active = true;
  SELECT count(*) INTO v_total_approvals FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved';
  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);
  v_quorum_met := v_total_approvals >= v_quorum_needed;

  IF v_quorum_met THEN
    UPDATE change_requests SET status = 'approved', approved_at = now() WHERE id = p_cr_id AND status != 'approved';
    INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
    VALUES (v_member_id, 'cr_approved_quorum', 'change_request', p_cr_id,
      jsonb_build_object('cr_number', v_cr.cr_number, 'approvals', v_total_approvals, 'quorum', v_quorum_needed));
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_approved', v_cr.cr_number || ' aprovado por quorum!',
      v_cr.title || ' aprovado com ' || v_total_approvals || '/' || v_quorum_needed || ' votos.',
      '/governance', 'change_request', p_cr_id
    FROM members m WHERE (m.operational_role IN ('sponsor','manager') OR m.is_superadmin = true) AND m.is_active = true;
  ELSE
    INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
    SELECT m.id, 'governance_cr_vote', v_cr.cr_number || ': ' || v_member_name || ' votou ' || p_action,
      v_cr.title, '/governance', 'change_request', p_cr_id
    FROM members m WHERE m.operational_role = 'sponsor' AND m.is_active = true AND m.id != v_member_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'action', p_action, 'signature_hash', v_hash,
    'approvals', v_total_approvals, 'quorum_needed', v_quorum_needed, 'quorum_met', v_quorum_met,
    'cr_status', CASE WHEN v_quorum_met THEN 'approved' ELSE 'under_review' END);
END;
$$;

GRANT EXECUTE ON FUNCTION approve_change_request(uuid, text, text, inet, text) TO authenticated;

-- PART 3: get_cr_approval_status RPC
DROP FUNCTION IF EXISTS get_cr_approval_status(uuid);
CREATE OR REPLACE FUNCTION get_cr_approval_status(p_cr_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE v_total_sponsors int; v_quorum_needed int; result jsonb;
BEGIN
  SELECT count(*) INTO v_total_sponsors FROM members WHERE operational_role = 'sponsor' AND is_active = true;
  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);
  SELECT jsonb_build_object(
    'cr_id', p_cr_id, 'total_sponsors', v_total_sponsors, 'quorum_needed', v_quorum_needed,
    'approval_count', (SELECT count(*) FROM cr_approvals WHERE cr_id = p_cr_id AND action = 'approved'),
    'sponsors', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id, 'name', m.name,
        'has_voted', EXISTS (SELECT 1 FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id),
        'vote', (SELECT a.action FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id),
        'comment', (SELECT a.comment FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id),
        'signed_at', (SELECT a.created_at FROM cr_approvals a WHERE a.cr_id = p_cr_id AND a.member_id = m.id)
      ) ORDER BY m.name) FROM members m WHERE m.operational_role = 'sponsor' AND m.is_active = true
    ), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_cr_approval_status(uuid) TO authenticated;

-- PART 4: get_governance_dashboard RPC
DROP FUNCTION IF EXISTS get_governance_dashboard();
CREATE OR REPLACE FUNCTION get_governance_dashboard()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_member_id uuid; v_member_name text; v_is_sponsor boolean; v_is_superadmin boolean;
  v_total_sponsors int; v_quorum_needed int; result jsonb;
BEGIN
  SELECT id, name, (operational_role = 'sponsor'), is_superadmin
  INTO v_member_id, v_member_name, v_is_sponsor, v_is_superadmin
  FROM members WHERE auth_id = auth.uid();
  SELECT count(*) INTO v_total_sponsors FROM members WHERE operational_role = 'sponsor' AND is_active = true;
  v_quorum_needed := GREATEST(CEIL(v_total_sponsors::numeric * 3 / 5), 1);

  SELECT jsonb_build_object(
    'member_name', v_member_name, 'is_sponsor', COALESCE(v_is_sponsor, false),
    'is_superadmin', COALESCE(v_is_superadmin, false),
    'can_approve', COALESCE(v_is_sponsor, false) OR COALESCE(v_is_superadmin, false),
    'total_sponsors', v_total_sponsors, 'quorum_needed', v_quorum_needed,
    'stats', jsonb_build_object(
      'total_crs', (SELECT count(*) FROM change_requests WHERE status NOT IN ('withdrawn','cancelled')),
      'pending', (SELECT count(*) FROM change_requests WHERE status IN ('submitted','proposed','under_review','open','pending_review','in_review')),
      'approved', (SELECT count(*) FROM change_requests WHERE status = 'approved'),
      'implemented', (SELECT count(*) FROM change_requests WHERE status = 'implemented'),
      'rejected', (SELECT count(*) FROM change_requests WHERE status = 'rejected')
    ),
    'pending_crs', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cr.id, 'cr_number', cr.cr_number, 'title', cr.title, 'category', cr.category,
        'priority', cr.priority, 'status', cr.status, 'description', cr.description,
        'justification', cr.justification, 'proposed_changes', cr.proposed_changes,
        'impact_level', cr.impact_level, 'impact_description', cr.impact_description,
        'submitted_at', cr.submitted_at,
        'my_vote', (SELECT action FROM cr_approvals WHERE cr_id = cr.id AND member_id = v_member_id),
        'approval_count', (SELECT count(*) FROM cr_approvals WHERE cr_id = cr.id AND action = 'approved'),
        'total_votes', (SELECT count(*) FROM cr_approvals WHERE cr_id = cr.id)
      ) ORDER BY CASE cr.priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END, cr.cr_number)
      FROM change_requests cr
      WHERE cr.status IN ('submitted','proposed','under_review','open','pending_review','in_review')
    ), '[]'::jsonb),
    'recent_approved', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cr.id, 'cr_number', cr.cr_number, 'title', cr.title, 'category', cr.category, 'approved_at', cr.approved_at
      ) ORDER BY cr.approved_at DESC NULLS LAST)
      FROM (SELECT * FROM change_requests WHERE status = 'approved' LIMIT 10) cr
    ), '[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_governance_dashboard() TO authenticated;
NOTIFY pgrst, 'reload schema';
