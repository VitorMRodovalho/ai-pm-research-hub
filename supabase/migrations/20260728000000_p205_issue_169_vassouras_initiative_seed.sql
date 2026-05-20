-- ============================================================================
-- p205 / Issue #169 — IA & Competências 2026 — Mesa Redonda Vassouras
-- ============================================================================
--
-- Seeds the modeling for the external co-organized event on 2026-06-02
-- (T-11 days from this migration). Per P201_WHATSAPP_ACTION_INTAKE_MAP §4
-- and PM decision at p205 close (Option C: full initiative + engagements).
--
-- What this seeds (all idempotent via NOT EXISTS guards):
--   1. partner_entity for Universidade de Vassouras — Polo Saquarema
--   2. initiative kind='congress' (precedent: LATAM LIM 2026), title
--      "IA & Competências 2026 — Mesa Redonda Universidade de Vassouras"
--   3. 3 engagements for confirmed participants:
--      - João Coelho Júnior — workgroup_coordinator/coordinator (initiative leader)
--      - Vitor Maia Rodovalho — speaker/speaker (confirmed)
--      - Sarah Rodovalho — speaker/speaker (confirmed; profile: System
--        Engineering / data center infrastructure perspective)
--   4. event row 2026-06-02 19:10 BRT, type='evento_externo'
--
-- What this does NOT seed (left for board/UI after merge, per privacy/scope):
--   - Ana Carla, Letícia — proposed speakers TBD; board checklist will track
--   - WhatsApp planning URL — operational private data; admin fills via UI
--     into initiative.metadata.whatsapp_url after merge (repo is public)
--   - Fabricio Costa engagement — confirmed UNAVAILABLE per WhatsApp
--   - Students / PMI-RJ chapter board contacts — board cards drive intake
--     (visitor_leads or observer engagements when individuals are identified)
--   - Sympla registration / sponsorship metadata — decisions pending
--
-- Privacy constraint (P201_WHATSAPP_ACTION_INTAKE_MAP §4):
--   Sarah's employment history must NOT appear in any public artifact.
--   Profile descriptor used here is the public-safe shape: "System Engineering
--   PhD focus; infrastructure / data center perspective."
--
-- Idempotency:
--   Re-running this migration is a no-op. Each INSERT is guarded with
--   WHERE NOT EXISTS against a stable identifier (partner name, initiative
--   title, engagement (person_id, kind, initiative_id), event (initiative_id,
--   date)). Future updates land as separate migrations or admin UI ops.
--
-- Rollback:
--   DELETE FROM events WHERE initiative_id = '<initiative_uuid>';
--   DELETE FROM engagements WHERE initiative_id = '<initiative_uuid>';
--   DELETE FROM initiatives WHERE id = '<initiative_uuid>';
--   DELETE FROM partner_entities WHERE id = '<partner_uuid>';
--   The initiative + partner UUIDs are stable (deterministic UUIDs below) so
--   rollback is reproducible. Idempotency guards make accidental re-apply safe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. partner_entity — Universidade de Vassouras (Polo Saquarema)
-- ----------------------------------------------------------------------------

INSERT INTO public.partner_entities (
  id,
  name,
  entity_type,
  description,
  partnership_date,
  contact_name,
  contact_email,
  status,
  chapter,
  organization_id,
  notes
)
SELECT
  '6e9af7a8-1696-4169-a1a1-c0e160600001'::uuid,
  'Universidade de Vassouras — Polo Saquarema',
  'academic',
  'Polo regional da Universidade de Vassouras em Saquarema (RJ). Curso de Engenharia de Software. Parceria operacional para a mesa redonda "IA & Competências" em 2026-06-02 (online + presencial). Potencial para colaboração recorrente em ensino de gestão de projetos via plataforma Núcleo IA.',
  '2026-05-19'::date,
  'João Coelho Júnior',
  'j_coelho@id.uff.br',
  'active',
  'PMI-RJ',
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  'Cross-chapter (PMI-CE liaison via João Coelho Júnior; PMI-RJ chapter board engaged via Dani Paoliello, Presidente PMI-RJ). MOU stage TBD.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.partner_entities
  WHERE name = 'Universidade de Vassouras — Polo Saquarema'
    AND organization_id = '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
);

-- ----------------------------------------------------------------------------
-- 2. initiative — IA & Competências 2026 (kind='congress')
-- ----------------------------------------------------------------------------

INSERT INTO public.initiatives (
  id,
  kind,
  organization_id,
  title,
  description,
  status,
  origin_partner_entity_id,
  join_policy,
  metadata
)
SELECT
  '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid,
  'congress',
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  'IA & Competências 2026 — Mesa Redonda Universidade de Vassouras',
  'Mesa redonda "Inteligência Artificial e o Futuro das Competências: Carreiras, Habilidades e Adaptação Profissional" co-organizada com Universidade de Vassouras (Polo Saquarema). Formato híbrido (online + presencial) em 2026-06-02 19:10-21:30 BRT. Público: alunos de Engenharia de Software + audiência aberta via YouTube. Co-broadcast canal Núcleo + canal evento. Oportunidade de ensino prático de gestão de projetos para os alunos via colaboração no board da iniciativa.',
  'active',
  '6e9af7a8-1696-4169-a1a1-c0e160600001'::uuid,
  'invite_only',
  jsonb_build_object(
    'our_role', 'co_organizer',
    'initiative_subtype', 'external_event_collaboration',
    'teaching_scope', true,
    'audience', 'Engenharia de Software (alunos Vassouras Saquarema) + audiência aberta YouTube',
    'event_date', '2026-06-02',
    'event_time_start', '19:10',
    'event_time_end', '21:30',
    'timezone', 'America/Sao_Paulo',
    'venue', 'Online + Universidade de Vassouras — Polo Saquarema',
    'youtube_channel_event', 'https://www.youtube.com/@sestec.software',
    'youtube_channel_nucleo', 'planned co-broadcast — confirm pre-event',
    'chapters_involved', jsonb_build_array('PMI-CE', 'PMI-RJ'),
    'collaborators', jsonb_build_object(
      'leader_person_id', '6eeafafb-c592-4a71-b51c-7be557a93e8f',
      'leader_name', 'João Coelho Júnior',
      'gp_person_id', 'd6e3622a-ebb6-43e1-86a6-5391c9350685',
      'gp_name', 'Vitor Maia Rodovalho'
    ),
    'confirmed_speakers', jsonb_build_array(
      jsonb_build_object('person_id', 'd6e3622a-ebb6-43e1-86a6-5391c9350685', 'name', 'Vitor Maia Rodovalho', 'angle', 'GP + IA aplicada / gestão de projetos'),
      jsonb_build_object('person_id', 'a1966b77-ff29-4ea9-b965-4c85a3bb17ac', 'name', 'Sarah Rodovalho', 'angle', 'System Engineering PhD; infraestrutura / data centers')
    ),
    'proposed_speakers_pending_confirmation', jsonb_build_array(
      jsonb_build_object('person_id', 'efa17598-f9f3-4282-b761-dec7d0a4b049', 'name', 'Ana Carla Cavalcante'),
      jsonb_build_object('person_id', 'da5856a8-2428-41a9-b011-548c518795b5', 'name', 'Letícia Rodrigues Vieira')
    ),
    'confirmed_unavailable', jsonb_build_array(
      jsonb_build_object('person_id', '199b0514-6868-41fc-a1bb-a189399e94b3', 'name', 'Fabricio Costa', 'reason', 'agenda na data')
    ),
    'logistics_external', jsonb_build_object(
      'sponsorship_status', 'partial — camisas + sorteio + coffee-break confirmados via patrocínios locais; bolsa de pós em discussão',
      'sympla_registration', 'em avaliação',
      'audience_reached_youtube', 126,
      'audience_reached_youtube_as_of', '2026-05-19'
    ),
    'whatsapp_url', null,
    'open_questions', jsonb_build_array(
      'Confirmação Ana Carla como palestrante',
      'Decisão sobre Letícia (alternativa) ou cobertura via Sarah',
      'Sympla on/off para inscrição',
      'Co-broadcast canal Núcleo (confirmar técnica day-of)',
      'PMI-RJ Diretoria de Filiação no loop (pitch institucional)'
    )
  )
WHERE NOT EXISTS (
  SELECT 1 FROM public.initiatives
  WHERE id = '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid
);

-- ----------------------------------------------------------------------------
-- 3. engagements — 3 confirmed participants
-- ----------------------------------------------------------------------------

-- 3a. João Coelho Júnior — workgroup_coordinator/coordinator (initiative leader)
INSERT INTO public.engagements (
  id, person_id, organization_id, initiative_id, kind, role, status, start_date,
  legal_basis, granted_by, granted_at, metadata
)
SELECT
  gen_random_uuid(),
  '6eeafafb-c592-4a71-b51c-7be557a93e8f'::uuid,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid,
  'workgroup_coordinator',
  'coordinator',
  'active',
  '2026-05-19'::date,
  'consent',
  'd6e3622a-ebb6-43e1-86a6-5391c9350685'::uuid,
  now(),
  jsonb_build_object(
    'capacity', 'initiative_leader',
    'source', 'p205_issue_169_seed',
    'note', 'Operacional leader for the external co-organized event. Does not modify João existing researcher engagement.'
  )
WHERE NOT EXISTS (
  SELECT 1 FROM public.engagements
  WHERE person_id = '6eeafafb-c592-4a71-b51c-7be557a93e8f'::uuid
    AND initiative_id = '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid
    AND kind = 'workgroup_coordinator'
    AND status = 'active'
);

-- 3b. Vitor Maia Rodovalho — speaker (confirmed)
INSERT INTO public.engagements (
  id, person_id, organization_id, initiative_id, kind, role, status, start_date,
  legal_basis, granted_by, granted_at, metadata
)
SELECT
  gen_random_uuid(),
  'd6e3622a-ebb6-43e1-86a6-5391c9350685'::uuid,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid,
  'speaker',
  'speaker',
  'active',
  '2026-05-19'::date,
  'consent',
  'd6e3622a-ebb6-43e1-86a6-5391c9350685'::uuid,
  now(),
  jsonb_build_object(
    'capacity', 'speaker',
    'angle', 'GP + IA aplicada / gestão de projetos',
    'source', 'p205_issue_169_seed'
  )
WHERE NOT EXISTS (
  SELECT 1 FROM public.engagements
  WHERE person_id = 'd6e3622a-ebb6-43e1-86a6-5391c9350685'::uuid
    AND initiative_id = '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid
    AND kind = 'speaker'
    AND status = 'active'
);

-- 3c. Sarah Rodovalho — speaker (confirmed)
INSERT INTO public.engagements (
  id, person_id, organization_id, initiative_id, kind, role, status, start_date,
  legal_basis, granted_by, granted_at, metadata
)
SELECT
  gen_random_uuid(),
  'a1966b77-ff29-4ea9-b965-4c85a3bb17ac'::uuid,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid,
  'speaker',
  'speaker',
  'active',
  '2026-05-19'::date,
  'consent',
  'd6e3622a-ebb6-43e1-86a6-5391c9350685'::uuid,
  now(),
  jsonb_build_object(
    'capacity', 'speaker',
    'angle', 'System Engineering PhD; infraestrutura / data centers',
    'source', 'p205_issue_169_seed'
  )
WHERE NOT EXISTS (
  SELECT 1 FROM public.engagements
  WHERE person_id = 'a1966b77-ff29-4ea9-b965-4c85a3bb17ac'::uuid
    AND initiative_id = '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid
    AND kind = 'speaker'
    AND status = 'active'
);

-- ----------------------------------------------------------------------------
-- 4. event — 2026-06-02 19:10 BRT
-- ----------------------------------------------------------------------------

INSERT INTO public.events (
  id, type, title, date, time_start, duration_minutes, status, visibility,
  initiative_id, organization_id, timezone, created_by, nature, notes
)
SELECT
  '6e9af7a8-1696-4169-a1a1-c0e160600003'::uuid,
  'evento_externo',
  'IA & Competências — Mesa Redonda Vassouras Saquarema',
  '2026-06-02'::date,
  '19:10:00'::time,
  140,  -- 19:10 to 21:30 = 2h20min
  'scheduled',
  'all',
  '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  'America/Sao_Paulo',
  -- events.created_by FK → auth.users(id), NOT persons(id). Vitor auth_id resolved via members.auth_id.
  '58675a94-eb44-483b-ab7d-9f8892e4fc3c'::uuid,
  'avulsa',  -- valid nature: kickoff/recorrente/avulsa/encerramento/workshop/entrevista_selecao
  'Mesa redonda híbrida (online + presencial Polo Saquarema). Co-broadcast YouTube canal evento (@sestec.software) + canal Núcleo (planejado). Audiência: Engenharia de Software + público aberto.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.events
  WHERE id = '6e9af7a8-1696-4169-a1a1-c0e160600003'::uuid
);

-- ----------------------------------------------------------------------------
-- 5. project_board + board_items — planning checklist per P201 spec §4
-- ----------------------------------------------------------------------------

INSERT INTO public.project_boards (
  id, board_name, source, columns, is_active, board_scope,
  domain_key, initiative_id, organization_id, created_by
)
SELECT
  '6e9af7a8-1696-4169-a1a1-c0e160600004'::uuid,
  'IA & Competências 2026 — Planning Board',
  'manual',
  '["backlog","todo","in_progress","review","done"]'::jsonb,
  true,
  'global',
  'communication',  -- enforce_project_board_taxonomy requires domain_key for global/operational boards
  '6e9af7a8-1696-4169-a1a1-c0e160600002'::uuid,
  '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '880f736c-3e76-4df4-9375-33575c190305'::uuid  -- project_boards.created_by FK → members(id) (NOT auth.users like events.created_by)
WHERE NOT EXISTS (
  SELECT 1 FROM public.project_boards
  WHERE id = '6e9af7a8-1696-4169-a1a1-c0e160600004'::uuid
);

-- 5 board cards (status='todo', curation_status='draft', initiative-scoped via board)

INSERT INTO public.board_items (id, board_id, title, description, status, curation_status,
  assignee_id, position, due_date, organization_id, created_by, labels)
SELECT '6e9af7a8-1696-4169-a1a1-c0e160600101'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600004'::uuid,
  'Lineup de palestrantes — confirmar Ana, decidir Letícia',
  'Confirmar Ana Carla Cavalcante como palestrante (pitch + agenda check). Decidir slot da Letícia (alternativa) vs. cobertura via Sarah. Se Ana ou outro palestrante drop, mapear substituto. Atualizar metadata.confirmed_speakers da iniciativa quando aceitar.',
  'todo', 'draft',
  '293fcaf8-7dda-46f7-8e3b-1daf4c54f420'::uuid,
  1, '2026-05-26'::date, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,  -- board_items.created_by FK → members(id)
  '{"area": "speakers", "priority": "high"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.board_items WHERE id='6e9af7a8-1696-4169-a1a1-c0e160600101'::uuid);

INSERT INTO public.board_items (id, board_id, title, description, status, curation_status,
  assignee_id, position, due_date, organization_id, created_by, labels)
SELECT '6e9af7a8-1696-4169-a1a1-c0e160600102'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600004'::uuid,
  'Comunicação + canais YouTube',
  'Alinhar co-broadcast: canal Núcleo + canal evento (@sestec.software). Confirmar técnica day-of (stream redirect, OBS, etc). Envolver time de alunos/comms locais (curso Eng Software Vassouras) no planejamento de divulgação. Briefing de cada palestrante (formato mesa redonda, tom + audiência alunos).',
  'todo', 'draft',
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  2, '2026-05-29'::date, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  '{"area": "comms", "priority": "high"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.board_items WHERE id='6e9af7a8-1696-4169-a1a1-c0e160600102'::uuid);

INSERT INTO public.board_items (id, board_id, title, description, status, curation_status,
  assignee_id, position, due_date, organization_id, created_by, labels)
SELECT '6e9af7a8-1696-4169-a1a1-c0e160600103'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600004'::uuid,
  'Inscrição/registro: Sympla on-off + lead capture',
  'Decisão: ativa inscrição Sympla ou usa só RSVP do YouTube + WhatsApp? Se Sympla, criar evento + integrar fluxo de leads (visitor_leads quando contato útil). Documentar política de privacidade simplificada para estudantes (LGPD).',
  'todo', 'draft',
  '293fcaf8-7dda-46f7-8e3b-1daf4c54f420'::uuid,
  3, '2026-05-25'::date, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  '{"area": "registration", "priority": "medium"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.board_items WHERE id='6e9af7a8-1696-4169-a1a1-c0e160600103'::uuid);

INSERT INTO public.board_items (id, board_id, title, description, status, curation_status,
  assignee_id, position, due_date, organization_id, created_by, labels)
SELECT '6e9af7a8-1696-4169-a1a1-c0e160600104'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600004'::uuid,
  'Operação day-of: patrocínios + logística local',
  'Coordenado por João + time local. Camisas evento (confirmar produção/entrega). Coffee-break (confirmar fornecedor). Sorteio carteira de motorista (regulamento + fluxo de inscrição). Bolsa de pós-graduação (pedido do coordenador acadêmico — em andamento).',
  'todo', 'draft',
  '293fcaf8-7dda-46f7-8e3b-1daf4c54f420'::uuid,
  4, '2026-06-01'::date, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  '{"area": "operations", "priority": "high"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.board_items WHERE id='6e9af7a8-1696-4169-a1a1-c0e160600104'::uuid);

INSERT INTO public.board_items (id, board_id, title, description, status, curation_status,
  assignee_id, position, due_date, organization_id, created_by, labels)
SELECT '6e9af7a8-1696-4169-a1a1-c0e160600105'::uuid,
  '6e9af7a8-1696-4169-a1a1-c0e160600004'::uuid,
  'Integração institucional + continuidade',
  'PMI-RJ chapter board (Dani Paoliello, Tatiana) no loop para pitch institucional aos alunos. Documentação: criar pasta Drive da iniciativa, vincular via /admin/portfolio. Registrar URL do WhatsApp privado em initiative.metadata.whatsapp_url via UI admin (NÃO via PR público). Pós-evento: avaliar continuidade da parceria como initiative recorrente Universidade de Vassouras.',
  'todo', 'draft',
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  5, '2026-06-09'::date, '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid,
  '880f736c-3e76-4df4-9375-33575c190305'::uuid,
  '{"area": "institutional", "priority": "medium"}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.board_items WHERE id='6e9af7a8-1696-4169-a1a1-c0e160600105'::uuid);

-- ----------------------------------------------------------------------------
-- 6. PostgREST cache refresh — initiatives + engagements + events + board shapes touched
-- ----------------------------------------------------------------------------

NOTIFY pgrst, 'reload schema';
