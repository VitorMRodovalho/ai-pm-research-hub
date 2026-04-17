# ADR-0014: Log Retention Policy (per-category archive/purge windows)

- Status: Accepted
- Data: 2026-04-17
- Aprovado por: Vitor (PM) em 2026-04-17
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Define a janela de retenção (archive/purge) para cada categoria de
  tabela log/event catalogada em ADR-0013. Fecha o TODO deixado por
  ADR-0013 ("retention policy ADR futuro") e o gap identificado em issue log
  17/Abr p3 como opportunity arquitetural.

## Contexto

ADR-0013 classificou 15 tabelas log/event em 5 categorias (A/B/C/D/E) mas
deixou explícito que **política de retenção não estava coberta**: "Categoria C
pressupõe política de retenção, que ainda não existe para `mcp_usage_log`."

Hoje (17/Abr/2026) a plataforma **não tem nenhum pg_cron de purge/archive
para tabelas log**. Os jobs de anonimização existentes (`lgpd-anonymize-inactive-monthly`,
`v4-anonymize-by-kind-monthly`) escopam apenas entidades de identidade
(`members`, `persons`, `engagements`), não logs.

### Volumes atuais (live, 17/Abr)

| Categoria | Tabela | Rows | Oldest | Rate (proj./ano) |
|---|---|---|---|---|
| A | `admin_audit_log` | 72 | 2026-03-20 | ~1.000/ano |
| B | `board_lifecycle_events` | 213 | 2026-03-14 | ~2.300/ano |
| B | `webinar_lifecycle_events` | 9 | 2026-03-28 | <100/ano |
| B | `publication_submission_events` | 0 | — | baixo |
| B | `curation_review_log` | 0 | — | baixo |
| C | `mcp_usage_log` | 250 | 2026-03-30 | ~7.000/ano |
| C | `comms_metrics_ingestion_log` | 11 | — | ~130/ano |
| C | `knowledge_insights_ingestion_log` | 1 | — | <50/ano |
| C | `data_anomaly_log` | 0 | — | spike-driven |
| D | `pii_access_log` | 0 | — | compliance-driven |
| E | `email_webhook_events` | 416 | 2026-03-27 | ~7.100/ano |
| E | `broadcast_log` | 25 | 2026-03-09 | ~800/ano |
| E | `trello_import_log` | 5 | 2026-03-10 | frozen (one-time) |
| A (pend.) | `platform_settings_log` | 1 | — | <50/ano |

Nas taxas atuais, **ninguém vai estourar storage tão cedo**. O problema que
este ADR resolve é de outra natureza:

1. **Governance clarity**: sem política explícita, cada tabela acumula
   indefinidamente por default — o que é inconsistente com a postura LGPD
   Art. 15/16 (minimização + retenção justificada).
2. **LGPD posture**: `email_webhook_events` guarda payload bruto com email do
   destinatário; `broadcast_log` guarda body completo. Sem purge, request-to-forget
   fica incompleto — mesmo que o `members` row seja anonimizado, o email aparece
   em log.
3. **Observability hygiene**: `mcp_usage_log` é observabilidade operacional —
   agregados (rate, success%, latência) são preservados em dashboards. Rows
   individuais acima de 90d têm valor quase-zero.
4. **Consistência pós-V4**: ADR-0008 definiu lifecycle per-kind para engagements.
   Paralelo para logs é natural: retenção é decisão de design, não acidente
   de não-ter-job.

## Decisão

### Janelas de retenção por categoria

| Cat | Regra | Justificativa |
|---|---|---|
| **A** `admin_audit_log` | 5 anos ativo → archive `z_archive.admin_audit_log_YYYY`; 7 anos → drop | Compliance (LGPD Art. 16, CF Art. 5º prescrição quinquenal) + investigação forense |
| **B** `*_lifecycle_events`, `curation_review_log` | **Indefinido** (parte do histórico de domínio) | UI lê diretamente (timeline); drop apagaria contexto da entidade |
| **C** `mcp_usage_log` | 90d → drop | Agregados preservados em dashboards; rows individuais para debug only |
| **C** `data_anomaly_log` | 180d após `fixed_at IS NOT NULL` → drop; **unresolved mantém indefinido** | Não perder anomalia não-resolvida; pattern analysis ≤6mo |
| **C** `comms_metrics_ingestion_log` | 90d → drop | Agregados em `comms_executive_kpis`; log é só para troubleshoot ingestão |
| **C** `knowledge_insights_ingestion_log` | 90d → drop | Idem (ingestão de insights) |
| **D** `pii_access_log` | 5 anos → anonymize `accessor_id` (mantém fato do acesso); 6 anos → drop | LGPD Art. 37: manter registro de tratamento por 5 anos; anonymização preserva estatística |
| **E** `email_webhook_events` | 180d → drop | Bounce retry window 72h; debug window 6mo suficiente; contém email (PII) |
| **E** `broadcast_log` | 2 anos → drop | Body completo pode conter PII; histórico relevante por ciclo operacional |
| **E** `trello_import_log` | **Freeze** (one-time historical) | Referência de import inicial — não acumula |

