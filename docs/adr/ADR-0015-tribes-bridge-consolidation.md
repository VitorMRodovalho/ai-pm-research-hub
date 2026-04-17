# ADR-0015: Tribes Bridge Consolidation — `tribe_id` Deprecation Path

- Status: Accepted
- Data: 2026-04-17
- Aprovado por: Vitor (PM) em 2026-04-17
- Autor: Vitor (PM) + Claude (comitê arquitetural)
- Escopo: Define o caminho de deprecação para a coluna legacy `tribe_id`
  em 18 tabelas base + 5 views, categorizando onde a coluna permanece,
  onde é redundante e pode ser removida, e em que ordem atacar. Não é
  deprecação da entidade `tribes` — essa permanece permanente.

## Contexto

V4 refactor (ADR-0005) estabeleceu `initiatives` como primitivo de domínio;
`tribes` virou bridge via dual-write. Concluído 2026-04-13. Hoje a plataforma
convive com:

- `tribes` table (8 rows, 15 FKs apontando para ela) — mantida pelos ADRs
  V4 como entidade permanente (muitos readers, UI histórica V3).
- `initiatives` table (12 rows) — primitivo pós-V4, inclui as 8 tribos via
  `legacy_tribe_id` + 4 initiatives não-tribo (CPMAI, Hub Comms, Publicações, ...).
- Dual-write triggers `trg_a_sync_initiative_*` + `trg_b_sync_tribe_*` em 13 tabelas
  mantendo `tribe_id ↔ initiative_id` coerentes.
- **23 surfaces** (18 base tables + 5 views) ainda portam coluna `tribe_id`.

### Inventário factual (live DB, 17/Abr)

| Categoria | Tabela/View | Tipo | tribe_id | initiative_id | FK→tribes | Dual-write | Rows | Notas |
|---|---|---|---|---|---|---|---|---|
| Domain primitive | `tribes` | table | — | — | 15 inbound | — | 8 | Entidade permanente. |
| Bridge-locked | `tribe_deliverables` | table | NOT NULL | yes | 1 | sim | 71 | Nome implica tribo; manter. |
| Bridge-locked | `tribe_meeting_slots` | table | NOT NULL | no | 1 | — | 9 | Slots semanais fixos por tribo. |
| Bridge-locked | `tribe_selections` | table | NOT NULL | no | — | trg custom | 35 | Outcome de seleção por tribo. |
| Bridge-locked | `tribe_lineage` | table | n/a* | — | 2 | — | ? | parent/child entre tribos. |
| Bridge-locked | `tribe_continuity_overrides` | table | n/a* | — | 2 | — | ? | Overrides por tribo. |
| Bridge-locked | `board_source_tribe_map` | table | NOT NULL | no | 1 | — | 5 | Mapeamento explícito. |
| Bridge-locked | `member_cycle_history` | table | nullable | no | — | — | 124 | Dim snapshot por ciclo. |
| **Droppable C3** | `events` | table | nullable | yes | — | sim | 270 (150 both, 2 init-only) | Redundante; initiative_id é suficiente. |
| **Droppable C3** | `announcements` | table | nullable | yes | 1 | sim | — | — |
| **Droppable C3** | `broadcast_log` | table | NOT NULL | yes | 1 | sim | 25 | — |
| **Droppable C3** | `hub_resources` | table | nullable | yes | 1 | sim | — | — |
| **Droppable C3** | `ia_pilots` | table | nullable | yes | 1 | sim | — | — |
| **Droppable C3** | `meeting_artifacts` | table | nullable | yes | 1 | sim | 12 (11 both) | — |
| **Droppable C3** | `pilots` | table | nullable | yes | 1 | sim | — | — |
| **Droppable C3** | `project_boards` | table | nullable | yes | 1 | sim | 14 (9 both, 3 init-only) | Initiative-native possible. |
| **Droppable C3** | `public_publications` | table | nullable | yes | 1 | sim | — | — |
| **Droppable C3** | `publication_submissions` | table | nullable | yes | 1 | sim | 8 | — |
| **Droppable C3** | `webinars` | table | nullable | yes | 1 | sim | 6 | — |
| Deferred | `members` | table | nullable | yes | — | sim | 71 (43 both) | Frontend V3 ainda lê; cutover separado. |
| View | `active_members` | view | yes | no | — | — | — | Auto-atualiza. |
| View | `impact_hours_summary` | view | yes | no | — | — | — | Auto-atualiza. |
| View | `members_public_safe` | view | yes | no | — | — | — | Auto-atualiza. |
| View | `public_members` | view | yes | yes | — | — | — | Auto-atualiza. |
| View | `recurring_event_groups` | view | yes | no | — | — | — | Auto-atualiza. |
| Legacy | `artifacts` | table | yes | no | — | — | 29 | Sem dual-write; investigar se é órfão. |

\* `tribe_lineage` e `tribe_continuity_overrides` usam `parent_tribe_id`/`child_tribe_id` (não a coluna `tribe_id` simples), mas igualmente ancoradas à entidade tribes.

