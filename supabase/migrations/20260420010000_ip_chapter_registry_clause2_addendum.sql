-- ============================================================================
-- IP Chapter Registry + Revised Clause 2 (Draft) + Cooperation Addendum
-- ADR: ADR-0010 (Wiki Scope) + CR-050 (IP Policy)
-- Purpose:
--   1. Create chapter_registry table for dynamic CNPJ/legal_name per chapter
--   2. Insert draft volunteer_term_template with revised clause 2 (subclauses 2.1-2.5)
--   3. Insert IP addendum template for cooperation agreements
--   4. Update sign_volunteer_agreement() to pull CNPJ from chapter_registry
-- Context: Current clause 2 assigns all IP to PMI-GO alone. CR-050 submitted 13/Apr,
--   awaiting approval. Draft template runs PARALLEL to active (R3-C3) — current signing
--   flow unchanged. Activation only after 5 presidents approve.
-- Rollback:
--   DROP TABLE IF EXISTS chapter_registry;
--   DELETE FROM governance_documents WHERE version = 'R3-C3-IP';
--   DELETE FROM governance_documents WHERE doc_type = 'addendum' AND title ILIKE '%Propriedade Intelectual%';
--   -- Re-apply previous sign_volunteer_agreement() from migration 20260415020000
-- ============================================================================

-- ═══ PART 1: chapter_registry ═══

CREATE TABLE IF NOT EXISTS chapter_registry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_code text NOT NULL UNIQUE,  -- e.g. 'GO', 'CE', 'DF', 'MG', 'RS'
  legal_name text NOT NULL,
  cnpj text,  -- null = VEP blocked for this chapter until filled
  state text NOT NULL,
  is_contracting_chapter boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- RLS
ALTER TABLE chapter_registry ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chapter_registry_read_authenticated"
  ON chapter_registry FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "chapter_registry_write_superadmin"
  ON chapter_registry FOR ALL
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM members WHERE auth_id = auth.uid() AND is_superadmin = true)
  );

-- Seed 5 chapters
INSERT INTO chapter_registry (chapter_code, legal_name, cnpj, state, is_contracting_chapter) VALUES
  ('GO', 'Seção Goiânia, Goiás — Brasil do Project Management Institute (PMI Goiás)', '06.065.645/0001-99', 'Goiás', true),
  ('CE', 'PMI Fortaleza Ceará Brazil Chapter', '06.138.890/0001-89', 'Ceará', false),
  ('DF', 'Seção Distrito Federal — Brasil do Project Management Institute', '04.271.340/0001-08', 'Distrito Federal', false),
  ('MG', 'Project Management Institute Brazil Minas Gerais Chapter', '04.372.685/0001-58', 'Minas Gerais', false),
  ('RS', 'Seção Rio Grande do Sul — Brasil do Project Management Institute', '04.595.012/0001-67', 'Rio Grande do Sul', false)
ON CONFLICT (chapter_code) DO NOTHING;


-- ═══ PART 2: Draft volunteer_term_template with revised clause 2 (2.1-2.5) ═══

