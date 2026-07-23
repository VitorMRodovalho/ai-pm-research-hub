# Prompt de arranque — SESSÃO LIMPA: Onda 1 (aplicar A1+A2 seleção) + merge

> Cole o bloco abaixo como PRIMEIRA mensagem de uma sessão nova/limpa.
> **Modelo:** Opus 4.8 (não pinar). **Effort:** `/effort xhigh`. Esta é sessão de EXECUÇÃO (aplica + mergeia à main).
> Antes de agir: ler MEMORY.md + [[project-scoring-merit-audit-2026-07-21]], `git fetch`, e RE-ATERRAR todo número ao vivo.

---

Sessão de execução no ai-pm-research-hub — **Onda 1** do roadmap de correção de pontuação/mérito
(relatório: `docs/audit/2026-07-21_scoring_merit_audit.md`). **Rodar em Opus 4.8 + xhigh.**

## Contexto travado (NÃO re-litigar; provado na auditoria de 2026-07-21)
- Ciclo 4 = `cycle4-2026` (`08c1e301-9f7b-4d01-a13c-43ac7775c0f7`), open/evaluating.
- PR draft **#1466** (branch `fix/selection-scoring-rank-audit`) carrega as migrations, NÃO aplicadas:
  - `20260805000475` (A2, #1461): `compute_application_scores` deriva research_score de
    `objective_score_avg + interview_score` (PERT já min-gated). Nula 17 apps de 1-avaliador.
  - `20260805000476` (A1, #1462): `get_selection_rankings` + `get_my_selection_result` rank em tempo de leitura.
- Onda 2 (corte active-only, PR #1467) e B0 (gamificação, #1464) são DEPOIS. Não tocar aqui.

## Mandato desta sessão (Onda 1)
1. **Re-aterrar ANTES (grounding obrigatório):** re-rodar ao vivo e capturar o "antes":
   - `count(*) FILTER (research_score NOT NULL AND objective_score_avg NULL)` no ciclo (esperado ~17).
   - rank vivo vs armazenado do researcher (esperado: Francisco J. armazenado #39 / vivo #7; 13 NULL-stored).
2. **Aplicar as 2 migrations** (regras da casa, `.claude/rules/database.md`):
   - `apply_migration` (byte-igual ao arquivo) para 475 e depois 476.
   - Cada apply via MCP cria PHANTOM tracking-row com versão de DATA REAL (`202607*`), que ordena ANTES do
     sintético `202608*` — deletar por versão EXATA (`version IN (...)`, sem LIKE curto). Ver
     [[feedback-apply-migration-creates-tracking-row]].
   - `migration repair --status applied 20260805000475` e `...476`.
   - `NOTIFY pgrst, 'reload schema'` (mudou assinatura/surface de RPC).
3. **Backfill de dado (o que muda ranks):**
   `SELECT public.compute_application_scores(id) FROM public.selection_applications WHERE cycle_id='08c1e301-9f7b-4d01-a13c-43ac7775c0f7';`
   Isso nula os 17 e recomputa research/leader/final com a nova regra.
4. **Re-aterrar DEPOIS (antes→depois ao vivo):**
   - os 17 viraram research_score NULL (e saíram do ranking).
   - `get_selection_rankings` agora inclui os 13+3 antes ocultos e Francisco J. aparece ~#7.
   - conferir que nenhuma app de 2+ avaliadores mudou de score (divergência deve ser 0).
5. **`npx astro build` + `npm test`** (com SUPABASE_URL + SERVICE_ROLE_KEY → roda os DB-aware). 0 fail.
   - Não pinar baseline; a fonte é rodar o comando.
6. **Merge do PR #1466 à main** (é sessão main; pode mergear). Fecha #1461 + #1462.
7. Atualizar [[project-scoring-merit-audit-2026-07-21]] com o antes→depois vivo e o estado (Onda 1 fechada).

## Regras da casa (não esquecer)
- Números em prompt/PR/commit/memória = de tool result DESTA sessão; nunca recitar de memória.
- Sem em-dash em entregáveis. Trailer `Assisted-By: Claude (Anthropic)`, nunca `Co-Authored-By`.
- DDL só via `apply_migration` (não `execute_sql`). Deletar phantom por versão exata.
- Onda 2 (#1467 corte retroativo) só DEPOIS desta mergeada (serial por drift-gate) e é decisão sensível (7 aprovados).
