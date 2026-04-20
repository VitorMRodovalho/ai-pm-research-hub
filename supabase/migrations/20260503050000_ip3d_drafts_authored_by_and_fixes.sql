-- IP-3d cleanup sequence applied 19/04/2026 p34 (via MCP apply_migration):
--   * Fix h3→h2 no Adendo PI title
--   * Remove changelog paragraph do Termo Voluntariado + move to notes
-- Details: drafts locked_at IS NULL → trigger não bloqueia UPDATE.
UPDATE public.document_versions
SET content_html = regexp_replace(content_html, '<h3><strong>Adendo de Propriedade Intelectual aos Acordos de Cooperação Bilateral</strong></h3>',
                                  '<h2><strong>Adendo de Propriedade Intelectual aos Acordos de Cooperação Bilateral</strong></h2>')
WHERE id = '733d9bb8-b919-479c-b261-d6de5c5d4516' AND content_html LIKE '<h3>%';

UPDATE public.document_versions
SET content_html = regexp_replace(content_html, '<p><em>Alterações em relação ao R3-C3 \(termo vigente\):.*?</em></p>\s*$', '', 's'),
    notes = coalesce(notes, '') || E'\nChangelog: Cláusula 2 integralmente substituída; Cláusula 4 com parágrafo único de ressalvas; Cláusula 9 com Encarregado e §2º; Cláusula 11 com parágrafo único; Cláusulas 13 e 14 incluídas.'
WHERE id = 'd864d1bf-cb00-4bed-bfa2-f8eeb1dba35c' AND content_html LIKE '%Alterações em relação ao R3-C3%';
