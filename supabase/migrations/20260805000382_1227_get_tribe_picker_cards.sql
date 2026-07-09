-- #1227: expose the tribe-picker per-card public metadata (leader LinkedIn + explainer
-- video) that the picker (TribesSection) currently hardcodes in src/data/tribes.ts. The
-- SSOT already lives in the DB — tribes.video_url/video_duration + tribes.leader_member_id →
-- members.linkedin_url — but `tribes` is not anon-readable (RLS), so the SSR frontmatter
-- cannot read it directly. This SECURITY DEFINER RPC returns ONLY public professional data
-- (LinkedIn + YouTube video), the same class already public via public_members / the homepage.
-- No PII (email/phone/pmi_id). Anon-safe (LGPD GC-162 / Key Architecture Decision #6).
CREATE OR REPLACE FUNCTION public.get_tribe_picker_cards()
 RETURNS TABLE(tribe_id integer, leader_linkedin text, video_url text, video_duration text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT t.id, m.linkedin_url, t.video_url, t.video_duration
  FROM public.tribes t
  LEFT JOIN public.members m ON m.id = t.leader_member_id
  WHERE t.is_active = true;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_tribe_picker_cards() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_tribe_picker_cards() TO anon, authenticated, service_role;
