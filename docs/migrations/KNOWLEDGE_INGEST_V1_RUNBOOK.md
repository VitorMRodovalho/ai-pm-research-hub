# KNOWLEDGE_INGEST_V1 Runbook

## Objetivo
Lançar a base de ingestão de conhecimento (YouTube-first) para alimentar Knowledge Hub e futuro RAG interno, com foco em baixo custo e ingestão em lote.

## Artefatos
- `supabase/migrations/20260308041010_knowledge_ingestion_v1.sql`
- `docs/migrations/knowledge-ingest-v1-audit.sql`
- `docs/migrations/knowledge-ingest-v1-rollback.sql`
- `supabase/functions/sync-knowledge-youtube/index.ts`

## Passos
1. Aplicar migration no ambiente alvo (`supabase db push` ou SQL Editor).
2. Deploy da função:
   - `supabase functions deploy sync-knowledge-youtube --no-verify-jwt`
3. Configurar secret da função:
   - `SYNC_KNOWLEDGE_INGEST_SECRET`
4. Rodar smoke dry-run:
   - `POST /functions/v1/sync-knowledge-youtube` com `{ "dry_run": true }` e header `x-sync-secret`.
5. Rodar ingestão de teste com 1-2 vídeos (payload manual `rows`).
6. Rodar auditoria SQL (`knowledge-ingest-v1-audit.sql`).

## Critérios de aceite
- Tabelas e políticas criadas sem erro.
- Pelo menos 1 item em `knowledge_assets` e chunks associados em `knowledge_chunks`.
- Log registrado em `knowledge_ingestion_runs`.
- RPC `knowledge_assets_latest` retornando dados autenticados.

## Guardrails de custo
- Ingestão em lote agendada (sem chamadas LLM em tempo real na UI).
- Processar somente delta por `source + external_id`.
- Embeddings opcionais; fase inicial pode operar sem vetorização para controlar custos.
