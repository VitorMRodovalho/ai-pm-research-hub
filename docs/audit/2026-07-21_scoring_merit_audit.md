# Auditoria criteriosa de pontuação e mérito — Ciclo 4 (2026/2) + Gamificação

> Data: 2026-07-21. Sessão adversarial (Opus 4.8 + effort xhigh, ultracode).
> Método: rastreio ponta a ponta (avaliação bruta por critério -> agregação -> score -> ranking -> corte),
> cada afirmação provada por query ao vivo no DB `ldrfrvwhxsmgaabwmaik`; corpo VIVO das funções (`pg_get_functiondef`)
> vence migration/comentário. Achados marcados `[VERIF]` sobreviveram a re-derivação por cético independente
> (workflow multi-agente); `[DIRETO]` foram computados por query ao vivo nesta sessão.
> Nomes mascarados (Primeiro U.) por revisão cega + LGPD.

Ciclo 4 = `cycle4-2026` (id `08c1e301-9f7b-4d01-a13c-43ac7775c0f7`), status `open`, phase `evaluating`, 74 aplicações.
Fórmula ratificada v1.0-cr047: PERT `(2*min+4*avg+2*max)/8`; `research_score = objective_pert + interview_pert`;
`leader_score = research_score*0.7 + leader_extra_pert*0.3`; RANK() competition, desempate `applicant_name ASC`.

---

## VEREDITO DO CORTE (pergunta explícita do owner)

**O valor 130.9 está aritmeticamente CORRETO. A questão é de MÉTODO, e é decisão sua.**

- Armazenado: alvo `130.89`, banda `98.17-130.89`, `cohort_n=45`, método `dynamic`, calculado `2026-07-20 13:00 UTC`.
- Recomputado ao vivo do cohort (researcher, `objective_score_avg` não-nulo): n=45, min=58.50, avg=135.29, max=194.50
  -> `(2*58.50 + 4*135.29 + 2*194.50)/8 = 130.89`. **Confere.** `[DIRETO]`
- **Ressalva de método (ver A3):** o cohort de 45 inclui **7 já rejeitados**. Excluindo-os, o alvo sobe para
  **142.69** (min sobe de 58.5 para 93.5). O corte "dinâmico" está ancorado parcialmente em candidatos já eliminados,
  o que **rebaixa a régua em ~11.8 pontos (~9%)** para todos os demais.
- **Corte de líder NÃO calculado** (leader_extra n=9<10; final_score-líder n=8<10 -> método `disabled`). Decisões de
  líder hoje não têm régua PERT própria.

---

## A. SELEÇÃO

### A1 — Ranks persistidos estão DESATUALIZADOS (não apenas vazios) `[VERIF]` — ALTA
Nenhum gatilho recomputa o ranking do ciclo quando um score muda. Os gatilhos em `selection_evaluations`
(`trg_recompute_app_pert`, `trg_recompute_application_scores`) recomputam **apenas a linha** (via
`compute_application_scores`/`_recompute_application_pert`); **nenhum** chama `recalculate_cycle_rankings`. Este só roda
no botão "Recalcular Rankings".
- Último snapshot de ranking: `2026-07-02 23:42`. Avaliações submetidas depois disso: **26**.
- Researcher: 53 ranqueáveis ao vivo, **47 divergem** do `rank_researcher` armazenado, **13 que deveriam ter rank estão NULL**.
  Inversão grave: **Francisco J.** (research 259.50, `approved`) exibido **#39**, rank vivo **#7** (gap 32).
- Líder: 9 ranqueáveis, 7 divergem, 3 NULL. O 4º maior `leader_score` (**Paulo A.**) aparece **sem rank**.
- Impacto direto na superfície: `get_selection_rankings` (admin/curador) ordena pelo rank armazenado E **descarta linhas
  com rank NULL**, então os 13 researchers + 3 líderes somem da lista. `get_my_selection_result` mostra o rank stale ao
  próprio candidato (35 de 41 apps em status final estão errados).
- **Fix:** recomputar ranks quando `research_score`/`leader_score` mudam (gatilho statement-level debounced ->
  `recalculate_cycle_rankings`) OU ranquear em tempo de leitura via `RANK()` sobre scores vivos. Interino: rodar
  `recalculate_cycle_rankings` agora + expor `ranks_recomputed_at`.
- Entry points: `recalculate_cycle_rankings`, `get_selection_rankings`, `get_my_selection_result`, `_trg_recompute_application_scores`.

