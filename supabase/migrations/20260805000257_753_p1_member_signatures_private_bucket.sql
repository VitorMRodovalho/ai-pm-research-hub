-- #753 Part 1 — make member-signatures a PRIVATE bucket (HIGH / LGPD Art.11/46)
-- Signature images are biometric-adjacent personal data and were served from a guessable PUBLIC URL
-- (signatures/<sanitized_email>.png, public=true) → anyone who guessed a member's email could fetch their
-- signature with no auth. Live surface: 3 objects — 1 GP/issuer signature (on every cert, semi-public) +
-- 2 member self-signatures (the sensitive exposure). Make the bucket private; readers mint short-TTL signed
-- URLs (client + the CF-Browser-Rendering server route) instead of the raw public URL.
--
-- Access model: a signature object is readable by an authenticated caller iff its owning member is
--   (a) the caller (own signature → profile self-view), OR
--   (b) a GP/issuer (manage_platform) → the issuer signature stays renderable on certs for everyone.
-- Member self-signatures (non-GP) are therefore OWNER-ONLY. service_role bypasses RLS (server render + frozen PDFs).
--
-- Escaped LIKE pattern mirrors mig …256 (P2) so the injected @/. underscores stay literal.
-- DDL = bucket flag + policy (no pg_proc body-drift / Phase C concern).
-- ROLLBACK: UPDATE storage.buckets SET public=true WHERE id='member-signatures';
--           DROP POLICY IF EXISTS member_signatures_read_own_or_issuer ON storage.objects;

UPDATE storage.buckets SET public = false WHERE id = 'member-signatures';

DROP POLICY IF EXISTS member_signatures_read_own_or_issuer ON storage.objects;
CREATE POLICY member_signatures_read_own_or_issuer ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'member-signatures'
    AND EXISTS (
      SELECT 1 FROM public.members m
      WHERE storage.objects.name ~~* (
        replace(replace(replace('signatures/' || regexp_replace(m.email, '[@.]', '_', 'g'),
          E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '.%'
      )
      AND (
        m.auth_id = auth.uid()                          -- owner reads own (profile self-view)
        OR public.can_by_member(m.id, 'manage_platform') -- issuer/GP signature stays renderable on certs
      )
    )
  );

COMMENT ON POLICY member_signatures_read_own_or_issuer ON storage.objects IS
'#753 P1: member-signatures is private. Authenticated read iff the owning member is the caller (own sig) OR a '
'GP/issuer (manage_platform) whose signature appears on certificates. Member self-signatures are owner-only. '
'service_role bypasses RLS for server-side cert render + frozen volunteer-agreement PDFs.';
