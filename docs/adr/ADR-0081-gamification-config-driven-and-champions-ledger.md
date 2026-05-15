# ADR-0081: Gamification rules config-driven + Champions ledger (3-surface manual award)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-05-15 (sessão p161, ratified p162) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260645000000` (rules + champions schema + V4 seed) · `20260646000000` (4 Champion RPCs) · `20260647000000` (CHECK→FK hotfix) · `20260648000000` (8 auto-XP triggers) |
| Cross-ref | [SEMANTIC_TAXONOMY.md](../reference/SEMANTIC_TAXONOMY.md) Q5–Q7 · [ADR-0009](./ADR-0009-tribes-as-initiatives-bridge-and-config-not-code.md) (config-not-code pattern) · [ADR-0050](./ADR-0050-gamification-leaderboard-v2-and-opt-out.md) (leaderboard v2 + opt-out) · [ADR-0062](./ADR-0062-gamification-streak-and-cycle-points.md) (streak + cycle points + NULL-safe pattern) · [V4 Authority Model](../reference/V4_AUTHORITY_MODEL.md) |
| Closes | TIER A handoff p161 item 2 (Gamification + Champion design) |

## Context

A taxonomia semântica (SEMANTIC_TAXONOMY.md) levantou três gaps em gamificação:

1. **Hardcoded XP rules** — `gamification_points.category` era CHECK com 14 valores fixos. Cada nova categoria exigia migration + deploy. Quebra ADR-0009 (config-not-code).
2. **79% do XP concentrado em `attendance`** — produção/curadoria/ratificação não geravam pontos. Membros que entregavam mas não compareciam a evento ficavam invisíveis no leaderboard.
3. **"Champion" só existia como string i18n** (`rules.dashboard.text`) — prática informal em reuniões gerais ("protagonistas do dia") sem audit trail, ranking ou pontuação.

PM ratificou em batches durante p161 (3 sessões de design+execução):
- Q5 → Champion modelado como **manual com critérios objetivos** (não algoritmo automático)
- Q6 → 11 categorias novas (3 champion_* + 3 production auto + 5 curation auto)
- Q7 → **Opção B config-driven** (gamification_rules table)

Esta ADR captura o design end-to-end, registra a decisão de backfill (forward-only) e documenta os 3 padrões que sedimentaram.

## Decision

### Componente 1 — `gamification_rules` (config-driven, forward-only)

Tabela canônica com tuning admin sem deploy:

```sql
gamification_rules (
  slug text,                    -- ex: 'champion_general', 'attendance', 'curation_doc_published'
  display_name_i18n jsonb,      -- pt-BR / en-US / es-LATAM
  description_i18n jsonb,
  base_points integer,
  bonus_per_criterion integer DEFAULT 0,  -- só Champion usa
  cap_points integer NULL,                -- só Champion usa
  trigger_source text CHECK IN ('manual','auto_trigger','rpc_callback'),
  active boolean DEFAULT true,
  effective_from timestamptz DEFAULT now(),
  organization_id uuid REFERENCES organizations(id),
  UNIQUE (organization_id, slug)
)
```

**Forward-only semantics:** quando admin edita `base_points`, novos registros usam o novo valor; XP histórico fica imutável. Cada lookup faz `WHERE active=true AND effective_from <= now() ORDER BY effective_from DESC LIMIT 1` — multi-row por slug suporta versioning futuro sem schema change.

**Seed inicial: 23 regras** organizadas em 3 tiers:
- **Tier 1 — Existing categories converted** (12): attendance(10), badge(10), course(15), trail(20), knowledge_ai_pm(20), specialization(25), showcase(20), 5 cert_pmi_*
- **Tier 2 — Champion manual** (3): champion_general(30+5/crit, cap 50), champion_tribe(20+5, cap 40), champion_deliverable(40+5, cap 60)
- **Tier 3 — Production auto** (3): deliverable_completed(30), artifact_published(15), action_resolved(5)
- **Tier 4 — Curation auto** (5): curation_doc_authored(20), curation_doc_locked(10), curation_doc_published(30), curation_ratification(25), curation_comment_resolved(5)