INSERT INTO governance_documents (
  title, doc_type, description, version, status, valid_from,
  parties, signatories, content
)
SELECT
  'Termo de Compromisso de Voluntário — Núcleo de IA & GP',
  'volunteer_term_template',
  'Template do Termo de Voluntariado com cláusula 2 revisada (subcláusulas 2.1-2.5 de PI). Draft — pendente aprovação CR-050 pelos 5 presidentes.',
  'R3-C3-IP',
  'draft',
  now()::date,
  ARRAY['PMI-GO','PMI-CE','PMI-DF','PMI-MG','PMI-RS'],
  '[{"name":"Vitor Maia Rodovalho","role":"Gerente de Projeto"}]'::jsonb,
  '{
    "clause1": "O VOLUNTÁRIO declara que está ciente e que aceitou os termos da Lei do Serviço Voluntário, nº 9.608, de 18 de fevereiro de 1998, anexo a este termo, sendo que:",
    "clause1a": "O {chapterName} não terá qualquer vínculo trabalhista, previdenciário, fiscal e/ou financeiro com o VOLUNTÁRIO;",
    "clause1b": "Da mesma forma, qualquer parceiro do {chapterName} que venha a ter atividades desenvolvidas junto ao VOLUNTÁRIO, não terá, por razão destas atividades, qualquer vínculo trabalhista, previdenciário, fiscal e/ou financeiro com o VOLUNTÁRIO.",
    "clause1c": "O {chapterName} não se obriga a comprar, alugar, instalar, disponibilizar e/ou manter qualquer tipo de equipamento ou sistemas que venham a ser utilizados pelo VOLUNTÁRIO na execução das atividades voluntárias.",

    "clause2": "Propriedade Intelectual — Os direitos sobre obras intelectuais produzidas pelo VOLUNTÁRIO no âmbito do Programa seguem as regras abaixo:",
    "clause2_1": "2.1 Direitos Morais: O VOLUNTÁRIO retém todos os direitos morais sobre suas obras, incluindo o direito de paternidade, crédito e integridade, conforme a Lei 9.610/1998, Art. 24-27. Esses direitos são inalienáveis e irrenunciáveis.",
    "clause2_2": "2.2 Licença ao Núcleo: O VOLUNTÁRIO concede ao Núcleo de Estudos e Pesquisa em IA & GP licença não-exclusiva, gratuita, irrevogável e mundial para reproduzir, distribuir, exibir publicamente, criar obras derivadas e sublicenciar as obras produzidas no âmbito do Programa — exclusivamente para fins educacionais e científicos.",
    "clause2_3": "2.3 Direito de Publicação: O VOLUNTÁRIO mantém o direito de publicar individualmente ou em coautoria as obras produzidas, desde que inclua atribuição ao Núcleo conforme a Política de Publicação e Propriedade Intelectual vigente.",
    "clause2_4": "2.4 Notificação: Publicações externas de obras produzidas no Programa requerem notificação prévia ao Gerente de Projeto com 15 dias de antecedência, exceto para conteúdo classificado como confidencial (cláusula 9). O GP pode solicitar revisão, mas não pode vetar publicação de conteúdo Track A (Aberto).",
    "clause2_5": "2.5 Propriedade Industrial: Invenções patenteáveis desenvolvidas no âmbito do Programa seguem a Lei 9.279/1996 (Lei de Propriedade Industrial). A avaliação de patenteabilidade deve preceder qualquer divulgação. Os termos de titularidade serão definidos em instrumento específico.",

    "clause3": "O VOLUNTÁRIO, por sua vez, tem direito ao reconhecimento oficial de seu trabalho de acordo com as responsabilidades efetivamente assumidas e as tarefas efetivamente executadas.",
    "clause4": "O VOLUNTÁRIO não poderá emitir conceitos, falar ou utilizar o nome ou documentos do {chapterName} sem a prévia autorização do {chapterName}.",
    "clause5": "O VOLUNTÁRIO deverá agir sempre em conformidade com as políticas e os padrões éticos e procedimentais do PMI, e seguir todas as normas internas e do ordenamento jurídico aplicável quando do exercício de suas atividades.",
    "clause6": "A rescisão do compromisso do VOLUNTÁRIO com o {chapterName} pode ser feita em qualquer tempo, e sem qualquer ônus para ambas as partes.",
    "clause7": "O VOLUNTÁRIO poderá ser ressarcido pelas despesas que comprovadamente realizar no desempenho das atividades voluntárias, desde que previamente autorizadas pelo {chapterName} e conforme políticas do {chapterName} em vigor.",
    "clause7a": "Parágrafo único — As despesas a serem ressarcidas deverão estar expressamente autorizadas pela entidade a que for prestado o serviço voluntário.",
    "clause8": "O presente Termo tem validade indeterminada ou até o rompimento conforme disposto no artigo 6º.",
    "clause9": "Confidencialidade e LGPD: A Lei Geral de Proteção de Dados Pessoais (LGPD) dispõe ainda que quaisquer dados de terceiros e/ou informações pessoais que possam ser obtidas ou utilizadas por qualquer das partes em decorrência do presente contrato, serão recolhidos, utilizados, armazenados e mantidos de acordo com os padrões geralmente aceitos para coleta de dados, pela legislação aplicável, a Lei 13.709/2018. O voluntário se obriga a:",
    "clause9a": "Em cumprimento à Lei Geral de Proteção de Dados — LGPD, tratar os dados que forem eventualmente coletados, conforme sua necessidade ou obrigatoriedade, respeitando os princípios da finalidade, adequação, transparência, livre acesso, segurança, prevenção e não discriminação;",
    "clause9b": "Manter sigilo, tanto escrito como verbal, ou, por qualquer outra forma, de todos os dados, gerais e pessoais, informações científicas e técnicas obtidas por meio da prestação de serviço voluntário, sendo vedada a divulgação a qualquer terceiro, pessoa física ou jurídica a partir da assinatura deste termo e para todo o sempre;",
    "clause9c": "Não revelar, reproduzir, produzir cópias ou backups, utilizar ou dar conhecimento, em hipótese alguma, a terceiros, de dados, informações ou materiais obtidos por meio da prestação de serviço;",
    "clause9d": "Não tomar qualquer medida com vistas a obter para si ou para terceiros, os direitos de propriedade intelectual relativos às informações sigilosas a que tenham acesso;",
    "clause9e": "Utilizar as informações confidenciais e sigilosas apenas com o propósito de bem e fielmente cumprir com os fins do programa voluntário;",
    "clause9f": "Manter procedimentos administrativos adequados à prevenção de extravios ou perda de quaisquer documentos ou informações confidenciais, devendo comunicar imediatamente ao diretor da área a ocorrência de incidentes desta natureza, o que não excluirá sua responsabilidade.",
    "clause9note": "Parágrafo único: O {chapterName} não disponibiliza informações e/ou imagens para bancos de dados, empresas ou associações. A gestão destas informações é tratada de forma controlada e se presta somente para registro dos documentos necessários para efetivação do trabalho voluntário.",
    "clause10": "O presente Termo de Compromisso de Voluntariado estabelece e consolida as obrigações do VOLUNTÁRIO relativas à confidencialidade, ao sigilo de informações e à proteção de dados pessoais, nos termos da Lei nº 13.709/2018 (LGPD), sendo suficiente para reger tais matérias no âmbito do programa de voluntariado do {chapterName}. Para esses fins específicos, este termo substitui a necessidade de celebração de instrumento apartado de confidencialidade NDA (Non-Disclosure Agreement), sem prejuízo da possibilidade de o {chapterName}, em situações específicas e justificadas, celebrar outros acordos ou termos complementares com o VOLUNTÁRIO, conforme a natureza da atividade a ser desempenhada.",
    "clause11": "Ao assinar este Termo o VOLUNTÁRIO autoriza a utilização de fotos ou imagens profissionais captadas em evento para divulgação e promoção do trabalho voluntário e ações promovidas pelo {chapterName}, bem como, o envio de informações, contatos e outros assuntos referente ao trabalho pelo {chapterName} e outros Capítulos para seus meios de contato, sem data determinada.",
    "clause12": "Não se estabelece entre as partes, por força deste Contrato, qualquer forma de sociedade, associação, mandato, representação, agência, consórcio ou responsabilidade solidária para quaisquer fins."
  }'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM governance_documents
  WHERE doc_type = 'volunteer_term_template' AND version = 'R3-C3-IP'
);