### Mecanismo

- **RPC única**: `public.purge_expired_logs(p_dry_run boolean default true, p_limit integer default 10000)`
  - Uma seção por tabela coberta, com constante `v_<table>_retention_days` no topo para discoverability
  - Retorna `table_name, purge_mode ('drop'|'archive'|'anonymize'), rows_affected, oldest_row_kept`
  - Dry-run default true: executa todos os queries como `WHERE ... RETURNING count(*)` sem commit
  - Log de execução em `admin_audit_log` com `action='platform.log_retention_run'` e `metadata={table, rows_affected, mode}`
- **pg_cron**: `log-retention-monthly` — schedule `0 4 1 * *` (dia 1º, 04:00 UTC, após jobs de anonimização)
  - Chama `purge_expired_logs(p_dry_run := false, p_limit := 50000)`
  - Limite por job: 50k rows/invocação (evita lock em tabelas grandes quando tivermos volumes altos)
- **Archive strategy (Categoria A)**:
  - Rows ≥5 anos copiadas para `z_archive.admin_audit_log_<year>` (schema de archive já em uso para B8/B9 consolidation)
  - Rows ≥7 anos: `DELETE` da archive também (statute of limitations expirado)
- **Anonymization strategy (Categoria D)**:
  - `UPDATE pii_access_log SET accessor_id = NULL, metadata = jsonb_set(metadata, '{_anonymized}', 'true')`
  - Preserva `target_id`, `fields_accessed`, `reason`, `accessed_at` — útil para "houve acesso a este registro?"
  - Após 6 anos: DELETE definitivo

### Invariantes

1. **Nenhum log é dropado dentro da janela de retenção ativa**: purge job só remove rows onde `<data_column> < now() - interval '<retention_days> days'`.
2. **`admin_audit_log` nunca é dropado ativamente**: move-se para `z_archive`, que é schema persistido permanentemente.
3. **Categoria B é off-limits para este job**: RPC não toca em `*_lifecycle_events` ou `curation_review_log`. Limpeza manual quando domain entity for deletada.
4. **Dry-run sempre disponível**: toda invocação manual deve começar com `p_dry_run := true` para preview.
5. **Falha em uma tabela não bloqueia as demais**: cada seção tem `BEGIN/EXCEPTION/END` com log do erro e continua.

### Exceções documentadas

- `trello_import_log` congelado: não é removido por este job — é referência histórica da migração Trello→plataforma. Se for preciso limpar, ação manual explícita.
- `platform_settings_log` (Cat. A pendente consolidação B8.1): aplica-se regra de Categoria A (5y→archive) a partir do momento em que for migrado para `admin_audit_log`. Antes disso, ficará como está (volume baixo, não urgente).

## Consequências

### Positivas

- **LGPD posture coerente**: request-to-forget de um membro não deixa mais fantasma em `email_webhook_events` após 6 meses; `pii_access_log` segue Art. 37 de forma auditável.
- **Governance clarity**: reviewer de PR consulta tabela de janelas e tem a resposta em 30s ("já tem retenção, ok / cria categoria nova se for caso atípico").
- **Observability sustentável**: `mcp_usage_log` não vira tabela de 10M rows em 3 anos — dashboards continuam performáticos.
- **Forensic readiness**: `admin_audit_log` com 5y ativo + 7y archive cobre investigações sem explodir tabela quente.

### Negativas / Trade-offs

