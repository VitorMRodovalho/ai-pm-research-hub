-- ============================================================================
-- GC-118: Governance Batch Update
-- CR corrections + CR-006 withdrawn + 8 new CRs + governance_documents table
-- + quadrant column + requested_by fix + content_pt summaries
-- ============================================================================

-- BLOCK 1: governance_documents table
CREATE TABLE IF NOT EXISTS governance_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type text NOT NULL CHECK (doc_type IN ('manual','cooperation_agreement','framework_reference','addendum','policy')),
  title text NOT NULL,
  description text,
  version text,
  parties text[],
  docusign_envelope_id text,
  signed_at timestamptz,
  signatories jsonb,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','superseded','archived')),
  pdf_url text,
  valid_from timestamptz,
  valid_until timestamptz,
  exit_notice_days int,
  related_manual_sections uuid[],
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE governance_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY gd_read ON governance_documents FOR SELECT TO authenticated USING (true);
CREATE POLICY gd_deny_insert ON governance_documents FOR INSERT TO authenticated WITH CHECK (false);
CREATE POLICY gd_deny_update ON governance_documents FOR UPDATE TO authenticated USING (false);
CREATE POLICY gd_deny_delete ON governance_documents FOR DELETE TO authenticated USING (false);

-- Seed 5 documents
INSERT INTO governance_documents (doc_type, title, description, version, parties, docusign_envelope_id, signed_at, signatories, status, valid_from, exit_notice_days) VALUES
('manual',
 'Manual de Governança e Operações — R2',
 'Documento regulador do Núcleo IA. 7 secções + Apêndice A. 22 páginas. Aprovado por consenso dos capítulos GO e CE.',
 'R2', ARRAY['PMI-GO','PMI-CE'],
 'B2AFB185-4FC7-42C5-82A5-615EC7BDC98A',
 '2025-09-22T16:00:00Z',
 '[{"name":"Vitor Maia Rodovalho","role":"Gerente de Projeto"},{"name":"Ivan Lourenço","role":"Presidente PMI-GO"},{"name":"Cristiano Oliveira","role":"Presidente PMI-CE"}]'::jsonb,
 'active', '2025-09-22', NULL),

('cooperation_agreement',
 'Acordo de Cooperação PMI-GO ↔ PMI-CE',
 'Ratificação da parceria C1-C2 + formalização para C3. Duração perpétua com 30 dias aviso para saída.',
 NULL, ARRAY['PMI-GO','PMI-CE'],
 '31896EC7-25BD-4ECE-AB20-6DF2AE2E85EB',
 '2025-12-10T09:21:08Z',
 '[{"name":"Ivan Lourenço","role":"Presidente PMI-GO"},{"name":"Vitor Maia Rodovalho","role":"GP"},{"name":"Cristiano Oliveira","role":"Presidente CE 2024-2025"},{"name":"Francisca Jessica de Sousa de Alcântara","role":"Presidente CE 2026-2027"}]'::jsonb,
 'active', '2025-12-10', 30),

('cooperation_agreement',
 'Acordo de Cooperação PMI-GO ↔ PMI-DF',
 'Parceria para C3. PMI-DF fornece suporte técnico e intelectual. Duração perpétua.',
 NULL, ARRAY['PMI-GO','PMI-DF'],
 '6BAEE8D1-8495-4C36-BFF2-51882EDE389C',
 '2025-12-09T16:39:51Z',
 '[{"name":"Ivan Lourenço","role":"Presidente PMI-GO"},{"name":"Vitor Maia Rodovalho","role":"GP"},{"name":"Matheus Frederico Rosa Rocha","role":"Presidente PMI-DF"}]'::jsonb,
 'active', '2025-12-09', 30),

('cooperation_agreement',
 'Acordo de Cooperação PMI-GO ↔ PMI-MG',
 'Parceria para C3. PMI-MG fornece suporte técnico e intelectual. Duração perpétua.',
 NULL, ARRAY['PMI-GO','PMI-MG'],
 '23371C58-B66F-4BEB-A6E0-DC770DD44974',
 '2025-12-08T14:14:39Z',
 '[{"name":"Ivan Lourenço","role":"Presidente PMI-GO"},{"name":"Vitor Maia Rodovalho","role":"GP"},{"name":"Felipe Moraes Borges","role":"Presidente PMI-MG"},{"name":"Rogério do Carmo Peixoto","role":"Dir. Certificação PMI-MG"}]'::jsonb,
 'active', '2025-12-08', 30),

