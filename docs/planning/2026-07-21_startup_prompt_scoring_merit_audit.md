# Prompt de arranque — SESSÃO LIMPA: auditoria criteriosa de pontuação e mérito

> Cole o bloco abaixo como PRIMEIRA mensagem de uma sessão nova/limpa.
> **Modelo:** Opus 4.8 (não baixar/pinar; é o mais capaz — quality-first). `/fast` opcional se ficar interativo.
> **Level of effort:** **`/effort xhigh`** (ou keyword `ultrathink`) — tema difícil e de alto risco.
> Antes de agir: ler MEMORY.md, `git fetch`, re-aterrar TODO número ao vivo (grounding do CLAUDE.md).

---

Sessão de trabalho no ai-pm-research-hub. **Rodar em Opus 4.8 + effort xhigh.** Tema SÉRIO: pontuação
e mérito envolvem **transparência e credibilidade** e vêm sendo levados de lado. Mandato: **auditoria
criteriosa, adversarial, sem hand-waving** — nada de "parece certo"; traçar a matemática ponta a ponta,
provar cada afirmação com query ao vivo, e reconciliar UI ↔ RPC ↔ DB. Regras da casa: DDL só via
apply_migration byte-igual + repair + NOTIFY + deletar phantom rows (data real `202607*` ordena ANTES
do sintético `202608*`; deletar por versão exata, checar SEM `LIMIT` curto — a armadilha do drift-lock);
merge só na sessão main exceto autorização explícita do owner; sem em-dash em entregáveis; Assisted-By
nunca Co-Authored-By.

## Escopo (DOIS subsistemas, uma ótica: transparência + credibilidade do mérito)

### A. Seleção — pontuação / ranking / corte (Ciclo 4 - 2026/2)
Owner reportou (2026-07-21, print em `docs/planning/`): a tela de Processo Seletivo está errada.
**Anomalias observadas (LEADS, não conclusões — provar/refutar ao vivo):**
- Banner "**Rankings vazios: 14/14 aplicações sem rank (100%)**" MAS as linhas mostram ranks #47/#52/#12/#55
  (contradição: 100% sem rank vs ranks exibidos).
- "**Corte: 130.9 (98.2–130.9, n=45, dynamic)**" convivendo com rankings supostamente vazios (o corte foi
  calculado sobre quê, se não há ranks?).
- "**Corte Líder não calculado (cohort < 10 ou sem avaliações)**"; régua líder n=9<10 / n=8<10.
- Botões "Recalcular Rankings" / "Iniciar Triagem"; blind review "not all evaluators have submitted yet".
- **Pergunta explícita do owner:** o **corte do Ciclo 4 - 2026/2 está correto?**

Entry points (portas de entrada, aterrar corpo VIVO via `pg_get_functiondef`, não grep de migration velha):
- Ranking: `calculate_rankings`, `recalculate_cycle_rankings`, `get_selection_rankings`, `get_selection_dashboard`.
- Corte: `compute_pert_cutoff`, `_compute_pert_cutoff_core`, `get_pert_cutoff_summary`,
  `get_cutoff_dispatch_health`, `recompute_all_active_pert_cutoffs`, `_selection_cutoff_pending_cron`,
  `notify_selection_cutoff_approved`.
- Gate de entrevista por `objective_score_avg` (ver [[handoff_session_2026_07_21_selection_vep]]).
- Schema/critério: `supabase/migrations/20260319100025_w124_phase2_blind_eval_scoring.sql`,
  `20260401070000_s3_s11_criterion_notes_membership_flag.sql`, `20260401100000_interview_rubrics_observer_role.sql`.
- UI: `src/pages/admin/selection.astro` + ilhas de avaliação.

### B. Gamificação de membros — XP / pilares / leaderboard
Owner: "ainda não está arrumado, ainda está errado". Sessão C (21/07) tocou #1448/#1449 (PR#1455, mig 472),
mas segue errado. Entry points:
- `get_gamification_leaderboard`, `get_public_leaderboard`, `get_member_gamification_stats`,
  `get_my_gamification_stats`, `get_member_xp_pillars`, `get_gamification_rules_catalog`,
  `get_gamification_category_activity`, `get_initiative_gamification`, `get_tribe_gamification`,
  `get_cpmai_leaderboard`, `get_pre_onboarding_leaderboard`.
- Regra fluxo (cycle) vs vitalício (estoque), surface-aware: [[reference-gamification-xp-flow-vs-lifetime-surface-aware]].
- Issues vivos: **#1069** ([audit] sweep gamification/leaderboard RPCs por RETURNS TABLE OUT-var ORDER BY
  conflict — CLASSE DE BUG que pode produzir ranking errado; começar por aqui), **#591** (drill-down pillar
  breakdown), **#718** (split protagonismo no breakdown), **#1209** (fallback badge/10 Credly), **#1221**
  (mérito imutável ao executor — guard MCP + auditoria), **#873** (jornada gamificada pré-onboarding).

### C. Transparência por critério (pedido explícito do owner, atravessa A e B)
"a forma de transparência de ver a **pontuação de todos alocada por critério**." Auditar: existe uma
superfície (UI + RPC) que mostra, de forma auditável, o score de cada pessoa **decomposto por critério**
(seleção: rubricas/critérios de avaliação; gamificação: pilares/categorias)? Está correto, completo, e
visível para quem deve ver (respeitando blind review + LGPD)? Se não existe ou está errado, é o coração
do problema de credibilidade.

## Método de auditoria (criterioso)
1. **Ponta a ponta:** avaliação bruta por critério → agregação → score final → ranking → corte. Provar cada
   salto com query ao vivo. Onde a UI, o RPC e o DB divergem, isso É o achado.
2. **Adversarial:** para cada "está certo", tentar refutar. Não pinar contagem como invariante (a invariante
   é a regra, não o N — ver [[reference-guardian-must-not-recite-counts]]).
3. **Corpo vivo vence comentário/log/migration velha** ([[reference-live-body-beats-failure-log-and-stale-comments]]).
4. **Roteamento de conselho (justificado por ser tema estratégico de credibilidade):** `data-architect`
   na matemática do score/ranking/corte + schema; `product-leader`/`ux-leader` na superfície de transparência
   por critério; `security-engineer` no quem-vê-o-quê (blind review + LGPD). `/council-review` no fecho se
   virar decisão de desenho. 1 agente por subação; declarar a justificativa antes de convocar múltiplos.
5. **Entregável:** relatório de auditoria (achados provados, com antes/depois ao vivo) → issues/PRs por
   achado. Corte do Ciclo 4: veredito explícito (correto? se não, por quê e qual o valor certo).

## Não re-litigar / contexto travado
- Wave 2 já fechada nesta rodada: #1170, #1008 (nome ACD aprovado pelo owner — [[project-wave2-human-decisions-ratified]]),
  #1152 (committee_majority ativado). #1424-D adiado sáb 25/07.
- Antes de doc/DDL de issue: GREP `docs/project-governance/` + `docs/council/decisions/` (lição do #1008).