RLS: read `authenticated within org`; write `manage_platform` only.

### Componente 2 — `champions_awarded` (manual award ledger)

Audit-load-bearing tabela com integridade tri-camada:

```sql
champions_awarded (
  recipient_id uuid REFERENCES members(id),
  awarded_by uuid REFERENCES members(id),
  surface text CHECK IN ('general','tribe','deliverable'),
  context_kind text CHECK IN ('event','deliverable','artifact'),
  context_id uuid,
  criteria_met text[] CHECK (cardinality BETWEEN 1 AND 4),
  justification text CHECK (length(trim()) >= 50),
  points_awarded integer,                -- imutável pós-grant (snapshot da rule)
  status text DEFAULT 'active' CHECK IN ('active','revoked'),
  revoked_at / revoked_by / revoked_reason,  -- soft-revoke trio
  organization_id uuid,
  initiative_id uuid NULL,
  CONSTRAINT champions_revocation_consistency  -- todos NULL OR todos preenchidos
  CONSTRAINT champions_surface_initiative_consistency  -- general↔NULL; tribe/deliverable↔NOT NULL
  CONSTRAINT champions_no_self_award  -- recipient ≠ awarded_by
)
```

**Auditoria preservada na revogação:** `status='revoked'` mantém a row + reason + by + at; XP correspondente é DELETEd de `gamification_points` (não compõe XP a partir de Champion revogado). Justificativa textual obrigatória (≥50 chars) força reflexão antes do grant.

### Componente 3 — 4 RPCs de Champion

| RPC | Resp | Auth | Notas |
|---|---|---|---|
| `award_champion(recipient, surface, context_kind, context_id, criteria[], justification)` | jsonb com `champion_id`, `points_awarded`, `soft_cap_warning`, `rule_slug` | V4 `award_champion` (org-scope para general; initiative-scope para tribe/deliverable) | Valida elegibilidade (presence em event para general/tribe; assigned_member_id para deliverable; created_by para artifact). Anti-inflação 3-camada (ver Componente 4). Forward-only rule lookup. |
| `revoke_champion(champion_id, reason)` | jsonb com `points_removed`, `revoked_within_window`, `by_platform_admin` | original awarder dentro de 7d OU `manage_platform` anytime | Soft-row + DELETE XP. Reason obrigatório (≥10 chars). |
| `get_champions_ranking(scope_kind, scope_id, cycle_code, limit)` | jsonb com `ranking[]` + `cycle_*` | authenticated within org | Scope ∈ {global, initiative}. Respeita LGPD opt-out (`gamification_opt_out`). NULL-safe cycle_end (ADR-0062 pattern). |
| `get_member_champions_history(member_id)` | jsonb com `totals` + `history[]` | self always; cross-member exige `view_pii` OR target not opted out | Audit-load-bearing — surfaceada em /profile/me + /admin/gamification. |

V4 grants seedados em `engagement_kind_permissions`:
- **Org-scope** (4): volunteer manager, co_gp, deputy_manager, comms_leader
- **Initiative-scope** (5): volunteer leader, committee_member leader, study_group_owner leader+owner, workgroup_member leader

### Componente 4 — Anti-inflação tri-camada (Champion only)

Champion é manual + influencia ranking público → exige guard contra inflação:

| Camada | Cap | Por quê |
|---|---|---|
| **Per-event** | 3 general / 2 tribe / 1 deliverable | impede "todo mundo é Champion" — mantém escassez do reconhecimento |
| **Per-grantor-per-event** | 3 hard | impede 1 líder distribuir todos os Champions; força consenso entre lideranças quando há mais de 1 |
| **Per-cycle (recipient)** | 5 general / 8 tribe / 3 deliverable (soft) | warning não bloqueante — sinaliza que membro pode estar saturando a categoria; PM decide se é caso real ou pattern abusivo |