('cooperation_agreement',
 'Acordo de Cooperação PMI-GO ↔ PMI-RS',
 'Parceria para C3. PMI-RS fornece suporte técnico e intelectual. Duração perpétua.',
 NULL, ARRAY['PMI-GO','PMI-RS'],
 '488F733C-D447-4E08-B271-CA608B05DFDB',
 '2025-12-10T09:15:16Z',
 '[{"name":"Ivan Lourenço","role":"Presidente PMI-GO"},{"name":"Vitor Maia Rodovalho","role":"GP"},{"name":"Márcio Silva dos Santos","role":"Presidente PMI-RS"}]'::jsonb,
 'active', '2025-12-10', 30)
ON CONFLICT DO NOTHING;

-- BLOCK 2: Add quadrant to tribes
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='tribes' AND column_name='quadrant') THEN
    ALTER TABLE tribes ADD COLUMN quadrant text;
  END IF;
END $$;

UPDATE tribes SET quadrant = 'Q1' WHERE number = 1;
UPDATE tribes SET quadrant = 'Q2' WHERE number = 2;
UPDATE tribes SET quadrant = 'Q3' WHERE number IN (3,4,5,6);
UPDATE tribes SET quadrant = 'Q4' WHERE number IN (7,8);

-- BLOCK 3: Withdraw CR-006
UPDATE change_requests SET status = 'withdrawn', review_notes = 'Moved to backlog — not a manual change, is an implementation gap', updated_at = now() WHERE cr_number = 'CR-006';

