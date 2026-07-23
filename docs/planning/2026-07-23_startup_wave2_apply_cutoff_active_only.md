# Prompt de arranque - SESSÃO LIMPA: Onda 2 (corte active-only retroativo A3) + merge

> Cole o bloco abaixo como PRIMEIRA mensagem de uma sessão nova/limpa.
> **Modelo:** Opus 4.8 (não pinar). **Effort:** `/effort xhigh`. Sessão de EXECUÇÃO (aplica + mergeia à main).
> Antes de agir: ler MEMORY.md + [[project-scoring-merit-audit-2026-07-21]], `git fetch`, e RE-ATERRAR todo número ao vivo.

---

Sessão de execução no ai-pm-research-hub - **Onda 2** do roadmap de pontuação/mérito
(relatório: `docs/audit/2026-07-21_scoring_merit_audit.md`). **Rodar em Opus 4.8 + xhigh.**
Onda 1 (A1/A2 + invariante M) já está MERGEADA (main `387f20d3`, #1461+#1462). Onda 2 estava serial-depois; agora desbloqueada.

## Contexto travado (NÃO re-litigar; decisão do owner na auditoria de 2026-07-21)
- Ciclo 4 = `cycle4-2026` (`08c1e301-9f7b-4d01-a13c-43ac7775c0f7`), open/evaluating.
- **A3:** `_compute_pert_cutoff_core` aceita `p_filter_active_only` e NUNCA o usa (só loga `filter_active_only_legacy_arg`). O cohort do corte objetivo inclui já-rejeitados.
- **Decisão do owner: corte active-only RETROATIVO.** Sobe a régua de todos. Ciente de que há aprovados entre a régua antiga e a nova; **NÃO revogar aprovação** de ninguém, **tratar o DISPLAY** dos que ficam abaixo da banda elevada.
- PR draft **#1467** (branch `fix/selection-cutoff-active-only`) carrega a migration `20260805000477_audit_A3_cutoff_active_only_filter.sql`, NÃO aplicada.

## Números re-aterrados 2026-07-22 (pós-Onda 1; RE-ATERRAR DE NOVO antes de aplicar)
- Corte objetivo armazenado: **130.89** (`dynamic`, cohort n=**45** researchers com `objective_score_avg` não-nulo).
- Active-only (excluindo rejeitados/terminais): **142.69** (n=**38**; exclui 7).
- Onda 1 NÃO mexeu nesses números (o backfill de Onda 1 escreveu régua `final_score_pert`, não o corte objetivo `pert_target_score`).

## Mandato desta sessão (Onda 2)
1. **Re-aterrar ANTES (obrigatório):** re-rodar ao vivo corte armazenado (esperado 130.89), active-only (esperado 142.69), cohort n=45→38, e a lista NOMINAL dos aprovados com `objective_score_avg` entre 130.89 e 142.69 (os que "caem" com a régua nova). Capturar o "antes".
2. **Renumerar a migration (recomendado):** 477 < 478 da Onda 1 (fica out-of-order no histórico). A 477 NÃO está aplicada; renomear o arquivo para a próxima versão livre (`SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 1` → next). OU manter 477 (funciona, só não é monotônico). Decidir e ajustar referências internas do arquivo.
3. **Basear no corpo VIVO:** a 477 é CREATE OR REPLACE de `_compute_pert_cutoff_core`. Antes de aplicar, `pg_get_functiondef` do corpo VIVO (Onda 1 NÃO alterou essa função, mas confirme) e garanta que a 477 só muda o ramo do `p_filter_active_only` (ver [[reference-create-or-replace-base-on-live-body]]). Aplicar byte-fiel + provar por md5 normalizado live==arquivo (ver [[reference-apply-large-function-mcp-inline-md5-verify]]).
4. **Aplicar + registrar:** `apply_migration` via MCP; deletar phantom por versão EXATA; `migration repair --status applied <versão>`; `NOTIFY pgrst`.
5. **Recompute do corte (o que muda a régua):** recomputar SÓ o corte objetivo active-only: `SELECT public._compute_pert_cutoff_core('08c1e301-...','researcher', TRUE, 'objective_score_avg', <actor>);`. **NÃO rodar `compute_application_scores` em massa** - isso re-dispararia a cascata da régua `final_score_pert` histórica que a Onda 1 limpou (ver [[reference-full-cycle-backfill-final-score-regua-side-effect]]).
6. **Tratar cross-role (A3 parte 2):** o UPDATE do corte grava `pert_target_score` em TODAS as linhas do ciclo (inclusive líderes), e `get_cutoff_dispatch_health` compara sem filtro de role. Verificar se a 477 já corrige; senão, tratar (corte objetivo é researcher-only).
7. **DISPLAY dos aprovados abaixo da banda elevada:** decidir com o owner como exibir os aprovados que ficam abaixo de 142.69 (badge/nota "aprovado antes da revisão de régua", NÃO revogar). É a parte sensível - **checkpoint humano**.
8. **Re-aterrar DEPOIS:** corte armazenado 130.89→142.69, banda nova, quem mudou de posição na banda.
9. **`npx astro build` + `npm test`** (com SUPABASE_URL + SERVICE_ROLE_KEY → DB-aware). 0 fail. Atenção: `p273-365e-current-cycle-pert-cohort` e `p274-365f-pert-band-thresholds` provavelmente checam a régua - podem exigir ajuste de baseline pós-corte.
10. **Merge do PR #1467 à main** (sessão main; pode mergear). Fecha #1463.
11. Atualizar [[project-scoring-merit-audit-2026-07-21]] + MEMORY.md com o antes→depois vivo (Onda 2 fechada) e o LL em #588.

## Regras da casa (não esquecer)
- Números em prompt/PR/commit/memória = de tool result DESTA sessão; nunca recitar de memória.
- Sem em-dash em entregáveis. Trailer `Assisted-By: Claude (Anthropic)`, nunca `Co-Authored-By`.
- DDL só via `apply_migration` (não `execute_sql`). Deletar phantom por versão exata.
- Grounding adversarial antes de mutação irreversível em prod (workflow 3-lentes valeu na Onda 1).
- Higiene: branch local morto `fix/scoring-merit-audit` pode ser deletado (`git branch -D`; não-pushado, redundante).

## Ondas seguintes (depois da 2)
3=B0 gamificação (`occurred_at`, rejanelar ciclo por data-do-fato) → [[reference-gamification-cycle-windowed-by-createdat-trap]]; 4=backend transparência (criterion_notes + blind-review unificado); 5=CAPSTONE UX #1465.
