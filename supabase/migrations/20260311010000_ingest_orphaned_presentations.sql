-- Ingest 21 orphaned presentation files discovered by knowledge_file_detective.ts
-- These are Cycle 1-3 presentations found in data/staging-knowledge/ but not yet in the DB.
-- All inserted with status='review' so they appear on the Kanban curatorship board.
-- member_id is set to the first superadmin found (system import attribution).

DO $$
DECLARE
  v_member_id UUID;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE is_superadmin = true LIMIT 1;
  IF v_member_id IS NULL THEN
    SELECT id INTO v_member_id FROM members ORDER BY created_at ASC LIMIT 1;
  END IF;

  INSERT INTO artifacts (title, type, tribe_id, cycle, status, submitted_at, member_id) VALUES
    ('2025 02 24 apresentacao 01', 'presentation', NULL, 2, 'review', now(), v_member_id),
    ('2026 02 17 nucleo ia gp ciclo3 kickoff lideranca', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('ai at work 2024 slideshow 2024 june', 'presentation', NULL, 1, 'review', now(), v_member_id),
    ('apresentacao novos membros tribo 4', 'presentation', 4, 3, 'review', now(), v_member_id),
    ('apresentacao pmi goias palestrante vitormaia dia 2', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('apresentacao pmi goias palestrante vitormaia', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('bem vindo a ao ciclo 03 quadrante 4 tribo 07 governanca trustworthy ai marcos klemz', 'presentation', 7, 3, 'review', now(), v_member_id),
    ('bem vindo ao ciclo 03   quadrante 3   tribo 03 tmo pmo do futuro marcel fleming .mp4', 'presentation', 3, 3, 'review', now(), v_member_id),
    ('bem vindoa ao ciclo 03   quadrante 2   tribo 02  agentes autonomos equipes hibridas framework eaa com debora moura', 'presentation', 2, 3, 'review', now(), v_member_id),
    ('certificado espirito de colaboracao tribo 6', 'presentation', 6, 3, 'review', now(), v_member_id),
    ('certificado excelencia tecnica tribo 3', 'presentation', 3, 3, 'review', now(), v_member_id),
    ('certificado tribo revelacao tribo 3', 'presentation', 3, 3, 'review', now(), v_member_id),
    ('final pmi ai hub presentation', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('fluxo agente mayanna tribo 3', 'presentation', 3, 3, 'review', now(), v_member_id),
    ('levantamento de requisitos agentes ia tribo 3.docx 1', 'presentation', 3, 3, 'review', now(), v_member_id),
    ('modelagem fluxo do agente eva nucleo tribo 3 mayanna duarte', 'presentation', 3, 3, 'review', now(), v_member_id),
    ('nucleo ia apresentacao', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('perfil minimo liderancas nucleo ia', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('ricardo vargas pmrank apresentacao', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('ricardo vargas pmrank exemplofichaprojeto', 'presentation', NULL, 3, 'review', now(), v_member_id),
    ('ricardo vargas pmrank funil', 'presentation', NULL, 3, 'review', now(), v_member_id);

  RAISE NOTICE 'Ingested 21 orphaned presentations with member_id=%', v_member_id;
END $$;
