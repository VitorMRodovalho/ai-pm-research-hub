# Prompt de arranque - SESSÃO LIMPA: Onda 4 (backend de transparência por critério)

> Cole o bloco abaixo como PRIMEIRA mensagem de uma sessão nova/limpa.
> **Modelo:** Opus 4.8 (não pinar). **Effort:** `/effort xhigh`. Sessão de EXECUÇÃO (aplica + mergeia à main).
> Antes de agir: ler MEMORY.md + [[project-scoring-merit-audit-2026-07-21]], `git fetch`, e RE-ATERRAR todo número ao vivo.

---

Sessão de execução no ai-pm-research-hub - **Onda 4** do roadmap de pontuação/mérito
(relatório: `docs/audit/2026-07-21_scoring_merit_audit.md`, seções C-sel + C-blind). **Rodar em Opus 4.8 + xhigh.**
Ondas 1 (main `387f20d3`), 2 (`5758eaa3`) e 3 (`b5c7eaa2`, #1464 gamificação occurred_at) já MERGEADAS. Onda 4 = **backend de transparência por critério** (materialidade BAIXA; dois fixes de RPC + render).

## Contexto travado (achados provados ao vivo; re-aterrar antes de aplicar)
- **C-sel (BAIXA):** existe decomposição critério×avaliador (`get_evaluation_results`, renderizado em `selection.astro:4078`:
  matriz + subtotal ponderado + alertas de calibração). MAS as `criterion_notes` (racional qualitativo por critério) **não
  aparecem** no consolidado admin. Ao vivo 2026-07-22: **78 avaliações com criterion_notes preenchidas no Ciclo 4** (de 194
  evals / 71 apps). Coluna = `selection_evaluations.criterion_notes` (jsonb). Só aparecem (a) no form travado do próprio
  avaliador, (b) via MCP `get_application_score_breakdown` (`returns_criterion_notes=true`) que NENHUM `.astro` chama.
  Um curador reconciliando score divergente não lê a justificativa no app web.
- **C-blind (BAIXA, latente):** as duas superfícies DISCORDAM sobre quando desanonimizar. Confirmado ao vivo:
  `get_evaluation_results` desanonimiza co-avaliador ao atingir `min_evaluators` (checks_min_evaluators=true); 54/74 apps já
  em 2+ no C4. `get_application_score_breakdown` cega não-superadmins por FASE (evaluating/interviews). A promessa de revisão
  cega fica inconsistente. Latente hoje (nenhum usuário alcança as duas superfícies no estado cego), mas é dívida.

## Mandato desta sessão (Onda 4)
1. **Re-aterrar ANTES:** re-rodar a contagem de criterion_notes do ciclo corrente, os corpos VIVOS de `get_evaluation_results`
   e `get_application_score_breakdown` (`pg_get_functiondef`), e as duas lógicas de cegamento (min_evaluators vs phase).
2. **C-sel fix:** incluir `criterion_notes` no retorno de `get_evaluation_results` (por critério×avaliador, respeitando o
   cegamento vigente da própria função) E renderizar no consolidado (`selection.astro` ~4078). i18n pt/en/es se houver rótulo novo.
   Base = corpo VIVO; byte-fiel md5 live==arquivo. DDL via `apply_migration`; deletar phantom por versão exata; migration repair.
3. **C-blind fix (DECISÃO DO OWNER JÁ RATIFICADA — ver seção abaixo; NÃO re-perguntar):** unificar a regra de
   desanonimização nas DUAS funções conforme a regra do owner — **candidato NUNCA vê; comitê vê; revelar co-avaliador
   ao comitê APÓS o peer review (cego DURANTE, enquanto os avaliadores ainda submetem; revela quando o peer review
   termina = min_evaluators atingido para a app). Aplicar a MESMA regra em ambas.** Preservar autoridade existente
   (superadmin/manage_platform enxerga tudo). NENHUMA superfície de candidato é criada nesta onda.
4. **Grounding adversarial** (workflow 3-lentes) antes de aplicar: (a) o cegamento não vaza PII de co-avaliador na fase cega;
   (b) o render de criterion_notes não expõe nota fora do escopo de quem pode ver; (c) completude — as duas funções ficam
   consistentes e nenhuma outra superfície (MCP, outras .astro) diverge.
5. **`npx astro build` + `npm test`** (com SUPABASE_URL + SERVICE_ROLE_KEY → DB-aware). 0 fail. Registrar teste novo nas 2 whitelists.
6. **Aplicar + merge à main** (sessão main; pode mergear). Fecha as issues de transparência (C-sel/C-blind — criar se não existirem).
7. **Deploy do frontend** (`npx astro build && npx wrangler deploy`) — o consolidado admin é server-rendered; a nota só aparece pós-deploy.
8. Atualizar [[project-scoring-merit-audit-2026-07-21]] + MEMORY.md (Onda 4 fechada) + **PRÓXIMA = Onda 5 (CAPSTONE UX #1465)**.

## DECISÃO DO OWNER — RATIFICADA 2026-07-22 (LOCKED; não re-perguntar, não re-litigar)
Regra de cegamento unificada (palavras do owner: "o candidato não pode ter acesso, o comitê tem que ter acesso, após o peer review"):
- **Candidato: NUNCA tem acesso** a criterion_notes, notas ou nomes de avaliadores. (Já é verdade hoje — ambas as RPCs são
  gated por autoridade de comitê/admin; NÃO criar nenhuma superfície de candidato nesta onda.)
- **Comitê: TEM acesso.** Vê a matriz, as justificativas (C-sel) e, após o peer review, os nomes/scores dos co-avaliadores.
- **Revelar co-avaliador ao comitê APÓS o peer review:** cego enquanto o peer review acontece (avaliadores ainda submetendo);
  revela quando o peer review termina. Mapear "peer review terminou" = **`min_evaluators` atingido** para a application
  (é o sinal natural de "os pares já avaliaram"). Aplicar essa MESMA regra nas duas funções (`get_evaluation_results` já
  faz ~isso por min_evaluators; alinhar `get_application_score_breakdown`, que hoje cega por fase, ao mesmo gatilho).
  Se ao re-aterrar houver ambiguidade real entre "min_evaluators" e "fase de avaliação fechada", confirmar com o owner
  qual sinal — mas o candidato NUNCA vê em nenhum caso.

## Regras da casa (não esquecer)
- Números em prompt/PR/commit/memória = de tool result DESTA sessão; nunca recitar de memória.
- Sem em-dash (—) em entregáveis. Trailer `Assisted-By: Claude (Anthropic)`, nunca `Co-Authored-By`.
- DDL só via `apply_migration`; db-push BLOQUEADO neste repo (tracking divergente) → aplicar por função inline + md5-verify.
- Head de migrations após Onda 3: **20260805000480**. Próxima livre = re-consultar ao vivo.
- Adicionar coluna/retorno pode quebrar `gen-types-drift` → `npm run db:types` + commit `src/lib/database.gen.ts` (CLI pin 2.109.0).
- Testes que fixam corpo canônico de função por md5 (p625/p599 e similares) → re-apontar para a migration nova se reescrever a função.