-- ═══ PART 3: IP Addendum for Cooperation Agreements ═══

INSERT INTO governance_documents (
  title, doc_type, description, version, status, valid_from,
  parties, signatories, content
)
SELECT
  'Adendo de Propriedade Intelectual aos Acordos de Cooperação',
  'addendum',
  'Template de adendo de PI para anexar aos 4 Acordos de Cooperação bilaterais. Define regime de obras coletivas, direitos de uso irrevogável e regras de saída.',
  'v1.0-draft',
  'draft',
  now()::date,
  ARRAY['PMI-GO','PMI-CE','PMI-DF','PMI-MG','PMI-RS'],
  '[{"name":"Vitor Maia Rodovalho","role":"Gerente de Projeto"}]'::jsonb,
  '{
    "title": "Adendo de Propriedade Intelectual aos Acordos de Cooperação Bilateral",
    "version": "v1.0-draft",
    "status": "draft — pendente aprovação dos 5 presidentes",
    "reference_policy": "Política de Publicação e Propriedade Intelectual do Núcleo de IA & GP (v1.0)",

    "preambulo": "O presente adendo integra o Acordo de Cooperação bilateral celebrado entre os Capítulos signatários e tem por objetivo estabelecer regras claras de propriedade intelectual para obras produzidas no âmbito do Núcleo de Estudos e Pesquisa em Inteligência Artificial e Gestão de Projetos.",

    "art1_obras_coletivas": {
      "titulo": "Art. 1º — Obras Coletivas",
      "texto": "Obras intelectuais produzidas por voluntários de múltiplos capítulos no âmbito do Programa são consideradas obras coletivas, nos termos do Art. 5º, VIII, alínea h, da Lei 9.610/1998. Os direitos patrimoniais das obras coletivas pertencem ao Núcleo como programa interinstitucional, garantido o crédito individual aos autores conforme a Política de Publicação."
    },

    "art2_direito_uso": {
      "titulo": "Art. 2º — Direito de Uso Irrevogável",
      "texto": "Cada capítulo signatário tem direito irrevogável de uso das obras produzidas durante sua participação no Programa, incluindo reprodução, distribuição e criação de derivados para fins educacionais e científicos, conforme licenciamento definido na Política de Publicação (Track A: CC-BY 4.0; Track B: CC-BY-SA 4.0 ou MIT)."
    },

    "art3_saida": {
      "titulo": "Art. 3º — Saída de Capítulo",
      "texto": "Em caso de saída de capítulo (aviso prévio de 30 dias conforme Acordo de Cooperação), o capítulo retém direito de uso perpétuo das obras criadas durante sua participação, sem exclusividade. Novas obras produzidas após a saída não geram direito para o capítulo que deixou o Programa."
    },

    "art4_direitos_morais": {
      "titulo": "Art. 4º — Direitos Morais",
      "texto": "Os direitos morais dos autores individuais (paternidade, crédito, integridade) são inalienáveis e irrenunciáveis, conforme Lei 9.610/1998, Art. 24-27. Nenhuma disposição deste adendo ou dos Acordos de Cooperação pode restringir esses direitos."
    },

    "art5_credito": {
      "titulo": "Art. 5º — Regras de Crédito",
      "texto": "Todo output publicado deve incluir: (a) nomes dos autores individuais na ordem de contribuição substantiva; (b) afiliação institucional no formato: Núcleo de Estudos e Pesquisa em IA & GP — PMI [Capítulos de origem]; (c) líder de tribo como coautor se supervisionou o trabalho e contribuiu intelectualmente."
    },

    "art6_vigencia": {
      "titulo": "Art. 6º — Vigência",
      "texto": "Este adendo entra em vigor na data de sua assinatura pelos representantes dos capítulos e permanece vigente enquanto durar o Acordo de Cooperação ao qual está vinculado."
    },

    "art7_revisao": {
      "titulo": "Art. 7º — Revisão",
      "texto": "Este adendo será revisado anualmente ou quando houver mudança significativa na composição de capítulos ou na legislação aplicável, seguindo o processo de Change Request do Manual Operacional."
    }
  }'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM governance_documents
  WHERE doc_type = 'addendum'
    AND title ILIKE '%Propriedade Intelectual%Acordos de Cooperação%'
);


