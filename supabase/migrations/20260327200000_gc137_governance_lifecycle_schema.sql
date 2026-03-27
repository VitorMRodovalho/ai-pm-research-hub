-- ============================================================================
-- GC-137: Governance Lifecycle Schema — Sprint 1 "Encantamento"
-- 10 new columns across 3 tables + 2 RPCs
-- ============================================================================

-- PART 1: governance_documents — link to partner_entities
ALTER TABLE governance_documents
  ADD COLUMN IF NOT EXISTS partner_entity_id uuid REFERENCES partner_entities(id);

-- PART 2: change_requests — auto-generation and traceability
ALTER TABLE change_requests
  ADD COLUMN IF NOT EXISTS auto_generated boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS source_document_id uuid REFERENCES governance_documents(id);

-- PART 3: certificates — digital signature fields
ALTER TABLE certificates
  ADD COLUMN IF NOT EXISTS signature_hash text,
  ADD COLUMN IF NOT EXISTS signed_ip inet,
  ADD COLUMN IF NOT EXISTS signed_user_agent text,
  ADD COLUMN IF NOT EXISTS counter_signed_by uuid REFERENCES members(id),
  ADD COLUMN IF NOT EXISTS counter_signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS template_id text,
  ADD COLUMN IF NOT EXISTS content_snapshot jsonb;

-- PART 4: RPC — get_governance_preview()
DROP FUNCTION IF EXISTS get_governance_preview();
CREATE OR REPLACE FUNCTION get_governance_preview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_crs', (SELECT count(*) FROM change_requests WHERE status NOT IN ('withdrawn', 'rejected')),
    'by_category', (
      SELECT COALESCE(jsonb_object_agg(category, cnt), '{}'::jsonb)
      FROM (SELECT category, count(*) as cnt FROM change_requests WHERE status NOT IN ('withdrawn', 'rejected') GROUP BY category) sub
    ),
    'by_status', (
      SELECT COALESCE(jsonb_object_agg(status, cnt), '{}'::jsonb)
      FROM (SELECT status, count(*) as cnt FROM change_requests WHERE status NOT IN ('withdrawn') GROUP BY status) sub
    ),
    'sections', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'section_id', sub.category,
        'section_title', sub.section_title,
        'crs', sub.crs
      ) ORDER BY sub.sort_key), '[]'::jsonb)
      FROM (
        SELECT category,
               CASE category
                 WHEN 'manual_update' THEN 'Atualizacoes ao Manual'
                 WHEN 'role_structure' THEN 'Estrutura de Papeis'
                 WHEN 'operational_procedure' THEN 'Procedimentos Operacionais'
                 WHEN 'technical_architecture' THEN 'Arquitetura Tecnica'
                 ELSE category
               END as section_title,
               CASE category
                 WHEN 'manual_update' THEN 1
                 WHEN 'role_structure' THEN 2
                 WHEN 'operational_procedure' THEN 3
                 WHEN 'technical_architecture' THEN 4
                 ELSE 5
               END as sort_key,
               jsonb_agg(jsonb_build_object(
                 'cr_number', cr_number,
                 'title', title,
                 'description', description,
                 'proposed_changes', proposed_changes,
                 'justification', justification,
                 'status', status,
                 'priority', priority,
                 'category', category,
                 'gc_references', gc_references,
                 'impact_level', impact_level,
                 'impact_description', impact_description
               ) ORDER BY cr_number) as crs
        FROM change_requests
        WHERE status NOT IN ('withdrawn', 'rejected')
        GROUP BY category
      ) sub
    ),
    'manual_structure', jsonb_build_array(
      jsonb_build_object('id', '1', 'title', '§1 — Missao, Visao e Framework Teorico', 'status', 'new', 'cr', 'CR-029'),
      jsonb_build_object('id', '2', 'title', '§2 — Estrutura Organizacional', 'status', 'updated', 'crs', ARRAY['CR-003','CR-004','CR-014']),
      jsonb_build_object('id', '3', 'title', '§3 — Processo Seletivo', 'status', 'proposals', 'note', '7 propostas pendentes de aprovacao'),
      jsonb_build_object('id', '4', 'title', '§4 — Papeis e Responsabilidades', 'status', 'updated', 'crs', ARRAY['CR-001','CR-002','CR-007']),
      jsonb_build_object('id', '4.5', 'title', '§4.5 — Reconhecimento e Gamificacao', 'status', 'new', 'cr', 'CR-009'),
      jsonb_build_object('id', '4.6', 'title', '§4.6 — Transicoes e Desligamento', 'status', 'new', 'cr', 'CR-023'),
      jsonb_build_object('id', '4.7', 'title', '§4.7 — Framework de Acesso e Delegacao', 'status', 'new', 'cr', 'CR-033'),
      jsonb_build_object('id', '5', 'title', '§5 — Comunicacao, Eventos e Fluxos', 'status', 'updated', 'crs', ARRAY['CR-016','CR-032','CR-022']),
      jsonb_build_object('id', '6', 'title', '§6 — Sustentabilidade e KPIs', 'status', 'updated', 'crs', ARRAY['CR-013','CR-005']),
      jsonb_build_object('id', '7', 'title', '§7 — Processos de Governanca', 'status', 'updated', 'crs', ARRAY['CR-012','CR-035','CR-011']),
      jsonb_build_object('id', '7.2', 'title', '§7.2 — Servidor MCP', 'status', 'new', 'cr', 'CR-030'),
      jsonb_build_object('id', 'A', 'title', 'Anexo A — Terminologia', 'status', 'new', 'cr', 'CR-031')
    )
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_governance_preview() TO authenticated;

