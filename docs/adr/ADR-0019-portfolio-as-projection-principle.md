# ADR-0019: Portfolio as Projection Principle — sem workflow separado de escalação

- Status: Proposed
- Data: 2026-04-21
- Autor: Claude (debug session 9908f3, issue #89) — aguardando aprovação PM
- Escopo: Formaliza que o **portfólio executivo** é uma *view* agregada sobre `board_items` com `is_portfolio_item=true`, NÃO uma entidade separada com lifecycle próprio. Define quem pode escalar, como é auditado, e por que não existe (nem deve existir) workflow formal de "portfolio request / approval".

## Contexto

Sessão debug 9908f3 (21/Abr) investigou preocupação do GP sobre governance do campo `board_items.is_portfolio_item`. Pergunta original: *"tiers fora do GP não conseguem alterar né? pois seria uma falha de governanca"*.

Runtime evidence coletada:

| Fato | Número |
|---|---:|
| Cards totais em produção | 465 |
| Portfolio items ativos | 55 (12%) |
| Boards contribuindo | 8 (múltiplas tribos + workgroups) |
| Audit `portfolio_flag_changed` em `board_lifecycle_events` | 7 eventos |
| Audit `baseline_*` (set, locked, changed) | 5 eventos |
| Audit `forecast_update` | 51 eventos |
| MCP portfolio tools expostas | 2 (`get_portfolio_overview`, `get_portfolio_health`) |
| MCP tools com enforcement `update_board_item` no flag | 1 (via `update_board_item` RPC) |

Enforcement atual no RPC `update_board_item`:

```sql
IF p_fields ? 'is_portfolio_item' THEN
  IF NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin THEN
    RAISE EXCEPTION 'Only Leader or GP can change portfolio flag';
  END IF;
END IF;
```

Onde:
- `v_is_gp` = `is_superadmin` OR `manager`/`deputy_manager` OR `'co_gp' = ANY(designations)`
- `v_is_leader` = `operational_role='tribe_leader'` AND `tribe_id = board_legacy_tribe_id`
- `v_is_board_admin` = membro do `board_members` com `board_role='admin'`

### Forças em tensão

1. **Descentralização vs centralização** — líder de tribo conhece suas entregas mais profundamente e pode julgar elegibilidade para portfólio executivo. GP não escala se tiver que aprovar cada escalação.
2. **Transparência vs processo** — adicionar workflow de "propose → approve" dá transparência formal, mas cria latência em operação de 55 items/ano (6 meses efetivos — ~1 item/semana média, picos maiores).
3. **Imutabilidade de baseline vs agilidade** — `baseline_date` tem proteção reforçada (auto-lock 7d + GP-only após + reason obrigatório). Isso garante o que realmente importa: **data de compromisso é imutável após se consolidar**. Escalação para portfólio NÃO é evento tão crítico.
4. **Single source of truth** — `is_portfolio_item` no próprio `board_items` vs tabela paralela `portfolio_requests`. Duplicação de fonte gera drift.

## Decisão

**Portfolio executivo é PROJECTION de `board_items` com `is_portfolio_item=true`.** Não é entidade separada. Não tem workflow de aprovação formal. Não existe tabela `portfolio_requests`.

### D1 — Quem pode escalar

Mantém modelo atual descentralizado:
- **GP / manager / deputy_manager / co_gp** — qualquer board
- **Tribe leader** — apenas cards do board da própria tribo
- **Board admin** — cards do board onde é admin (permite workgroup coordinators)

Justificativa: líder de tribo tem contexto editorial sobre elegibilidade. Adicionar GP como gatekeeper obrigatório criaria bottleneck operacional sem ganho de governance proporcional — o enforcement atual já bloqueia tiers que não deveriam escalar (researchers, members sem role de gestão, etc.).

### D2 — `baseline_date` mantém proteção reforçada

Diferente do flag portfolio, `baseline_date` **tem** valor legal/compromisso:
- Auto-lock após 7 dias (grace period para ajuste inicial)
- Após lock: **somente GP** pode mudar
- Mudança pós-lock exige `reason` obrigatório
- Mudança gera evento `baseline_changed` em `board_lifecycle_events`

Esse nível de rigor é apropriado para baseline — entrega de compromisso vs portfólio em si.

### D3 — Audit automático

Toda mudança em `is_portfolio_item`, `baseline_date`, `forecast_date` gera registro em `board_lifecycle_events`:
- `portfolio_flag_changed` — mudança do flag
- `baseline_set` / `baseline_locked` / `baseline_changed`
- `forecast_update` / `forecast_changed`

Esses 6 eventos são suficientes para auditoria completa. NÃO requer tabela separada.

### D4 — Critérios de elegibilidade

Não hard-coded no schema. Cada tribo define por convenção (ADRs internos, documentação do líder, rubric do board). Isso é **intencional** — heterogeneidade editorial é apropriada para múltiplas tribos com diferentes naturezas de entrega (research_tribe vs workgroup vs committee).

### D5 — Revisão periódica (non-blocking)

Cron mensal lista portfolio items com `updated_at < (now() - 60 days)` e notifica GP via `notifications`. **Não bloqueia**, apenas informa. Propósito: prevenir "portfolio zombie" (item escalado um ciclo atrás sem progresso nem demotion).

### D6 — MCP tooling

Portfolio é exposto via 2 tools agregadas hoje:
- `get_portfolio_overview` (wrap `get_portfolio_dashboard`) — admin-only
- `get_portfolio_health` (wrap `exec_portfolio_health`) — admin/sponsor

Adicionar (melhoria leve, não workflow):
- `get_portfolio_items(tribe_id?, status?, cycle?)` — list-level com filtros (não-agregado)
- Expor 3 RPCs portfolio já existentes sem MCP wrapper: `get_portfolio_timeline`, `get_portfolio_planned_vs_actual`, `exec_portfolio_board_summary`

### D7 — Link opcional com KPIs anuais (overlap ADR-0015, issue #84)

Campo opcional futuro:
```sql
ALTER TABLE board_items ADD COLUMN portfolio_kpi_refs text[];
```

Líder pode marcar "este portfolio item contribui para KPI `webinars_delivered`". Não-obrigatório, não-blocking. Facilita `get_tribe_housekeeping` (issue #84).

## Consequências

### Positivas

- **Operação ágil mantida** — 55 items/ciclo sem friction de approval
- **Audit trail robusto** — 6 event types em `board_lifecycle_events` cobrem 100% das mudanças
- **Sem dívida técnica** — não criamos entidade duplicada que precisaria sync
- **Heterogeneidade editorial preservada** — cada tribo aplica julgamento próprio
- **Alinhamento com realidade** — formaliza o que já funciona em produção há 6+ meses

### Negativas

- **Sem visibility forçado de escalação** — quando líder marca item portfolio, GP só descobre via dashboard/cron review (não por notificação proativa). Mitigação: D5 reminder mensal + (opcional futuro) notification on-set para GP se o líder quiser feedback.
- **Critérios de elegibilidade heterogêneos** — cada tribo tem sua régua. Para alguns, é pró (respeita especificidade); para outros, é contra (falta de standard cross-tribe). Aceitamos esse trade-off.
- **Dependência de julgamento editorial** — líder "ruim" pode inflar seu portfólio para aparência. Mitigação: GP/co_gp podem editar (removendo flag) e `portfolio_flag_changed` audit identifica padrões.

### Não-consequências

- Não impede adicionar workflow no futuro se volume crescer >10x — mas por ora, overengineering seria não-justificado.
- Não muda baseline enforcement — esse fica como está (GP-only após lock + reason).

## Alternativas consideradas e rejeitadas

1. **Workflow `portfolio_requests` (propose → review → approve)** — rejeitada: duplicaria responsabilidade com `is_portfolio_item`, adicionaria latência sem ganho proporcional de governance. Volume atual não justifica.
2. **GP-only gating (só GP pode setar flag)** — rejeitada: GP vira bottleneck operacional; líder conhece suas entregas melhor; contradiz princípio de descentralização que funciona para outras dimensões (baseline, forecast, assignee).
3. **Hard-coded eligibility criteria** (ex.: só cards com `status='in_progress'` ou `due_date` futuro) — rejeitada: heterogeneidade editorial é apropriada. Cada tribo aplica seu critério.
4. **Periodic GP review obrigatório (blocking)** — rejeitada: cria friction operacional. Alternativa D5 (non-blocking reminder) preserva visibility sem bloquear.

## Compliance e auditoria

- **LGPD**: portfolio não expõe PII adicional além do que `board_items` já tem (assignee_name, description). Nada novo.
- **PMI compliance**: ADR descritivo basta. Não há requirement formal de PMI sobre o processo interno de portfolio.
- **Auditoria externa futura** (DPO / PMI global review): 6 event types em `board_lifecycle_events` + RLS policies demonstram controles técnicos. ADR-0019 documenta racional da decisão.

## Métricas de sucesso

Após 6 meses (out/2026):
- 0 incidentes reportados de "alguém marcou portfolio errado"
- Cron D5 disparou <10% de items como zombie (item escalado mas stale)
- `get_portfolio_items` adotado como ferramenta canônica de consulta

Se métricas falham:
- >10% zombie → reativar discussão sobre workflow leve
- Incidentes governance → avaliar se é caso isolado ou padrão

## Referências

- Issue #89 — Portfolio governance + Webinar series + Comms self-service + MCP security
- ADR-0015 — Tribes Bridge Consolidation (contexto board_items evolution)
- ADR-0011 — V4 Auth Pattern (base enforcement RPC)
- Migração `20260319100046_w141_board_engine_evolution.sql` (onde portfolio foi introduzido)
- `update_board_item` RPC — enforcement canônico
- `board_lifecycle_events` — audit trail

## Aprovação

Aguarda revisão PM Vitor antes de status `Accepted`.
