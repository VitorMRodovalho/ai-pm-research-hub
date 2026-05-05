-- p90 Round 6 editorial hotfix — Ricardo Santos critique absorption (Phase 1: Editorial-only)
-- Decisions Vitor 2026-05-04:
--   1. Path A — Vitor handles curador comm via WhatsApp grupo curadoria
--   3. Termo title: "Termo de Adesão ao Serviço Voluntário"
--   4. Política title: "Política de Governança de Propriedade Intelectual"
--   5. Lei 14.063/2020 + MP 2.200-2/2001 ADITIVO
--   7. Tributária — sem Anexo Fiscal; regra-mãe simples (time financeiro caso a caso)
-- Glossary 13 new terms appended to §13.4
-- Material fixes (4) HOLD para Ângelina engagement
-- Spec doc: docs/specs/p90-round-6-editorial-material-fixes-matrix.md

BEGIN;

-- =========================================================================
-- Section 1: Title renames (3 docs) — pure metadata
-- =========================================================================
UPDATE governance_documents
SET title = 'Política de Governança de Propriedade Intelectual do Núcleo de IA & GP',
    updated_at = now()
WHERE id = 'cfb15185-2800-4441-9ff1-f36096e83aa8';

UPDATE governance_documents
SET title = 'Termo de Adesão ao Serviço Voluntário — Núcleo de IA & GP',
    updated_at = now()
WHERE id = '280c2c56-e0e3-4b10-be68-6c731d1b4520';

UPDATE governance_documents
SET title = 'Adendo Retificativo ao Termo de Adesão ao Serviço Voluntário',
    updated_at = now()
WHERE id = 'd2b7782c-dc1a-44d4-a5d5-16248117a895';

-- =========================================================================
-- Section 2: Compose v4 versions with editorial transformations
-- Trigger trg_sync_current_version_on_publish auto-updates current_version_id
-- when INSERT has locked_at IS NOT NULL
-- =========================================================================

DO $do$
DECLARE
  v_pm_id uuid;
  v_old_html text;
  v_new_html text;
  v_old_tributaria text;
  v_new_tributaria text;
  v_old_material_editorial text;
  v_new_material_editorial text;
  v_old_glossary_close text;
  v_new_glossary_close text;