- **RPC acumula complexidade**: uma seção por tabela, crescerá conforme novas tabelas entrarem. Mitigação: cada seção independente (BEGIN/EXCEPTION/END), facilita code review.
- **Archive `z_archive` gera bloat**: schema paralelo não é limpo por este job em Categoria A (só após 7 anos). Aceito: velocidade de investigação > storage.
- **Perda de dados históricos em Categoria C**: depois de 90d, `mcp_usage_log` individual não é recuperável. Se precisarmos de análise retrospectiva granular (ex: "quem usou a tool X em março passado"), temos só agregados. Mitigação: se surgir necessidade, criar view `mcp_usage_daily_agg` antes do purge.
- **Nenhuma categoria B tem retenção**: `board_lifecycle_events` poderá chegar a 100k rows em 5 anos. Aceito hoje (UI precisa); revisitável quando performance degradar.

## Implementação

**Migration**: `20260427010000_log_retention_policy.sql` (sessão futura — não bloqueante nesta sessão).

Scaffold aproximado:

```sql
CREATE OR REPLACE FUNCTION public.purge_expired_logs(
  p_dry_run boolean DEFAULT true,
  p_limit integer DEFAULT 10000
)
RETURNS TABLE (
  table_name text,
  purge_mode text,
  rows_affected bigint,
  oldest_row_kept timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mcp_retention_days integer := 90;
  v_email_webhook_retention_days integer := 180;
  v_broadcast_retention_days integer := 730;  -- 2y
  v_data_anomaly_resolved_days integer := 180;
  v_pii_access_anonymize_years integer := 5;
  v_pii_access_drop_years integer := 6;
  v_admin_audit_archive_years integer := 5;
  v_admin_audit_drop_years integer := 7;
  v_count bigint;
BEGIN
  -- Auth check: superadmin or cron context
  IF current_user NOT IN ('postgres','supabase_admin')
     AND NOT public.can_by_member(auth.uid(), 'manage_platform') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Category C: mcp_usage_log (90d drop)
  BEGIN
    IF p_dry_run THEN
      SELECT count(*) INTO v_count FROM public.mcp_usage_log
        WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval;
    ELSE
      WITH del AS (
        DELETE FROM public.mcp_usage_log
        WHERE created_at < now() - (v_mcp_retention_days || ' days')::interval
        LIMIT p_limit
        RETURNING 1
      ) SELECT count(*) INTO v_count FROM del;
    END IF;
    RETURN QUERY SELECT 'mcp_usage_log'::text, 'drop'::text, v_count,
      (SELECT min(created_at) FROM public.mcp_usage_log);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'mcp_usage_log purge failed: %', SQLERRM;
  END;

  -- ... (one block per table, same pattern)

  -- Audit meta-log
  IF NOT p_dry_run THEN
    INSERT INTO public.admin_audit_log (
      actor_id, action, target_type, target_id, metadata
    ) VALUES (
      NULL, 'platform.log_retention_run', 'system', NULL,
      jsonb_build_object('executed_at', now(), 'limit', p_limit)
    );
  END IF;
END;
$$;

-- pg_cron
SELECT cron.schedule(
  'log-retention-monthly',
  '0 4 1 * *',
  $$SELECT public.purge_expired_logs(p_dry_run := false, p_limit := 50000);$$
);
```

Smoke test esperado (imediatamente após migration):
- Dry-run retorna contagem por tabela, 0 drops
- Primeira execução real em 1º de maio: purgar `mcp_usage_log` anterior a ~fev/2026 (≥90d)

## Próximos passos

1. **Migration `20260427010000`** (sessão dedicada) — scaffold acima + unit tests + NOTIFY pgrst
2. **Dashboard**: adicionar painel "log retention status" em `/admin/analytics` com last_run + rows_dropped por tabela (opcional, low-prio)
3. **ADR revisit**: quando Categoria B crescer além de 100k rows, avaliar archive strategy distinta (partitioning por ano?)
4. **`data_anomaly_log` unresolved purge**: monitoring para alertar se surgirem anomalies sem fix há >180d — não drop automático (regra atual), mas surface

## Referências

- ADR-0008 — Per-Kind Engagement Lifecycle (precedente de política declarativa de retenção)
- ADR-0013 — Log Table Taxonomy (base de categorização usada aqui)
- Migration `20260425020000_b8_audit_log_consolidation.sql` — uso de `z_archive` como padrão
- LGPD Art. 15 (finalidade), Art. 16 (retenção), Art. 37 (registro de tratamento)
- RPC `anonymize_by_engagement_kind` — padrão de cron de anonymization mensal
