-- P3.3: Ensure documents storage bucket exists for PDF uploads
insert into storage.buckets (id, name, public)
values ('documents', 'documents', true)
on conflict (id) do nothing;

-- Allow authenticated users to upload to knowledge-pdfs/
create policy "Authenticated upload to knowledge-pdfs"
on storage.objects for insert
to authenticated
with check (bucket_id = 'documents' and (storage.foldername(name))[1] = 'knowledge-pdfs');

-- Public read access for documents bucket
create policy "Public read documents"
on storage.objects for select
to public
using (bucket_id = 'documents');

-- Admin can delete documents
create policy "Admin delete documents"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'documents'
  and exists (
    select 1 from public.members m
    where m.auth_id = auth.uid()
    and (m.is_superadmin = true or m.operational_role in ('manager', 'deputy_manager'))
  )
);