BEGIN
  -- Get GP member id
  SELECT id INTO v_pm_id
  FROM members
  WHERE email = 'vitor.rodovalho@outlook.com';

  IF v_pm_id IS NULL THEN
    RAISE EXCEPTION 'GP member not found for email vitor.rodovalho@outlook.com';
  END IF;

  -- ====================================================================
  -- 2.1 Política IP v4 (5 transformations)
  -- ====================================================================
  SELECT content_html INTO v_old_html
  FROM document_versions
  WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = 'cfb15185-2800-4441-9ff1-f36096e83aa8');

  -- Transform 1: "Termo de Compromisso" → "Termo de Adesão ao Serviço Voluntário"
  v_new_html := REPLACE(v_old_html, 'Termo de Compromisso', 'Termo de Adesão ao Serviço Voluntário');

  -- Transform 2: "art. 46 Lei 9.610 + fair use" → "art. 46 da Lei nº 9.610/1998"
  v_new_html := REPLACE(v_new_html, 'art. 46 Lei 9.610 + fair use', 'art. 46 da Lei nº 9.610/1998');

  -- Transform 3: Tributária simplification (replace (e).1-(e).8 by regra-mãe simples)
  v_old_tributaria := '(e) <strong>Obrigações Tributárias sobre Royalties: Retenção e Recolhimento do IRRF.</strong></p><p><strong>(e).1 Responsabilidade da fonte pagadora.</strong> O PMI-GO, como fonte pagadora, é responsável pela retenção e recolhimento do IRRF sobre royalties, nos termos do art. 7.º da Lei n.º 7.713/1988 e do art. 685 do Decreto n.º 9.580/2018 (RIR/2018). O valor retido é deduzido do montante bruto a transferir ao beneficiário, com comprovante de retenção emitido no ato do pagamento ou em até 5 dias úteis.</p><p><strong>(e).2 Beneficiário PF residente no Brasil — tabela progressiva.</strong> Aplica-se a tabela progressiva mensal vigente (Lei 7.713/1988 atualizada pela MP 1.206/2024, faixas indicativas sujeitas a atualização anual): até R$ 2.824/mês isento; 2.824-3.751 → 7,5%; 3.751-4.664 → 15%; 4.664-6.101 → 22,5%; acima 6.101 → 27,5%. O cálculo observa deduções legais (dependentes, pensão alimentícia judicial, previdência oficial) mediante declaração do beneficiário em até 30 dias antes do primeiro pagamento.</p><p><strong>(e).3 Beneficiário PF não residente — alíquota fixa.</strong> 15% sobre valor bruto (IN RFB 1.455/2014 art. 3.º + RIR 2018 art. 685 II). Excepcionalmente 25% para residentes em jurisdição de tributação favorecida (art. 24 Lei 9.430/1996) ou regime fiscal privilegiado (art. 24-A).</p><p><strong>(e).4 Tratados para evitar dupla tributação (CDT).</strong> Quando houver CDT vigente e promulgada entre Brasil e país de residência, aplica-se a alíquota reduzida do artigo de "Royalties" da convenção, em substituição a (e).3. Para aplicação, o beneficiário apresenta previamente: (i) certificado de residência fiscal do país de domicílio, validade ≤ 12 meses; (ii) declaração escrita de beneficial owner (Modelo OCDE). Sem os documentos, aplica-se (e).3, com direito posterior de restituição do excesso retido. <em>Países com CDT vigente relevantes: Alemanha (Dec. 76.988/1976), França (Dec. 70.506/1972), Portugal (Dec. 4.012/2001), Japão (Dec. 61.899/1967), Argentina (Dec. 87.976/1982) — verificar lista RFB atualizada antes de cada pagamento.</em></p><p><strong>(e).5 Isenção e alíquota zero.</strong> Beneficiários com enquadramento em isenção legal (moléstia grave art. 6.º XIV Lei 7.713/88; rendimento anual abaixo do limite) apresentam laudo/declaração idônea antes do pagamento. PMI-GO analisa sem garantia de concessão; na dúvida, retém e orienta recuperação via DIRPF.</p><p><strong>(e).6 DIRF e obrigações acessórias.</strong> O PMI-GO inclui pagamentos de royalties e valores de IRRF retidos na DIRF (ou instrução normativa substituta vigente — e-Reinf a partir de 2025) do ano-calendário, entregue até último dia útil de fevereiro do ano subsequente. Beneficiário recebe Comprovante Anual de Rendimentos e Retenções.</p><p><strong>(e).7 Cooperação do beneficiário.</strong> Cada beneficiário informa ao PMI-GO, por declaração escrita: (i) nome completo; (ii) CPF ou NIF+passaporte para não residentes; (iii) endereço fiscal; (iv) conta bancária; (v) enquadramento em CDT ou isenção aplicável. Omissão ou falsidade isenta o PMI-GO de responsabilidade por retenção incorreta.</p><p><strong>(e).8 Revisão anual.</strong> As faixas da tabela progressiva, alíquotas de remessa e lista de CDTs são verificadas pelo GP a cada exercício fiscal antes de qualquer pagamento, sem exigir alteração textual desta Política — prevalece a legislação tributária vigente na data de cada pagamento.</p>';

  v_new_tributaria := '(e) <strong>Obrigações Tributárias.</strong></p><p>Os pagamentos de royalties e demais valores observarão a legislação tributária federal vigente na data do pagamento, sob orientação técnica do time financeiro do PMI-GO ou do capítulo responsável pela operação. Esta Política não detalha alíquotas, regimes específicos ou obrigações acessórias, que estão sujeitas a alterações legais frequentes; a aplicação concreta é verificada caso a caso conforme a legislação vigente, incluindo retenções, tratados internacionais, DIRF/eSocial/EFD-Reinf e demais instruções normativas em vigor no ato do pagamento.</p>';

  v_new_html := REPLACE(v_new_html, v_old_tributaria, v_new_tributaria);

  -- Transform 4: Glossary §13.4 — expand "Material change / Editorial change" entry
  v_old_material_editorial := '<li><strong>Material change / Editorial change.</strong> Cláusulas 12.2 e 12.3.</li>';
  v_new_material_editorial := '<li><strong>Material change.</strong> Alteração que afeta direitos, deveres, sanções, uso das obras ou regras de dados pessoais, exigindo aceite expresso dos voluntários afetados (Cláusula 12.2).</li><li><strong>Editorial change.</strong> Alteração de redação, clareza, ortografia ou organização sem impacto em direitos e deveres, podendo ser implementada com comunicação simples (Cláusula 12.3).</li>';
  v_new_html := REPLACE(v_new_html, v_old_material_editorial, v_new_material_editorial);

  -- Transform 5: Glossary — append 12 new bullets before §13.5 URL canônica
  v_old_glossary_close := '</ul><p><strong>13.5 URL canônica';
  v_new_glossary_close := '<li><strong>SCC (Standard Contractual Clauses).</strong> Cláusulas contratuais padrão usadas para autorizar transferência internacional de dados pessoais entre jurisdições sem decisão de adequação reconhecida.</li><li><strong>Adequação.</strong> Reconhecimento formal por autoridade reguladora (ANPD, Comissão Europeia, ICO, etc.) de que outra jurisdição oferece nível adequado de proteção de dados pessoais.</li><li><strong>CDT (Convenção para Evitar Dupla Tributação).</strong> Tratado entre países que disciplina a tributação de rendimentos transfronteiriços, evitando bitributação.</li><li><strong>Beneficial owner.</strong> Titular real ou efetivo de um direito ou ativo, conforme legislação fiscal e de prevenção à lavagem de dinheiro.</li><li><strong>Standby.</strong> Estado em que um voluntário ou processo aguarda determinada condição para prosseguir, sem ter sido encerrado nem retomado.</li><li><strong>Aceite expresso.</strong> Manifestação ativa e inequívoca de concordância (assinatura, clique de aceite, declaração formal). Requerido para alterações materiais (Cláusula 12.2).</li><li><strong>Aceite tácito por ato concludente.</strong> Concordância presumida pela continuidade da participação após prazo para manifestação contrária, aplicável apenas a alterações editoriais (Cláusula 12.3).</li><li><strong>Direitos morais.</strong> Direitos personalíssimos e irrenunciáveis do autor (art. 24 Lei 9.610/1998), incluindo reconhecimento da autoria e respeito à integridade da obra.</li><li><strong>Direitos patrimoniais.</strong> Direitos relativos à exploração econômica da obra (art. 28-29 Lei 9.610/1998), que podem ser licenciados ou cedidos.</li><li><strong>Coautoria.</strong> Criação conjunta da obra com contribuição intelectual relevante de duas ou mais pessoas (art. 15 Lei 9.610/1998).</li><li><strong>Obra sensível.</strong> Obra que contém dado pessoal identificável, informação confidencial, segredo estratégico, conteúdo de terceiro com restrição ou matéria potencialmente registrável (referenciado em Cláusulas 5.3 e 9).</li><li><strong>Período de graça (INPI).</strong> Janela de 12 meses anteriores ao depósito de patente, durante a qual divulgações pelo próprio inventor não impedem a proteção (art. 12 Lei 9.279/1996).</li></ul><p><strong>13.5 URL canônica';

  v_new_html := REPLACE(v_new_html, v_old_glossary_close, v_new_glossary_close);

  -- Sanity check transformations applied
  IF v_new_html = v_old_html THEN
    RAISE EXCEPTION 'Política IP — no transformations applied (sentinel mismatch). Aborting.';
  END IF;

  -- Insert Política IP v4
  INSERT INTO document_versions (
    document_id, version_number, version_label, content_html,
    authored_by, authored_at, locked_at, locked_by, notes
  ) VALUES (
    'cfb15185-2800-4441-9ff1-f36096e83aa8',
    4,
    'v2.4-p90-editorial-hotfix',
    v_new_html,
    v_pm_id,
    now(),
    now(),
    v_pm_id,
    'p90 editorial hotfix Ricardo Santos critique (Phase 1): (1) Termo de Compromisso → Termo de Adesão ao Serviço Voluntário; (2) art. 46 Lei 9.610 + fair use → art. 46 da Lei nº 9.610/1998 (drop terminologia EUA); (3) Tributária §4.5(e) simplificada para regra-mãe (sem Anexo Fiscal — verificação caso a caso pelo time financeiro); (4) Glossário §13.4 expandido com Material change + Editorial change definitions; (5) Glossário §13.4 expandido com 12 termos novos (SCC, Adequação, CDT, Beneficial owner, Standby, Aceite expresso, Aceite tácito, Direitos morais, Direitos patrimoniais, Coautoria, Obra sensível, Período de graça INPI). Material fixes (Aceite tácito framework + LGPD UE-UK + Cláusula plataforma) HOLD para Ângelina engagement.'
  );

  -- ====================================================================
  -- 2.2 Termo de Adesão (was Termo de Compromisso) v4
  -- ====================================================================
  SELECT content_html INTO v_old_html
  FROM document_versions
  WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = '280c2c56-e0e3-4b10-be68-6c731d1b4520');

  v_new_html := REPLACE(v_old_html, 'Termo de Compromisso', 'Termo de Adesão ao Serviço Voluntário');

  IF v_new_html = v_old_html THEN
    RAISE EXCEPTION 'Termo — no transformations applied. Aborting.';
  END IF;

  INSERT INTO document_versions (
    document_id, version_number, version_label, content_html,
    authored_by, authored_at, locked_at, locked_by, notes
  ) VALUES (
    '280c2c56-e0e3-4b10-be68-6c731d1b4520',
    4,
    'R3-C3-IP v2.4-p90-editorial-hotfix',
    v_new_html,
    v_pm_id,
    now(),
    now(),
    v_pm_id,
    'p90 editorial hotfix: Termo de Compromisso → Termo de Adesão ao Serviço Voluntário (conformidade Lei 9.608/1998 art. 2). Self-references no doc atualizadas.'
  );

  -- ====================================================================
  -- 2.3 Adendo Retificativo v4
  -- ====================================================================
  SELECT content_html INTO v_old_html
  FROM document_versions
  WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = 'd2b7782c-dc1a-44d4-a5d5-16248117a895');

  v_new_html := REPLACE(v_old_html, 'Termo de Compromisso', 'Termo de Adesão ao Serviço Voluntário');
  v_new_html := REPLACE(v_new_html, 'Lei nº 14.063/2021 (assinaturas eletrônicas).', 'Lei nº 14.063/2020 (assinaturas eletrônicas) e Medida Provisória nº 2.200-2/2001.');
  v_new_html := REPLACE(v_new_html, 'Lei nº 14.063/2021', 'Lei nº 14.063/2020 e MP nº 2.200-2/2001');

  IF v_new_html = v_old_html THEN
    RAISE EXCEPTION 'Adendo Retificativo — no transformations applied. Aborting.';
  END IF;

  INSERT INTO document_versions (
    document_id, version_number, version_label, content_html,
    authored_by, authored_at, locked_at, locked_by, notes
  ) VALUES (
    'd2b7782c-dc1a-44d4-a5d5-16248117a895',
    4,
    'v2.4-p90-editorial-hotfix',
    v_new_html,
    v_pm_id,
    now(),
    now(),
    v_pm_id,
    'p90 editorial hotfix: (1) Termo de Compromisso → Termo de Adesão ao Serviço Voluntário (Lei 9.608/1998); (2) Lei 14.063/2021 → Lei 14.063/2020 + Medida Provisória 2.200-2/2001 (typo factual + substrate ICP-Brasil para contratos privados).'
  );

  -- ====================================================================
  -- 2.4 Acordo Cooperação Bilateral v3 (was at v2)
  -- ====================================================================
  SELECT content_html INTO v_old_html
  FROM document_versions
  WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = 'cd170c37-3975-49c3-aae6-a918c07f157e');

  v_new_html := REPLACE(v_old_html, 'Termo de Compromisso', 'Termo de Adesão ao Serviço Voluntário');
  v_new_html := REPLACE(v_new_html, 'Lei nº 14.063/2021 (assinaturas eletrônicas);', 'Lei nº 14.063/2020 (assinaturas eletrônicas) e Medida Provisória nº 2.200-2/2001;');
  v_new_html := REPLACE(v_new_html, 'Lei nº 14.063/2021', 'Lei nº 14.063/2020 e MP nº 2.200-2/2001');

  IF v_new_html = v_old_html THEN
    RAISE EXCEPTION 'Acordo Cooperação — no transformations applied. Aborting.';
  END IF;

  INSERT INTO document_versions (
    document_id, version_number, version_label, content_html,
    authored_by, authored_at, locked_at, locked_by, notes
  ) VALUES (
    'cd170c37-3975-49c3-aae6-a918c07f157e',
    3,
    'v1.2-p90-editorial-hotfix',
    v_new_html,
    v_pm_id,
    now(),
    now(),
    v_pm_id,
    'p90 editorial hotfix: (1) Termo de Compromisso → Termo de Adesão ao Serviço Voluntário; (2) Lei 14.063/2021 → Lei 14.063/2020 + MP 2.200-2/2001.'
  );