Pontuação híbrida: `base + (bonus × cardinality(criteria_met))` clamped a `cap_points`. Ex: champion_general com 3 critérios = 30 + 5×3 = 45 pts (sob cap 50). Com 4 critérios = 30 + 5×4 = 50 pts (= cap).

### Componente 5 — 8 auto-XP triggers + helper `_grant_auto_xp`

DRY helper compartilhado por todos os triggers:

```sql
_grant_auto_xp(p_slug text, p_recipient_id uuid, p_ref_id uuid, p_reason text)
```

Responsabilidades:
1. Skip if `recipient_id IS NULL` ou org não encontrável
2. Lookup forward-only `gamification_rules` (active + effective_from)
3. Idempotency check: `(ref_id, category, member_id)` triple
4. INSERT em `gamification_points` com `base_points` da rule

**NEVER raises** — triggers não podem bloquear writes da tabela-fonte. Falha silenciosa preservada via early `RETURN`.

Triggers cobertos:
| Trigger | Tabela | Fire | Recipient |
|---|---|---|---|
| `tribe_deliverable_completed_xp` | tribe_deliverables | AFTER UPDATE OF status (→ 'completed') | NEW.assigned_member_id |
| `meeting_artifact_published_xp` | meeting_artifacts | AFTER UPDATE OF is_published (false→true) | NEW.created_by |
| `meeting_action_resolved_xp` | meeting_action_items | AFTER UPDATE OF resolved_at (NULL→NOT NULL) | NEW.assignee_id |
| `doc_version_authored_xp` | document_versions | AFTER INSERT | NEW.authored_by |
| `doc_version_locked_xp` | document_versions | AFTER UPDATE OF locked_at (NULL→NOT NULL) | NEW.locked_by |
| `doc_version_published_xp` | document_versions | AFTER UPDATE OF published_at (NULL→NOT NULL) | NEW.published_by |
| `approval_signoff_xp` | approval_signoffs | AFTER INSERT | NEW.signer_id |
| `doc_comment_resolved_xp` | document_comments | AFTER UPDATE OF resolved_at (NULL→NOT NULL) | NEW.resolved_by |

**Anti-farm explícito** em `curation_comment_resolved`: paga ao **resolver**, não ao **commenter**. Quem cria comentário não ganha; quem o resolve ganha. Fecha o feedback loop com sinal de qualidade.

### Componente 6 — Curador como RECIPIENT (não grantor de Champion-de-entregável)

**Diretiva PM (p161 batch 3):** quando curador valida formato de um entregável, ele ganha XP via `curation_*` triggers (Tier 4), **não** via Champion. Champion-de-entregável tem como grantor o **líder de tribo do contexto** (julga qualidade do conteúdo). Separa **autoridade técnica/formal** (curador) de **autoridade qualitativa** (líder).

Implicação prática: V4 grant `award_champion` em `kind=volunteer / role=leader / scope=initiative` cobre líder de tribo; curador acumula XP automático via curation_doc_published(30), curation_ratification(25), etc.

### Componente 7 — Hardcoded CHECK → FK composta (hotfix 20260647)

Schema original tinha `gamification_points.category_check` com 14 valores hardcoded. Smoke da Fase 2 capturou: novas categorias (`champion_general`, `curation_doc_authored`, etc) violavam CHECK → INSERT falhava.

Replace por FK composta `(organization_id, category) → (organization_id, slug)` em `gamification_rules`:
- **ON DELETE RESTRICT** — não permite drop de rule se há XP histórico (preserva audit)
- **ON UPDATE CASCADE** — slug rename raro propaga automaticamente
- **DEFERRABLE INITIALLY DEFERRED** — atomicidade trigger-friendly