-- PART 5: RPC — verify_certificate(code) — PUBLIC (anon + authenticated)
DROP FUNCTION IF EXISTS verify_certificate(text);
CREATE OR REPLACE FUNCTION verify_certificate(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  cert record;
  v_member_name text;
  v_issuer_name text;
  v_countersigner_name text;
BEGIN
  SELECT c.* INTO cert
  FROM certificates c
  WHERE c.verification_code = p_code;

  IF cert IS NULL THEN
    RETURN jsonb_build_object('valid', false, 'error', 'not_found');
  END IF;

  -- Get member name
  SELECT name INTO v_member_name FROM members WHERE id = cert.member_id;

  -- Get issuer name
  IF cert.issued_by IS NOT NULL THEN
    SELECT name INTO v_issuer_name FROM members WHERE id = cert.issued_by;
  END IF;

  -- Get countersigner name if exists
  IF cert.counter_signed_by IS NOT NULL THEN
    SELECT name INTO v_countersigner_name FROM members WHERE id = cert.counter_signed_by;
  END IF;

  RETURN jsonb_build_object(
    'valid', COALESCE(cert.status, 'issued') = 'issued',
    'revoked', cert.status = 'revoked',
    'revoked_at', cert.revoked_at,
    'revoked_reason', cert.revoked_reason,
    'type', cert.type,
    'title', cert.title,
    'member_name', v_member_name,
    'issued_at', cert.issued_at,
    'issued_by', v_issuer_name,
    'counter_signed_by', v_countersigner_name,
    'counter_signed_at', cert.counter_signed_at,
    'cycle', cert.cycle,
    'period_start', cert.period_start,
    'period_end', cert.period_end,
    'function_role', cert.function_role,
    'language', cert.language,
    'verification_code', cert.verification_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION verify_certificate(text) TO anon, authenticated;

-- PART 6: Update CR-033 content with full tier framework
UPDATE change_requests
SET proposed_changes = 'Nova §4.7 — Framework de Acesso e Delegacao de Autoridade

O Nucleo opera com um modelo de permissoes em camadas (tiers) que traduz a hierarquia operacional em capacidades concretas na plataforma.

Tier 1 — Visitante: Ver homepage, blog, changelog
Tier 2 — Candidato: Aplicar ao processo seletivo
Tier 3 — Observer/Alumni: Ver conteudo, nao participar
Tier 4 — Pesquisador: Operar cards da tribo, registar producao
Tier 5 — Pesquisador Senior: Criar cards, atribuir tarefas
Tier 6 — Lider de Tribo: Gerir equipa, registar presenca, dashboard
Tier 7 — Curador: Revisar artefactos de todas as tribos (22 permissoes)
Tier 8 — Comunicacao: Publicar conteudo, gerir campanhas (7 permissoes)
Tier 9 — Deputy PM: Gerir membros, configuracoes, auditoria
Tier 10 — GP: Tudo
Tier 11 — Superadmin: Acesso tecnico independente de papel

4 eixos laterais de designacao: Curador (22 RPCs), Comunicacao (7 RPCs), Embaixador (5 RPCs), Deputy (delegacao plena).

A delegacao de autoridade e automatizada: ao atribuir um papel, as permissoes correspondentes sao activadas imediatamente.'
WHERE cr_number = 'CR-033';

NOTIFY pgrst, 'reload schema';