### Observação crítica sobre densidade de dados

Nas tabelas com dual-write ativo, **zero rows têm `tribe_only`** (tribe_id sem initiative_id):

- `events`: 150 both, 2 init-only, 0 tribe-only
- `members`: 43 both, 0 init-only, 0 tribe-only
- `project_boards`: 9 both, 3 init-only, 0 tribe-only
- `webinars`, `meeting_artifacts`, `publication_submissions`, `tribe_deliverables`: 100% both ou init-only

Isso significa: **`initiative_id` é superset semântico de `tribe_id`** em todas as tabelas C3. Drop da coluna tribe_id é lossless.

## Decisão

### 4 categorias de tratamento

**C1 — Domain primitive (mantida indefinidamente)**
- `tribes` (a tabela) — ADR-0005 estabelece dual-write como permanente. 15 FKs inbound tornam conversão para view tech-prohibitively caro. Stays.

**C2 — Bridge-locked (tribe_id fica; referencia `tribes` por design)**
- `tribe_deliverables`, `tribe_meeting_slots`, `tribe_selections`, `tribe_lineage`, `tribe_continuity_overrides`, `board_source_tribe_map`, `member_cycle_history`
- **Critério**: nome da tabela implica semântica tribo, ou FK é structural ao modelo V3 preservado
- **Tratamento**: nenhum. Dual-write não se aplica (nem sempre existe). Manter.

**C3 — Droppable (dual-write cutover → DROP COLUMN)**
- 11 tabelas: `events`, `announcements`, `broadcast_log`, `hub_resources`, `ia_pilots`, `meeting_artifacts`, `pilots`, `project_boards`, `public_publications`, `publication_submissions`, `webinars`
- **Critério**: tem `initiative_id` (equivalente funcional) + dual-write ativo + nenhuma row tribe-only
- **Tratamento**: 4 fases — reader audit, reader cutover, trigger drop, column drop

**C4 — Deferred (members.tribe_id)**
- `members.tribe_id` tem 43 rows populadas + 28 NULL + dual-write ativo
- Frontend V3 (components de tribe/roster/dashboard) ainda lê `members.tribe_id` em múltiplas queries diretas
- **Critério**: exige cutover completo de frontend + RPCs pré-drop
- **Tratamento**: deferred; track como ADR-0015 Fase 5 (separate delivery)

**Legacy — artifacts**
- 29 rows com tribe_id, sem initiative_id, sem dual-write. Possivelmente tabela órfã da arquitetura pré-V4 (artefatos genéricos).
- **Tratamento**: investigate em fase zero. Se sem readers → drop tabela. Se com readers → mover para `meeting_artifacts` ou Categoria C2.

**Views (automáticas)**
- `active_members`, `impact_hours_summary`, `members_public_safe`, `public_members`, `recurring_event_groups`
- **Tratamento**: reescrever quando tabelas C3/C4 perderem tribe_id. Baixo custo.

### Fases de execução (não-bloqueante, multi-sessão)

#### Fase 0 — Investigação e baseline (pré-migration)
- [ ] Grep codebase por `tribe_id` em `src/`, RPCs de `supabase/migrations/`, EFs
- [ ] Identificar readers em MCP tools (76 tools) — quais referenciam tribe_id
- [ ] Investigar `artifacts` table (29 rows) — há readers? Migration path?
- [ ] Confirmar que initiatives cobertas por CPMAI/Hub Comms/Publicações não precisam tribe_id em nenhum fluxo

Entregável: lista de readers por tabela C3 + ação por reader (cutover inline / migrar / skip).

#### Fase 1 — Reader cutover para C3 (uma tabela por sessão)
Por tabela C3, em ordem de risco (baixo → alto):
1. `webinars` (6 rows, isolado) — easiest
2. `publication_submissions` (8 rows)
3. `meeting_artifacts` (12 rows)
4. `broadcast_log` (25 rows)
5. `hub_resources`, `ia_pilots`, `pilots`, `announcements`, `public_publications` (volume baixo)
6. `project_boards` (14 rows, 3 init-only já) — médio
7. `events` (270 rows) — maior exposição UI

Cada cutover:
- Atualiza queries/RPCs para usar `initiative_id` (LEFT JOIN initiatives + COALESCE initiative_name)
- Preserva shape de retorno (não quebra frontend)
- Smoke test com dados reais
- Commit atômico por tabela

#### Fase 2 — Trigger drop (one-shot após readers migrados)
Após todas tabelas C3 terem readers em `initiative_id`:
- DROP trigger `trg_a_sync_initiative_<table>` + `trg_b_sync_tribe_<table>` em cada tabela C3
- DROP função `sync_tribe_from_initiative()` se não for mais usada por nenhuma tabela
- Função `sync_initiative_from_tribe()` continua necessária para `members`/C2 se aplicável

#### Fase 3 — Column drop + FK drop (one-shot por tabela)
Para cada tabela C3, em mesma ordem da Fase 1:
- `ALTER TABLE <t> DROP CONSTRAINT <fk_to_tribes>` se houver
- `ALTER TABLE <t> DROP COLUMN tribe_id`
- Smoke test
- Commit