Lesson: config-driven não basta — toda constraint downstream que referencia a coluna config-driven precisa também migrar para FK (não CHECK).

## Backfill decision — forward-only (recommended)

PM input needed: **rodar retroactive sync sobre dados existentes ou forward-only?**

### Dados disponíveis (snapshot 2026-05-15)

| Slug | Pts/each | Rows existentes | Backfill total | Trigger ON UPDATE? |
|---|---:|---:|---:|---|
| curation_ratification | 25 | 39 | 975 | INSERT — não fira em re-INSERT |
| curation_doc_authored | 20 | 40 | 800 | INSERT — não fira |
| curation_doc_published | 30 | 19 | 570 | OF published_at — só fira em NULL→NOT NULL |
| curation_doc_locked | 10 | 39 | 390 | OF locked_at — só fira em NULL→NOT NULL |
| artifact_published | 15 | 12 | 180 | OF is_published — só fira em false→true |
| curation_comment_resolved | 5 | 17 | 85 | OF resolved_at — só fira em NULL→NOT NULL |
| deliverable_completed | 30 | 1 | 30 | OF status — só fira em →'completed' |
| action_resolved | 5 | 0 | 0 | OF resolved_at — só fira em NULL→NOT NULL |
| **Total** | — | **167** | **3030** | |

### Top-7 afetados (se backfill executado)

| Membro | retro_pts | retro_rows | Papel |
|---|---:|---:|---|
| Vitor Maia Rodovalho | 1640 | 96 | GP / PM |
| Fabricio Costa | 505 | 20 | Vice-GP |
| Sarah Faria Alcantara Macedo Rodovalho | 265 | 13 | Líder tribo |
| Roberto Macêdo | 195 | 15 | Curador |
| Débora Moura | 150 | 10 | Líder tribo |
| Marcos Antunes Klemz | 100 | 4 | Líder tribo |
| Jefferson Pinto | 15 | 1 | Tribo |

### Recommendation: forward-only

Razões:
1. **Coerência semântica** — `effective_from` da rule é `2026-05-15`. Backfillar XP de evento ocorrido 2026-04-01 viola o invariante "rules apply forward from their effective date".
2. **Optics** — PM/GP (designer do sistema) recebe 54% do backfill (1640/3030). Mesmo correto, é leitura ruim publicamente.
3. **Cycle leaderboard rerank** — cycle 3 atual tem ranking estabilizado por presence+showcase+cert. Injetar +3030 pts retro re-rankeia bruscamente e distorce o histórico que membros já viram.
4. **Curator effort ≠ promised reward** — quem assinou 39 ratificações em 2026-04 não o fez esperando XP. Recompensar retro cria expectativa de que toda mudança de regra futura será backfilled.
5. **Forward-only é reversível** — se PM decidir em p163+ que quer backfill, basta uma migration `DO $$ ... PERFORM _grant_auto_xp ... $$` sobre rows existentes (idempotency check já garantida pelo helper). Forward-only não é decisão one-way.

### Counter (porque backfill **poderia** fazer sentido)

- **Justiça intra-cycle**: cycle 3 está em curso; XP de eventos do mesmo ciclo "deveria" contar (recipient ainda pode mudar comportamento). Mitigação parcial: backfillar apenas rows com `created_at >= cycle_3_start`.
- **Sinal de valor para curadores**: backfill mostra que produção/curadoria importam tanto quanto presença. Mitigação: comunicação interna pode dizer isso sem backfill (anúncio + tutorial).

### Decisão PM (ratificada 2026-05-15 sessão p162)

- [x] **Forward-only** — nenhuma ação adicional; rules aplicam-se a writes futuros via triggers já ativos
- [ ] ~~Partial backfill~~ — só rows com `created_at >= cycle_3_start`
- [ ] ~~Full backfill~~ — todos os 167 rows; aceita rerank de cycle 3

