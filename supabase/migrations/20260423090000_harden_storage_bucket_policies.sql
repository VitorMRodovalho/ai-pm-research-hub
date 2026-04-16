-- ═══════════════════════════════════════════════════════════════
-- Storage bucket hardening — fix real security gaps, not just advisor noise
-- Why:
--   1. "Public read documents"/"Anyone can read photos"/"Public photo access"
--      allow .list() on the buckets. Public buckets serve URLs without RLS,
--      so these policies only enable listing — not intended usage.
--   2. "Anyone can update/upload photos" (roles={-}, public) — any anonymous
--      client could upload to member-photos. Real DoS/abuse vector.
--   3. "Members manage signatures" (polcmd='*', no user scoping) — any
--      authenticated user could read/modify ANY other member's signature.
-- Approach: scope INSERT/UPDATE by caller's email matching file path
-- (uploads use pattern avatars/{sanitized_email}.{ext} and
-- signatures/{sanitized_email}.png — see profile.astro L1306-1341).
-- Rollback: recreate dropped policies (see git blame in this commit).
-- ═══════════════════════════════════════════════════════════════

-- documents
DROP POLICY IF EXISTS "Public read documents" ON storage.objects;

-- member-photos
DROP POLICY IF EXISTS "Anyone can read photos" ON storage.objects;
DROP POLICY IF EXISTS "Public photo access" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can update photos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can upload photos" ON storage.objects;
DROP POLICY IF EXISTS "Auth update photos" ON storage.objects;
DROP POLICY IF EXISTS "Auth upload photos" ON storage.objects;

CREATE POLICY "member_photos_own_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND name ILIKE 'avatars/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );

CREATE POLICY "member_photos_own_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND name ILIKE 'avatars/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );

-- member-signatures
DROP POLICY IF EXISTS "Members manage signatures" ON storage.objects;

CREATE POLICY "member_signatures_own_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND name ILIKE 'signatures/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );

CREATE POLICY "member_signatures_own_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND name ILIKE 'signatures/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );
