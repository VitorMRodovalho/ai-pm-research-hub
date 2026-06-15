-- #625 C2 (D1=C): vocabulário de tipos de membro configurável + i18n trilíngue.
-- display_name segue como PT-BR canônico/fallback; display_i18n carrega en/es.
-- Traduções ficam no catálogo (config) → honra ADR-0009: kind novo + traduções sem deploy.
ALTER TABLE public.engagement_kinds
  ADD COLUMN IF NOT EXISTS display_i18n jsonb NOT NULL DEFAULT '{}'::jsonb;

UPDATE public.engagement_kinds ek SET display_i18n = v.i18n
FROM (VALUES
  ('alumni',                  '{"en":"Alumni","es":"Alumni"}'::jsonb),
  ('ambassador',              '{"en":"Ambassador","es":"Embajador"}'::jsonb),
  ('candidate',               '{"en":"Candidate","es":"Candidato"}'::jsonb),
  ('chapter_board',           '{"en":"Chapter Board","es":"Junta del Capítulo"}'::jsonb),
  ('committee_coordinator',   '{"en":"Committee Coordinator","es":"Coordinador de Comité"}'::jsonb),
  ('committee_member',        '{"en":"Committee Member","es":"Miembro de Comité"}'::jsonb),
  ('external_reviewer',       '{"en":"External Reviewer","es":"Revisor Externo"}'::jsonb),
  ('external_signer',         '{"en":"External Signer","es":"Firmante Externo"}'::jsonb),
  ('guest',                   '{"en":"Guest","es":"Invitado"}'::jsonb),
  ('observer',                '{"en":"Observer","es":"Observador"}'::jsonb),
  ('partner_contact',         '{"en":"Partner Contact","es":"Contacto de Socio"}'::jsonb),
  ('speaker',                 '{"en":"Speaker","es":"Ponente"}'::jsonb),
  ('sponsor',                 '{"en":"Sponsor","es":"Patrocinador"}'::jsonb),
  ('study_group_owner',       '{"en":"Study Group Lead","es":"Líder de Grupo de Estudio"}'::jsonb),
  ('study_group_participant', '{"en":"Study Group Participant","es":"Participante de Grupo de Estudio"}'::jsonb),
  ('volunteer',               '{"en":"Active Volunteer","es":"Voluntario Activo"}'::jsonb),
  ('workgroup_coordinator',   '{"en":"Workgroup Coordinator","es":"Coordinador de Equipo"}'::jsonb),
  ('workgroup_member',        '{"en":"Workgroup Member","es":"Miembro de Equipo"}'::jsonb)
) AS v(slug, i18n)
WHERE ek.slug = v.slug;

COMMENT ON COLUMN public.engagement_kinds.display_i18n IS
  '#625 C2: traduções en/es do display_name (PT-BR canônico). Config no catálogo (ADR-0009), não no código.';
