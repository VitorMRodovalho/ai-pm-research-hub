-- Drive Phase 4 — register the /Atas subfolders for each initiative.
-- 12 detected via drive-list-folder-files scan after PM created them in Drive UI.
-- 13th (Newsletter) created via drive-create-subfolder EF same session.
-- Idempotent: ON CONFLICT DO NOTHING (initiative_id + drive_folder_id + link_purpose UNIQUE).
-- After this seed: Phase 4 cron drive-discover-atas-daily can populate
-- drive_file_discoveries with auto-match against events.minutes_url.

INSERT INTO public.initiative_drive_links (initiative_id, drive_folder_id, drive_folder_url, drive_folder_name, link_purpose, linked_by) VALUES
('89e13063-0be5-4f59-a162-0392f4408178', '1KxaVCHjf9tZL1WabbgjXDvZa9sOGOyKp', 'https://drive.google.com/drive/folders/1KxaVCHjf9tZL1WabbgjXDvZa9sOGOyKp', 'Atas (T1 Radar)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('6c7e5945-1457-4eb3-ae99-28d7b1e72db9', '1edIIGNyuUbDTHyMKjdlYD2wxEiFcRnnS', 'https://drive.google.com/drive/folders/1edIIGNyuUbDTHyMKjdlYD2wxEiFcRnnS', 'Atas (T6 ROI)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('e885525e-a0f1-4e16-813c-497047209047', '1waHSEf3lon0TlLefRrkiIBEM3uDCZcYs', 'https://drive.google.com/drive/folders/1waHSEf3lon0TlLefRrkiIBEM3uDCZcYs', 'Atas (Publicações)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19', '1LwOY80De1aizsJjLVYkxsS0tovbe9HjG', 'https://drive.google.com/drive/folders/1LwOY80De1aizsJjLVYkxsS0tovbe9HjG', 'Atas (CPMAI)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('9ea82b09-55c6-4cc3-ab7f-178518d0ab47', '1Z_OV2OguYnHiv4m_AsT5govEkLD4p3CV', 'https://drive.google.com/drive/folders/1Z_OV2OguYnHiv4m_AsT5govEkLD4p3CV', 'Atas (Hub Comunicação)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('d01c1f43-4dab-487f-a3fc-fb1634bf8eaf', '1xhd1oL2uEw_9za8WUqi6dTd_CGndrRSS', 'https://drive.google.com/drive/folders/1xhd1oL2uEw_9za8WUqi6dTd_CGndrRSS', 'Atas (T7 Governança)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('6c3ffc94-207c-4c63-9e83-c6f3d48529d7', '1MOgC1U-ILEt8GJO08LdbwCXI4Nu9x-9P', 'https://drive.google.com/drive/folders/1MOgC1U-ILEt8GJO08LdbwCXI4Nu9x-9P', 'Atas (T2 Agentes)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('a68fcc06-7de8-400b-b5b3-60e368fb46ac', '10W3XjETf7jB2_TTxn6uxA-pkauiK8oP3', 'https://drive.google.com/drive/folders/10W3XjETf7jB2_TTxn6uxA-pkauiK8oP3', 'Atas (LATAM LIM 2026)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('9cbaf0b9-de4d-4e40-8375-5767cc97a9a4', '1kJEy-j-Y8i2zw5u-U8AXvDYzmzbLT1T-', 'https://drive.google.com/drive/folders/1kJEy-j-Y8i2zw5u-U8AXvDYzmzbLT1T-', 'Atas (T8 Inclusão)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('6a93cc94-c4a0-4280-8ea7-452ec6ec48a5', '1TmzC9ieFyHha-NyLjjzBtDQQKR703qHF', 'https://drive.google.com/drive/folders/1TmzC9ieFyHha-NyLjjzBtDQQKR703qHF', 'Atas (Comitê Curadoria)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('18a40313-b6d9-4d60-b1b1-ede526685bcb', '1hYngjnWec2fB68gO6zvNiH1HaxSBs9tI', 'https://drive.google.com/drive/folders/1hYngjnWec2fB68gO6zvNiH1HaxSBs9tI', 'Atas (T5 Talentos)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('05635518-d831-4548-b7c0-89fe5e5e7651', '1nWPy45uHNZlnbhEklC6A6pOEcm84xjl4', 'https://drive.google.com/drive/folders/1nWPy45uHNZlnbhEklC6A6pOEcm84xjl4', 'Atas (T4 Cultura)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305'),
('ba824d24-af69-429d-a601-3672e97f8e37', '1rQFkxx8nJT7cxuRXffLNckJEKvAvef2R', 'https://drive.google.com/drive/folders/1rQFkxx8nJT7cxuRXffLNckJEKvAvef2R', 'Atas (Newsletter)', 'minutes', '880f736c-3e76-4df4-9375-33575c190305')
ON CONFLICT (initiative_id, drive_folder_id, link_purpose) DO NOTHING;