Justificativa PM: aceita recomendação por consistência com `effective_from` semantics + reversibilidade preservada (migration adicional em p163+ pode aplicar `_grant_auto_xp` sobre rows existentes via idempotency check).

## Consequences

**Positive:**
- 11 novas categorias XP diversificam o leaderboard (deixa de ser ~79% attendance)
- Admin tuna pontuação sem deploy (ADR-0009 pattern aplicado)
- Champion vira sistema auditável (audit trail completo + 3 caps + soft revoke)
- Curador como recipient + anti-farm em comment_resolved fecham incentive loop com qualidade
- Helper DRY `_grant_auto_xp` (~25 linhas) economiza ~150 linhas dispersas em 8 triggers
- Forward-only semantics consistente com `effective_from` desde dia 1

**Neutral:**
- Champion ranking depende de comportamento de líderes; baixa adoção → ranking vazio (não é bug, é sinal de processo)
- Per-cycle cap é **soft** (warning, não block); GP pode auditar pattern abusivo via `get_member_champions_history`
- `criteria_met` é text[] livre (não FK); admin precisa documentar listas válidas em SEMANTIC_TAXONOMY.md ou alinhar com /admin/gamification helper (4c carry-forward)

**Negative:**
- 23 regras seedadas = 23 testes implícitos. Mudança de pontuação base requer admin entender FK composta + forward-only (treinamento de admin pendente)
- Triggers AFTER UPDATE com `OF column` exigem que UPDATE explicite a coluna; UPDATE em massa de outras colunas não fira XP mesmo se o predicado seria satisfeito. Aceitável: triggers existentes do codebase já tocam as colunas-fonte corretas.
- Backfill forward-only deixa 167 rows sem XP retro; se PM decidir mudar de opinião em p163+, precisa migration adicional (idempotência protege duplicate firings).

## Path impact (Trentim)

- **Path A (PMI internal)**: leaderboard diversificado + Champion auditável = produto vendável para outros PMI chapters como módulo de engagement
- **Path B (consulting)**: gamification_rules table + helper pattern = template reusável para clientes (advanced gamification sem custom code)
- **Path C (community)**: Champion como **reconhecimento de pares com critérios objetivos** alinha com PMI volunteer recognition principles; reduz dependência de presence-only para visibilidade

## Patterns sedimented

42. **Config-driven exige FK alinhamento downstream** — introduzir `<feature>_rules` table sem migrar constraints downstream para FK composta gera bug invisível até o primeiro INSERT do tipo novo. Smoke happy path para CADA categoria seedada antes de declarar feature done. (Aprendido em p161 Fase 2, hotfix 20260647.)

43. **Soft revocation + delete derived XP** — Champion (ou qualquer reconhecimento manual com pontuação) deve preservar audit row em `status='revoked'` mas DELETE da pontuação derivada. Compromisso entre "auditoria nunca apaga" e "ranking não pode ser inflado por reconhecimento revogado". Aplicável a futuros tipos de manual award.

44. **Anti-farm via resolver-pays-not-commenter** — gamification em ações com 2 atores (comentário + resolução) deve pagar ao closer, não ao opener. Inverte incentivo de "criar muito" para "fechar com qualidade". Aplicável a: issues, threads de discussão, action items, etc.

45. **Helper `_grant_*_xp` shared across triggers** — quando >3 triggers compartilham mesma estrutura (lookup rule + idempotency check + insert), DRY via helper `SECURITY DEFINER` que NEVER raises. Triggers ficam de ~3 linhas cada; helper concentra mudança de política.

46. **Forward-only `effective_from` é decisão atômica, não default** — ao introduzir tabela de regras configuráveis, a primeira pergunta é "rules existentes valem retroativo?" PM-input load-bearing. Recommendation default: forward-only (reversível) ao invés de backfill (não-reversível sem migration adicional + comunicação).

## Verification

