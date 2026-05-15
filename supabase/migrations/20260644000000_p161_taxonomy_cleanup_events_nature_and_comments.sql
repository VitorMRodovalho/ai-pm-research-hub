-- p161 Q1+Q3 — Taxonomy cleanup
-- Refs: docs/reference/SEMANTIC_TAXONOMY.md Q1 + Q3
-- PM ratification: 2026-05-14 (sessão p161)
--
-- Q1: deprecate nature='entrevista_selecao' (35 rows) — 1:1 redundante com type='entrevista'.
--     Após este migration: nature NULL = "type já self-descreve" (canonical for interviews).
--
-- Q3: clarificar overload do termo "artifact" — meeting_artifacts (4a) vs página /artifacts (4b, tribe_deliverables).

-- ── Q1 cleanup ──
UPDATE events
SET nature = NULL
WHERE nature = 'entrevista_selecao';

-- ── Q1 schema documentation ──
COMMENT ON COLUMN events.type IS
'Categoria/proposito do evento (canonical filter axis for RPCs). '
'Valores: tribo | geral | entrevista | 1on1 | lideranca | webinar | parceria | evento_externo | kickoff. '
'Ver docs/reference/SEMANTIC_TAXONOMY.md termo 1.';

COMMENT ON COLUMN events.nature IS
'Padrao de agendamento + marcador especial (ortogonal a events.type). '
'Valores: avulsa | recorrente | kickoff | NULL. '
'NULL = nature undefined (type ja self-descreve, ex: type=entrevista). '
'DEPRECATED 2026-05-14 (p161): valor "entrevista_selecao" colapsado em NULL — era redundante com type=entrevista. '
'Ver docs/reference/SEMANTIC_TAXONOMY.md termo 1 e Q1.';

-- ── Q3 schema documentation ──
COMMENT ON TABLE meeting_artifacts IS
'Registro RICO de reuniao — agenda + minutes + deliberations + snapshot. '
'NAO confundir com a pagina /artifacts (que renderiza tribe_deliverables, entregaveis de pesquisa). '
'"Artifact" aqui = registro tecnico da reuniao (taxonomy term 4a). '
'"Artefato" na UX externa = entrega de pesquisa (term 4b, tabela tribe_deliverables). '
'Ver docs/reference/SEMANTIC_TAXONOMY.md termo 4.';

-- ── Rollback ──
-- 1. UPDATE events SET nature='entrevista_selecao' WHERE type='entrevista' AND nature IS NULL;
-- 2. COMMENT ON COLUMN events.type IS NULL;
-- 3. COMMENT ON COLUMN events.nature IS NULL;
-- 4. COMMENT ON TABLE meeting_artifacts IS NULL;