-- BLOCK 4: Fix requested_by for seeded CRs (set to Vitor's member_id)
UPDATE change_requests SET requested_by = (SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1), requested_by_role = 'manager' WHERE cr_number ~ '^CR-\d{3}$' AND requested_by IS NULL;

-- BLOCK 5: Update existing CRs with corrected descriptions
-- CR-001: Add 9 tiers detail
UPDATE change_requests SET
  title = 'Org Chart v4: 9 tiers operacionais + superadmin + 4 designações laterais',
  description = 'O Manual R2 (§2.1) define 5 níveis funcionais + Comitê de Curadoria. A operação actual expandiu para 9 tiers: (1) GP, (2) Deputy GP, (3) Stakeholders, (4) CoP Leaders, (5) Project Collaborator, (6) Researchers, (7) Participant/Observer, (8) Observer/Alumni, (9) Candidates — com flag superadmin ortogonal e 4 eixos laterais: Curator (22 RPCs), Comms Team (7 RPCs), Ambassador (5 RPCs), Deputy (via designation).',
  proposed_changes = 'Reescrever §2.1 com 9 tiers + superadmin flag + 4 designações laterais. Actualizar §3.1-3.7 com novos papéis. Adicionar §3.8 impacto no onboarding.',
  updated_at = now()
WHERE cr_number = 'CR-001';

-- CR-003: Fix tribe history + add quadrants
UPDATE change_requests SET
  title = 'Reestruturação completa de tribos: C1(4)→C2(5)→C3(8 em 4 quadrantes)',
  description = 'C1/2024: 4 tribos piloto (T1-T4). C2/2025: T1 descontinuada, T2-T6 activas (5 tribos, Manual R2 lista como 1-5). C3/2026: Repaginação total — 8 tribos (T1-T8) organizadas em 4 quadrantes estratégicos: Q1 O Praticante Aumentado, Q2 Gestão de Projetos de IA, Q3 Liderança Organizacional, Q4 Futuro e Responsabilidade. 100% de rotação de liderança entre C2 e C3.',
  proposed_changes = 'Actualizar §2.2 com 8 tribos em 4 quadrantes, nomes e líderes do C3. Formalizar adendos T6-T8. Actualizar Apêndice A. Adicionar conceito de quadrantes ao manual.',
  updated_at = now()
WHERE cr_number = 'CR-003';

-- CR-004: Add cooperation agreements reference
UPDATE change_requests SET
  description = 'PMI-DF, PMI-MG e PMI-RS aderiram formalmente via Acordos de Cooperação DocuSign (8-10/Dez/2025). PMI-CE ratificou parceria C1-C2. Total: 4 acordos bilaterais assinados, todos referenciando o Manual de Governança e o PMI Chapter Partnerships Framework. Todos perpétuos com 30 dias aviso para saída.',
  proposed_changes = 'Actualizar Sumário + §2 + Apêndice A com 5 capítulos. R3 assinado por 5 presidents. Novo Apêndice B listando acordos vigentes com DocuSign IDs e datas.',
  updated_at = now()
WHERE cr_number = 'CR-004';

-- CR-008: Expand scope
UPDATE change_requests SET
  title = 'Protocolos de Participação Digitalizados (§3.7)',
  description = 'Digitalização completa dos protocolos de §3.7: attendance tracking automático, detecção de 3+ ausências consecutivas em SQL, gestão de ciclos, transição de participação entre ciclos, rastreamento de actividade por membro.',
  proposed_changes = 'Expandir §3.7 para referenciar sistema digital de attendance, detractor detection automático, e gestão de ciclos via plataforma.',
  updated_at = now()
WHERE cr_number = 'CR-008';

-- CR-010: Add cross-board curadoria
UPDATE change_requests SET
  description = 'As 7 etapas do §4.2 serão digitalizadas no BoardEngine com boards por tribo + view cross-board para curadoria. O Comitê de Curadoria vê items de todas as tribos numa vista unificada, alinhado com §3.6.',
  proposed_changes = 'Referenciar BoardEngine em §4.2. Explicar que curadoria opera como cross-board view. Vincular com §3.6 (Comitê de Curadoria).',
  updated_at = now()
WHERE cr_number = 'CR-010';

-- CR-011: Detail proposed §5.4
UPDATE change_requests SET
  proposed_changes = 'Adicionar §5.4 Privacidade e Protecção de Dados com: base legal (consentimento + legítimo interesse), inventário de dados (nome, email, capítulo, badges, attendance, XP), período de retenção (participação + 2 anos), direitos do titular (acesso, correcção, eliminação), DPO/responsável (GP), medidas técnicas (members_public_safe VIEW, RLS, SECURITY DEFINER, OAuth providers).',
  updated_at = now()
WHERE cr_number = 'CR-011';

-- BLOCK 6: Create 8 new CRs (CR-014→CR-021)
INSERT INTO change_requests (cr_number,title,description,cr_type,status,priority,impact_level,impact_description,justification,proposed_changes,gc_references,manual_version_from,requested_by,requested_by_role,submitted_at,created_at,updated_at)
SELECT v.* FROM (VALUES
('CR-014','Quadrantes Estratégicos (4Q organizam 8 tribos)','O C3 organiza 8 tribos em 4 quadrantes: Q1 O Praticante Aumentado (T1), Q2 Gestão de Projetos de IA (T2), Q3 Liderança Organizacional (T3-T6), Q4 Futuro e Responsabilidade (T7-T8). Manual R2 não tem conceito de quadrantes.','structural','submitted','high','high','Mudança arquitectural na organização do conhecimento.','PMBOK 8 ICC: WBS restructuring — agrupamento temático por quadrante.','Adicionar conceito de quadrantes em §2.2. Coluna quadrant na tabela tribes.',ARRAY['GC-multiple'],'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now()),
('CR-015','Plataforma Digital como ferramenta oficial','Manual R2 não menciona plataforma digital. A operação actual depende de plataforma Astro+React+Supabase+Cloudflare com: attendance, gamification, publications, boards, admin, blog, analytics, i18n trilingual, governança. 784 testes, 115 GC entries.','structural','submitted','high','high','Toda operação quotidiana depende da plataforma não documentada no manual.','PMBOK 8 ICC: Tool/technique addition fundamental.','Nova secção §4.5 ou §8 Plataforma Digital: stack, acesso por tier, relação com processos.',ARRAY['GC-001:GC-117'],'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now()),
('CR-016','Equipe de Comunicação como designação formal','Plataforma tem: Mayanna (comms_leader), Leticia + Andressa (comms_team), 7 RPCs dedicadas, Board de Comunicação, campanhas Resend. Manual R2 não prevê papel de comunicação.','operational','submitted','medium','medium','Papel operacional activo sem base no manual.','PMBOK 8 ICC: Resource addition.','Adicionar Equipe de Comunicação em §2.1 como papel de suporte. Referência em §3.7.',ARRAY['GC-multiple'],'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now()),
('CR-017','Trilha de Certificação IA — PMI','C3 tem 7 mini-cursos PMI com badges Credly obrigatórios, meta 70% completa, sync automático pg_cron, leaderboard na homepage. Manual R2 não menciona.','operational','submitted','medium','medium','Componente central do desenvolvimento profissional C3.','PMBOK 8 ICC: Scope addition — development program.','Referenciar em §3.8.2 (Desenvolvimento Contínuo) e §1.5 (metas).',ARRAY['CRON','W139'],'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now()),
('CR-018','CPMAI como objectivo de certificação','C3 tem meta de 2 certificados CPMAI. Prep course workspace em desenvolvimento (Pedro + Marcos + Herlon). Manual R2 não menciona PMI-CPMAI.','operational','submitted','medium','medium','Objectivo estratégico de certificação não documentado.','PMBOK 8 ICC: Strategic objective addition.','Referenciar em §1.5 (metas) e §3.8.2.',ARRAY['Pedro-1on1'],'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now()),
('CR-019','Operação por Ciclos (definição formal)','Manual R2 menciona ciclos casualmente mas não define: duração, transição, handover, selecção entre ciclos, reestruturação de tribos. Na prática: semestrais, com processo seletivo, tribos podem mudar.','operational','submitted','medium','medium','Conceito fundamental sem definição formal.','PMBOK 8 ICC: Process definition.','Nova subsecção em §4 ou §3.8: Ciclos Operacionais.',NULL,'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now()),
('CR-020','Canais de Comunicação Actualizados','§4.1 menciona WhatsApp, Slack, Teams. Na prática só WhatsApp é usado com grupos por tribo. Plataforma é canal principal para info assíncrona.','editorial','submitted','low','low','Actualização factual.','PMBOK 8 ICC: Communication plan update.','Actualizar §4.1 com canais reais.',NULL,'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now()),
('CR-021','Acordos de Cooperação + Documentos Oficiais','4 Acordos DocuSign (GO↔CE/DF/MG/RS, Dez/2025) não estão referenciados no Manual R2 nem rastreados na plataforma. Todos perpétuos, alinhados com PMI Partnerships Framework. Tabela governance_documents criada.','structural','submitted','high','high','Documentos formais assinados sem rastreamento no manual ou plataforma.','PMBOK 8 ICC: Governance framework + stakeholder documentation.','Novo Apêndice B listando acordos. Processo adesão novos capítulos alinhado com PMI Partnerships Framework 7 passos.',ARRAY['GC-118'],'R2',(SELECT id FROM members WHERE name ILIKE '%Vitor%Rodovalho%' LIMIT 1),'manager',now(),now(),now())
) AS v(cr_number,title,description,cr_type,status,priority,impact_level,impact_description,justification,proposed_changes,gc_references,manual_version_from,requested_by,requested_by_role,submitted_at,created_at,updated_at)
WHERE NOT EXISTS (SELECT 1 FROM change_requests WHERE change_requests.cr_number = v.cr_number);

-- BLOCK 7: Link new CRs to manual sections
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('2.2','1.4') AND is_current) WHERE cr_number='CR-014' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('4','7') AND is_current) WHERE cr_number='CR-015' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('2.1','3.7') AND is_current) WHERE cr_number='CR-016' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('3.8','1.5') AND is_current) WHERE cr_number='CR-017' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('1.5','3.8') AND is_current) WHERE cr_number='CR-018' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('3.8','4') AND is_current) WHERE cr_number='CR-019' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number = '4.1' AND is_current) WHERE cr_number='CR-020' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids = ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('7','A') AND is_current) WHERE cr_number='CR-021' AND manual_section_ids IS NULL;

