-- Expand hub_resources asset_type constraint + normalize bulk-imported data
-- reference/other → document (PDFs, Google Docs), article (LinkedIn, Medium), video (YouTube)

ALTER TABLE hub_resources DROP CONSTRAINT IF EXISTS hub_resources_asset_type_check;
ALTER TABLE hub_resources ADD CONSTRAINT hub_resources_asset_type_check
  CHECK (asset_type = ANY (ARRAY['course', 'reference', 'webinar', 'other', 'article', 'presentation', 'governance', 'certificate', 'template', 'video', 'document', 'tool', 'book', 'podcast']));

UPDATE hub_resources SET asset_type = 'video'
WHERE asset_type IN ('reference','other') AND (url ILIKE '%youtube%' OR url ILIKE '%youtu.be%');

UPDATE hub_resources SET asset_type = 'article'
WHERE asset_type IN ('reference','other') AND (url ILIKE '%linkedin.com/pulse%' OR url ILIKE '%medium.com%' OR url ILIKE '%projectmanagement.com%' OR url ILIKE '%hbr.org%');

UPDATE hub_resources SET asset_type = 'document'
WHERE asset_type IN ('reference','other') AND (url ILIKE '%.pdf' OR url ILIKE '%docs.google%' OR url ILIKE '%drive.google%');