#### Fase 4 — Views rewrite
- Reescrever `active_members`, `impact_hours_summary`, `members_public_safe`, `public_members`, `recurring_event_groups` sem `tribe_id` (ou trocar para `initiative_id` quando semanticamente correto)

#### Fase 5 — members.tribe_id cutover (DEFERRED)
Separate delivery:
- Audit todas queries de frontend que leem `members.tribe_id`
- Migrar para derivação via `engagements` (ADR-0006) ou `members.initiative_id`
- Drop coluna só após zero leitores
- Prazo: após CBGPL (pós 28/Abr)

### Invariantes preservadas

1. **`tribes` table permanece** — 15 FKs inbound + UI V3 requires.
2. **Dual-write em `members`, bridge tables, artifacts** não é afetado pelo drop em C3.
3. **`initiatives.legacy_tribe_id`** continua FK para tribes — bridge integrity preservada.
4. **Contract `schema-invariants.F_initiative_legacy_tribe_orphan`** continua passando.
5. **Row data preservada**: drop da coluna tribe_id em C3 é lossless (initiative_id é superset).

### Critério para NOVAS tabelas pós-ADR-0015

Nenhuma nova tabela deve adicionar `tribe_id`. Se o domínio é tribe-centric de design (raro pós-V4), usar `initiative_id` com validação `WHERE initiative_kind = 'research_tribe'` no código. Diretriz já documentada em `.claude/rules/refactor-in-progress.md` mas reforçada aqui.

## Consequências

### Positivas

- **Clareza semântica**: pós-C3, cada tabela tem UMA coluna de escopo (`initiative_id`). Reviewer não pergunta "qual é source of truth, tribe_id ou initiative_id".
- **Performance triggers**: eliminar dual-write em 11 tabelas reduz overhead de INSERT/UPDATE (atualmente ~50ms extra por operação em tabelas hot como events).
- **Menos triggers**: 22 triggers (trg_a + trg_b em 11 tabelas) → 0. Schema mais simples.
- **Alinhamento com ADR-0012 Princípio 1**: single source of truth por conceito. Hoje `tribe_id` é "cache legacy", pós-ADR-0015 não existe mais.
- **Contract test stronger**: `schema-cache-columns` test pode adicionar asserção "nova tabela não pode ter tribe_id" como anti-drift.

### Negativas / Trade-offs

- **Multi-sessão execution**: não é deliverable de uma sessão. Pelo menos 4 fases × múltiplas sessões.
- **Risco de reader perdido**: qualquer query não detectada na Fase 0 vai quebrar quando `tribe_id` cair. Mitigação: grep rigoroso + staged rollout (uma tabela por vez).
- **Frontend V3 debt em `members`**: Fase 5 fica pendente indefinidamente até cutover de UI. Mitigação: explicit deferred, não esconder como tech debt implícito.
- **`tribes` table stays**: não resolve o desconforto de "por que ainda temos essa tabela?". Resposta: FKs + V3 UI + ADR-0005 decision. Aceita como permanente.

### Riscos específicos por tabela

- **`events`**: 270 rows, reader em múltiplos dashboards, attendance grids, meetings. Risco de UI quebrar se grep falhar. **Mitigação**: Fase 1 atacar events POR ÚLTIMO, após padrão consolidado em tabelas menores.
- **`project_boards`**: 3 rows init-only já (boards de initiatives não-tribo). Já está parcialmente migrada — drop limpa.
- **`webinars`**: mínimo risco (6 rows). Good starter.
- **`members`** (C4): frontend tem queries diretas em múltiplas telas. Risco mais alto de regressão. Mantém Fase 5 separada por isso.

## Próximos passos

1. **Fase 0 immediate**: sweep de readers. Criar `docs/refactor/TRIBE_ID_READERS_AUDIT.md` com inventário por tabela.
2. **Fase 1 primeira vítima**: `webinars` — smallest, isolated. Cutover + smoke test + commit. Serve de template.
3. **Guardian check**: após cada fase, `check_schema_invariants()` + manual smoke de UI críticas (attendance, portfolio, board).
4. **Contract test extension**: adicionar assertion em `tests/contracts/schema-cache-columns.test.mjs` — "C3 tables não podem ter ALTER TABLE ADD COLUMN tribe_id" (anti-regress).

## Referências

- ADR-0005 — Initiative as Domain Primitive (bridge architecture decision)
- ADR-0006 — Person + Engagement Identity (replaces members catch-all)
- ADR-0007 — Authority as Engagement Grant (auth derivation)
- ADR-0012 — Schema Consolidation Principles (Princípio 1: single source of truth)
- ADR-0013 — Log Table Taxonomy (precedente de taxonomy-first decision)
- Migration `20260413000000_v4_phase2_initiative_primitive.sql` — establece dual-write
- Migration `20260413080000_v4_phase7b_drop_tribe_rpcs.sql` — parte do cutover V4
- `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` — histórico completo V4
