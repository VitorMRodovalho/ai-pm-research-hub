-- #889: cache Instagram media thumbnails into a public Storage bucket, instead of
-- storing expiring cdninstagram signed URLs (and null thumbnails for image posts).
-- Public bucket: the content is thumbnails of ALREADY-public social posts; the stable
-- public URL is loadable by <img> and is already covered by CSP img-src for supabase.co.

-- 1) public bucket (mirrors the 'documents'/'member-photos' public-bucket precedent)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('comms-media', 'comms-media', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- public read; writes are service-role only (the sync EF), which bypasses RLS
DROP POLICY IF EXISTS "comms_media_public_read" ON storage.objects;
CREATE POLICY "comms_media_public_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'comms-media');

-- 2) cached URL column. Set by sync-comms-metrics AFTER uploading to Storage; the
-- metrics upsert never writes this column, so it survives across daily syncs.
ALTER TABLE public.comms_media_items ADD COLUMN IF NOT EXISTS cached_image_url text;

-- 3) surface cached_image_url through the gated top-media RPC (frontend prefers it
-- over the raw thumbnail_url). Signature unchanged; gate unchanged.
CREATE OR REPLACE FUNCTION public.comms_top_media(p_channel text DEFAULT NULL::text, p_days integer DEFAULT 30, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.can_view_comms_analytics() THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(jsonb_agg(row_to_json(r) ORDER BY r.engagement_score DESC), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT m.channel, m.external_id, m.media_type,
      LEFT(m.caption, 120) as caption, m.permalink, m.thumbnail_url, m.cached_image_url,
      m.published_at, m.likes, m.comments, m.shares, m.saves, m.reach, m.views,
      (COALESCE(m.likes,0) + COALESCE(m.comments,0)*2 + COALESCE(m.shares,0)*3 + COALESCE(m.saves,0)*2) as engagement_score
    FROM public.comms_media_items m
    WHERE (p_channel IS NULL OR m.channel = p_channel)
      AND m.published_at >= NOW() - (p_days || ' days')::interval
    ORDER BY (COALESCE(m.likes,0) + COALESCE(m.comments,0)*2 + COALESCE(m.shares,0)*3 + COALESCE(m.saves,0)*2) DESC
    LIMIT p_limit
  ) r;
  RETURN v_result;
END;
$function$;