-- BLOCK 8: RPC for governance_documents
DROP FUNCTION IF EXISTS get_governance_documents(text);
CREATE FUNCTION get_governance_documents(p_doc_type text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public','pg_temp' AS $$
DECLARE v_caller record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  SELECT jsonb_agg(jsonb_build_object(
    'id',gd.id,'doc_type',gd.doc_type,'title',gd.title,'description',gd.description,
    'version',gd.version,'parties',gd.parties,'docusign_envelope_id',gd.docusign_envelope_id,
    'signed_at',gd.signed_at,'status',gd.status,'valid_from',gd.valid_from,
    'exit_notice_days',gd.exit_notice_days,
    'signatories', CASE WHEN v_caller.is_superadmin IS TRUE OR v_caller.operational_role IN ('manager','deputy_manager','sponsor','chapter_liaison') THEN gd.signatories ELSE NULL END,
    'pdf_url', CASE WHEN v_caller.is_superadmin IS TRUE OR v_caller.operational_role IN ('manager','deputy_manager','sponsor','chapter_liaison') THEN gd.pdf_url ELSE NULL END
  ) ORDER BY gd.signed_at DESC) INTO v_result
  FROM governance_documents gd
  WHERE (p_doc_type IS NULL OR gd.doc_type = p_doc_type) AND gd.status = 'active';
  RETURN COALESCE(v_result, '[]'::jsonb);
END; $$;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- SELECT count(*) FROM governance_documents;  -- Expected: 5
-- SELECT count(*) FROM change_requests WHERE status = 'submitted';  -- Expected: 19 (12 old + 8 new - 1 withdrawn)
-- SELECT count(*) FROM change_requests WHERE status = 'withdrawn';  -- Expected: 1 (CR-006)
-- SELECT cr_number, title, status, impact_level FROM change_requests ORDER BY cr_number;
-- SELECT number, name, quadrant FROM tribes ORDER BY number;
-- SELECT get_governance_documents();
