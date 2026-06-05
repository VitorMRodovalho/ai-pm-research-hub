# ADR-0096: `impact_hours_total` view — accepted advisor risk

- Status: Accepted
- Data: 2026-05-22 (p223)
- Aprovado por: Vitor (PM) em 2026-05-22 (decisão p223 audit triage MED #10)
- Autor: Vitor (PM) + Claude (drafting)
- Escopo: Tratamento da advisor finding `security_definer_view` em `public.impact_hours_total`

## Contexto

Supabase Postgres advisor flagou `public.impact_hours_total` como `SECURITY DEFINER VIEW`
com `level: ERROR`. Auditoria p223 confirmou estado atual:

- **ACL**: `anon` NÃO tem SELECT (REVOKE'd em migration `20260426155255_track_r_pg_graphql_anon_revoke_batch2.sql` linha 120). Apenas `authenticated` + `service_role` + `postgres` (owner) podem SELECT.
- **Conteúdo**: agregado platform-wide YTD de horas de impacto (sem PII por linha — totais escalares + target + percentual).
- **Definição** (canonical p170 BUG-HOI, migration `20260674400000_p170_hoi_canonical.sql`):

```sql
CREATE OR REPLACE VIEW public.impact_hours_total AS
SELECT
  COALESCE(round(sum(COALESCE(e.duration_actual, e.duration_minutes)/60.0)
                  FILTER (WHERE a.present = true AND a.excused IS NOT TRUE), 1), 0) AS total_impact_hours,
  count(DISTINCT e.id) AS total_events,
  count(a.id) FILTER (WHERE a.present = true AND a.excused IS NOT TRUE) AS total_attendances,
  1800.0 AS annual_target_hours,
  round(...) AS percent_of_target
FROM events e LEFT JOIN attendance a ON a.event_id = e.id
WHERE e.date >= make_date(EXTRACT(year FROM now())::int, 1, 1) AND e.date <= CURRENT_DATE;
```

**5 callsites** (inventory p223):

| Use case | File / migration |
|---|---|
| Authenticated UI client-fetch | `src/pages/attendance.astro:663` |
| KPI summary RPC (member-facing dashboard) | migration `20260309001000_kpi_summary_rpc.sql:17-19` |
| KPI targets health check | migration `20260319000002_w104_kpi_targets_health.sql:50,99` |
| Cycle report RPC | migration `20260319000003_w105_cycle_report_rpc.sql:152` |
| Analytics v2 internal readonly | migration `20260312110000_analytics_v2_internal_readonly_and_metrics.sql:350` |

## Decisão

**Manter view com `SECURITY DEFINER` (Postgres view default).** Advisor finding registrada
como risco aceito documentado neste ADR + `COMMENT ON VIEW` referenciando-o.

Esta decisão **explicita** a intenção que já estava codificada em migration
`20260508030000_security_sweep_wave1_flip_invoker_6_views.sql` (Wave 1 invoker-flip
sweep), que explicitamente NÃO flipou `impact_hours_total` (comentário linha 27:
*"impact_hours_total — platform-wide aggregate, anon grant kept (UI anon-pre-auth)"*).
O comentário ficou desatualizado quando migration posterior fez REVOKE anon
(`20260426155255` linha 120), mas a decisão arquitetural de manter SECDEF permanece
válida pelos motivos abaixo.

## Análise de trade-off

Quatro caminhos avaliados:

| Opção | Custo | Risco UX | Advisor closes |
|---|---:|---|---:|
| α — flip `security_invoker=true` + RLS herda de attendance/events | 1-2h | medium (attendance.astro pode quebrar; depende de attendance RLS expor agregados) | yes |
| β — DROP view + SECDEF RPC `get_impact_hours_total()` | 3-4h | low-medium (5 callsites para refactor + retest cycle_report + KPI summary) | yes |
| γ — slim view (drop colunas) + SECDEF RPC para sensitive | n/a | n/a | n/a (view já não tem colunas sensíveis — só agregados escalares) |
| **δ — document risk** | **30min** | **none** | **no (tracked)** |

PM escolheu **δ** com justificativa:

1. **Conteúdo é platform-aggregate** — totais escalares (horas, count, target, pct). Zero PII por linha. Threat surface materialmente menor que `public_members` (ADR-0024, 22 colunas pessoais).
2. **`anon` já REVOKE'd** — surface real é `authenticated` (membros logados vendo KPI da plataforma). View existe especificamente porque KPI da comunidade deve ser visível a todos os membros, não filtrado por engagement individual.
3. **Decisão arquitetural já documentada em migration** (`20260508030000`) — flip-to-invoker foi explicitamente skipped para esta view. ADR formaliza o que código já praticava.
4. **5 callsites consolidados** em RPCs (kpi_summary, w104_kpi_targets_health, w105_cycle_report) — qualquer refactor exige cascading retest. Custo desproporcional ao benefício (advisor green vs documented risk).

## Consequências

### Positivas

- **Zero regression UX**: attendance.astro + 4 RPCs continuam funcionando sem touch.
- **Trade-off explícito**: ADR + COMMENT ON VIEW deixam decisão rastreável. Auditoria futura sabe que finding foi avaliada (não missed).
- **Padrão consistente com ADR-0024** (`public_members`): risk-accepted SECDEF view pattern para conteúdo intencionalmente exposto aos consumidores legítimos.

### Negativas

- **Advisor finding stays open** com `level: ERROR` para `security_definer_view`. Pode re-aparecer em audit reports até refactor (β). Mitigated por este ADR como trail explícito.

## Risco aceito

SECURITY DEFINER bypassa RLS de querying user, executando como view owner (`postgres`).
Para `impact_hours_total`:

- **Não há RLS em events/attendance que filtre por org/initiative para authenticated** (KPI é platform-wide por design).
- **Conteúdo é agregado escalar, não rows de usuário** — não há "vazamento" possível porque não há rows individualizáveis na resposta.
- **anon não tem acesso** (REVOKE confirmed live p223) — superfície real é authenticated, que já tem acesso conceitual à informação.

Threat model não materializa: an attacker authenticated não obtém via esta view nada que não obteria também via cálculo derivado de `events`/`attendance` (que ele já pode ler).

## Follow-up planejado

**Não comprometido em sprint específico.** Caminho δ é definitivo a menos que:

1. Audit externo flagar como blocker (não advisor).
2. Mudança arquitetural exigir per-tenant scoping de KPI (e.g., multi-org strict
   separation) — momento natural para β.
3. Refactor consolidado for combinado com ADR-0024 (`public_members`) em uma "SECDEF
   view cleanup wave".

Quando refactor for executado (recomendação β):

1. Criar `get_impact_hours_total()` SECDEF RPC com mesma assinatura return (5 colunas).
2. Refactor 5 callsites:
   - `src/pages/attendance.astro:663` → `sb.rpc('get_impact_hours_total')`
   - 4 migrations consumidoras → CREATE OR REPLACE com nova subquery
3. DROP VIEW `public.impact_hours_total`.
4. Smoke: attendance.astro KPI bar + cycle_report end-to-end + kpi_summary dashboard.

Quando feito, este ADR pode ser superseded ou marked com nota "remediated by ADR-XXXX".

## Critério de revisão

Este ADR deve ser revisado se:
1. Audit externo (não Supabase advisor) flagar a exposição como blocker.
2. Per-tenant strict separation virar requisito (multi-org enterprise tenant).
3. View ganhar coluna PII por engano (regression — neste caso reverter ADR + executar β).
4. Adoção de view materializada para perf — pode forçar mudança de modelo.

## Implementação

`COMMENT ON VIEW` atualizado em migration `20260805000002_p223_med_10_impact_hours_total_accepted_risk_comment.sql`
referenciando este ADR + preservando rationale p170 BUG-HOI canonical formula:

```sql
COMMENT ON VIEW public.impact_hours_total IS
  'Platform-wide YTD impact hours aggregate. SECURITY DEFINER view — accepted advisor risk per ADR-0096.
   anon REVOKE''d (only authenticated/service_role); content is scalar aggregates (no PII per row).
   Canonical formula (p170 BUG-HOI): SUM(COALESCE(duration_actual, duration_minutes)/60) FILTER (present=true AND excused IS NOT TRUE).
   Consumed by: attendance.astro + kpi_summary RPC + w104_kpi_targets_health + w105_cycle_report + analytics_v2 internal readonly.';
```

## Referências

- Audit p223 (2026-05-22) — MED #10 finding triggering this ADR
- ADR-0024 — sibling pattern (`public_members` accepted-risk SECDEF view)
- Migration `20260674400000_p170_hoi_canonical.sql` — view canonical formula (p170 BUG-HOI)
- Migration `20260508030000_security_sweep_wave1_flip_invoker_6_views.sql` — Wave 1 invoker flip sweep (explicitly skipped this view)
- Migration `20260426155255_track_r_pg_graphql_anon_revoke_batch2.sql` — anon REVOKE batch 2 (line 120)
- Advisor finding: `security_definer_view_public_impact_hours_total`
