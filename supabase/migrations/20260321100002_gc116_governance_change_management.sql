-- ============================================================================
-- MIGRATION: Governance Change Management Infrastructure
-- GC-116: manual_sections + change_requests upgrade + RPCs + R2 seed
-- CORRECTED for existing change_requests columns:
--   id, cr_number, title, status, priority, description,
--   requested_by, created_at, updated_at, proposed_changes,
--   justification, requested_by_role, reviewed_by, reviewed_at, review_notes
-- ============================================================================

-- PART 1A: manual_sections table
CREATE TABLE IF NOT EXISTS manual_sections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section_number text NOT NULL,
  title_pt text NOT NULL,
  title_en text,
  title_es text,
  content_pt text,
  content_en text,
  content_es text,
  manual_version text NOT NULL DEFAULT 'R2',
  parent_section_id uuid REFERENCES manual_sections(id),
  sort_order int NOT NULL DEFAULT 0,
  is_current boolean NOT NULL DEFAULT true,
  page_start int,
  page_end int,
  approved_at timestamptz,
  approved_by uuid[],
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ms_current_uniq ON manual_sections (section_number, manual_version) WHERE is_current = true;
CREATE INDEX IF NOT EXISTS idx_ms_version ON manual_sections (manual_version);
CREATE INDEX IF NOT EXISTS idx_ms_parent ON manual_sections (parent_section_id) WHERE parent_section_id IS NOT NULL;

-- PART 1B: Add missing columns to change_requests
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='cr_type') THEN
    ALTER TABLE change_requests ADD COLUMN cr_type text CHECK (cr_type IN ('editorial','operational','structural','emergency'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='manual_section_ids') THEN
    ALTER TABLE change_requests ADD COLUMN manual_section_ids uuid[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='gc_references') THEN
    ALTER TABLE change_requests ADD COLUMN gc_references text[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='impact_level') THEN
    ALTER TABLE change_requests ADD COLUMN impact_level text CHECK (impact_level IN ('low','medium','high','critical'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='impact_description') THEN
    ALTER TABLE change_requests ADD COLUMN impact_description text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='submitted_at') THEN
    ALTER TABLE change_requests ADD COLUMN submitted_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='approved_by_members') THEN
    ALTER TABLE change_requests ADD COLUMN approved_by_members uuid[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='approved_at') THEN
    ALTER TABLE change_requests ADD COLUMN approved_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='implemented_by') THEN
    ALTER TABLE change_requests ADD COLUMN implemented_by uuid REFERENCES members(id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='implemented_at') THEN
    ALTER TABLE change_requests ADD COLUMN implemented_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='manual_version_from') THEN
    ALTER TABLE change_requests ADD COLUMN manual_version_from text DEFAULT 'R2';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='change_requests' AND column_name='manual_version_to') THEN
    ALTER TABLE change_requests ADD COLUMN manual_version_to text;
  END IF;
END $$;

-- PART 1C: RLS for manual_sections
ALTER TABLE manual_sections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS manual_sections_read ON manual_sections;
CREATE POLICY manual_sections_read ON manual_sections FOR SELECT TO authenticated USING (is_current = true);
DROP POLICY IF EXISTS manual_sections_deny_insert ON manual_sections;
CREATE POLICY manual_sections_deny_insert ON manual_sections FOR INSERT TO authenticated WITH CHECK (false);
DROP POLICY IF EXISTS manual_sections_deny_update ON manual_sections;
CREATE POLICY manual_sections_deny_update ON manual_sections FOR UPDATE TO authenticated USING (false);
DROP POLICY IF EXISTS manual_sections_deny_delete ON manual_sections;
CREATE POLICY manual_sections_deny_delete ON manual_sections FOR DELETE TO authenticated USING (false);

-- ============================================================================
-- PART 2: RPCs
-- ============================================================================

DROP FUNCTION IF EXISTS get_manual_sections(text);
CREATE FUNCTION get_manual_sections(p_version text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public','pg_temp' AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id',id,'section_number',section_number,'title_pt',title_pt,'title_en',title_en,
    'content_pt',content_pt,'content_en',content_en,'manual_version',manual_version,
    'parent_section_id',parent_section_id,'sort_order',sort_order,
    'page_start',page_start,'page_end',page_end,'approved_at',approved_at
  ) ORDER BY sort_order) INTO v_result
  FROM manual_sections WHERE is_current=true AND (p_version IS NULL OR manual_version=p_version);
  RETURN COALESCE(v_result,'[]'::jsonb);
