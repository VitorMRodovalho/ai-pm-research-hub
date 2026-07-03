# Gamificação — Auditoria de Transparência/Auditabilidade + Spec de Melhoria (3 ondas)

> **Data da auditoria:** 2026-07-03 · **Método:** exploração de código (frontend + backend/migrations/MCP) + queries vivas no Postgres de produção (grounding rule — todos os números abaixo vieram de tool calls desta sessão).
> **Objetivo do owner:** a gamificação deve ser **auditável e transparente aos participantes** — o membro entende nas telas como ganha ponto por categoria, com trilha verificável de ponta a ponta.
> **Escopo decidido (owner):** completo — telas + API + hardening do ledger. Execução em **3 ondas** (backend→frontend→hardening), 1 PR verde mergeável por onda.

---

## 1. Sumário executivo

O **piso de transparência já existe** e é melhor do que a percepção inicial:

- RLS permite ao membro ler as **próprias linhas do ledger** (`gamification_read_members`).
- Um **extrato per-transação já existe** na aba "Meus Pontos" de `/gamification` e no drill-down de pilares de `/profile`.
- O histórico de champions em `/profile` mostra **quem concedeu, justificativa e critérios** (`get_member_champions_history`).
- O ledger é higiênico: 27 categorias em uso, **todas** casam com `gamification_rules` (FK composto, 0 órfãs), **0 linhas sem `reason`**.

Os gaps reais estão em **três camadas**:

1. **Drift** — os valores de regra estão duplicados hardcoded em 3 lugares do frontend, a mesma classe de bug que causou o incidente do rollup #1080 (Pattern 47 do ADR-0081 vale para readers SQL, mas ninguém o estendeu ao frontend).
2. **API** — não existe RPC nem MCP tool para o extrato per-transação nem para o catálogo de regras; o extrato vive só como leitura PostgREST crua no browser. Agentes/chat (superfície MCP) não conseguem auditar a pontuação de um membro.
3. **Auditabilidade estrutural** — o ledger não registra o **ator** (`granted_by`) e o `revoke_champion` **hard-deleta** as linhas espelho — o extrato do membro perde entradas silenciosamente (não é append-only).

---

## 2. Auditoria — estado atual

### 2.1 Dados vivos (queries 2026-07-03)

**`gamification_rules` (SSOT de regras):** 33 regras ativas, 8 pilares:

| Pilar | Regras | Exemplos (slug → base_points) |
|---|---|---|
| `certificacoes` | 6 | cert_pmi_senior→50, cert_cpmai→45, cert_pmi_mid→40, badge→10 |
| `champions` | 3 | champion_deliverable→40 (+5/critério, cap 60), champion_general→30 (cap 50), champion_tribe→20 (cap 40) |
| `curadoria` | 5 | curation_doc_published→30, curation_ratification→25, curation_doc_authored→20, curation_doc_locked→10, curation_comment_resolved→5 |
| `presenca` | 1 | attendance→10 |
| `producao` | 10 | deliverable_completed→30 (+10 on-time), showcase_case_study/talk→25, showcase/prompt_week/tool_review→20, artifact_published/awareness/quick_insight→15, action_resolved→5 (+2 on-time) |
| `protagonismo` | 4 | agenda_block_protagonismo→0 + bônus (external_guest→2, first_time→1, shared_material→1) |
| `trilha` | 4 | specialization→25, trail/knowledge_ai_pm→20, course→15 |

Colunas: `slug, display_name_i18n, description_i18n, base_points, bonus_per_criterion, cap_points, on_time_bonus_points, trigger_source (manual|auto_trigger|rpc_callback), active, effective_from, pillar`.

**`gamification_points` (ledger):** `id, member_id, points, reason, category, ref_id, created_at, organization_id`.
- 27 categorias em uso; FK composto `(organization_id, category) → gamification_rules(organization_id, slug)` `ON DELETE RESTRICT` (mig `20260647000000`) — regra não pode ser deletada com pontos referenciando.
- 0 linhas sem `reason`; `ref_id` NULL só nas categorias Credly-derived (trail/knowledge/specialization/certs/badge/course — datas originais antigas, by design).
- **Sem coluna `granted_by`/ator.** Proveniência = `category` + `reason` (texto livre) + `ref_id`.

