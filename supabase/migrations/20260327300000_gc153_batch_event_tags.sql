-- GC-153: Fix N+1 query — batch event tags RPC
-- Problem: loadEventTagMap() called get_event_tags(uuid) once per event
-- With 277 events = 277 concurrent RPCs → pool exhaustion → "Could not connect"

CREATE OR REPLACE FUNCTION public.get_event_tags_batch(p_event_ids uuid[])
RETURNS TABLE(event_id uuid, tag_id uuid, tag_name text, label_pt text, color text, tier tag_tier)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  RETURN QUERY
  SELECT eta.event_id, t.id, t.name, t.label_pt, t.color, t.tier
  FROM public.tags t
  JOIN public.event_tag_assignments eta ON eta.tag_id = t.id
  WHERE eta.event_id = ANY(p_event_ids)
  ORDER BY eta.event_id, t.display_order;
END; $$;

GRANT EXECUTE ON FUNCTION public.get_event_tags_batch(uuid[]) TO authenticated;
NOTIFY pgrst, 'reload schema';