- [x] Migrations applied (4 — `20260645000000` a `20260648000000`)
- [x] Schema invariants: gamification_rules + champions_awarded com RLS ENABLED + indexes esperados
- [x] FK composta `gamification_points.category` → `gamification_rules` aplicada + comentada
- [x] 23 rules seedadas (12 Tier 1 + 3 Champion + 3 Tier 2 + 5 Tier 3)
- [x] 9 V4 grants seedados em `engagement_kind_permissions`
- [x] 4 Champion RPCs com REVOKE FROM PUBLIC + GRANT EXECUTE TO authenticated
- [x] 8 triggers AFTER UPDATE/INSERT com helper `_grant_auto_xp` (DRY)
- [x] Smoke happy path (in-session via execute_sql, auth-spoofed Vitor):
  - award_champion + retorna `champion_id` + `points_awarded` (40 pts general com 2 critérios em evento valid)
  - get_member_champions_history retorna `totals` + `history[]`
  - get_champions_ranking retorna ranking
  - revoke_champion soft-row + DELETE XP (verified `champion_xp_rows=0` após revoke)
  - Trigger auto-XP `action_resolved` fired (+5 pts via _grant_auto_xp)
- [x] MCP smoke (initialize HTTP 200 + tools/list count=289)
- [x] Worker deploy `9efc927c` (page /admin/gamification UI render)
- [ ] **Browser smoke do /admin/gamification** — pendente sessão p162 (PM login required)
- [ ] **PM ratificação backfill decision** — recomendação forward-only acima
- [ ] **i18n EN/ES** para /admin/gamification — hoje só PT-BR inline (carry-forward p162 TIER B)
- [ ] **Member-facing UI** — /profile/me Champion section + /tribe/[id] Champion ranking (carry-forward p162 TIER B)
- [ ] **Pickers polidos no admin grant form (Fase 4c)** — autocomplete evento/membro/deliverable (carry-forward p162)

## Amendment A — Reader RPCs aligned with config (p165, 2026-05-15)

Phase 1–3 of this ADR delivered the **writer** side of the config-driven contract:
seed `gamification_rules`, FK-enforce `gamification_points.category` against the rules
table, route auto-XP through `_grant_auto_xp` (forward-only, idempotent). What had
*not* been migrated were two **reader / single-RPC writer** surfaces still on the
pre-config-driven shape:

1. `get_gamification_leaderboard` aggregated points into eight hardcoded buckets via
   literal slug lists in `FILTER (WHERE gp.category = ANY (ARRAY['...']))`. Every new
   slug introduced after the original write went into a `bonus_points` catch-all by
   default. Plus a pre-existing bug: the `artifact_points` filter compared against
   the literal `'artifact'`, but the real slug is `'artifact_published'` — so the
   bucket was always 0. And `specialization` (pillar=trilha) was being summed into
   `badge_points` (a residue from the earlier flat taxonomy).
2. `register_event_showcase` hardcoded its per-subtype XP table (case_study=25,
   tool_review=20, prompt_week=20, quick_insight=15, awareness=15) and wrote all
   rows with `category='showcase'`. The seeded `gamification_rules.showcase` rule
   (base_points=20) was a placeholder — the RPC ignored it and admin had no way
   to tune the subtypes without code deploy.

### Closure

- **Migration `20260664000000_p165_get_gamification_leaderboard_config_driven.sql`** —
  DROP + CREATE the leaderboard RPC with `LEFT JOIN gamification_rules gr ON
  (gp.organization_id = gr.organization_id AND gp.category = gr.slug)`. All bucket
  filters now reference `gr.pillar` / `gr.slug` directly. Preserved 8 legacy column
  names (backward-compat with `TribeGamificationTab` + `gamification.astro`) and
  added 3 new pillar buckets: `producao_points`, `curadoria_points`,
  `champions_points` (+ cycle mirrors). `bonus_points` becomes a defensive
  catch-all (= 0 today; `gamification_rules.pillar` CHECK enum is exhaustive over
  the six pillars). Smoke (impersonated Vitor): bucket arithmetic balanced for all
  members; `curation_ratification` (50pts) surfaced from `bonus_points` into
  `curadoria_points`; `specialization` (1150pts, Vitor cohort) moved from
  `badge_points` to `learning_points`.