**RLS (verificado em `pg_policy`):**
- `gamification_points`: membro lê próprias linhas OU `rls_is_authoritative_member()` (read-all Tier 1+); escrita só superadmin/SECDEF. Sem INSERT policy para authenticated — usuário não escreve ponto direto. ✅
- `gamification_rules`: SELECT para authenticated na org; write gated `rls_can('manage_platform')`. ✅
- `champions_awarded`: SELECT para authenticated na org — inclui `awarded_by`, `criteria_met[]`, `justification (≥50 chars)`, `points_awarded` (snapshot imutável), `status`, `revoked_*`. ✅ ledger de champion é auditável por si.

**RPCs existentes (pg_proc):** `get_gamification_leaderboard`, `get_public_leaderboard`, `get_my_gamification_stats`, `get_member_gamification_stats`, `get_member_cycle_xp`, `get_member_xp_pillars`, `get_gamification_category_activity` (admin, agregado por regra + detecção de órfãs), `get_tribe_gamification`, `get_initiative_gamification`, `get_champions_ranking`, `get_member_champions_history`, `get_champion_criteria_for_surface`, `get_event_champion_suggestions`, `get_cpmai_leaderboard`, `get_public_trail_ranking`, `set_my_gamification_visibility`, `award_champion`/`revoke_champion`/`set_event_champions`, `_grant_auto_xp`, `_grant_agenda_block_xp`/`revoke_agenda_block_xp`, `sync_attendance_points`, 8 triggers `trg_*_xp`, `recalculate_cycle_rankings` (⚠️ opera em `selection_ranking_snapshots`, não no leaderboard de gamificação — naming enganoso no MCP tool).

**Caminhos de escrita (todos SECDEF):**
- `_grant_auto_xp` (idempotente por `(ref_id, category, member_id)`, forward-only, never-raise) ← 8 triggers AFTER: deliverable_completed, artifact_published, action_resolved, curation_doc_authored/locked/published, curation_ratification, curation_comment_resolved ("resolver ganha, não commenter" — anti-farm).
- `rpc_callback` inline: `register_event_showcase` (showcase_*), sync attendance, Credly (course/trail/badge/cert), bônus on-time.
- `award_champion`: valida surface/contexto/elegibilidade/anti-self-award, caps per-evento 3/2/1 + per-grantor 3 (bloqueiam) + per-ciclo 5/8/3 (soft warning); insere `champions_awarded` + espelho no ledger.

### 2.2 Inventário de UI member-facing

