-- W139 Item 1: Create active_members view
-- Referenced by /workspace (tribe member counts) and attendance (member list)
-- GC-039: Formal definition of 'active member' criteria: is_active = true

CREATE OR REPLACE VIEW public.active_members AS
SELECT *
FROM public.members
WHERE is_active = true;

-- Grant access for the view
GRANT SELECT ON public.active_members TO authenticated;
GRANT SELECT ON public.active_members TO anon;

COMMENT ON VIEW public.active_members IS 'W139: Active members view. Criteria: is_active = true. Used by workspace dashboard and attendance module.';
