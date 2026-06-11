-- #632 — pacote jurídico revisado traz 3 instrumentos NOVOS sem doc_type adequado
-- no CHECK (decisão PM 2026-06-11: os 9 docs entram como drafts; numeração de
-- draft não migra). Tipos novos:
--   declaration_template      → doc07 Declaração de Exclusão de PI (template per-membro,
--                               instanciável; Anexo I gerado da pi_exclusion registry — #569 S4b)
--   accession_term            → doc10 Termo de Adesão Simplificado (rito Cl.14 do Acordo
--                               Bilateral; adesão de capítulo SEM aditivo do Acordo)
--   data_processing_agreement → doc11 Acordo de Operador / DPA art. 39 LGPD (Instrumento nº 9)
-- Rollback: restaurar o CHECK anterior (sem os 3 valores) — exige antes remover/alterar
-- os docs que usem os tipos novos.

ALTER TABLE public.governance_documents DROP CONSTRAINT governance_documents_doc_type_check;
ALTER TABLE public.governance_documents ADD CONSTRAINT governance_documents_doc_type_check
  CHECK ((doc_type = ANY (ARRAY['manual'::text, 'cooperation_agreement'::text, 'framework_reference'::text, 'cooperation_addendum'::text, 'volunteer_addendum'::text, 'policy'::text, 'volunteer_term_template'::text, 'executive_summary'::text, 'project_charter'::text, 'editorial_guide'::text, 'governance_guideline'::text, 'declaration_template'::text, 'accession_term'::text, 'data_processing_agreement'::text])));
