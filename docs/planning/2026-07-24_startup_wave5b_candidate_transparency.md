# Brief de arranque — Onda 5b (candidato pós-decisão: breakdown do aprovado, "não selecionado" do rejeitado)

> **Sub-onda 5b do arco de auditoria pontuação/mérito (umbrella #1465).** A **5a fechou + mergeou** (#1473,
> main `5172e964`). Esta é a segunda e ÚLTIMA sub-onda. **Materialidade MAIOR que a 5a: outward-facing** (candidato =
> aplicante externo), envolve o que um **rejeitado** vê → superfície sensível. Modelo Opus 4.8 (não pinar), `/effort xhigh`.
> **NÃO é LOCKED nos detalhes de UX:** abre com uma rodada curta de decisões do owner + `legal-counsel` ANTES de construir.

---

## HANDOFF — estado ao fechar a 5a (2026-07-22)

**Arco 1–4 + 5a FECHADOS + MERGEADOS.** Detalhe vivo → memória `project-scoring-merit-audit-2026-07-21`.

- **5a** (#1473 `5172e964`, PR#1475, mig **482**): painel "Minha Pontuação, auditável" (`/minha-pontuacao`). Helper interno
  `_points_statement_json` + `get_my_points_statement` (self) + `get_member_points_ledger` (admin `?member=`). Deploy worker
  `b0fb51bb`. Follow-up **#1478** (unificar janela/org de `get_member_cycle_xp.cycle_points` vs ledger) — independente, não bloqueia.
- **Migration head (ao vivo 2026-07-22): `20260805000482`** → próxima livre provável `20260805000483` (re-consultar ao vivo).
- **Umbrella #1465 ABERTO** (`Refs`, não `Closes`) — fechar À MÃO quando a 5b mergear (5a já mergeada).

---

## O QUE A 5b ENTREGA (Parte B do relatório `docs/audit/2026-07-21_scoring_merit_audit.md`)

O **comitê** já tem a matriz critério×avaliador com `criterion_notes` (Onda 4). Falta a **visão do próprio candidato** pós-decisão:

- **Candidato APROVADO** vê **seu próprio breakdown por critério** (scores agregados próprios — PERT objetivo / entrevista / líder)
  + posição vs banda de corte + rank. NUNCA `criterion_notes`, notas ou nomes de avaliadores (LOCKED Onda 4).
- **Candidato REJEITADO** vê **SÓ "não selecionado"** — sem breakdown NUMÉRICO novo.

---

## GROUNDING VIVO (2026-07-22, re-aterrar no início da sessão — NÃO recitar destes números)

**Ciclos de seleção** (tabela `selection_cycles`, com `phase` própria — distinta dos `cycles` de gamificação):
- `cycle3-2026` = **fase `announcement` (DECIDIDO/fechado)** → coorte de QA: **34 approved + 2 converted + 35 rejected**. Ideal
  para QA por impersonação (tem os DOIS lados decididos). `cycle3-2026-b2`: 1 approved + 8 rejected + 1 withdrawn.
- `cycle4-2026` = **fase `evaluating` (ABERTO)** → o gate de fase da 5b **NÃO** deve renderizar breakdown aqui até virar `announcement`.

**RPCs de candidato que JÁ existem (todos self-only via `auth.uid()`, sem args):**
- `get_my_selection_result()` — ⚠️ **JÁ retorna `objective_score`/`interview_score`/`research_score`/`leader_score` + `rank`
  (RANK() ao vivo) para TODOS os status finais, INCLUINDO `rejected`** (`is_final` = approved/converted/rejected/objective_cutoff/
  withdrawn/cancelled). **Este é o ponto #1 da sessão** (ver abaixo).
- `get_my_evaluation_feedback()` — revela scores + `feedback` qualitativo gateado por **FASE** (`evaluations_closed`, `interviews`,
  `interviews_closed`, `ranking`, `announcement`, `onboarding`). Pré-existente — a decisão "só não selecionado" é sobre o breakdown
  NUMÉRICO NOVO, **não** sobre este feedback qualitativo pré-existente. **Não regredir.**
- `get_my_application_status()` — status/phase/`submitted_eval` count durante `evaluating` (sem identidades).
- Página do candidato: `src/pages/minha-candidatura.astro`.

---

## ⚠️ PONTO #1 DA SESSÃO — auditar ANTES de desenhar (potencial conflito com a decisão LOCKED)

`get_my_selection_result()` **já devolve scores numéricos + rank para candidatos `rejected`**. A decisão LOCKED é "rejeitado vê só
'não selecionado'". Logo, a PRIMEIRA tarefa é **auditar o que `minha-candidatura.astro` RENDERIZA hoje** para um rejeitado (via
impersonação de um `rejected` do `cycle3-2026`):
- Se o front **já esconde** scores/rank do rejeitado (só o RPC devolve, mas a UI não mostra) → a 5b só precisa garantir que o
  breakdown por-critério NOVO também respeite isso.
- Se o front **mostra** scores/rank ao rejeitado hoje → há uma exposição pré-existente que a 5b deve reconciliar com a decisão do
  owner (é regressão de política ou estado atual aceito? decidir com o owner + `legal-counsel`; não assumir).

Não construir nada antes de responder isso com evidência ao vivo.

---

## DECISÕES DO OWNER — já ratificadas (não re-litigar), CONFIRMAR só o timing

