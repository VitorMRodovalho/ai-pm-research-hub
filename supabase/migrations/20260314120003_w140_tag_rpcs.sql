-- ============================================================
-- W140 BLOCO 4: Tag CRUD RPCs + Audience RPCs
-- ============================================================

-- Create tag
CREATE OR REPLACE FUNCTION public.create_tag(
  p_name text, p_label_pt text, p_color text DEFAULT '#6B7280',
  p_tier text DEFAULT 'semantic', p_domain text DEFAULT 'all',
  p_description text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_id uuid; v_caller_id uuid; v_member record;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_member FROM public.members WHERE auth_id = v_caller_id LIMIT 1;

  IF p_tier = 'system' THEN
    RAISE EXCEPTION 'System tags can only be created via migrations';
  ELSIF p_tier = 'administrative' THEN
    IF NOT (v_member.is_superadmin OR v_member.operational_role IN ('manager','deputy_manager')) THEN
      RAISE EXCEPTION 'Only admins/GP can create administrative tags';
    END IF;
  ELSIF p_tier = 'semantic' THEN
    IF NOT (v_member.is_superadmin OR v_member.operational_role IN ('manager','deputy_manager','tribe_leader')) THEN
      RAISE EXCEPTION 'Only admins/GP/tribe leaders can create semantic tags';
    END IF;
  END IF;

  INSERT INTO public.tags (name, label_pt, color, tier, domain, description, display_order, created_by)
  VALUES (p_name, p_label_pt, p_color, p_tier::tag_tier, p_domain::tag_domain, p_description,
    (SELECT COALESCE(MAX(display_order),0)+1 FROM public.tags), v_member.id)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

-- Delete tag (non-system only)
CREATE OR REPLACE FUNCTION public.delete_tag(p_tag_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_tag record;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_tag FROM public.tags WHERE id = p_tag_id;
  IF v_tag IS NULL THEN RAISE EXCEPTION 'Tag not found'; END IF;
  IF v_tag.tier = 'system' THEN RAISE EXCEPTION 'System tags cannot be deleted'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.members WHERE auth_id = auth.uid()
    AND (is_superadmin = true OR operational_role IN ('manager','deputy_manager'))
  ) THEN RAISE EXCEPTION 'Only admins/GP can delete tags'; END IF;
  DELETE FROM public.tags WHERE id = p_tag_id;
END; $$;

-- Assign tags to event (replaces all existing)
CREATE OR REPLACE FUNCTION public.assign_event_tags(p_event_id uuid, p_tag_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_tid uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  DELETE FROM public.event_tag_assignments WHERE event_id = p_event_id;
  FOREACH v_tid IN ARRAY p_tag_ids LOOP
    INSERT INTO public.event_tag_assignments (event_id, tag_id)
    VALUES (p_event_id, v_tid) ON CONFLICT DO NOTHING;
  END LOOP;
END; $$;

-- Set event audience rules (replaces all existing)
CREATE OR REPLACE FUNCTION public.set_event_audience(p_event_id uuid, p_rules jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_rule jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  DELETE FROM public.event_audience_rules WHERE event_id = p_event_id;
  FOR v_rule IN SELECT * FROM jsonb_array_elements(p_rules) LOOP
    INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
    VALUES (p_event_id, v_rule->>'attendance_type', v_rule->>'target_type', v_rule->>'target_value');
  END LOOP;
END; $$;

-- Set event invited members (replaces all existing)
CREATE OR REPLACE FUNCTION public.set_event_invited_members(p_event_id uuid, p_members jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_m jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  DELETE FROM public.event_invited_members WHERE event_id = p_event_id;
  FOR v_m IN SELECT * FROM jsonb_array_elements(p_members) LOOP
    INSERT INTO public.event_invited_members (event_id, member_id, attendance_type, notes)
    VALUES (p_event_id, (v_m->>'member_id')::uuid, COALESCE(v_m->>'attendance_type','mandatory'), v_m->>'notes');
  END LOOP;
END; $$;

-- Get all tags (with usage counts)
CREATE OR REPLACE FUNCTION public.get_tags(p_domain text DEFAULT NULL)
RETURNS TABLE (id uuid, name text, label_pt text, color text, tier tag_tier, domain tag_domain,
  description text, display_order integer, event_count bigint, board_item_count bigint)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT t.id, t.name, t.label_pt, t.color, t.tier, t.domain, t.description, t.display_order,
    (SELECT count(*) FROM public.event_tag_assignments eta WHERE eta.tag_id = t.id),
    (SELECT count(*) FROM public.board_item_tag_assignments bita WHERE bita.tag_id = t.id)
  FROM public.tags t
  WHERE (p_domain IS NULL OR t.domain = p_domain::tag_domain OR t.domain = 'all')
  ORDER BY t.display_order;
END; $$;

-- Get event with its tags
CREATE OR REPLACE FUNCTION public.get_event_tags(p_event_id uuid)
RETURNS TABLE (tag_id uuid, tag_name text, label_pt text, color text, tier tag_tier)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT t.id, t.name, t.label_pt, t.color, t.tier
  FROM public.tags t
  JOIN public.event_tag_assignments eta ON eta.tag_id = t.id
  WHERE eta.event_id = p_event_id
  ORDER BY t.display_order;
END; $$;

-- Get event audience rules
CREATE OR REPLACE FUNCTION public.get_event_audience(p_event_id uuid)
RETURNS TABLE (
  rule_id uuid, attendance_type text, target_type text, target_value text,
  invited_members jsonb
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT ear.id, ear.attendance_type, ear.target_type, ear.target_value,
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'member_id', eim.member_id,
        'member_name', m.name,
        'attendance_type', eim.attendance_type,
        'notes', eim.notes
      ))
      FROM public.event_invited_members eim
      JOIN public.members m ON m.id = eim.member_id
      WHERE eim.event_id = p_event_id
    ), '[]'::jsonb)
  FROM public.event_audience_rules ear
  WHERE ear.event_id = p_event_id;
END; $$;

GRANT EXECUTE ON FUNCTION public.create_tag TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_tag TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_event_tags TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_event_audience TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_event_invited_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_tags TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_event_tags TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_event_audience TO authenticated;
