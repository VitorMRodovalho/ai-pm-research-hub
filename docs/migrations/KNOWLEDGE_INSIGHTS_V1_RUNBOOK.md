# KNOWLEDGE_INSIGHTS_V1_RUNBOOK

## Arquivos
- `supabase/migrations/20260308043820_knowledge_insights_v1.sql`
- `docs/migrations/knowledge-insights-v1-audit.sql`
- `docs/migrations/knowledge-insights-v1-rollback.sql`

## Ordem de execução (produção)
1. Aplicar migration:
   - `supabase db push --linked`
2. Rodar auditoria SQL:
   - `docs/migrations/knowledge-insights-v1-audit.sql`
3. Smoke funcional:
   - validar que as RPCs retornam sem erro, mesmo em base vazia

## Critérios de aceite
- Tabela `knowledge_insights` criada com RLS ativa.
- Policies `knowledge_insights_read` e `knowledge_insights_manage` presentes.
- RPCs `knowledge_insights_overview` e `knowledge_insights_backlog_candidates` disponíveis para `authenticated`.
- Query de backlog candidato executa sem erro.

## Rollback
- Executar `docs/migrations/knowledge-insights-v1-rollback.sql`.
