-- GC-164: search_hub_resources RPC (may already exist — CREATE OR REPLACE is safe)
CREATE OR REPLACE FUNCTION search_hub_resources(
  p_query text, p_asset_type text DEFAULT NULL, p_limit int DEFAULT 15
)
RETURNS TABLE(id uuid, title text, description text, url text, asset_type text, source text, tags text[], tribe_id int, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid() AND m.is_active = true) THEN RETURN; END IF;
  RETURN QUERY SELECT r.id, r.title, r.description, r.url, r.asset_type, r.source, r.tags, r.tribe_id, r.created_at
  FROM hub_resources r WHERE r.is_active = true
    AND (r.title ILIKE '%' || p_query || '%' OR r.description ILIKE '%' || p_query || '%'
      OR EXISTS (SELECT 1 FROM unnest(r.tags) t WHERE t ILIKE '%' || p_query || '%'))
    AND (p_asset_type IS NULL OR r.asset_type = p_asset_type)
  ORDER BY CASE WHEN r.title ILIKE '%' || p_query || '%' THEN 0 ELSE 1 END, r.created_at DESC
  LIMIT p_limit;
END; $$;
GRANT EXECUTE ON FUNCTION search_hub_resources TO authenticated;
NOTIFY pgrst, 'reload schema';
