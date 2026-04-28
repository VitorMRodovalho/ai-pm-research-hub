-- Drive Integration Phase 2 ACTIVATED: vincula 12 iniciativas a Drive folders
-- (PM CSV 2026-04-28). SA email autorizado em todas as pastas.
-- Smoke test wave confirmou acesso: 12/12 pastas, 56 files reais mapeados.
-- Idempotent via ON CONFLICT.

INSERT INTO public.initiative_drive_links (initiative_id, drive_folder_id, drive_folder_url, drive_folder_name, link_purpose, linked_by) VALUES
('a68fcc06-7de8-400b-b5b3-60e368fb46ac', '1xzBl3UUZDU8S388LkV88SAyNZGDabK5r', 'https://drive.google.com/drive/folders/1xzBl3UUZDU8S388LkV88SAyNZGDabK5r', 'LATAM LIM 2026', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('6a93cc94-c4a0-4280-8ea7-452ec6ec48a5', '1qXPDojoODXAcwEMrO3YqU58lXiBh4one', 'https://drive.google.com/drive/folders/1qXPDojoODXAcwEMrO3YqU58lXiBh4one', 'Comite de Curadoria', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('89e13063-0be5-4f59-a162-0392f4408178', '19k9QY_bKjZrZJfRY2e6FbybcwHOG3SWF', 'https://drive.google.com/drive/folders/19k9QY_bKjZrZJfRY2e6FbybcwHOG3SWF', 'T1 Radar Tecnológico', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('6c3ffc94-207c-4c63-9e83-c6f3d48529d7', '1-ENrmN-iVEugDvVbFJ5C2qtaR7DTRc_C', 'https://drive.google.com/drive/folders/1-ENrmN-iVEugDvVbFJ5C2qtaR7DTRc_C', 'T2 Agentes Autônomos', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('05635518-d831-4548-b7c0-89fe5e5e7651', '1oB2tkpeacCrlVFfOzdAGuqqCGBzMvLai', 'https://drive.google.com/drive/folders/1oB2tkpeacCrlVFfOzdAGuqqCGBzMvLai', 'T4 Cultura & Change', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('18a40313-b6d9-4d60-b1b1-ede526685bcb', '1l6sYHyh1o2p_2csY21Y_Wggm_SdOIstR', 'https://drive.google.com/drive/folders/1l6sYHyh1o2p_2csY21Y_Wggm_SdOIstR', 'T5 Talentos & Upskilling', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('6c7e5945-1457-4eb3-ae99-28d7b1e72db9', '1OGip-_EsltVrbYF2cqX-yNn9jcS0Bq4-', 'https://drive.google.com/drive/folders/1OGip-_EsltVrbYF2cqX-yNn9jcS0Bq4-', 'T6 ROI & Portfólio', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('d01c1f43-4dab-487f-a3fc-fb1634bf8eaf', '1OD0GG8OxtdhdpAikm81VKeMIBXYkOS7d', 'https://drive.google.com/drive/folders/1OD0GG8OxtdhdpAikm81VKeMIBXYkOS7d', 'T7 Governança & Trustworthy AI', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('9cbaf0b9-de4d-4e40-8375-5767cc97a9a4', '1a8FJTIBrBvibpBgLwF_rD5iCry-rKotL', 'https://drive.google.com/drive/folders/1a8FJTIBrBvibpBgLwF_rD5iCry-rKotL', 'T8 Inclusão & Colaboração & Comunicação', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19', '1KW1aWddwaTKyWHQm7aI6YwfRLTq4Cb8E', 'https://drive.google.com/drive/folders/1KW1aWddwaTKyWHQm7aI6YwfRLTq4Cb8E', 'Preparatório CPMAI', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('9ea82b09-55c6-4cc3-ab7f-178518d0ab47', '1f_qfm5YrQ4FUcGDJZidoCGBu1gBk5QdQ', 'https://drive.google.com/drive/folders/1f_qfm5YrQ4FUcGDJZidoCGBu1gBk5QdQ', 'Hub de Comunicacao', 'workspace', '880f736c-3e76-4df4-9375-33575c190305'),
('e885525e-a0f1-4e16-813c-497047209047', '1l4rYQjuXRbzcjg9-4oqzUvZMUH38yJ3c', 'https://drive.google.com/drive/folders/1l4rYQjuXRbzcjg9-4oqzUvZMUH38yJ3c', 'Publicacoes & Submissoes', 'workspace', '880f736c-3e76-4df4-9375-33575c190305')
ON CONFLICT (initiative_id, drive_folder_id, link_purpose) DO NOTHING;
