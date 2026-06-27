-- #753 Parts 2+4 — storage member-write RLS hardening (follow-up to #752 security review)
-- Part 1 (member-signatures public->private + signed URLs) is a SEPARATE PR (touches legal cert PDFs).
--
-- Part 2 (MEDIUM): the 4 owner-scoped policies match `'<prefix>/' || regexp_replace(email,'[@.]','_','g') || '.%'`
--   with ILIKE (~~*). The underscores produced by the @/. sanitization are LIKE SINGLE-CHAR WILDCARDS, so two
--   distinct emails can sanitize to overlapping patterns (e.g. a@b.com -> a_b_com matches signatures/aXbYcom.png),
--   letting one member overwrite another's file. Fix: escape `\` `%` `_` in the prefix (backslash is ILIKE's
--   default ESCAPE char) so each literal underscore matches only a literal underscore. The trailing `.%` extension
--   wildcard is preserved (png/jpg/webp). Behavior-preserving for every legitimately-matching path; only removes
--   the cross-member fuzzy overlap. Mirrors the EF write path (upload-member-asset: email.replace(/[@.]/g,'_')).
--
-- Part 4 (LOW): no FOR DELETE policy existed on either bucket, so the "remove signature" flow only cleared the DB
--   field and orphaned the storage object (LGPD Art.16 minimization). Add owner-scoped DELETE policies; the
--   profile.astro remove handler now calls storage.remove() (see same PR).
--
-- DDL = policies (not functions) -> no pg_proc body-drift (Phase C) concern; inline comments are fine here.
-- ROLLBACK: restore the unescaped patterns via ALTER, and DROP the two *_own_delete policies.

-- ===== Part 2 — escape the `_`/`%`/`\` wildcards in the 4 existing owner policies =====

ALTER POLICY member_signatures_own_upload ON storage.objects
  WITH CHECK (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('signatures/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  );

ALTER POLICY member_signatures_own_update ON storage.objects
  USING (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('signatures/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  )
  WITH CHECK (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('signatures/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  );

ALTER POLICY member_photos_own_upload ON storage.objects
  WITH CHECK (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('avatars/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  );

ALTER POLICY member_photos_own_update ON storage.objects
  USING (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('avatars/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  )
  WITH CHECK (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('avatars/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  );

-- ===== Part 4 — owner-scoped DELETE policies (data minimization) =====

DROP POLICY IF EXISTS member_signatures_own_delete ON storage.objects;
CREATE POLICY member_signatures_own_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('signatures/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  );

DROP POLICY IF EXISTS member_photos_own_delete ON storage.objects;
CREATE POLICY member_photos_own_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'member-photos'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND storage.objects.name ~~* (
          replace(replace(replace('avatars/' || regexp_replace(m.email, '[@.]', '_', 'g'),
            E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
        )
    )
  );
