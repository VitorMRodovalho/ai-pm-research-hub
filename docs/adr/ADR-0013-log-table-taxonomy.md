# ADR-0013: Log Table Taxonomy (consolidate vs keep-separate)

- Status: Accepted
- Data: 2026-04-17
- Aprovado por: Vitor (PM) em 2026-04-17
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Quando uma tabela de log/audit/event consolida em `admin_audit_log`
  vs quando justifica existir separada. Fecha a questão deixada em aberto por
  ADR-0012 Princípio 5 e por B8 (consolidação parcial 2 de 17).

> **Nota sobre numeração:** ADR-0012 listou "ADR-0013 (futuro): roadmap de
> deprecation de tribes/tribe_id" como próximo passo. A reclassificação para
> "log table taxonomy" reflete ordem de urgência levantada em issue log 18/Abr
> (B8 consolidou 2, falta decidir o resto). Tribes deprecation vira ADR
> futuro quando for atacado concretamente.

## Contexto

B8 (17/Abr) consolidou `member_role_changes` (13 rows) + `member_status_transitions`
(21 rows) em `admin_audit_log` via migration 20260425020000. Isso deixou **13 outras
tabelas log/event** ativas na plataforma, sem uma regra clara sobre o destino de cada
uma. A pergunta recorrente do PM em sessões: *"essa tabela também consolida?"*

ADR-0012 Princípio 5 deu os critérios abstratos (shape diferente, volume alto,
retenção distinta) mas não fez a aplicação caso-a-caso. Este ADR fecha a lacuna.

### Inventário atual (18/Abr, 15 tabelas em `public`)

| Tabela | ~rows | Shape | Status |
|---|---|---|---|
| `admin_audit_log` | 38+ | actor+action+target+changes+metadata | **Source canônico** |
| `board_lifecycle_events` | — | board_id + event_type + actor + detail | Keep separate |
| `broadcast_log` | 25 | sender + subject + body + recipient_count + status | Keep separate |
| `comms_metrics_ingestion_log` | — | channel + fetched_at + status + rows_ingested | Keep separate |
| `curation_review_log` | — | board_item + curator + scores + decision + SLA | Keep separate |
| `data_anomaly_log` | — | anomaly_type + severity + context + auto_fixed | Keep separate |
| `email_webhook_events` | — | raw webhook payload + provider event_id | Keep separate |
| `knowledge_insights_ingestion_log` | — | source + fetched_at + rows_ingested | Keep separate |
| `mcp_usage_log` | 241+ | member + tool_name + success + execution_ms | Keep separate |
| `member_cycle_history` | 124 | member + cycle + snapshot row | Not a log (dim/fact) |
| `pii_access_log` | — | accessor + target + fields_accessed + reason | Keep separate |
| `platform_settings_log` | — | setting_key + previous + new + actor + reason | **Consolidate** |
| `publication_submission_events` | — | submission + event_type + actor + detail | Keep separate |
| `trello_import_log` | — | historical import batch (one-time) | Keep (freeze) |
| `webinar_lifecycle_events` | — | webinar + event_type + actor + detail | Keep separate |

## Decisão

### Taxonomia em 5 categorias

Cada tabela de log/event se encaixa em **exatamente uma** destas categorias. A categoria
determina o destino.

#### Categoria A — Admin Audit (consolidar em `admin_audit_log`)

Tabelas que registram **"ator humano autenticado fez mudança administrativa X em entidade Y"**
e cujo shape mapeia naturalmente para `admin_audit_log`:
`(actor_id, action, target_type, target_id, changes, metadata)`.

**Critérios:**
- Actor é humano (não sistema/cron/webhook)
- Ação é CRUD ou mudança de estado administrativa
- Volume baixo-médio (~dezenas/dia, não milhares)
- Retenção indefinida (compliance + audit trail)

**Tabelas atuais**: `platform_settings_log` (pendente consolidar).

**Consolidação B8 (feita 17/Abr)**: `member_role_changes`, `member_status_transitions`.

#### Categoria B — Domain Lifecycle Events (manter separada, shape `*_events`)

Registros de **eventos de state machine de um domínio específico**, normalmente
gerados por trigger ou RPC do próprio domínio, com shape domain-aware.

**Critérios:**
- Rastreiam um lifecycle de uma entidade de domínio (board, webinar, submission)
- Shape inclui colunas semânticas do domínio (não cabe em `changes` jsonb genérico)
- São lidas diretamente pela UI do domínio (ex: timeline de atividade do board)
- Podem ser populadas por triggers, não só por ações de humanos

**Tabelas atuais**: `board_lifecycle_events`, `webinar_lifecycle_events`,
`publication_submission_events`.

Critério de linha: se uma mudança administrativa **também** precisa virar audit (e.g.
admin moveu card, não trigger automático), o RPC escreve em **ambas** (domain_events +
admin_audit_log).

#### Categoria C — High-Volume Operational (manter separada, isolamento de IO)

Tabelas com **write volume alto** (centenas/dia+) onde consolidar em admin_audit_log
inflaria a tabela central.

