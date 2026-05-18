-- ============================================================
-- p195 Opção B+: extract VEP resume binary to Supabase Storage
-- ============================================================
-- WHAT:
-- 1. CREATE bucket 'selection-resumes' (private) for sustainable resume storage
-- 2. ADD columns selection_applications.resume_storage_path + resume_synced_at
-- 3. Storage RLS policies — read gated by view_pii capability (chair + assigned evaluators
--    inherit via existing RPC chains); write service_role only (Worker)
--
-- WHY (PM decision p195, Opção B+):
-- VEP Azure SAS URLs expire ~24h → PM had to re-import JSON daily to keep CV links
-- functional during ~35-candidate evaluation cycles. Sustainable solution: Worker
-- downloads PDF binary during /ingest (using same SAS link that was generated for
-- the human recruiter), uploads to Supabase Storage bucket. UI links shift from
-- ephemeral Azure SAS → controlled-TTL Supabase signed URLs (7d default).
--
-- ROLLBACK:
--   DROP POLICY ... ON storage.objects;
--   ALTER TABLE selection_applications DROP COLUMN resume_storage_path, DROP COLUMN resume_synced_at;
--   DELETE FROM storage.buckets WHERE id = 'selection-resumes';
--   (Optional manual: clear bucket contents before delete to free storage cost.)
-- ============================================================

-- 1. Add columns
ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS resume_storage_path text,
  ADD COLUMN IF NOT EXISTS resume_synced_at timestamptz;

COMMENT ON COLUMN public.selection_applications.resume_storage_path IS
  'Path in Supabase Storage bucket "selection-resumes" (LGPD scoped via Art. 7º VI organização sem fins lucrativos finalidade legítima + Art. 18 erasure). NULL = resume only in VEP Azure (legacy/fallback/import failed).';

COMMENT ON COLUMN public.selection_applications.resume_synced_at IS
  'When resume PDF was last fetched from VEP Azure to local Storage. Stale signal for UI ("considere re-importar"). NULL = never synced (only Azure link available).';

-- 2. Storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('selection-resumes', 'selection-resumes', false)
ON CONFLICT (id) DO NOTHING;

-- 3. RLS policies on storage.objects (RLS is already enabled on storage.objects by default)
-- READ: members with view_pii capability (chair + designated evaluators)
DROP POLICY IF EXISTS "selection_resumes_read_view_pii" ON storage.objects;
CREATE POLICY "selection_resumes_read_view_pii"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'selection-resumes'
    AND public.can(auth.uid(), 'view_pii')
  );

-- WRITE/UPDATE/DELETE: service_role only (Worker via service-role key)
-- Default deny is sufficient for authenticated/anon since no policy grants them write.
-- service_role bypasses RLS by design, so explicit policy not needed.
