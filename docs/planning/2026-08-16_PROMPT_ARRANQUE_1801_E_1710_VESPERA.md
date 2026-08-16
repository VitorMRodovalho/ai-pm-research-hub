# Prompt de arranque — a triagem do #1801, a véspera do #1710 e o resto do #1780

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-15_handoff_1797_mergeada_e_1572_com_o_ciclo_certo.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **15/08/2026** e vários se
movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit,
numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** Custou de novo em 15/08: `gh api
  dependabot/alerts` **sem `--paginate`** devolveu **0 abertos** quando havia **3**. A primeira
  página não é a coleção.
- **`gh pr checks` cresce durante a espera.** Foi de 10 → 11 → **12** linhas nesta sessão: o
  `quality_gate` chega por último, e o `check-advisors` só aparece em PR que toca SQL. Espere os
  pendentes; não conte linhas.
- **Ausência de par só é conclusiva se o carimbo cobre a janela inteira.**
- **Varra `pg_proc`, não o repositório** — e conte quantas funções têm o nome antes de confiar nele.
- **Conte pelo predicado INTEIRO da policy, não pela capacidade que a issue nomeia.**
- **Um guard verde fala de UM eixo.** Pergunte de que direção o verde está falando.
- 🆕 **`created_at` não é a data do fato, é a data da LINHA.** Um backfill histórico torna o registro
  antigo o mais novo da tabela. Qualquer `ORDER BY created_at DESC LIMIT 1` que signifique "o atual"
  é suspeito até prova em contrário.
- 🆕 **Leitura que volta vazia sob impersonação pode ser RLS, não ausência.** `RESET ROLE` antes de
  conferir o efeito de uma escrita, senão o veredito mede o papel, não o dado.

---

## Estado (16/08, madrugada)

`main` em **`961fc229`**. **Zero PRs abertas. Zero alertas Dependabot. Zero bypass na janela de 7
dias.** Worker em produção na versão `20339768`.

A sessão fechou **4 merges com zero bypass** e as issues **#1783** e **#1572**.

⚠️ **Re-medir a janela de bypass** antes de qualquer `--admin`. Não recitar.

---

## 🔎 ITEM 1 — #1801, a triagem que sobrou

Uma de 10 funções foi corrigida (`get_selection_health`). **Faltam 9**, e o trabalho é de leitura,
não de sweep.

`selection_cycles.created_at` é a data de **escrita da linha**. O backfill do `cycle2-2025` entrou em
2026-07-13 e virou a linha mais nova; o ciclo aberto é o `cycle4-2026`.

Candidatas medidas em 15/08 (ordenam por `created_at DESC` sem consultar `status`):
`compute_ai_calibration_weekly` · `get_diversity_dashboard` · `get_evaluator_calibration_stats` ·
`get_my_pending_evaluations` · `get_selection_cycles` · `get_selection_pipeline_metrics` ·
`get_selection_rankings` · `recompute_all_active_pert_cutoffs` ·
`_test_invariants_with_synthetic_breach`.

⚠️ **O critério é "esta função escolhe UM ciclo para chamar de ativo?", não "esta função cita
`created_at`".** `get_selection_cycles` **lista** ciclos e ordenar assim ali é legítimo. Ler o corpo
antes de mudar.

📌 **Referência de quem já faz certo:** `get_selection_dashboard`, `get_chapter_selection_summary`,
`get_affiliation_verification_queue` (usam `status = 'open'`), e o corpo do
`detect_stuck_selection_funnel`, que traz a nota da #1586(b).

📌 **O entregável que evita a terceira rodada:** um contract test ratchet que reprove resolução de
ciclo **ativo** por `created_at`, para a classe não voltar pela próxima função nova.

---

## ⏰ ITEM 2 — #1710, e o prazo é 24/08

Config **conferida no banco em 15/08**, não recitada:

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que
reproduz coorte + carência, e o ensaio da própria função — e só então levar o número ao PM.
⚠️ **É teto, e encolhe a cada presença registrada por um líder.**

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando
`grace_days` para dar o mesmo corte que 14 darão em 24/08, recuando também o `floor_date` (senão
volta `skipped: before_floor`), e terminando em `RAISE EXCEPTION` com o resultado. A exceção aborta o
bloco inteiro e o `UPDATE` volta sozinho. **Confira a config depois do ensaio.**

⚖️ **DECIDIDO pelo PM (15/08), NÃO re-litigar:** as células que nenhum líder de tribo alcança ficam
com o **GP, pela grade geral**. Nada muda no código.
📌 **Ação da véspera:** levar ao GP a lista **nominal** dessas células — **na conversa, não em issue
nem em PR** (repo público).

✅ **Já fechado, não re-investigar:** zero faltas ficariam sem superfície · `unseal_event_attendance`
**existe** · o selo grava **só `present=false`**, com `ON CONFLICT DO NOTHING`.

---

## ITEM 3 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist num predicado
  só; as outras seguem espalhadas.
- **8 verbos de curadoria sem porta MCP nenhuma** — um ciclo inteiro de trabalho só alcançável pela
  tela. **Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas seguem decidindo escrita só por capacidade, todas com **zero**
  linhas confidenciais hoje. O contrato falha se aparecer uma nova.
- **Linha de base do #1784:** 10 filhas de outros domínios seguem sem gate de leitura, idem.

---