END; $$;

DROP FUNCTION IF EXISTS get_change_requests(text,text);
CREATE FUNCTION get_change_requests(p_status text DEFAULT NULL, p_cr_type text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public','pg_temp' AS $$
DECLARE v_caller record; v_result jsonb;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  IF v_caller.operational_role='observer' AND v_caller.is_superadmin IS NOT TRUE THEN
    RETURN jsonb_build_object('error','No access');
  END IF;
  SELECT jsonb_agg(cr_row ORDER BY cr_row->>'created_at' DESC) INTO v_result FROM (
    SELECT jsonb_build_object(
      'id',cr.id,'cr_number',cr.cr_number,'title',cr.title,'description',cr.description,
      'cr_type',cr.cr_type,'status',cr.status,'priority',cr.priority,
      'impact_level',cr.impact_level,'impact_description',cr.impact_description,
      'justification',cr.justification,'proposed_changes',cr.proposed_changes,
      'gc_references',cr.gc_references,'manual_section_ids',cr.manual_section_ids,
      'manual_version_from',cr.manual_version_from,'manual_version_to',cr.manual_version_to,
      'requested_by',cr.requested_by,'requested_by_role',cr.requested_by_role,
      'requested_by_name',rm.name,'submitted_at',cr.submitted_at,
      'reviewed_by',cr.reviewed_by,'reviewed_at',cr.reviewed_at,'review_notes',cr.review_notes,
      'approved_by_members',cr.approved_by_members,'approved_at',cr.approved_at,
      'implemented_at',cr.implemented_at,'created_at',cr.created_at
    ) AS cr_row FROM change_requests cr LEFT JOIN members rm ON rm.id=cr.requested_by
    WHERE (p_status IS NULL OR cr.status=p_status) AND (p_cr_type IS NULL OR cr.cr_type=p_cr_type)
      AND (v_caller.is_superadmin IS TRUE
        OR v_caller.operational_role IN ('manager','deputy_manager','sponsor','chapter_liaison')
        OR EXISTS (SELECT 1 FROM unnest(v_caller.designations) d WHERE d='curator')
        OR cr.status IN ('approved','implemented'))
  ) sub;
  RETURN COALESCE(v_result,'[]'::jsonb);
END; $$;

DROP FUNCTION IF EXISTS submit_change_request(text,text,text,uuid[],text[],text,text,text);
CREATE FUNCTION submit_change_request(
  p_title text, p_description text, p_cr_type text,
  p_manual_section_ids uuid[] DEFAULT NULL, p_gc_references text[] DEFAULT NULL,
  p_impact_level text DEFAULT 'medium', p_impact_description text DEFAULT NULL,
  p_justification text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public','pg_temp' AS $$
DECLARE v_caller record; v_mid uuid; v_crn text; v_nid uuid;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  IF v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager','deputy_manager','tribe_leader')
    AND NOT EXISTS (SELECT 1 FROM unnest(v_caller.designations) d WHERE d='curator')
  THEN RETURN jsonb_build_object('error','Unauthorized'); END IF;
  IF p_cr_type NOT IN ('editorial','operational','structural','emergency') THEN
    RETURN jsonb_build_object('error','Invalid cr_type'); END IF;
  SELECT 'CR-'||LPAD((COALESCE(MAX(SUBSTRING(cr_number FROM 4)::int),0)+1)::text,3,'0')
    INTO v_crn FROM change_requests WHERE cr_number ~ '^CR-\d+$';
  INSERT INTO change_requests (
    cr_number,title,description,cr_type,status,priority,
    manual_section_ids,gc_references,impact_level,impact_description,justification,
    requested_by,requested_by_role,submitted_at,manual_version_from,created_at,updated_at
  ) VALUES (
    v_crn,p_title,p_description,p_cr_type,'submitted',p_impact_level,
    p_manual_section_ids,p_gc_references,p_impact_level,p_impact_description,p_justification,
    v_mid,v_caller.operational_role,now(),'R2',now(),now()
  ) RETURNING id INTO v_nid;
  RETURN jsonb_build_object('success',true,'id',v_nid,'cr_number',v_crn);
END; $$;

DROP FUNCTION IF EXISTS review_change_request(uuid,text,text);
CREATE FUNCTION review_change_request(p_cr_id uuid, p_action text, p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public','pg_temp' AS $$
DECLARE v_caller record; v_mid uuid; v_cr record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id=auth.uid();
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Not authenticated'); END IF;
  v_mid := v_caller.id;
  SELECT * INTO v_cr FROM change_requests WHERE id=p_cr_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','CR not found'); END IF;
  IF v_caller.is_superadmin IS NOT TRUE AND v_caller.operational_role NOT IN ('manager','deputy_manager') THEN
    IF EXISTS (SELECT 1 FROM unnest(v_caller.designations) d WHERE d='curator') THEN
      IF v_cr.cr_type='structural' AND p_action='approve' THEN
        RETURN jsonb_build_object('error','Curators cannot approve structural CRs'); END IF;
    ELSIF v_caller.operational_role IN ('sponsor','chapter_liaison') THEN NULL;
    ELSE RETURN jsonb_build_object('error','Unauthorized'); END IF;
  END IF;
  IF p_action='approve' THEN
    UPDATE change_requests SET status='approved',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=COALESCE(p_notes,review_notes),
      approved_by_members=array_append(COALESCE(approved_by_members,'{}'),v_mid),
      approved_at=now(),updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='reject' THEN
    UPDATE change_requests SET status='rejected',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='request_changes' THEN
    UPDATE change_requests SET status='under_review',reviewed_by=v_mid,reviewed_at=now(),
      review_notes=p_notes,updated_at=now() WHERE id=p_cr_id;
  ELSIF p_action='implement' THEN
    IF v_cr.status!='approved' THEN RETURN jsonb_build_object('error','Must be approved first'); END IF;
    UPDATE change_requests SET status='implemented',implemented_by=v_mid,implemented_at=now(),
      manual_version_to='R3',updated_at=now() WHERE id=p_cr_id;
  ELSE RETURN jsonb_build_object('error','Invalid action'); END IF;
  RETURN jsonb_build_object('success',true,'cr_number',v_cr.cr_number,'new_status',p_action);
END; $$;

DROP FUNCTION IF EXISTS get_section_change_history(uuid);
CREATE FUNCTION get_section_change_history(p_section_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public','pg_temp' AS $$
DECLARE v_result jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'cr_number',cr.cr_number,'title',cr.title,'status',cr.status,'cr_type',cr.cr_type,
    'impact_level',cr.impact_level,'submitted_at',cr.submitted_at,
    'approved_at',cr.approved_at,'implemented_at',cr.implemented_at
  ) ORDER BY cr.created_at DESC) INTO v_result
  FROM change_requests cr WHERE p_section_id = ANY(cr.manual_section_ids);
  RETURN COALESCE(v_result,'[]'::jsonb);
END; $$;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- PART 3: SEED DATA
-- ============================================================================

-- 3A. Manual sections (R2 — 33 sections)
INSERT INTO manual_sections (section_number,title_pt,title_en,manual_version,sort_order,page_start,page_end,is_current,approved_at) VALUES
('0','Sumário Executivo','Executive Summary','R2',0,3,3,true,'2025-09-22T16:00:00Z'),
('1','Mandato Estratégico, Visão, Missão e Objetivos','Strategic Mandate, Vision, Mission and Objectives','R2',10,3,5,true,'2025-09-22T16:00:00Z'),
('1.1','Mandato Estratégico','Strategic Mandate','R2',11,3,4,true,'2025-09-22T16:00:00Z'),
('1.2','Visão','Vision','R2',12,4,4,true,'2025-09-22T16:00:00Z'),
('1.3','Missão','Mission','R2',13,4,4,true,'2025-09-22T16:00:00Z'),
('1.4','Objetivos Estratégicos','Strategic Objectives','R2',14,4,5,true,'2025-09-22T16:00:00Z'),
('1.5','Metas Operacionais','Operational Goals','R2',15,5,5,true,'2025-09-22T16:00:00Z'),
('2','Estrutura Organizacional e Governança','Organizational Structure and Governance','R2',20,5,7,true,'2025-09-22T16:00:00Z'),
('2.1','Organograma Funcional','Functional Org Chart','R2',21,6,6,true,'2025-09-22T16:00:00Z'),
('2.2','Tribos Temáticas','Research Streams','R2',22,7,7,true,'2025-09-22T16:00:00Z'),
('3','Estrutura de Participação e Responsabilidades Funcionais','Participation Structure and Functional Responsibilities','R2',30,8,14,true,'2025-09-22T16:00:00Z'),
('3.0','Modalidades de Participação no Projeto','Project Participation Modalities','R2',31,8,9,true,'2025-09-22T16:00:00Z'),
('3.1','Nível 1: Liderança dos Capítulos','Level 1: Chapter Leadership','R2',32,9,9,true,'2025-09-22T16:00:00Z'),
('3.2','Nível 2: Gerente de Projeto','Level 2: Project Manager','R2',33,9,10,true,'2025-09-22T16:00:00Z'),
('3.3','Nível 3: Líder de Tribo','Level 3: Tribe Leader','R2',34,10,10,true,'2025-09-22T16:00:00Z'),
('3.4','Nível 4: Papéis Operacionais','Level 4: Operational Roles','R2',35,10,12,true,'2025-09-22T16:00:00Z'),
('3.5','Nível 5: Embaixador do Núcleo','Level 5: Ambassador','R2',36,12,12,true,'2025-09-22T16:00:00Z'),
('3.6','Órgão de Apoio: Comitê de Curadoria','Support Body: Curation Committee','R2',37,12,13,true,'2025-09-22T16:00:00Z'),
('3.7','Responsabilidades Funcionais e Protocolos de Participação','Functional Responsibilities and Protocols','R2',38,13,13,true,'2025-09-22T16:00:00Z'),
('3.8','Processo de Integração e Desenvolvimento','Onboarding and Development Process','R2',39,13,13,true,'2025-09-22T16:00:00Z'),
('3.9','Reconhecimento de Contribuições e Registro Institucional','Contribution Recognition and Institutional Registry','R2',40,14,14,true,'2025-09-22T16:00:00Z'),
('4','Processos Operacionais e Fluxos de Trabalho','Operational Processes and Workflows','R2',50,14,16,true,'2025-09-22T16:00:00Z'),
('4.1','Cadência de Comunicação','Communication Cadence','R2',51,14,14,true,'2025-09-22T16:00:00Z'),
('4.2','Fluxo de Trabalho para Produção de Artigos','Article Production Workflow','R2',52,14,15,true,'2025-09-22T16:00:00Z'),
('4.3','Registro Institucional e Reconhecimento','Institutional Registry and Recognition','R2',53,15,16,true,'2025-09-22T16:00:00Z'),
('4.4','Representação em Eventos','Event Representation','R2',54,16,16,true,'2025-09-22T16:00:00Z'),
('5','Diretrizes de Qualidade, Ética e Conformidade','Quality, Ethics and Compliance Guidelines','R2',60,16,18,true,'2025-09-22T16:00:00Z'),
('5.1','Padrões de Qualidade do Conteúdo','Content Quality Standards','R2',61,16,17,true,'2025-09-22T16:00:00Z'),
('5.2','Diretrizes Éticas','Ethical Guidelines','R2',62,17,18,true,'2025-09-22T16:00:00Z'),
('5.3','Mecanismos de Garantia e Auditoria de Qualidade','Quality Assurance and Audit Mechanisms','R2',63,18,18,true,'2025-09-22T16:00:00Z'),
('6','Melhoria Contínua e Desenvolvimento de Colaboradores','Continuous Improvement and Development','R2',70,18,18,true,'2025-09-22T16:00:00Z'),
('7','Disposições Administrativas e Gerais','Administrative and General Provisions','R2',80,18,19,true,'2025-09-22T16:00:00Z'),
('A','Apêndice A: Registro de Constituição e Evolução','Appendix A: Constitution and Evolution Record','R2',90,20,22,true,'2025-09-22T16:00:00Z')
ON CONFLICT DO NOTHING;

-- 3B. Parent references
UPDATE manual_sections SET parent_section_id=(SELECT id FROM manual_sections WHERE section_number='1' AND is_current AND manual_version='R2') WHERE section_number IN ('1.1','1.2','1.3','1.4','1.5') AND parent_section_id IS NULL AND manual_version='R2';
UPDATE manual_sections SET parent_section_id=(SELECT id FROM manual_sections WHERE section_number='2' AND is_current AND manual_version='R2') WHERE section_number IN ('2.1','2.2') AND parent_section_id IS NULL AND manual_version='R2';
UPDATE manual_sections SET parent_section_id=(SELECT id FROM manual_sections WHERE section_number='3' AND is_current AND manual_version='R2') WHERE section_number IN ('3.0','3.1','3.2','3.3','3.4','3.5','3.6','3.7','3.8','3.9') AND parent_section_id IS NULL AND manual_version='R2';
UPDATE manual_sections SET parent_section_id=(SELECT id FROM manual_sections WHERE section_number='4' AND is_current AND manual_version='R2') WHERE section_number IN ('4.1','4.2','4.3','4.4') AND parent_section_id IS NULL AND manual_version='R2';
UPDATE manual_sections SET parent_section_id=(SELECT id FROM manual_sections WHERE section_number='5' AND is_current AND manual_version='R2') WHERE section_number IN ('5.1','5.2','5.3') AND parent_section_id IS NULL AND manual_version='R2';

-- 3C. 13 CRs (using existing columns: requested_by, justification, priority, proposed_changes)
INSERT INTO change_requests (cr_number,title,description,cr_type,status,priority,impact_level,impact_description,justification,proposed_changes,gc_references,manual_version_from,created_at,updated_at) VALUES
('CR-001','Org Chart v4: 9 tiers + superadmin + designações laterais','Estrutura evoluiu de 5 níveis para 9 tiers com superadmin flag e 4 designações laterais.','structural','draft','high','high','Redefine toda a estrutura hierárquica.','PMBOK 8 ICC: Mudança no OBS afecta WBS, RAM, communication plan.','Reescrever §2.1 com 9 tiers. Actualizar §3.1-3.7.',ARRAY['GC-multiple'],'R2',now(),now()),
('CR-002','Criação do papel Deputy Manager','Fabrício Costa como Deputy GP com superadmin + curator. Mitiga single point of failure.','structural','draft','high','high','Linha de sucessão não prevista.','PMBOK 8 ICC: RACI chart + risk response update.','Adicionar §3.2.1 Deputy Manager.',ARRAY['GC-multiple'],'R2',now(),now()),
('CR-003','Adição T6-T8 + rotação de líderes','Expansão de 5 para 8 tribos. 100% rotação de liderança no Ciclo 3.','structural','draft','high','high','3 novos workstreams + rotação completa.','PMBOK 8 ICC: Scope change + resource reallocation.','Actualizar §2.2 com 8 tribos. Formalizar adendos T6-T8.',ARRAY['GC-multiple'],'R2',now(),now()),
('CR-004','Expansão de 2 para 5 capítulos','PMI-DF, PMI-MG, PMI-RS aderiram. R2 assinado por GO+CE apenas.','structural','draft','high','high','Stakeholder register triplicou.','PMBOK 8 ICC: Stakeholder management plan update.','Actualizar Sumário + §2 + Apêndice A. R3 com 5 signatários.',NULL,'R2',now(),now()),
('CR-005','Metas operacionais parametrizáveis','Plataforma usa annual_kpi_targets dinâmico vs metas fixas do §1.5.','operational','draft','medium','medium','Flexibiliza sem alterar objectivos.','PMBOK 8 ICC: Performance baseline update.','§1.5 referencia metas por ciclo no sistema de KPIs.',ARRAY['W104'],'R2',now(),now()),
('CR-006','Modalidade Especialista Convidado não implementada','§3.0 prevê modalidade sem implementação na plataforma.','operational','draft','low','low','Gap sem demanda imediata.','PMBOK 8 ICC: Scope addition deferred.','Documentar como backlog item.',NULL,'R2',now(),now()),
('CR-007','Unificação Pesquisador/Multiplicador/Facilitador','Plataforma usa researcher unificado vs 3 sub-papéis do §3.4.','operational','draft','medium','medium','Simplificação operacional.','PMBOK 8 ICC: WBS dictionary update.','Actualizar §3.4 com papel unificado.',NULL,'R2',now(),now()),
('CR-008','Detractor detection automatizado','Regra de 3 ausências do §3.7 implementada em SQL.','editorial','draft','low','low','Já alinhado — formalizar.','PMBOK 8 ICC: Automated quality control.','Nota em §3.7 referenciando automação.',ARRAY['GC-multiple'],'R2',now(),now()),
('CR-009','Sistema gamification (XP/badges/Credly)','Reconhecimento digital que excede §3.9.','operational','draft','medium','medium','Evolução positiva.','PMBOK 8 ICC: Scope addition.','Referência ao gamification em §3.9.',ARRAY['GC-multiple','W139'],'R2',now(),now()),
('CR-010','Pipeline publicações via BoardEngine','7 etapas do §4.2 digitalizadas no BoardEngine.','operational','draft','medium','medium','Operacionaliza fluxo existente.','PMBOK 8 ICC: Tool/technique addition.','Referenciar BoardEngine em §4.2.',ARRAY['BOARD_ENGINE_SPEC'],'R2',now(),now()),
('CR-011','LGPD hardening','4 RLS removidas + members_public_safe VIEW + MS OAuth.','structural','draft','high','high','Compliance regulatório.','PMBOK 8 ICC: Regulatory compliance.','Adicionar §5.4 Privacidade e Protecção de Dados.',ARRAY['GC-103'],'R2',now(),now()),
('CR-012','Processo formal de Change Request','§7 não define CR process. Estabelecer tipos, workflow, rastreabilidade.','structural','draft','critical','critical','Meta-CR: cria o processo ICC.','PMBOK 8 ICC: Establish ICC process.','Adicionar §7.1 Processo de Controle de Mudanças.',ARRAY['GC-116'],'R2',now(),now()),
('CR-013','Zero-cost architecture','GP assume infra (Claude Max, Supabase, Cloudflare). Capítulos custo zero.','editorial','draft','low','low','Documenta realidade.','PMBOK 8 ICC: Cost baseline update.','Nota em §7 Recursos.',NULL,'R2',now(),now())
ON CONFLICT (cr_number) DO NOTHING;

-- 3D. Link CRs to sections
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('2.1','3.1','3.2','3.3','3.4','3.5','3.6','3.7') AND is_current) WHERE cr_number='CR-001' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='3.2' AND is_current) WHERE cr_number='CR-002' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('2.2','A') AND is_current) WHERE cr_number='CR-003' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('0','A') AND is_current) WHERE cr_number='CR-004' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='1.5' AND is_current) WHERE cr_number='CR-005' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='3.0' AND is_current) WHERE cr_number='CR-006' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number IN ('2.1','3.4') AND is_current) WHERE cr_number='CR-007' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='3.7' AND is_current) WHERE cr_number='CR-008' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='3.9' AND is_current) WHERE cr_number='CR-009' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='4.2' AND is_current) WHERE cr_number='CR-010' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='5.2' AND is_current) WHERE cr_number='CR-011' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='7' AND is_current) WHERE cr_number='CR-012' AND manual_section_ids IS NULL;
UPDATE change_requests SET manual_section_ids=ARRAY(SELECT id FROM manual_sections WHERE section_number='7' AND is_current) WHERE cr_number='CR-013' AND manual_section_ids IS NULL;

-- ============================================================================
-- VERIFICATION (run after migration)
-- ============================================================================
-- SELECT count(*) AS sections FROM manual_sections WHERE is_current;  -- Expected: 33
-- SELECT count(*) AS crs FROM change_requests WHERE cr_number ~ '^CR-\d{3}$';  -- Expected: 13+
-- SELECT cr_number, title, cr_type, impact_level, array_length(manual_section_ids,1) AS linked FROM change_requests WHERE cr_number ~ '^CR-' ORDER BY cr_number;
-- SELECT section_number, title_pt, parent_section_id IS NOT NULL AS has_parent FROM manual_sections WHERE is_current ORDER BY sort_order;
-- SELECT get_manual_sections('R2');