### A2 — `research_score` foge da fórmula ratificada: sem trava de `min_evaluators` `[VERIF]` — ALTA
`compute_application_scores` grava `research_score = AVG(subtotais objetivos) + AVG(subtotais entrevista)` e
**não tem checagem de contagem de avaliadores**.
- **Metade LATENTE (AVG vs PERT):** a fórmula manda PERT `(2*min+4*avg+2*max)/8`; a função usa média simples. Em n<=2
  avaliadores PERT==AVG, e no Ciclo 4 nenhuma app tem >=3 avaliadores objetivos (17 têm 1, 54 têm 2), então **impacto
  numérico atual = 0**. Passa a divergir no instante em que qualquer tipo chegar a 3+ avaliadores.
- **Metade VIVA (sem trava de min):** `objective_score_avg` (usado no corte) exige 2 avaliadores; `research_score`
  aceita **1**. Resultado: **17 apps têm `research_score` mas `objective_score_avg` NULL** (71 com research vs 54 com
  obj_avg). Duas delas estão **ranqueadas E aprovadas com base em 1 único avaliador** (ex.: Priscila O., research 239.00).
  Isso fura a regra de revisão dupla que dá credibilidade ao mérito.
- O guard dedicado `check_application_score_consistency()` **não pega** isso (inspeciona as colunas PERT gated, nunca `research_score`).
- **Fix:** derivar `research_score` das colunas já consolidadas (`objective_score_avg + interview_score`) e deixar NULL
  até cada componente atingir seu `min_evaluators` ({objective:2, interview:1, leader_extra:2}).
- Entry points: `compute_application_scores`, `check_application_score_consistency`.

### A2b — Contradição "14/14 sem rank" vs linhas #47/#52 (a tela que o owner viu) `[DIRETO]` — MÉDIA (UX/confiança)
Não é corrupção de dado, é **dois conceitos de rank com a mesma linguagem visual**:
- A coluna "rank" da tabela exibe **`objective_rank`** (`selection.astro:404/1859`), que `get_selection_dashboard` calcula
  on-the-fly (`ROW_NUMBER() OVER (PARTITION BY role_applied ORDER BY objective_score_avg DESC)`) e **está sempre presente**.
- O banner "Rankings vazios" (`selection.astro:1618-1634`) audita os **4 ranks persistidos** (que só existem pós-botão).
- O "14/14 (100%)" é a view "pending" = `submitted`(10) + `interview_pending`(2) + `interview_scheduled`(2) = 14 linhas,
  todas sem rank persistido, cada uma mostrando seu badge `objective_rank`. Some com A1 resolvido + alinhar o badge ao
  rank de trilha (ou rotular explicitamente "rank objetivo provisório").

### A3 — Corte inclui já-rejeitados; parâmetro morto; carimbo cross-role `[DIRETO]` — MÉDIA (método/credibilidade)
- `_compute_pert_cutoff_core` aceita `p_filter_active_only` e **nunca o usa** (só o loga como `filter_active_only_legacy_arg`).
  O cohort = todos do role com score não-nulo, **incluindo rejeitados**. Sensibilidade: 130.89 (com 7 rejeitados) vs
  **142.69** (sem). Decisão de política (ver "Decisões").
- **Cross-role:** o corte objetivo é researcher-only, mas o UPDATE grava `pert_target_score=130.89` em **todas** as linhas
  do ciclo (inclusive líderes). E `get_cutoff_dispatch_health` compara `objective_score_avg >= pert_target_score` **sem
  filtro de role**, então um líder (obj ~199) é comparado ao corte de researcher.
- Entry points: `_compute_pert_cutoff_core`, `get_cutoff_dispatch_health`.

---

## C. TRANSPARÊNCIA POR CRITÉRIO (pedido explícito do owner)

### C-sel — A superfície existe, mas a justificativa qualitativa some no consolidado `[VERIF]` — BAIXA/PARCIAL
- **Existe** decomposição por critério: `get_evaluation_results` renderiza matriz critério x avaliador + subtotal ponderado
  + alertas de calibração (divergência > 3) em `selection.astro:4078`.
- **Lacuna:** as `criterion_notes` (racional por critério, 78 preenchidas no C4) **não aparecem** na visão consolidada do
  admin. Só aparecem (a) no formulário travado do próprio avaliador e (b) via MCP `get_application_score_breakdown` (que
  nenhuma `.astro` chama). Um curador reconciliando um score divergente não lê a justificativa no app web.