## ITEM 4 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`, conferindo
  na linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'`.
  ⚠️ **Não despachar para testar.** Re-medir a idade dos despachos sem reserva antes de sugerir.
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até uma
  linha carimbar reserva. **Não provocar despacho** — o cron gera linhas sozinho. Exigir
  `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## ITEM 5 — o que o #1572 deixou explicitamente de fora

Não é dívida escondida, é escopo declarado. Reabrir só com decisão do PM:

- **Rejeição sem avaliação não é bloqueada**, só contada e exposta. Estender o portão muda o que o GP
  experimenta num ciclo aberto.
- **Duas RPCs de reconciliação movem status sem o portão**, por desenho:
  `recompute_application_status` e `reconcile_vep_terminal_status`. **O portão não é universal.**
- **9 aprovadas e 6 rejeitadas sem avaliação seguem no histórico**, sem carimbo — as 8 mais antigas
  do `cycle2-2025` sem trilha em log nenhum. Não há como justificá-las retroativamente sem inventar
  autoria.

---

## Depois desses

**#1777** (o fluxo que gravou o papel divergente; o dado já está normalizado), **#1776**, **#1664
fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do PM), **#1729**, **#1742**,
**#1744**, **#1728** (20 RPCs da mesma classe, sem detalhe na issue), **#1592** (barreira contra DDL
nova; números re-ancorados em 15/08: **468 de 1105** SECDEF alcançáveis por chamador anônimo).
**Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **`apply_migration` recebe o SQL como STRING.** Feche o risco comparando
   `md5(regexp_replace(prosrc,'\s+',' ','g'))` do corpo vivo com o do arquivo. O parser canônico é
   `tests/helpers/rpc-body-drift-parser.mjs` (`parseMigration` + `normalizeBody` + `md5`); o lado
   vivo é `_audit_list_public_function_bodies()`. Bateu 5 de 5 em 15/08.
2. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar, ou o gate ADR-0097 fica vermelho. Com UMA chamada, não há fantasma a apagar.
3. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs abertas**
   e mergeie antes de aplicar a próxima. Foi o que permitiu duas migrations em sequência nesta sessão.
4. **Mudança de schema exige `npm run db:types` na MESMA PR.**
5. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
   migration — inclusive quando a função é RECRIADA por mudança de assinatura, porque a nova nasce
   aberta mesmo que a antiga estivesse fechada.
6. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
7. **A versão da superfície semântica tem QUATRO pins em arquivos que não se conhecem.**
8. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
9. **Suíte offline (~53 s) é o gate barato:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` antes de acreditar no guard (`set -a;
   source ./.env; set +a`) e confira que ele reporta **zero skips**. Confira `gh run list` antes: o
   `validate` com DB não tolera execução concorrente (#1505).
10. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E o espelho: **nunca escrever
    `close #N` sem intenção de fechar, nem para CITAR o padrão.**
11. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
12. ⚠️ **`supabase` CLI aqui não está linkado:** `--project-ref ldrfrvwhxsmgaabwmaik`.
13. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
14. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de
    pessoa não entra em issue, PR nem doc — conte a população, não a pessoa.
15. ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para
    `service_role`.** Derive do catálogo (`_audit_function_source`) ou impersone em transação
    abortada. **Ordem:** `set_config('request.jwt.claims', ...)` **antes** do `SET LOCAL ROLE`.
16. ⚠️ **`pg_get_function_identity_arguments` devolve nome E tipo** (`p_board_id uuid, ...`).
17. ⚠️ **NUNCA canalize a suíte por `| tail -N` rodando em background.** O pipe segura TODA a saída
    até o fim. Redirecione para arquivo (`> log 2>&1`).
18. ⚠️ **Para distinguir suíte LENTA de suíte TRAVADA, amostre os processos FILHOS** (`pgrep -P
    <pid>`): o pai fica em `ep_poll` com 0% de CPU nos dois casos.
19. ⚠️ **Um contract test que faz shell-out de lint pode TRAVAR em vez de falhar.** Rode os lints
    **separadamente ANTES** da suíte (`npm run lint:client-scripts`, ~20 s).
20. ⚠️ **O build para no primeiro erro e mente sobre o tamanho do estrago.** Rode o compilador sobre
    `git ls-files '*.astro'` de uma vez em vez de iterar build-corrige-build.
21. ⚠️ **Antes de propor "subir o pai" para um transitivo sem patch, leia a FAIXA que o pai declara**
    (`npm view <pai>@<nova> dependencies`). Pin exato (sem `^`) não alcança a versão nova do filho.
22. 🆕 ⚠️ **`pkill -f "<padrão>"` casa com a PRÓPRIA linha de comando do shell que o executa** e mata
    a si mesmo. Monte o padrão quebrado em duas partes, ou filtre `$$`.
23. 🆕 ⚠️ **Editar arquivos-fonte no meio de uma suíte em andamento invalida o resultado**, porque os
    testes que leem do disco leem o estado novo. Mate e rode de novo contra a árvore final, em vez de
    reportar um verde de entradas misturadas.
24. 🆕 ⚠️ **A UI não deve reimplementar a regra da RPC.** A linha do dashboard de seleção só carrega
    `peer_eval_count` (avaliação `objective`); o portão do #1572 conta **qualquer tipo**. Recalcular
    no cliente esconderia o campo justamente na candidatura que o servidor vai recusar.