-- ═══ PART 4: Update sign_volunteer_agreement() — dynamic CNPJ via chapter_registry ═══

CREATE OR REPLACE FUNCTION public.sign_volunteer_agreement(p_language text DEFAULT 'pt-BR'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record; v_template record; v_cert_id uuid; v_code text; v_hash text;
  v_content jsonb; v_cycle int; v_existing uuid; v_issuer_id uuid; v_vep record;
  v_period_start date; v_period_end date;
  v_member_role_for_vep text; v_history record; v_source text;
  v_missing_fields text[] := '{}';
  v_engagement_updated boolean := false;
  v_chapter_cnpj text; v_chapter_legal_name text;
BEGIN
  SELECT m.id, m.name, m.email, m.operational_role, m.tribe_id, m.pmi_id, m.chapter,
    m.phone, m.address, m.city, m.state, m.country, m.birth_date,
    t.name as tribe_name
  INTO v_member
  FROM members m LEFT JOIN tribes t ON t.id = m.tribe_id
  WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- ============================================================
  -- VALIDATION GATE: all required personal fields must be filled
  -- ============================================================
  IF v_member.pmi_id IS NULL OR length(trim(v_member.pmi_id)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'pmi_id');
  END IF;
  IF v_member.phone IS NULL OR length(trim(v_member.phone)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'phone');
  END IF;
  IF v_member.address IS NULL OR length(trim(v_member.address)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'address');
  END IF;
  IF v_member.city IS NULL OR length(trim(v_member.city)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'city');
  END IF;
  IF v_member.state IS NULL OR length(trim(v_member.state)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'state');
  END IF;
  IF v_member.country IS NULL OR length(trim(v_member.country)) = 0 THEN
    v_missing_fields := array_append(v_missing_fields, 'country');
  END IF;
  IF v_member.birth_date IS NULL THEN
    v_missing_fields := array_append(v_missing_fields, 'birth_date');
  END IF;

  IF array_length(v_missing_fields, 1) > 0 THEN
    RETURN jsonb_build_object(
      'error', 'profile_incomplete',
      'message', 'Você precisa completar seu perfil antes de assinar o Termo de Voluntariado.',
      'missing_fields', to_jsonb(v_missing_fields),
      'profile_url', '/profile'
    );
  END IF;

  -- ============================================================
  -- CHAPTER REGISTRY: dynamic CNPJ + legal_name
  -- ============================================================
  SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
  FROM chapter_registry cr
  WHERE cr.chapter_code = v_member.chapter AND cr.is_active = true;

  -- Fallback for members without chapter or missing registry entry
  IF v_chapter_cnpj IS NULL THEN
    -- Default to PMI-GO as contracting chapter
    SELECT cr.cnpj, cr.legal_name INTO v_chapter_cnpj, v_chapter_legal_name
    FROM chapter_registry cr
    WHERE cr.is_contracting_chapter = true AND cr.is_active = true
    LIMIT 1;
  END IF;

  -- Final fallback (should never happen with seed data)
  IF v_chapter_cnpj IS NULL THEN
    v_chapter_cnpj := '06.065.645/0001-99';
    v_chapter_legal_name := 'PMI Goias';
  END IF;

  v_cycle := EXTRACT(YEAR FROM now())::int;
  SELECT id INTO v_existing FROM certificates
  WHERE member_id = v_member.id AND type = 'volunteer_agreement' AND cycle = v_cycle AND status = 'issued';
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('error', 'already_signed', 'certificate_id', v_existing); END IF;

  SELECT * INTO v_template FROM governance_documents
  WHERE doc_type = 'volunteer_term_template' AND status = 'active'
  ORDER BY created_at DESC LIMIT 1;
  IF v_template.id IS NULL THEN RETURN jsonb_build_object('error', 'template_not_found'); END IF;

  SELECT id INTO v_issuer_id FROM members
  WHERE chapter = v_member.chapter AND 'chapter_board' = ANY(designations) AND is_active = true
  ORDER BY operational_role = 'sponsor' DESC LIMIT 1;
  IF v_issuer_id IS NULL THEN
    SELECT id INTO v_issuer_id FROM members WHERE operational_role = 'manager' AND is_active = true LIMIT 1;
  END IF;

  v_member_role_for_vep := CASE
    WHEN v_member.operational_role IN ('manager', 'deputy_manager') THEN 'manager'
    WHEN v_member.operational_role = 'tribe_leader' THEN 'leader'
    ELSE 'researcher'
  END;

  SELECT vo.* INTO v_vep FROM selection_applications sa
  JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
  WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
    AND vo.role_default = v_member_role_for_vep
    AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
  ORDER BY sa.created_at DESC LIMIT 1;

  IF v_vep.opportunity_id IS NOT NULL THEN
    v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_match';
  ELSE
    SELECT vo.* INTO v_vep FROM selection_applications sa
    JOIN vep_opportunities vo ON vo.opportunity_id = sa.vep_opportunity_id
    WHERE lower(trim(sa.email)) = lower(trim(v_member.email))
      AND EXTRACT(YEAR FROM vo.start_date) = v_cycle
    ORDER BY sa.created_at DESC LIMIT 1;
    IF v_vep.opportunity_id IS NOT NULL THEN
      v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'application_year_match';
    ELSE
      SELECT cycle_code, cycle_start, cycle_end INTO v_history
      FROM member_cycle_history WHERE member_id = v_member.id
      ORDER BY cycle_start DESC LIMIT 1;
      IF v_history.cycle_code IS NOT NULL THEN
        v_period_start := v_history.cycle_start;
        v_period_end := (v_history.cycle_start + interval '12 months' - interval '1 day')::date;
        v_source := 'cycle_history:' || v_history.cycle_code;
      ELSE
        SELECT * INTO v_vep FROM vep_opportunities
        WHERE EXTRACT(YEAR FROM start_date) = v_cycle
          AND role_default = v_member_role_for_vep AND is_active = true
        ORDER BY start_date DESC LIMIT 1;
        IF v_vep.opportunity_id IS NOT NULL THEN
          v_period_start := v_vep.start_date; v_period_end := v_vep.end_date; v_source := 'founder_role_vep';
        ELSE
          RETURN jsonb_build_object('error', 'cannot_derive_period',
            'message', 'No application, cycle history, or matching VEP found. Admin must set period manually.',
            'member_id', v_member.id, 'member_name', v_member.name);
        END IF;
      END IF;
    END IF;
  END IF;

  v_content := jsonb_build_object(
    'template_id', v_template.id, 'template_version', v_template.version, 'template_title', v_template.title,
    'member_name', v_member.name, 'member_email', v_member.email, 'member_role', v_member.operational_role,
    'member_tribe', v_member.tribe_name, 'member_pmi_id', v_member.pmi_id, 'member_chapter', v_member.chapter,
    'member_phone', v_member.phone, 'member_address', v_member.address,
    'member_city', v_member.city, 'member_state', v_member.state,
    'member_country', v_member.country, 'member_birth_date', v_member.birth_date,
    'language', p_language, 'signed_at', now(),
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name,
    'vep_opportunity_id', v_vep.opportunity_id, 'vep_title', v_vep.title,
    'period_start', v_period_start::text, 'period_end', v_period_end::text,
    'period_source', v_source
  );

  v_code := 'TERM-' || EXTRACT(YEAR FROM now())::text || '-' || UPPER(SUBSTRING(gen_random_uuid()::text FROM 1 FOR 6));
  v_hash := encode(sha256(convert_to(v_content::text || v_member.id::text || now()::text || 'nucleo-ia-volunteer-salt', 'UTF8')), 'hex');

  INSERT INTO certificates (
    member_id, type, title, description, cycle, issued_at, issued_by, verification_code,
    period_start, period_end, function_role, language, status, signature_hash, content_snapshot, template_id
  ) VALUES (
    v_member.id, 'volunteer_agreement',
    CASE p_language WHEN 'en-US' THEN 'Volunteer Agreement — Cycle ' || v_cycle
      WHEN 'es-LATAM' THEN 'Acuerdo de Voluntariado — Ciclo ' || v_cycle
      ELSE 'Termo de Voluntariado — Ciclo ' || v_cycle END,
    v_template.description, v_cycle, now(), v_issuer_id, v_code,
    v_period_start::text, v_period_end::text,
    v_member.operational_role, p_language, 'issued', v_hash, v_content, v_template.id::text
  ) RETURNING id INTO v_cert_id;

  -- V4: Link certificate to active volunteer engagement (ADR-0006/0007)
  UPDATE public.engagements
  SET agreement_certificate_id = v_cert_id
  WHERE person_id = (SELECT id FROM public.persons WHERE legacy_member_id = v_member.id)
    AND kind = 'volunteer'
    AND status = 'active'
    AND agreement_certificate_id IS NULL;

  IF FOUND THEN v_engagement_updated := true; END IF;

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'volunteer_agreement_signed', 'certificate', v_cert_id,
    jsonb_build_object('verification_code', v_code, 'cycle', v_cycle, 'chapter', v_member.chapter,
      'chapter_cnpj', v_chapter_cnpj,
      'period_source', v_source, 'engagement_linked', v_engagement_updated));

  INSERT INTO notifications (recipient_id, type, title, body, link, source_type, source_id)
  SELECT m.id, 'volunteer_agreement_signed',
    v_member.name || ' assinou o Termo de Voluntariado',
    'Capitulo: ' || COALESCE(v_member.chapter, '—') || '. Codigo: ' || v_code,
    '/admin/certificates', 'certificate', v_cert_id
  FROM members m
  WHERE m.is_active = true AND m.id != v_member.id
    AND (m.operational_role = 'manager' OR m.is_superadmin = true
         OR ('chapter_board' = ANY(m.designations) AND m.chapter = v_member.chapter));

  RETURN jsonb_build_object('success', true, 'certificate_id', v_cert_id, 'verification_code', v_code,
    'signature_hash', v_hash, 'signed_at', now(),
    'period_start', v_period_start, 'period_end', v_period_end, 'period_source', v_source,
    'engagement_linked', v_engagement_updated,
    'chapter_cnpj', v_chapter_cnpj, 'chapter_name', v_chapter_legal_name);
END;
$function$;

NOTIFY pgrst, 'reload schema';