- **Fix:** incluir `criterion_notes` em `get_evaluation_results` e renderizar, OU migrar a tela para `get_application_score_breakdown`.

### C-blind — Duas superfícies discordam sobre quando desanonimizar `[VERIF]` — BAIXA/PARCIAL (latente)
`get_evaluation_results` revela nome + scores do co-avaliador ao atingir `min_evaluators` (sem checar phase; 54/74 apps já
em 2+ no Ciclo 4), enquanto `get_application_score_breakdown` cega não-superadmins durante `evaluating`/`interviews`.
Latente hoje (nenhum usuário atual alcança as duas superfícies no estado cego), mas a promessa de revisão cega fica
inconsistente. **Fix:** escolher uma regra (recomendo a phase-gated own-only) e aplicá-la nas duas.

---

## B. GAMIFICAÇÃO

### B0 — Ranking do "ciclo atual" contaminado por backfill histórico `[DIRETO]` — ALTA
**Este é o defeito real que os membros questionam.** O placar "ciclo atual" é janelado por
`gamification_points.created_at` (data do LANÇAMENTO do ponto), não pela data real do evento (`events.date`). Não existe
coluna de data-do-fato, então um backfill de presença histórica cai inteiro no ciclo corrente.
- Em `2026-07-11 ~03:15 UTC` (batch, `granted_by=null`) foram inseridas **558 linhas de presença** (57 membros). Resolvendo
  `ref_id -> attendance -> events.date`: **525 são de eventos ANTERIORES ao cycle_4** (datas reais de 2025-10-08 a
  2026-07-09), só 33 do ciclo atual. **5250 pontos mal-atribuídos ao cycle_4, afetando 48 membros.**
- Efeito no ranking do ciclo (exibido vs corrigido por data-do-evento): Ana C. 280->50, **Jefferson P. 280->30**,
  Marcos A. 260->20, Fabricio C. 230->10. Quem tem atividade real do ciclo (Paulo A. 120, Honorio D. 150) aparece
  soterrado em #12/#20. O líder exibido do ciclo lidera com presença do Ciclo 3.