| Superfície | Fonte de dados | O que o membro vê | Gap |
|---|---|---|---|
| `/gamification` — Leaderboard | `get_gamification_leaderboard` (guest→`get_public_leaderboard`) | ranking ciclo/lifetime, chips por pilar | champions = número **sem atribuição** |
| `/gamification` — Ranking de tribos | agregação client-side | avg+membros×10, chips | fórmula só em caption |
| `/gamification` — Conquistas | thresholds **hardcoded** (`ACHIEVEMENT_DEFS`, L679-691) | 11 badges locked/unlocked | critérios não expostos como tabela |
| `/gamification` — **Meus Pontos** (L1071) | PostgREST direto em `gamification_points` (own rows) | **extrato per-transação completo** + totais por categoria + Credly tiers | enterrado numa aba; sem filtros/paginação; sem API |
| `/gamification` — legendas | **hardcoded** (níveis 0-30/31-90/91-200/201-400/401+; points-legend HTML) | resumo de valores | drift vs DB |
| `ScoringInfoPopover.tsx` (L50-121) | **hardcoded JSX** | tabela de ~18 valores | drift vs 33 regras vivas |
| `TribeGamificationTab.tsx` | `get_tribe_gamification`/`get_initiative_gamification` | KPIs, breakdown 7 pilares (#577), coaching drill | champions sem atribuição |
| `/profile` — pilares XP | `get_member_xp_pillars` (vivo!) + PostgREST | tabela de regras por pilar + drill per-transação (cap 30) | cap 30 linhas; só self |
| `/profile` — champions | `get_member_champions_history` | **awarder + justification + criteria** ✅ | único lugar com atribuição |
| Home pública | `get_public_trail_ranking` | ranking de trilha | — |

### 2.3 Gaps numerados (base do spec)

| # | Gap | Evidência |
|---|---|---|
| G1 | Valores de regra hardcoded em 3 lugares do frontend (drift; classe Pattern 47/#1080) | `ScoringInfoPopover.tsx` L50-121; `gamification.astro` legendas L222-284 |
| G2 | Sem RPC/MCP de extrato per-transação nem de catálogo de regras — extrato só via PostgREST cru no browser | `profile.astro` L513-519; MCP manifest sem tool |
| G3 | `set_my_gamification_visibility` sem UI (opt-out LGPD inacessível) | zero callers em `src/**` |
| G4 | Atribuição de champion assimétrica (só em /profile próprio) | leaderboard/tribo = número seco |
| G5 | Ledger sem `granted_by`; `revoke_champion` **hard-deleta** espelho (não append-only) | schema vivo; mig phase2 |
| G6 | Critérios das 11 conquistas hardcoded client-side | `ACHIEVEMENT_DEFS` L679-691 |
| G7 | RPCs órfãos sem UI (`get_my_xp_and_ranking`, `get_my_gamification_stats`, `get_champions_ranking`, `get_cpmai_leaderboard`); `get_member_xp_pillars`/`get_gamification_leaderboard` fora do MCP; MCP `recalculate_cycle_rankings` com descrição enganosa | grep + `nucleo-mcp/index.ts` |
| G8 | Modelo de pontuação canônico só como CR-054 no DB (Manual §3.9) — sem superfície "como funciona a pontuação" | `submit_change_request` operational 2026-07-03 |

### 2.4 Referências

ADR-0081 (config-driven + champions ledger; **Pattern 47**: readers derivam do SSOT, nunca listas literais), ADR-0062 (streak/cycle), ADR-0050/0051 (leaderboard v2 + opt-out), ADR-0088/0089, `docs/reference/SEMANTIC_TAXONOMY.md` (Q5-Q7), council `2026-06-08-577-gamification-progressive-disclosure.md`, `docs/reports/HANDOVER_2026-07-03_GAMIFICATION_CONCILIATION_C3.md`, migs `20260805000327` (fix buckets #1080), `20260805000322` (fix ORDER BY leaderboard #1068/#1069).

---

## 3. Princípios (boas práticas pós-auditoria)

1. **SSOT-driven UI** — Pattern 47 estendido ao frontend: nenhuma tela repete valor de regra; tudo deriva de `gamification_rules` (e critérios de champion do `champion_criteria_catalog`).
2. **Ledger append-only** — correção/revogação = lançamento de **estorno** (linha negativa referenciando a origem), nunca DELETE. Somas continuam corretas; a história fica visível.
3. **Proveniência de ator** — toda linha nova registra quem/qual fluxo creditou (`granted_by`; NULL = sistema/cron, explícito).
4. **Self-service LGPD** — o membro vê tudo sobre si (extrato, atribuições, estornos) e controla sua visibilidade pública (opt-out funcional).
5. **Progressive disclosure** (precedente #577) — resumo → pilar → transação, sem afogar a tela default.
6. **Paridade web/agente** — o que a tela mostra, o MCP expõe (chat e agentes conseguem responder "por que ganhei N pontos?").

---

## 4. Spec por onda

### Onda 1 — Backend: SSOT + API de transparência (1 PR; migrations + MCP)

| Item | Descrição | Resolve |
|---|---|---|
| 1.1 | **`get_gamification_rules_catalog()`** — RPC SECDEF (authenticated): regras ativas (pillar, base/bonus/cap/on-time, trigger_source, display/description i18n) + critérios de champion + **thresholds de nível** (mover os 5 tiers hardcoded para config). Wire como MCP tool. | G1 (fonte), G8 (fonte) |
| 1.2 | **`get_my_points_statement(p_scope, p_category, p_limit, p_offset)`** — RPC member-scoped via `auth.uid()` (padrão `get_my_meetings`, sem IDOR): extrato per-transação enriquecido (display name da regra, pilar, atribuição de champion via join `champions_awarded` on `ref_id`, flag de estorno). Wire como MCP tool. | G2 |
| 1.3 | **Coluna `granted_by uuid NULL`** no ledger (additive, forward-only, sem backfill): `_grant_auto_xp` ganha parâmetro de ator; `award_champion` passa `awarded_by`; triggers passam `auth.uid()` quando presente. | G5 (parte 1) |
| 1.4 | Wire MCP: `get_member_xp_pillars`; corrigir descrição do MCP tool `recalculate_cycle_rankings` (opera em selection, não gamificação). | G7 (parte) |
| 1.5 | Contract tests: statement self-only (sem IDOR), paridade catálogo↔rules, `granted_by` populado nos writers novos. | — |

**Aceite:** MCP responde catálogo completo + extrato do próprio membro; nenhum número novo hardcoded; CI verde com testes DB-aware.
**Disciplinas:** DDL via `apply_migration` + arquivo local + `migration repair` + `NOTIFY pgrst`; re-apontar Phase C `LATEST_CAPTURE_PATH` se redefinir RPC capturado (LL #727); checar phantom `202607%` sem LIMIT; ao alterar assinatura de `_grant_auto_xp`, DROP+CREATE e atualizar TODOS os 8 triggers callers no mesmo migration.

### Onda 2 — Frontend: data-driven + UX de transparência (1 PR)

| Item | Descrição | Resolve |
|---|---|---|
| 2.1 | `ScoringInfoPopover`, points-legend e legenda de níveis consomem `get_gamification_rules_catalog` (eliminar hardcode 3×). | G1 |
| 2.2 | **Extrato promovido**: aba "Meus Pontos" usa o statement RPC com filtros pilar/ciclo + paginação; cards de XP em /profile e /workspace deep-linkam pro extrato. | G2 (UX) |
| 2.3 | **Atribuição de champion** em leaderboard/tribo: drill/tooltip com awarder+justification+criteria (dados já legíveis por authenticated; respeitar opt-out). | G4 |
| 2.4 | **UI de opt-out** em /profile: toggle chamando `set_my_gamification_visibility` + estado atual. | G3 |
| 2.5 | **Conquistas transparentes**: tabela de critérios/thresholds das 11 badges visível na aba (config-driven completo = futuro). | G6 (mínimo) |
| 2.6 | i18n 3/3 (pt-BR/en-US/es-LATAM) em toda chave nova; /en/ /es/ já são re-exports. | — |

**Aceite:** grep confirma zero valores de pontos hardcoded em componentes; membro consegue: ver extrato filtrado, ver quem deu cada champion, se ocultar do leaderboard. `npx astro build` + i18n parity.

### Onda 3 — Hardening de auditabilidade + documentação (1 PR)

| Item | Descrição | Resolve |
|---|---|---|
| 3.1 | **Revoke append-only**: `revoke_champion` insere estorno (pontos negativos, `ref_id = champions_awarded.id`, reason com motivo) em vez de DELETE; validar rollups (SUM absorve estorno); contract test "no DELETE on ledger". | G5 (parte 2) |
| 3.2 | Extrato/statement rotula estornos claramente ("revogado: …"). | G5 |
| 3.3 | Superfície member-facing **"Como funciona a pontuação"** reconciliada com CR-054/Manual §3.9 — fonte = catálogo vivo (1.1), não texto duplicado. | G8 |
| 3.4 | Sweep final: remover ou wire os RPCs órfãos restantes; atualizar `SEMANTIC_TAXONOMY.md`/ADR-0081 com as invariantes novas (append-only, granted_by). | G7 |

**Aceite:** revogar um champion de teste deixa a linha original + estorno visíveis no extrato; teste de invariante append-only no CI; ADR/taxonomia atualizados.

---

## 5. Modelo de execução (recomendação)

- **3 ondas, 1 PR verde cada, mergeável independente.** Backend primeiro para o frontend nunca nascer apontando para hardcode; hardening por último porque muda semântica do revoke (maior risco conceitual, precisa de isolamento de review).
- Cada onda começa com **grounding-antes-de-construir** (LL macro 2026-07-03): re-auditar as premissas desta spec ao vivo antes de codar — este documento reflete 2026-07-03.
- Estimativa: Onda 1 ~1 sessão dev · Onda 2 ~1-1.5 sessão (maior superfície i18n/UI) · Onda 3 ~1 sessão.
- Merge = sessão main, autorizado pelo owner por PR (disciplina de lane vigente).

## 6. Fora de escopo / futuro

- Conquistas 100% config-driven (tabela `achievements` + engine) — G6 completo; avaliar após Onda 2.
- Notificação push/e-mail "você ganhou X pontos" (transparência ativa) — candidata a issue própria.
- Histórico público de mudanças de regra (`effective_from` já dá base) — expor "changelog de regras" no catálogo.
- Backfill de `granted_by` histórico — deliberadamente forward-only.
