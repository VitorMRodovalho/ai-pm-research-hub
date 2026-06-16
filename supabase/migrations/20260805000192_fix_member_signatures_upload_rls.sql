-- Hotfix #740-adjacent — member-signatures AND member-photos write RLS reference the wrong `name`
--
-- BUG: the INSERT/UPDATE policies on storage.objects for the `member-signatures` and
--   `member-photos` buckets (migration 20260423090000) intended to require the UPLOADED
--   OBJECT's path to match `signatures/<sanitized_email>.%` / `avatars/<sanitized_email>.%`.
--   They wrote an UNQUALIFIED `name ILIKE ...` INSIDE
--   `EXISTS (SELECT 1 FROM public.members m WHERE ...)`. Because `public.members` HAS a
--   `name` column, the unqualified `name` resolved to `m.name` (the member's PERSON name,
--   e.g. "Willian Junior"), NOT the storage object path. A person's name never matches
--   `signatures/email.%`, so the EXISTS is ALWAYS false → EVERY member's signature/photo
--   upload fails with "new row violates row-level security policy" (HTTP 400).
--   Verified live: 0 of 73 active members have a `members.name` matching the pattern;
--   member juniorwillian917@gmail.com hit repeated 400s on
--   POST /object/member-signatures/signatures/juniorwillian917_gmail_com.png.
--   (member-photos has the identical defect — found by the security-engineer review.)
--
-- FIX: qualify the object path explicitly as `storage.objects.name` so the predicate
--   checks the uploaded file path (not the member's name). Intent preserved + tight: an
--   authenticated member may only write/replace an object at
--   `<prefix>/<their-own-sanitized-email>.%`. Also add WITH CHECK (mirroring USING) to the
--   UPDATE policies so the post-image is validated, not only the pre-image.
--   Verified live: the corrected predicate evaluates TRUE for the blocked member's path.
--
-- SCOPE: storage RLS only. No data change. Pre-existing bug (failures predate the
--   2026-06-16 Wave-3 work; unrelated to it). Follow-ups tracked separately:
--   ILIKE `_` wildcard hardening (sanitized email collisions), member-signatures public-read
--   LGPD posture (biometric-adjacent → private + signed URLs), and a member DELETE policy.

-- ── member-signatures ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "member_signatures_own_upload" ON storage.objects;
CREATE POLICY "member_signatures_own_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ILIKE 'signatures/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );

DROP POLICY IF EXISTS "member_signatures_own_update" ON storage.objects;
CREATE POLICY "member_signatures_own_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ILIKE 'signatures/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  )
  WITH CHECK (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ILIKE 'signatures/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );

-- ── member-photos (same defect, found in security review) ────────────────────────
DROP POLICY IF EXISTS "member_photos_own_upload" ON storage.objects;
CREATE POLICY "member_photos_own_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ILIKE 'avatars/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );

DROP POLICY IF EXISTS "member_photos_own_update" ON storage.objects;
CREATE POLICY "member_photos_own_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ILIKE 'avatars/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  )
  WITH CHECK (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ILIKE 'avatars/' || regexp_replace(m.email, '[@.]', '_', 'g') || '.%'
    )
  );