- Caso Jefferson: "Ciclo Atual 280" = 28 presenças, 25 backfillpadas em 11/07 (Reunião Geral Ciclo 03, Talentos &
  Upskilling, Lideranca #1-6, Tribo semanal — 09/04 a 07/07). Reais do cycle_4: 3 eventos (30 pts). Ele nunca teve reunião
  de tribo do ciclo atual, correto.
- **Fix:** atribuir ciclo pela data real do fato. Adicionar `occurred_at`/`activity_date` em `gamification_points`
  (backfill a partir de `events.date` para presença) e janelar o ciclo por essa coluna, não por `created_at`. Interino:
  reprocessar as 525 linhas do backfill de 11/07 para `occurred_at`=data do evento (ou reverter e regravar com carimbo correto).
- Entry points: `gamification_points`, `get_member_gamification_stats`, `get_member_xp_pillars`, `get_public_leaderboard`,
  o job/rotina que fez o backfill de 11/07.

### Veredito: a MATEMÁTICA de agregação está correta; o ERRO é de atribuição de ciclo (B0) `[DIRETO]`
- Leaderboard vitalício: top raw sums (`2469, 1880, 1572, 1380, 1250...`) idênticos ao `get_gamification_leaderboard`,
  monotônico, **0 categorias órfãs, 0 pontos negativos, 0 divergência de reconciliação** em todos os top-12. Somar está certo.
- `#1069` (colisão OUT-var/ORDER BY): **sem colisão em nenhum dos 11 RPCs**, provado ao vivo por impersonação `[VERIF]`.
- Pilares reconciliam (vitalício): presença 19730, trilha 7640, certificações 3925, curadoria 3905, produção 2190, protagonismo 152, champions 150.
- Achado lateral: `get_member_xp_pillars` tem `ORDER BY CASE pillar` **sem o caso `protagonismo`** (fica sem posição de
  ordenação); e o header de chips do perfil mistura escopo ciclo x vitalício sem rótulo claro (parte da falha de transparência).

### B1 — Desync latente pilares x leaderboard `[VERIF]` — BAIXA
`get_member_xp_pillars` soma só categorias de regra ATIVA; `get_public_leaderboard` soma TODOS os pontos. Reconcilia hoje
(0/101), mas desativar uma regra com histórico faria o total do perfil cair abaixo do leaderboard/nível sem explicação
(ex.: desativar `attendance` sumiria 19730 pts de 99 membros do perfil, leaderboard intacto). **Fix:** pilar "legacy" para
pontos de regra inativa OU somar só regras ativas no leaderboard + contract test `SUM(all)==SUM(pilares)`.

### B2 — Leaderboard interno inclui inativos; público exclui `[DIRETO]` — BAIXA
27 membros inativos têm pontos. **Débora M.** (inativa, 1380) aparece **#4** no `get_gamification_leaderboard`; o
`get_public_leaderboard` a exclui (`is_active`). Inconsistência de quem-aparece entre superfícies interna e pública.

> Nota: não reproduzi nenhum erro numérico no leaderboard/pilares. Se há uma tela/número específico que parece errado,
> preciso do exemplo concreto (membro + número esperado vs exibido) para reproduzir.

---

## Plano B0 — corrigir atribuição de ciclo da gamificação (PR dedicado, validar ao vivo)
1. Adicionar `gamification_points.occurred_at timestamptz` = data REAL do fato (não do lançamento).
2. Backfill `occurred_at`: presença via `attendance.event_id -> events.date`; demais categorias via a fonte
   (`ref_id`) quando resolvível, senão fallback `created_at`.
3. Rejanelar a atribuição de ciclo por `occurred_at` (não `created_at`) em `get_member_gamification_stats`,
   `get_member_xp_pillars` (ramo `cycle`) e na lógica de ciclo do leaderboard. `created_at` continua sendo auditoria de quando foi lançado.
4. Normalizar o backfill de 2026-07-11 (525 linhas de eventos < 2026-07-09): `occurred_at` = data do evento, tirando-as do cycle_4.
5. Corrigir `get_member_xp_pillars`: `ORDER BY CASE pillar` sem o caso `protagonismo` (fica sem posição).
6. UI: rotular claramente chips de ciclo vs vitalício no perfil (fim da mistura sem legenda).
7. Contract test: pontos de ciclo janelam por `occurred_at`; um backfill NÃO pode alterar o ranking do ciclo corrente.

## Migrations preparadas nesta sessão (475/476 APLICADAS na Onda 1; 477 pendente Onda 2)
- `..475_audit_A2_...` (PR Onda 1) — A2: `compute_application_scores` deriva de PERT + trava min_evaluators (research NULL p/ 1-avaliador).
- `..476_audit_A1_...` (PR Onda 1) — A1: rank em tempo de leitura em `get_selection_rankings` + `get_my_selection_result` (fim do stale + não oculta ranqueáveis).
- `..477_audit_A3_...` (PR Onda 2) — corte active-only (honra `p_filter_active_only`; recompute -> 142.69 retroativo, escolha do owner). Fica por ÚLTIMO por ser o mais sensível.
> Apply + recompute + testes DB-aware ficam para a sessão main (owner pediu "sem tocar dado vivo agora").
> Backfills de dado (rodar `compute_application_scores` no ciclo, `recompute_all_active_pert_cutoffs`) são passos de apply, não estão nas migrations.

## Roadmap de correção em ondas (sessões limpas; apply -> merge serial por drift-gate)
| Onda | Escopo | Sensibilidade | Superfície |
|------|--------|---------------|------------|
| 1 | Seleção A1+A2 (rank read-time + trava min) + backfill scores no ciclo | baixa | backend + admin |
| 2 | Corte active-only A3 (retroativo 142.7); tratar display dos 7 aprovados abaixo da banda (NÃO revogar) | **humana** | backend + admin |
| 3 | Gamificação B0: `occurred_at` + rejanelar ciclo por data-do-evento + normalizar backfill 11/07 + `ORDER BY protagonismo` | **humana** | backend + membro |
| 4 | Backend de transparência: `criterion_notes` no consolidado; unificar blind-review; expor decomposição por critério/pilar | baixa | backend/RPC |
| **5 (CAPSTONE UX/UI)** | **Feature nova de transparência que os membros pedem** (só DEPOIS das correções: expor número certo, não enfeitar número errado) | média | **membro + candidato** |

### Onda 5 — capstone de transparência (a feature que os membros pediram)
Racional: corrigir primeiro (Ondas 1-4), expor depois. Escopo proposto:
- **Gamificação "Minha pontuação, auditável":** painel por membro (e admin vendo qualquer membro) com CICLO vs VITALÍCIO
  claramente separados e rotulados; breakdown por pilar expansível até a linha de CADA fato (evento/atividade) com a
  DATA REAL, o ciclo a que pertence e os pontos; rótulo explícito "certificações contam vitalício"; export. Responde direto
  ao "de onde vêm estes pontos e em qual ciclo" (o caso Jefferson). Depende do B0 (`occurred_at`) estar aplicado.
- **Seleção decomposta por critério:** visão consolidada critério x avaliador COM `criterion_notes` (racional), respeitando
  blind-review; e a visão do próprio candidato com seu breakdown por critério pós-decisão. Depende de A1/A3 + Onda 4.
- Princípio de credibilidade: a superfície de transparência só sobe quando os números por trás estão corrigidos e estáveis.

## Issues/PRs propostos (por severidade)

| # | Achado | Sev | Ação |
|---|--------|-----|------|
| 1 | A1 ranks stale (13 researchers + 3 líderes somem; Francisco #39 vs #7) | ALTA | PR: recompute-on-score-change + rodar `recalculate_cycle_rankings` agora |
| 2 | A2 `research_score` sem trava min_evaluators (17 apps 1-avaliador, 2 aprovadas) | ALTA | PR: reescrever `compute_application_scores` (deriva de colunas PERT + gate min) |
| 3 | A3 corte inclui rejeitados + param morto + carimbo cross-role | MÉDIA | Decisão de política + PR conforme decisão |
| 4 | A2b contradição objective_rank vs banner persistido | MÉDIA | PR UI: alinhar/rotular o badge de rank |
| 5 | C-sel `criterion_notes` invisíveis no consolidado | BAIXA | PR: expor notas por critério na tela admin |
| 6 | C-blind regra de cegamento divergente | BAIXA | PR: unificar regra phase-gated |
| 7 | B1 desync latente pilares x leaderboard | BAIXA | PR: pilar legacy + contract test |
| 8 | B2 inativos no leaderboard interno | BAIXA | Decisão: filtrar ou manter (histórico) |

## Decisões para o owner
1. **Corte (A3):** referência = pool completo (130.9, atual) ou só ativos (142.7)? Muda a régua de todos.
2. **Fixes ALTA (1 e 2):** implementar agora nesta sessão?
3. **Gamificação:** qual é o sintoma concreto de "ainda errado"? A matemática do leaderboard/pilares está provada correta.

---

## Onda 1: APLICADA (2026-07-22, sessão main)

Migrations 475 (A2) e 476 (A1) aplicadas via `apply_migration` (byte-igual ao arquivo); phantoms removidos por versão exata; `migration repair --status applied 20260805000475 20260805000476`; `NOTIFY pgrst`. Backfill `compute_application_scores` sobre as 74 apps do Ciclo 4: 74 processadas, 0 erro. Antes/depois provado ao vivo (não recitado de memória):

| Métrica | Antes | Depois |
|---|---|---|
| research_score não-nulo (ciclo) | 71 | 54 |
| leader_score não-nulo | 11 | 9 |
| researchers ranqueáveis | 53 | 38 |
| apps de 1 avaliador ainda pontuadas | 17 | 0 |
| Francisco J. (rank pesquisador) | stored #39, vivo #7 | #7 |

- As 54 apps de 2+ avaliadores ficaram byte-idênticas: fingerprint md5 do conjunto {research, leader, final} inalterado (`72283da9b5088a6d7d4a21eb01f822ea` antes e depois). Zero divergência colateral.
- 17 nulados = 3 researchers approved (Priscila O. 239, Nícolas R. 218, Rogerio P. 170) + 2 líderes submitted (216.80 e 108.50 para NULL) + 12 researchers pré-final. Os 3 approved mantêm status `approved` (nular score não revoga aprovação); saem do ranking por terem 1 único avaliador objetivo, que é a regra min-2 restaurada. Divergência vs. o plano documentado: eram 3 approved, não 2.
- Verificação adversarial pré-apply (3 lentes independentes: fórmula A2, paridade de rank A1 vs. `recalculate_cycle_rankings`, segurança/cascata): 0 blocking issues. Backfill sem side-effect outward-facing (candidato vê rank por pull); `_trg_recompute_final_score_pert` grava só colunas `final_score_pert_*`, então não clobbera o corte objetivo 130.89 que a Onda 2 usa.
- Onda 2 (mig 477, corte active-only retroativo) segue por último e é decisão humana.