- **Migration `20260665000000_p165_register_event_showcase_config_driven.sql`** —
  Seed 5 dedicated `showcase_<subtype>` rules (case_study=25, tool_review=20,
  prompt_week=20, quick_insight=15, awareness=15) with trilingual i18n. DROP +
  CREATE the RPC to resolve `v_slug := 'showcase_' || p_showcase_type`, look up
  the rule (forward-only, org-scoped), then award XP via the shared
  `_grant_auto_xp` helper. Explicit error response `showcase_type_not_configured`
  before reaching the `event_showcases.showcase_type` CHECK. Slug `showcase`
  remains active (FK integrity for 12 legacy rows); new writes flow through the
  per-subtype slugs. Smoke (impersonated Vitor, tx-wrapped with ROLLBACK):
  case_study→25, tool_review→20, awareness→15, bogus_type→explicit error.

### Pattern sedimented (new)

47. **Reader RPCs join the rules table — never literal slug lists**. When you
    introduce a config-driven *writer* side (rules table + FK), all *reader* RPCs
    that bucket or filter by the configurable column must also resolve their
    grouping via JOIN to the rules table. Hardcoded `IN ('slug_a','slug_b',...)`
    lists in readers re-introduce the same drift the writer migration was meant
    to eliminate, and the FK enforcement masks the gap — points pile up under a
    valid slug, just in the wrong UI bucket. Audit checklist when adding a
    config-driven dimension: writer + FK + at least one reader + every aggregator
    referencing the column. (Sedimented from p165 closures of leaderboard
    `bonus_points`-catchall drift and showcase RPC hardcoded XP.)

### Verification updates

- [x] **Migrations applied** — extended from 4 to 6 (`20260664` + `20260665`).
- [x] **Live smoke (leaderboard)** — bucket arithmetic balances; new slugs land in
      correct pillars; specialization moved out of badges; bonus_points = 0.
- [x] **Live smoke (showcase RPC)** — 3 happy-path subtypes + 1 negative (bogus
      subtype) all return expected shape; tx-wrapped with ROLLBACK, no prod data
      written.
- [x] **PM forward-only ratified** — no backfill; the 21 historical event_showcases
      keep their `showcase` slug and original XP; new writes use `showcase_*` slugs.

## References

- Migration `20260645000000_p161_gamification_rules_and_champions_phase1.sql`
- Migration `20260646000000_p161_champion_rpcs_phase2.sql`
- Migration `20260647000000_p161_gamification_points_category_fk_replace_check.sql`
- Migration `20260648000000_p161_auto_xp_triggers_phase3.sql`
- Migration `20260664000000_p165_get_gamification_leaderboard_config_driven.sql` (Amendment A)
- Migration `20260665000000_p165_register_event_showcase_config_driven.sql` (Amendment A)
- `docs/reference/SEMANTIC_TAXONOMY.md` Q5–Q7 (taxonomy ratified p161)
- ADR-0009 (config-not-code pattern for initiative kinds — same pattern applied here)
- ADR-0050 (leaderboard v2 + gamification_opt_out, respected by `get_champions_ranking` + `get_member_champions_history`)
- ADR-0062 (NULL-safe cycle_end pattern reused in `get_champions_ranking`)
- V4 Authority Model (`can_by_member`, `engagement_kind_permissions`, scope=organization vs initiative)
- `src/pages/admin/gamification.astro` (admin page shipped p161 — read-only rules table + grant modal + revoke 7d window)
- MCP tools v2.69.0/289: `award_champion`, `revoke_champion`, `get_champions_ranking`, `get_member_champions_history`

Assisted-By: Claude (Anthropic) <noreply@anthropic.com>
