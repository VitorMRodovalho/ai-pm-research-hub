-- ============================================================
-- p221 #267 alpha — Create `certificates` storage bucket (backfill scope)
-- ============================================================
-- WHY: Issue #267 (WATCH-258.A) - 42 certificates have pdf_url=NULL.
-- Scope alpha (PM pick 2026-05-22): backfill-only via local Node script.
-- Forward auto-gen + member-owned SELECT path deferred to Option C
-- (separate ticket, includes /verify route binding + signed URLs).
--
-- BUCKET:
--   id/name: certificates
--   public: false (PII-heavy content_snapshot rendered into PDF)
--   file_size_limit: 10485760 (10 MB; certs typically 50-200KB)
--   allowed_mime_types: application/pdf
--   storage path convention: <member_id>/<verification_code>.pdf
--
-- RLS DEFERRED to Option C:
--   This scope intentionally creates NO storage.objects policies.
--   Reasoning:
--     * service_role used by backfill script bypasses RLS (always works)
--     * bucket is private (public=false) so NO anon/authenticated read
--       paths exist without explicit policy
--     * NO consumer reads pdf_url yet (currently NULL for all certs;
--       admin/certificates page uses browser-print, NOT pdf_url)
--   Option C will add the policies when wiring verify-route + member
--   /certificates page. Those policies MUST be applied via Supabase
--   Studio UI Storage > Policies tab (storage.objects owner chain
--   prevents MCP apply_migration ownership — sediment p210).
--
-- ROLLBACK:
--   DELETE FROM storage.buckets WHERE id = 'certificates';
--   (NOT recommended after backfill: orphaned objects + dangling
--    certificates.pdf_url paths.)
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'certificates',
  'certificates',
  false,
  10485760,
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
