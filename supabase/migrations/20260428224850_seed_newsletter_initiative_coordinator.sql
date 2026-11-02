-- Seed Newsletter — Frontiers AI Project Management initiative.
-- Owner: Fabricio Costa (PhD doctorando + curator), per PM directive p78.
-- Drive folder: 11FKEzzU29fAGlhmNTgL6iuEpUCwOt1w_
-- Board: scope=global + domain_key=communication (newsletter is comms-domain workstream).
-- Engagement kind=workgroup_coordinator, role=coordinator, legitimate_interest.

DO $$
DECLARE
  v_org_id uuid := '2b4f58ab-7c45-4170-8718-b77ee69ff906';
  v_initiative_id uuid;
  v_board_id uuid;
  v_admin_member uuid := '880f736c-3e76-4df4-9375-33575c190305';
  v_admin_person uuid := 'd6e3622a-ebb6-43e1-86a6-5391c9350685';
  v_fabricio_person uuid := '199b0514-6868-41fc-a1bb-a189399e94b3';
BEGIN
  IF EXISTS (SELECT 1 FROM public.initiatives WHERE title = 'Newsletter — Frontiers AI Project Management') THEN
    RAISE NOTICE 'Newsletter initiative already exists, skipping seed.';
    RETURN;
  END IF;

  INSERT INTO public.initiatives (kind, title, description, organization_id, status, metadata)
  VALUES (
    'workgroup',
    'Newsletter — Frontiers AI Project Management',
    'Pipeline editorial recorrente do Núcleo IA — newsletter sobre AI Project Management. Coordena conteúdo entre tribos/iniciativas, curadoria, e publicação periódica. Owner: Fabricio Costa (PhD doctorando + curator).',
    v_org_id, 'active',
    jsonb_build_object('cadence_hint', 'monthly', 'channel_hint', 'email + linkedin')
  )
  RETURNING id INTO v_initiative_id;

  INSERT INTO public.project_boards (board_name, initiative_id, source, is_active, organization_id, board_scope, domain_key)
  VALUES ('Newsletter — Frontiers AI Project Management', v_initiative_id, 'manual', true, v_org_id, 'global', 'communication')
  RETURNING id INTO v_board_id;

  INSERT INTO public.engagements (
    person_id, organization_id, initiative_id, kind, role, status,
    start_date, legal_basis, granted_by, granted_at
  )
  VALUES (
    v_fabricio_person, v_org_id, v_initiative_id,
    'workgroup_coordinator', 'coordinator', 'active',
    CURRENT_DATE, 'legitimate_interest', v_admin_person, now()
  );

  INSERT INTO public.initiative_drive_links (
    initiative_id, drive_folder_id, drive_folder_url, drive_folder_name, link_purpose, linked_by
  )
  VALUES (
    v_initiative_id,
    '11FKEzzU29fAGlhmNTgL6iuEpUCwOt1w_',
    'https://drive.google.com/drive/folders/11FKEzzU29fAGlhmNTgL6iuEpUCwOt1w_',
    'Newsletter — Frontiers AI Project Management',
    'workspace', v_admin_member
  )
  ON CONFLICT (initiative_id, drive_folder_id, link_purpose) DO NOTHING;

  RAISE NOTICE 'Newsletter initiative created: % (board %, Fabricio coordinator engagement, Drive linked)', v_initiative_id, v_board_id;
END $$;
