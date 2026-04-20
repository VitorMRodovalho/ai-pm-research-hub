-- IP-3d: create "Acordo de Cooperação Bilateral — Template Unificado v1.0" draft
-- Applied 19/04/2026 via MCP apply_migration ip3d_create_cooperation_template.
-- Gap addressed: legal-counsel parecer p34 Opção C — novos capítulos precisam
-- de instrumento único que integre Acordo + Adendo IP.
-- Text: 8 seções (preâmbulo + 7 cláusulas do parecer). DRAFT editável por Vitor.
-- Rollback: DELETE FROM governance_documents WHERE title LIKE '%Template Unificado%';
SELECT 'No-op stub. Document created via MCP apply_migration.'::text;
