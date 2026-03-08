# KNOWLEDGE_ASSISTANT_V1_RUNBOOK

## Arquivos
- `supabase/migrations/20260308042540_knowledge_assistant_v1.sql`
- `docs/migrations/knowledge-assistant-v1-audit.sql`
- `docs/migrations/knowledge-assistant-v1-rollback.sql`

## Ordem de execução (produção)
1. Aplicar migration pelo pipeline oficial:
   - `supabase db push --linked`
2. Rodar auditoria SQL:
   - `docs/migrations/knowledge-assistant-v1-audit.sql`
3. Smoke de rota:
   - login de usuário ativo
   - abrir `/ai-assistant`
   - buscar por termo conhecido (ex.: `CPMAI`, `governança`, `trilha`)
   - validar retorno com título, snippet e link da fonte

## Critérios de aceite
- Índice `idx_knowledge_chunks_tsv_simple` presente.
- Função `public.knowledge_search_text(...)` criada e com `grant execute` para `authenticated`.
- Busca em `/ai-assistant` retornando resultados reais para fonte `youtube`.

## Rollback
- Executar `docs/migrations/knowledge-assistant-v1-rollback.sql`.

