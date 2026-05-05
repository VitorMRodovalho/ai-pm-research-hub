-- p90.b PATCH — fix cross-refs "Política de Publicação" → "Política de Governança"
-- + remove typo "Termo de Adesão ao Serviço Voluntário de Voluntário" duplicação
-- Detected via auditoria pós-Vitor questionamento 2026-05-04
-- See applied query in supabase migrations table for full content
-- Spec: docs/specs/p90-comms/audit_anti_alucinacao_e_checklist_coerencia.md

-- See migration body in supabase apply_migration trail (replicated content here for git source-of-truth)

DO $do$
DECLARE
  v_pm_id uuid;
  v_old_html text;
  v_new_html text;
BEGIN
  SELECT id INTO v_pm_id FROM members WHERE email = 'vitor.rodovalho@outlook.com';

  IF v_pm_id IS NULL THEN
    RAISE EXCEPTION 'GP member not found';
  END IF;

  -- Política IP v5
  SELECT content_html INTO v_old_html
  FROM document_versions
  WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = 'cfb15185-2800-4441-9ff1-f36096e83aa8');
  v_new_html := REPLACE(v_old_html, 'Política de Publicação e Propriedade Intelectual', 'Política de Governança de Propriedade Intelectual');
  v_new_html := REPLACE(v_new_html, 'Política de Publicação', 'Política de Governança');
  v_new_html := REPLACE(v_new_html, 'Termo de Adesão ao Serviço Voluntário de Voluntário', 'Termo de Adesão ao Serviço Voluntário');
  IF v_new_html = v_old_html THEN RAISE EXCEPTION 'Política IP v5 — no transformations'; END IF;
  INSERT INTO document_versions (document_id, version_number, version_label, content_html, authored_by, authored_at, locked_at, locked_by, notes)
  VALUES ('cfb15185-2800-4441-9ff1-f36096e83aa8', 5, 'v2.5-p90b-cross-ref-patch', v_new_html, v_pm_id, now(), now(), v_pm_id,
          'p90.b cross-ref patch: Politica de Publicacao -> Governanca + remove typo Termo de Adesao ao Servico Voluntario de Voluntario + H2 self-ref');

  -- Termo v5
  SELECT content_html INTO v_old_html FROM document_versions WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = '280c2c56-e0e3-4b10-be68-6c731d1b4520');
  v_new_html := REPLACE(v_old_html, 'Política de Publicação e Propriedade Intelectual', 'Política de Governança de Propriedade Intelectual');
  v_new_html := REPLACE(v_new_html, 'Política de Publicação', 'Política de Governança');
  v_new_html := REPLACE(v_new_html, 'Termo de Adesão ao Serviço Voluntário de Voluntário', 'Termo de Adesão ao Serviço Voluntário');
  IF v_new_html = v_old_html THEN RAISE EXCEPTION 'Termo v5 — no transformations'; END IF;
  INSERT INTO document_versions (document_id, version_number, version_label, content_html, authored_by, authored_at, locked_at, locked_by, notes)
  VALUES ('280c2c56-e0e3-4b10-be68-6c731d1b4520', 5, 'R3-C3-IP v2.5-p90b-cross-ref-patch', v_new_html, v_pm_id, now(), now(), v_pm_id,
          'p90.b cross-ref patch: Politica de Publicacao -> Governanca + remove duplicacao de Voluntario + H2 self-ref');

  -- Adendo Retificativo v5
  SELECT content_html INTO v_old_html FROM document_versions WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = 'd2b7782c-dc1a-44d4-a5d5-16248117a895');
  v_new_html := REPLACE(v_old_html, 'Política de Publicação e Propriedade Intelectual', 'Política de Governança de Propriedade Intelectual');
  v_new_html := REPLACE(v_new_html, 'Política de Publicação', 'Política de Governança');
  v_new_html := REPLACE(v_new_html, 'Termo de Adesão ao Serviço Voluntário de Voluntário', 'Termo de Adesão ao Serviço Voluntário');
  IF v_new_html = v_old_html THEN RAISE EXCEPTION 'Adendo Retificativo v5 — no transformations'; END IF;
  INSERT INTO document_versions (document_id, version_number, version_label, content_html, authored_by, authored_at, locked_at, locked_by, notes)
  VALUES ('d2b7782c-dc1a-44d4-a5d5-16248117a895', 5, 'v2.5-p90b-cross-ref-patch', v_new_html, v_pm_id, now(), now(), v_pm_id,
          'p90.b cross-ref patch');

  -- Adendo PI Cooperação v4 (first update of this doc)
  SELECT content_html INTO v_old_html FROM document_versions WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = '41de16e2-4f2e-4eac-b63e-8f0b45b22629');
  v_new_html := REPLACE(v_old_html, 'Política de Publicação e Propriedade Intelectual', 'Política de Governança de Propriedade Intelectual');
  v_new_html := REPLACE(v_new_html, 'Política de Publicação', 'Política de Governança');
  IF v_new_html = v_old_html THEN RAISE EXCEPTION 'Adendo PI Coop v4 — no transformations'; END IF;
  INSERT INTO document_versions (document_id, version_number, version_label, content_html, authored_by, authored_at, locked_at, locked_by, notes)
  VALUES ('41de16e2-4f2e-4eac-b63e-8f0b45b22629', 4, 'v2.4-p90b-cross-ref-patch', v_new_html, v_pm_id, now(), now(), v_pm_id,
          'p90.b cross-ref patch: 9 ocorrencias Politica de Publicacao -> Governanca');

  -- Acordo Cooperação Bilateral v4
  SELECT content_html INTO v_old_html FROM document_versions WHERE id = (SELECT current_version_id FROM governance_documents WHERE id = 'cd170c37-3975-49c3-aae6-a918c07f157e');
  v_new_html := REPLACE(v_old_html, 'Política de Publicação e Propriedade Intelectual', 'Política de Governança de Propriedade Intelectual');
  v_new_html := REPLACE(v_new_html, 'Política de Publicação', 'Política de Governança');
  v_new_html := REPLACE(v_new_html, 'Termo de Adesão ao Serviço Voluntário de Voluntário', 'Termo de Adesão ao Serviço Voluntário');
  IF v_new_html = v_old_html THEN RAISE EXCEPTION 'Acordo Coop Bilateral v4 — no transformations'; END IF;
  INSERT INTO document_versions (document_id, version_number, version_label, content_html, authored_by, authored_at, locked_at, locked_by, notes)
  VALUES ('cd170c37-3975-49c3-aae6-a918c07f157e', 4, 'v1.3-p90b-cross-ref-patch', v_new_html, v_pm_id, now(), now(), v_pm_id,
          'p90.b cross-ref patch: 12 ocorrencias Politica de Publicacao -> Governanca + 3 duplicacoes de Voluntario');
