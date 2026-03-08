# Data Scalability Roadmap (2026-03)

## Objetivo
Consolidar a próxima onda de evolução do banco de dados para manter custo baixo, previsibilidade de performance e governança auditável conforme o Hub escala (CoE + CoP).

## Diagnóstico técnico
- O banco já atua como backend transacional + motor de regras (RLS/RPC/Edge Functions).
- O principal gap agora é deslocar agregações pesadas do browser para modelos precomputados no servidor.
- A trilha de IA (knowledge + vetores) está funcional, mas precisa plano explícito para evolução de índice vetorial e recálculo controlado.

## Intervenções por prioridade

### Onda 1 — Agregação e Performance Operacional
1. `S-DB2` Materialized Views executivas
- Criar MViews para painéis de liderança/admin (funnel, snapshot por tribo, progresso de trilha por ciclo).
- Definir estratégia de refresh (`manual + scheduled`) com observabilidade de staleness.

2. `S-DB3` Índices e plano de consulta para tabelas de alto volume
- Revisar índices de junção/filtro em tabelas de maior leitura (`attendance`, `gamification_points`, `course_progress`, `comms_metrics_*`).
- Documentar checklist de `EXPLAIN ANALYZE` para queries críticas.

### Onda 2 — Escalabilidade IA (pgvector + base de conhecimento)
1. `S-DB4` Vetor index strategy v2
- Avaliar evolução de `ivfflat` para `hnsw` quando disponível/viável no ambiente.
- Definir fallback e critério de corte por cardinalidade (não forçar reindex sem evidência de ganho).

2. `S-DB5` Embedding refresh lifecycle
- Criar job operacional para recálculo seletivo de embeddings (delta updates), evitando reprocesso total.
- Persistir versionamento de embedding/modelo no metadata para rastreabilidade.

### Onda 3 — Governança e Auditabilidade
1. `S-DB6` Audit trail schema
- Adicionar trilha de auditoria para entidades sensíveis (`members`, `comms_metrics_*`, `gamification_points`).
- Capturar: ator, operação, antes/depois, timestamp, origem.

2. `S-DB7` Soft-delete parity
- Padronizar abordagem de retenção histórica (evitar hard delete em entidades analíticas).
- Definir checklist de integridade referencial para remover risco de quebrar métricas históricas.

## Guardrails
- Toda intervenção segue padrão: `migration + audit + rollback + runbook`.
- Mudanças de índice vetorial só entram com evidência de benchmark.
- Features de dashboard não serão marcadas `Done` sem modelo de agregação no servidor quando volume justificar.