**Critérios:**
- ~100+ writes/dia esperados em regime estável
- Queries primárias são agregações (funnel, performance, latência)
- Partitionable/archivable por tempo sem perda de valor funcional

**Tabelas atuais**: `mcp_usage_log` (1 row por tool call, ~241 rows em 2 semanas).

Decisão operacional: criar política de retenção (ex: purge > 90 dias) em ADR futuro.

#### Categoria D — Distinct Retention Policy (manter separada por compliance)

Tabelas cuja política de retenção é **fundamentalmente diferente** da
`admin_audit_log` (indefinida) por razões legais/regulatórias.

**Critérios:**
- LGPD Art. 16/18 (direito de apagamento) aplicável
- Retenção máxima definida em lei ou compliance (ex: 5 anos)
- Acesso restrito por regulação (ex: DPO-only)

**Tabelas atuais**: `pii_access_log` (LGPD 5y).

#### Categoria E — External Ingestion / Raw Data (manter separada, read-only após ingest)

Tabelas que **preservam payload bruto** de ingestão externa (webhook, API pull,
import batch) para troubleshooting e replay.

**Critérios:**
- Fonte externa (webhook provider, API social, CSV import)
- Payload bruto pode ser necessário para debug ou reprocessamento
- Não representa ação de humano autenticado na plataforma

**Tabelas atuais**: `email_webhook_events`, `comms_metrics_ingestion_log`,
`knowledge_insights_ingestion_log`, `trello_import_log` (freeze), `data_anomaly_log`
(system-generated).

**Sub-caso `broadcast_log`**: borderline com Categoria A (actor=admin envia broadcast)
mas classificado E por ter **body completo do email/whatsapp** — shape distinto de
`changes` jsonb + retenção potencialmente sujeita a request-to-forget.

### Critério de decisão para NOVAS tabelas (checklist de PR)

Quando alguém propuser criar uma tabela `*_log`, `*_events`, `*_history`, aplicar na ordem:

1. **É LGPD/compliance-sensitive com retenção própria?** → Categoria D, separada.
2. **É payload bruto de ingestão externa?** → Categoria E, separada.
3. **Espera-se ≥100 writes/dia em produção estável?** → Categoria C, separada.
4. **É state machine de um domínio com UI própria de timeline/activity?** → Categoria B, separada.
5. **Nenhuma das acima — é "humano fez mudança administrativa X"?** → Categoria A,
   **NÃO criar tabela nova**; escrever em `admin_audit_log` com `action=<entity>.<verb>`.

Default é consolidar. O ônus de justificativa está em quem propõe uma tabela nova.

### Ações concretas deste ADR

#### Consolidação pendente (P2)

- **`platform_settings_log`**: migrar escritas atuais para `admin_audit_log` com
  `action='platform.setting_changed'`, `target_type='setting'`, `target_id=<setting_key_hash>`,
  `changes={previous_value, new_value}`, `metadata={reason, setting_key}`. Backfill
  rows existentes com `metadata._backfill_source='platform_settings_log'`. Arquivar
  tabela em `z_archive`. Seguir padrão B8 (migration `20260425020000`).

Sessão dedicada: **não urgente** (baixo volume, shape simples). Pode entrar em uma
semana de housekeeping.

#### Sem ação imediata

- Demais 11 tabelas: classificadas e mantidas. Documentação deste ADR cobre o *porquê*
  de cada uma ficar separada.

- `member_cycle_history`: não é log — é dim/fact de membership por ciclo. Renomear
  seria churn sem ganho. Deixar.

## Consequências

### Positivas

- Pergunta "consolidar ou não?" tem resposta em menos de 1 minuto (5 critérios em ordem).
- Tabelas novas não proliferam por default — existem quando justificadas.
- `admin_audit_log` continua sendo destino único de mudanças administrativas.
- Reviewer tem checklist objetivo em PR que adiciona tabela log.

### Negativas / Tech debt reconhecida

- `platform_settings_log` fica desalinhado até consolidação (P2 tracked, baixo impacto).
- `broadcast_log` em Categoria E é borderline — se compliance pedir audit de "quem
  mandou o quê", vai exigir escrita dupla (broadcast_log + admin_audit_log).
  Antecipável mas não aplicado agora (nenhuma demanda ativa).
- Categoria C pressupõe política de retenção, que ainda não existe para `mcp_usage_log`.
  TODO: ADR de retention policy (não bloqueante).

## Próximos passos

1. **B8.1**: migration consolidando `platform_settings_log` em `admin_audit_log`
   (sessão futura, baixa prioridade).
2. **Retention policy**: ADR novo para `mcp_usage_log`, `data_anomaly_log`,
   `email_webhook_events` — política de archive/purge baseada em idade.
3. **Tribes deprecation** (originalmente planejado como ADR-0013): novo ADR quando
   a deprecação for atacada (requires inventário de 22 tabelas com tribe_id).

## Referências

- ADR-0012 Princípio 5 — critérios abstratos de log especializado vs consolidado.
- Migration `20260425020000_b8_audit_log_consolidation.sql` — precedente de consolidação
  (member_role_changes + member_status_transitions).
- Issue log 18/Abr — gap "consolidação adicional de log tables em admin_audit_log".