END $do$;

-- =========================================================================
-- Section 3: Audit log entries
-- =========================================================================
INSERT INTO admin_audit_log (
  actor_id, action, target_type, target_id, changes, created_at
)
SELECT
  (SELECT id FROM members WHERE email = 'vitor.rodovalho@outlook.com'),
  'governance.editorial_hotfix_p90',
  'governance_document',
  doc_id,
  jsonb_build_object(
    'session', 'p90',
    'session_date', '2026-05-04',
    'phase', 'editorial_only',
    'reason', 'Ricardo Santos critique absorption (5 of 8 fixes shipped editorial; 4 material HOLD Ângelina)',
    'spec_doc', 'docs/specs/p90-round-6-editorial-material-fixes-matrix.md',
    'curador_comm', 'Vitor handles via WhatsApp grupo curadoria audio explanation',
    'fixes_applied', jsonb_build_array(
      'title_rename',
      'termo_compromisso_to_adesao',
      'fair_use_to_art_46_lda',
      'lei_14063_2021_to_2020_plus_mp_2200_2',
      'tributaria_simplification_no_anexo_fiscal',
      'glossary_expansion_12_terms_plus_material_editorial_definition'
    )
  ),
  now()
FROM (VALUES
  ('cfb15185-2800-4441-9ff1-f36096e83aa8'::uuid),
  ('280c2c56-e0e3-4b10-be68-6c731d1b4520'::uuid),
  ('d2b7782c-dc1a-44d4-a5d5-16248117a895'::uuid),
  ('cd170c37-3975-49c3-aae6-a918c07f157e'::uuid)
) AS t(doc_id);

-- =========================================================================
-- Section 4: NOTIFY postgrest reload
-- =========================================================================
NOTIFY pgrst, 'reload schema';

COMMIT;
