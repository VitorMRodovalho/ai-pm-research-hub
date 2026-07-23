# Prompt de arranque - SESSÃO LIMPA: Onda 3 (B0 gamificação - occurred_at + rejanela por data-do-fato)

> Cole o bloco abaixo como PRIMEIRA mensagem de uma sessão nova/limpa.
> **Modelo:** Opus 4.8 (não pinar). **Effort:** `/effort xhigh`. Sessão de EXECUÇÃO (aplica + mergeia à main).
> Antes de agir: ler MEMORY.md + [[project-scoring-merit-audit-2026-07-21]] + [[reference-gamification-cycle-windowed-by-createdat-trap]] + [[reference-gamification-xp-flow-vs-lifetime-surface-aware]], `git fetch`, e RE-ATERRAR todo número ao vivo.

---

Sessão de execução no ai-pm-research-hub - **Onda 3** do roadmap de pontuação/mérito
(relatório: `docs/audit/2026-07-21_scoring_merit_audit.md`, seção B0 + "Plano B0"). **Rodar em Opus 4.8 + xhigh.**
Ondas 1 (A1/A2 + invariante M, main `387f20d3`) e 2 (corte active-only retroativo + cross-role, main `5758eaa3`, #1463 CLOSED) já MERGEADAS. Onda 3 = **B0 gamificação (issue #1464)**.

## Contexto travado (NÃO re-litigar; achado provado ao vivo na auditoria)
- **B0 (ALTA):** o ranking do "ciclo atual" está contaminado por backfill histórico. O placar é janelado por
  `gamification_points.created_at` (data do LANÇAMENTO do ponto), **não** pela data real do evento. Não existe
  coluna de data-do-fato, então um backfill de presença histórica cai inteiro no ciclo corrente.
- **A MATEMÁTICA de agregação está CORRETA** (leaderboard/pilares auditados: 0 categorias órfãs, 0 negativos, #1069 sem
  colisão em 11 RPCs). O erro é **atribuição de ciclo**, não soma. NÃO re-auditar a soma.
- `gamification_points` **NÃO tem `occurred_at`** (confirmado ao vivo 2026-07-22: colunas = id, member_id, points,
  reason, category, ref_id, created_at, organization_id, granted_by).
- **Windowing atual:** `get_member_gamification_stats` janela o ciclo por `gp.created_at >= cycles.cycle_start` (fonte =
  tabela `public.cycles` onde `is_current=true`). Confirmado ao vivo: `cycle_start` atual = **2026-07-09**.
- **PRESERVAR o surface-aware de certificações** (#1448/mig 472, [[reference-gamification-xp-flow-vs-lifetime-surface-aware]]):
  certificações contam VITALÍCIO na visão de pilar de ciclo. A rejanela por `occurred_at` é para pontos de **FLUXO**
  (presença etc.); NÃO pode quebrar o "certificações sempre contam" no perfil.

## Números re-aterrados 2026-07-22 (RE-ATERRAR DE NOVO antes de aplicar)
- Backfill de **2026-07-11** (batch, `granted_by IS NULL`): **560 linhas / 58 membros / 5620 pontos**.
- Destes, **525 linhas / 5250 pontos / 48 membros** resolvem para eventos com data **< 2026-07-09** (cycle_start), datas
  reais de **2025-10-08 a 2026-07-09** -> mal-atribuídos ao ciclo corrente. 2 linhas sem evento resolvível via `ref_id`.
- Resolução: `gamification_points.ref_id` -> `attendance.id` -> `attendance.event_id` -> `events.date`.

## Mandato desta sessão (Onda 3 - Plano B0 do relatório)
1. **Re-aterrar ANTES (obrigatório):** re-rodar ao vivo `cycle_start` (esperado 2026-07-09), o batch de 11/07 (esperado
   ~560/58/5620), os 525/5250/48 pré-ciclo, e um antes/depois NOMINAL de quem muda de posição no ranking do ciclo
   (o relatório cita Ana C. 280->50, Jefferson P. 280->30, Marcos A. 260->20, Fabricio C. 230->10 - RE-ATERRAR).
2. **Adicionar `gamification_points.occurred_at timestamptz`** = data REAL do fato (não do lançamento). DDL via
   `apply_migration`; nullable; index se necessário.
3. **Backfill `occurred_at`:** presença via `attendance.event_id -> events.date`; demais categorias via a fonte
   (`ref_id`) quando resolvível, senão fallback `created_at`. As 2 linhas de presença sem evento resolvível -> fallback
   `created_at` (documentar).
4. **Rejanelar a atribuição de ciclo por `occurred_at`** (não `created_at`) em: `get_member_gamification_stats`
   (CTEs `member_cycles` [streaks + active_cycles] E `cycle_pts` [points_this_cycle]), `get_member_xp_pillars` (ramo
   `cycle`), e a lógica de ciclo do leaderboard (`get_public_leaderboard` / `get_gamification_leaderboard` - checar o
   hybrid-scope p170). `created_at` continua sendo auditoria de "quando foi lançado". **Basear no corpo VIVO** (`pg_get_functiondef`);
   byte-fiel + md5 normalizado live==arquivo ([[reference-apply-large-function-mcp-inline-md5-verify]]).
5. **Normalizar o backfill de 2026-07-11** (525 linhas de eventos < cycle_start): `occurred_at` = data do evento,
   tirando-as do ciclo corrente. É a mudança que corrige o ranking exibido.
6. **Corrigir `get_member_xp_pillars`:** o `ORDER BY CASE pillar` não tem o caso `protagonismo` (fica sem posição de
   ordenação). Adicionar.
7. **UI (perfil):** rotular claramente chips de **ciclo** vs **vitalício** (fim da mistura sem legenda). i18n em pt/en/es.
8. **HUMAN CHECKPOINT (a parte sensível):** a correção **muda rankings VISÍVEIS do ciclo** para membros (ex.: quem liderava
   com presença de ciclos anteriores cai). Decidir com o owner **como comunicar/exibir**: silencioso (só corrige o número)?
   nota explicativa? Pontos VITALÍCIOS não mudam (nada é revogado) - só a atribuição de ciclo. Levar antes/depois nominal.
9. **Contract test:** pontos de ciclo janelam por `occurred_at`; um backfill (created_at no ciclo, occurred_at fora) NÃO
   pode alterar o ranking do ciclo corrente. Registrar em AMBAS as whitelists do `package.json` (test + test:contracts).
10. **`npx astro build` + `npm test`** (com SUPABASE_URL + SERVICE_ROLE_KEY -> DB-aware). 0 fail.
11. **Grounding adversarial** (workflow 3-lentes) antes do backfill de dado retroativo: null-safety dos leitores /
    side-effects (triggers de XP em `gamification_points`?) / completeness (surface-aware de certificações preservado?).
    Valeu nas Ondas 1 e 2 (pegou bugs pré-apply).
12. **Aplicar + registrar:** `apply_migration`; deletar phantom por versão EXATA ([[feedback-apply-migration-creates-tracking-row]]);
    `migration repair --status applied <versão>`; `NOTIFY pgrst` se afeta superfície PostgREST.
13. **Merge do PR à main** (sessão main; pode mergear). Fecha #1464.
14. Atualizar [[project-scoring-merit-audit-2026-07-21]] + MEMORY.md com o antes->depois vivo (Onda 3 fechada) + LL em #588.

## Regras da casa (não esquecer)
- Números em prompt/PR/commit/memória = de tool result DESTA sessão; nunca recitar de memória.
- Sem em-dash (—) em entregáveis. Trailer `Assisted-By: Claude (Anthropic)`, nunca `Co-Authored-By`.
- DDL só via `apply_migration` (não `execute_sql`). Deletar phantom por versão exata.
- Head de migrations atual: **20260805000479** (Onda 2). Próxima versão livre = re-consultar
  `SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 1`.
- Backfill retroativo de dado é irreversível-ish: grounding adversarial ANTES; byte-fidelidade provada.

## Entry points (verificar ao vivo)
- Tabela `gamification_points` (add `occurred_at`); `cycles` (`is_current`, `cycle_start/cycle_end`).
- RPCs: `get_member_gamification_stats`, `get_member_xp_pillars`, `get_public_leaderboard`, `get_gamification_leaderboard`.
- Triggers de XP em `gamification_points` (auto-XP phase3, mig p161) - checar se algum grava/lê data.
- Frontend: perfil (chips ciclo vs vitalício) - grep `points_this_cycle` / pilares / leaderboard.

## Ondas seguintes (depois da 3)
4=backend de transparência (criterion_notes no consolidado + blind-review unificado - findings C-sel/C-blind);
5=CAPSTONE UX #1465 (feature de transparência que os membros pedem - só DEPOIS das correções). Follow-up aberto **#1468**
(recompute_application_status mediana cross-role, materialidade baixa).