END $do$;

-- audit log
INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes, created_at)
SELECT (SELECT id FROM members WHERE email = 'vitor.rodovalho@outlook.com'),
  'governance.editorial_patch_p90b_cross_refs',
  'governance_document',
  doc_id,
  jsonb_build_object('session', 'p90.b', 'session_date', '2026-05-04', 'phase', 'editorial_patch',
    'reason', 'Auditoria pos-Vitor identificou cross-refs textuais nao atualizadas + typo do REPLACE',
    'spec_doc', 'docs/specs/p90-comms/audit_anti_alucinacao_e_checklist_coerencia.md',
    'fixes_applied', jsonb_build_array('politica_publicacao_to_governanca', 'remove_de_voluntario_duplicacao', 'h2_headers_self_ref')),
  now()
FROM (VALUES
  ('cfb15185-2800-4441-9ff1-f36096e83aa8'::uuid),
  ('280c2c56-e0e3-4b10-be68-6c731d1b4520'::uuid),
  ('d2b7782c-dc1a-44d4-a5d5-16248117a895'::uuid),
  ('41de16e2-4f2e-4eac-b63e-8f0b45b22629'::uuid),
  ('cd170c37-3975-49c3-aae6-a918c07f157e'::uuid)
) AS t(doc_id);

NOTIFY pgrst, 'reload schema';
