-- ============================================================================
-- Create board-attachments storage bucket with RLS policies
-- Required by BoardEngine CardDetail for file uploads
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'board-attachments',
  'board-attachments',
  false,
  5242880, -- 5MB
  ARRAY[
    'application/pdf',
    'image/png',
    'image/jpeg',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ]
) ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies
DROP POLICY IF EXISTS "board_attach_insert" ON storage.objects;
CREATE POLICY "board_attach_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'board-attachments');

DROP POLICY IF EXISTS "board_attach_select" ON storage.objects;
CREATE POLICY "board_attach_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'board-attachments');

DROP POLICY IF EXISTS "board_attach_delete" ON storage.objects;
CREATE POLICY "board_attach_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'board-attachments' AND auth.uid() = owner);
