-- ============================================================
-- W140 BLOCO 3: Data migration for existing events
-- Assigns tags based on events.type and creates audience rules
-- ============================================================

-- STEP 1: Assign tags based on events.type
INSERT INTO public.event_tag_assignments (event_id, tag_id)
SELECT e.id, t.id
FROM public.events e
JOIN public.tags t ON t.name = e.type AND t.domain IN ('event', 'all')
WHERE e.type IS NOT NULL
ON CONFLICT (event_id, tag_id) DO NOTHING;

-- STEP 2: Kickoff also gets 'general_meeting' tag (if kickoff event exists)
INSERT INTO public.event_tag_assignments (event_id, tag_id)
SELECT e.id, t.id
FROM public.events e
CROSS JOIN public.tags t
WHERE e.type = 'kickoff' AND t.name = 'general_meeting' AND t.domain IN ('event', 'all')
ON CONFLICT (event_id, tag_id) DO NOTHING;

-- STEP 3: Default audience rules by type

-- general_meeting -> mandatory all_active_operational
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type)
SELECT e.id, 'mandatory', 'all_active_operational'
FROM public.events e WHERE e.type = 'general_meeting'
ON CONFLICT DO NOTHING;

-- tribe_meeting -> mandatory for tribe
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
SELECT e.id, 'mandatory', 'tribe', e.tribe_id::text
FROM public.events e WHERE e.type = 'tribe_meeting' AND e.tribe_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- leadership_meeting -> mandatory for manager, deputy_manager, tribe_leader
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type, target_value)
SELECT e.id, 'mandatory', 'role', r.role_name
FROM public.events e
CROSS JOIN (VALUES ('manager'), ('deputy_manager'), ('tribe_leader')) AS r(role_name)
WHERE e.type = 'leadership_meeting'
ON CONFLICT DO NOTHING;

-- kickoff -> mandatory all_active_operational
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type)
SELECT e.id, 'mandatory', 'all_active_operational'
FROM public.events e WHERE e.type = 'kickoff'
ON CONFLICT DO NOTHING;

-- interview -> specific_members only
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type)
SELECT e.id, 'mandatory', 'specific_members'
FROM public.events e WHERE e.type = 'interview'
ON CONFLICT DO NOTHING;

-- external_event -> optional
INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type)
SELECT e.id, 'optional', 'all_active_operational'
FROM public.events e WHERE e.type = 'external_event'
ON CONFLICT DO NOTHING;

-- STEP 4: Fix "Conversar projeto Nucleo" -> alignment + specific_members
DELETE FROM public.event_audience_rules
WHERE event_id IN (SELECT id FROM public.events WHERE title LIKE '%Conversar projeto Nucleo%')
AND target_type = 'all_active_operational';

INSERT INTO public.event_audience_rules (event_id, attendance_type, target_type)
SELECT id, 'mandatory', 'specific_members'
FROM public.events WHERE title LIKE '%Conversar projeto Nucleo%'
ON CONFLICT DO NOTHING;

-- Add GP/DM as mandatory attendees for alignment meetings
INSERT INTO public.event_invited_members (event_id, member_id, attendance_type, notes)
SELECT e.id, m.id, 'mandatory', 'Reunião de alinhamento GP'
FROM public.events e
CROSS JOIN public.members m
WHERE e.title LIKE '%Conversar projeto Nucleo%'
  AND m.operational_role IN ('manager', 'deputy_manager')
  AND m.is_active = true
ON CONFLICT (event_id, member_id) DO NOTHING;

-- Replace general_meeting tag with alignment tag for those events
DELETE FROM public.event_tag_assignments
WHERE event_id IN (SELECT id FROM public.events WHERE title LIKE '%Conversar projeto Nucleo%')
AND tag_id = (SELECT id FROM public.tags WHERE name = 'general_meeting' AND domain IN ('event', 'all') LIMIT 1);

INSERT INTO public.event_tag_assignments (event_id, tag_id)
SELECT e.id, t.id
FROM public.events e CROSS JOIN public.tags t
WHERE e.title LIKE '%Conversar projeto Nucleo%' AND t.name = 'alignment'
ON CONFLICT (event_id, tag_id) DO NOTHING;