1. **Split SIM** (feito): 5a interna (mergeada), 5b outward-facing (esta). PR + merge serial próprios.
2. **Aprovado vê breakdown por critério próprio; REJEITADO vê só "não selecionado".** Candidato NUNCA vê criterion_notes/notas/
   nomes de avaliadores (LOCKED Onda 4). A restrição "só não selecionado" é sobre o breakdown NUMÉRICO NOVO.
3. **Timing (CONFIRMAR no início):** recomendação ratificada = **buildar AGORA, gated por fase** (só renderiza pós-decisão =
   `announcement`), com **QA contra apps decididas do `cycle3-2026` (fechado)** via impersonação. Racional: desacopla eng do
   calendário; feature pronta+testada antes da pressão do C4. Se o owner preferir aguardar o C4 fechar, adiar só a 5b. **Bater com
   o owner antes de construir.**
4. **i18n real** pt/en/es se criar rota nova (≠ do admin `selection.astro`, PT-hardcoded). Toda chave nova nas 3 dicts.

---

## MANDATO DA SESSÃO

1. **Re-aterrar ao vivo ANTES:** migration head; corpos VIVOS (`pg_get_functiondef`) de `get_my_selection_result` /
   `get_my_evaluation_feedback` / `get_my_application_status`; fase de cada `selection_cycles`; **e o PONTO #1** (auditar
   `minha-candidatura.astro` + impersonar um `rejected` do cycle3-2026). Nenhum número recitado.
2. **Rodada de decisões do owner** (`AskUserQuestion`) + convocar **`legal-counsel`** (1 agente — o que o rejeitado vê é decisão
   de política/LGPD) e **`ux-leader`** (1 agente — journey candidato pós-decisão). NÃO o conselho inteiro.
3. **Construir conforme a decisão:** a visão do aprovado = seus próprios scores agregados por critério (PERT objetivo/entrevista/
   líder) + posição vs banda de corte + rank. Se precisar de RPC/coluna nova: **DDL só via `apply_migration`**, corpo **byte-fiel
   ao arquivo** (ou alinhar o arquivo ao vivo depois — ver gotcha), REVOKE/GRANT corretos, phantom tracking-row por NOME/statement
   (não por range), `migration repair`, `NOTIFY pgrst`, `npm run db:types` se assinatura nova.
4. **Grounding adversarial (multi-lente)** antes de shippar: (a) candidato NUNCA vê criterion_notes/nomes/notas de terceiros;
   (b) rejeitado NÃO vê breakdown numérico novo (nem via RPC nem via UI); (c) gate de fase impede render antes de `announcement`;
   (d) números do candidato batem com os RPCs corrigidos (Ondas 1–2). QA por impersonação contra `cycle3-2026` (34 apr/35 rej).
5. **`npx astro build` + `npm test`** (com `SUPABASE_URL`+`SERVICE_ROLE_KEY` → DB-aware). 0 fail. Teste novo nas **2 whitelists**
   (`test` + `test:contracts` no package.json).
6. **Aplicar + merge à main** (sessão main pode mergear). Fecha **#1474**; o umbrella **#1465 fecha À MÃO** (5a já mergeada → ao
   mergear a 5b, fechar #1465 manualmente). Deploy frontend (`npx astro build && npx wrangler deploy`).
7. Atualizar `project-scoring-merit-audit-2026-07-21` + `MEMORY.md` (**ARCO DE AUDITORIA COMPLETO 1–5**).

---

## REGRAS DA CASA + GOTCHAS (herdados da 5a)

- Números em prompt/PR/commit/memória = de tool result DESTA sessão; nunca recitar.
- Sem em-dash (—/–) em entregáveis (inclui strings i18n user-facing e fallbacks no script). Trailer `Assisted-By: Claude
  (Anthropic)`, nunca `Co-Authored-By`.
- **GOTCHA Phase C (novo na 5a):** ao aplicar DDL, se você RE-DIGITAR o SQL no `apply_migration` (em vez de colar byte-fiel do
  arquivo) e enxugar comentários inline, o corpo vivo `prosrc` diverge do arquivo → `rpc-migration-coverage` Phase C fica VERMELHO.
  Corpo vivo é o SSOT: ou cole byte-fiel, ou alinhe o ARQUIVO ao vivo (`pg_get_functiondef`) depois. → memórias
  `reference-apply-large-function-mcp-inline-md5-verify`, `reference-create-or-replace-base-on-live-body`.
- **GOTCHA phantom (Onda 4/5a):** `apply_migration` MCP cria tracking-row com **timestamp REAL de hoje** (ex. `20260723004115`),
  não da série sintética `20260805…`. Procurar por NOME/statement (ou `version NOT LIKE '20260805%'`), deletar por versão EXATA;
  registrar a sintética com `migration repair`.
- Testes DB-aware rodam SERIAL (`--test-concurrency=1`) contra a prod compartilhada; `tx=rollback` NÃO desfaz INSERT de SECDEF
  (limpar explícito). Novo teste nas 2 whitelists senão nem roda no CI.
- **Flake conhecido já corrigido na 5a:** `tests/contracts/p277-419-m3-pr3a-tribe-stats-engagement.test.mjs` (tribo14 rounding
  Postgres numeric ROUND vs JS Math.round) agora tem tolerância de 1 unidade de arredondamento. Se reaparecer em outro teste de
  taxa (%), é a mesma classe (exact-equality de float entre banco e JS), não regressão.
- `get_member_points_ledger`/`get_my_points_statement` (5a) são o padrão de referência para RPC self vs admin-gated com helper
  interno compartilhado — reusar o padrão se a 5b precisar de leitura admin.
