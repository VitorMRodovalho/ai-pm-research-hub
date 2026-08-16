# Prompt de arranque — a véspera do #1710, o #1805 e o resto do #1780

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-16_handoff_1801_classe_fechada_com_ratchet.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **16/08/2026** e vários se
movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit,
numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** `gh api dependabot/alerts` **sem
  `--paginate`** já devolveu 0 abertos havendo 3.
- **`gh pr checks` cresce durante a espera** (chegou a 12 nesta sessão). Espere os pendentes; não
  conte linhas.
- **Varra `pg_proc`, não o repositório** — e leia o corpo antes de confiar na varredura.
- 🆕 **A lista da issue não é a classe.** A #1801 listava 10 funções; o catálogo tinha 12, e as duas
  que faltavam eram o defeito mais interessante. Derive do catálogo.
- 🆕 **Varredura por literal de coluna não diz de QUAL tabela é a coluna.** `status = '...'` em
  funções que citam `selection_cycles` devolveu **35** resultados, quase todos de
  `selection_applications`. Quando o alias importa, regex sobre `prosrc` não é medição.
- 🆕 **`created_at` não é a data do fato, é a data da LINHA.** Fechado como classe pelo ratchet do
  #1801, mas o raciocínio vale para qualquer tabela com backfill.

---

## Estado (16/08)

`main` em **`2d2902f6`**. **Zero PRs abertas. Zero alertas Dependabot. Zero bypass na janela de 7
dias.** A sessão fechou **#1801** (1 merge, 12/12) e abriu **#1805**.

⚠️ **Re-medir a janela de bypass** antes de qualquer `--admin`. Não recitar.

---

## ⏰ ITEM 1 — #1710, e o prazo é 24/08. É o item de maior risco de data.

Config **conferida no banco em 15/08** (re-conferir):

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que
reproduz coorte + carência, e o ensaio da própria função — e só então levar o número ao PM.
⚠️ **É TETO, e encolhe a cada presença registrada por um líder.** A última medição (15/08) deu
**43 selam, 80 faltas, 40 pessoas**; os dois caminhos bateram. **Não recitar isso — re-medir.**

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando
`grace_days` para dar o mesmo corte que 14 darão em 24/08, **recuando também o `floor_date`** (senão
volta `skipped: before_floor`), e terminando em `RAISE EXCEPTION` com o resultado. A exceção aborta o
bloco e o `UPDATE` volta sozinho. **Confira a config depois do ensaio.**

⚖️ **DECIDIDO pelo PM (15/08), NÃO re-litigar:** as células que nenhum líder de tribo alcança ficam
com o **GP, pela grade geral**. Nada muda no código.
📌 **Ação da véspera:** levar ao GP a lista **nominal** dessas células — **na conversa, não em issue
nem em PR** (repo público).

✅ **Já fechado, não re-investigar:** zero faltas ficariam sem superfície · `unseal_event_attendance`
**existe** · o selo grava **só `present=false`**, com `ON CONFLICT DO NOTHING`.

---

## 🔎 ITEM 2 — #1805, o literal de estado que nunca casa

Aberta nesta sessão, com os três casos **lidos no corpo** (não inferidos). Domínios do catálogo:

```
status: draft, open, evaluation, interview, decision, closed
phase:  planning, applications_open, screening, evaluating, evaluations_closed,
        interviews_scheduling, interviews, interviews_closed, ranking, announcement, onboarding
```

- **`recompute_all_active_pert_cutoffs`** (cron): `phase IN ('evaluating','interviews','open_apps')`
  — **`open_apps` não existe** (é `applications_open`). Ciclo com inscrições abertas nunca tem corte
  PERT recalculado. **Comece por este: é defeito real, com efeito em cron, e a correção é um
  literal.**
- **`compute_ai_calibration_weekly`** (cron): `status IN ('open','evaluating','decided','closed')` —
  dois literais são de `phase`; 4 estados do domínio nunca casam. Latente hoje.
- **`selection_consistency_report`**: `'active'` é literal morto.

⚠️ **A classe NÃO está varrida, e a forma que falhou está registrada na issue.** Varredura honesta
precisa resolver o alias por consulta, ou virar invariante em SQL comparando literal contra o CHECK
da coluna certa.

---

## ITEM 3 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist; as outras
  seguem espalhadas.
- **8 verbos de curadoria sem porta MCP nenhuma. Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas decidem escrita só por capacidade, todas com zero linhas
  confidenciais hoje. **Do #1784:** 10 filhas de outros domínios sem gate de leitura, idem.

---

## ITEM 4 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`, conferindo
  na linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'` (cap 3, separado do cap
  1 do cron). ⚠️ **Não despachar para testar.**
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até
  uma linha carimbar reserva. **Não provocar despacho** — o cron gera linhas sozinho. Exigir
  `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## ITEM 5 — dívida conhecida, com dono

- **#1592** — barreira contra DDL nova. Números re-ancorados em 15/08: **468 de 1105** SECDEF
  alcançáveis por chamador anônimo. Medido de passagem em 16/08 e ainda de pé:
  `get_my_pending_evaluations`, `get_selection_pipeline_metrics` e `get_selection_rankings` têm
  `EXECUTE` para PUBLIC **e** `anon`; `get_chapter_selection_summary` para `anon`. Todas gateiam por
  `auth.uid()` — profundidade, não porta aberta.
- **#1777** (o fluxo que gravou o papel divergente; dado já normalizado), **#1776**, **#1664 fase 2**,
  **#1762** (corrigir muda quem recebe candidato → precisa do PM), **#1729**, **#1742**, **#1744**,
  **#1728** (20 RPCs da mesma classe). **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. 🆕 ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO — puxe `pg_get_functiondef`, nunca o fragmento
   da varredura.** Nesta sessão quase apliquei uma função reconstruída a partir de 14 linhas: saiu
   com retorno errado, códigos errados e um bloco `EXCEPTION` inexistente.
2. **`apply_migration` recebe o SQL como STRING.** Feche o risco comparando
   `md5(regexp_replace(prosrc,'\s+',' ','g'))` do corpo vivo com o do arquivo. Parser canônico:
   `tests/helpers/rpc-body-drift-parser.mjs`; lado vivo: `_audit_list_public_function_bodies()`
   (devolve `body_md5` já normalizado). Bateu 10 de 10 em 16/08.
3. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar. Com UMA chamada não há fantasma a apagar, e **`migration repair` é desnecessário** —
   a linha já existe. (O CLI aqui não aceita `--project-ref` nesse subcomando.)
4. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs
   abertas** e mergeie antes de aplicar a próxima.
5. **Mudança de schema exige `npm run db:types` na MESMA PR** (o gate `gen-types-drift` pega).
6. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
   migration. (`CREATE OR REPLACE` de função **existente** preserva as ACLs — conferido em 16/08.)
7. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
8. 🆕 ⚠️ **No ARE do Postgres, `\b` é BACKSPACE** — fronteira de palavra é `\y`. Com `\b` a varredura
   devolve **zero** e parece "nada a corrigir".
9. 🆕 ⚠️ **A ganância do RE inteiro vem do PRIMEIRO quantificador com preferência**: `\s+` antes de
   `[^;]*?` torna tudo guloso. Use janela limitada — e o Postgres **recusa contagem acima de 255**.
10. 🆕 ⚠️ **Guard de texto acusa a própria documentação.** O `COMMENT ON` que ENSINA a não usar um
    padrão o cita literalmente. Separe prosa de SQL executável (o filtro de `--` **não** pega blocos
    `COMMENT ON`); não apague a doc.
11. 🆕 📌 **Prove que o guard fica VERMELHO.** Plante a violação numa transação abortada. Um guard
    que nasce verde é indistinguível de um guard cego.
12. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`), no início
    da lista.
13. **Suíte offline (~53 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` (`set -a; source ./.env; set +a`) e confira
    **zero skips**. Suíte com DB: ~10 min. Confira `gh run list` antes (#1505).
14. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E nunca escreva `close #N` sem
    intenção de fechar, **nem para CITAR o padrão**.
15. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`. **E confira o nome que você criou
    antes do `push`** — errei o sufixo nesta sessão e o push falhou.
16. ⚠️ **O `git status` do início da sessão pode estar STALE.** Nesta sessão ele listava como
    untracked 4 docs de planning que estavam rastreados. `git fetch` / `git ls-files` antes.
17. ⚠️ **`supabase` CLI aqui não está linkado:** `--project-ref ldrfrvwhxsmgaabwmaik` (onde o
    subcomando aceitar).
18. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de
    pessoa não entra em issue, PR nem doc — conte a população, não a pessoa.
19. ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para
    `service_role`.** Impersone em transação abortada: `set_config('request.jwt.claims', ...)`
    **antes** do `SET LOCAL ROLE`, e `RESET ROLE` antes de conferir o efeito.
20. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background** — o pipe segura toda a saída.
    Redirecione para arquivo.
21. ⚠️ **Um contract test que faz shell-out de lint pode TRAVAR em vez de falhar.** Rode os lints
    **antes**, separados (`npm run lint:client-scripts`, ~20 s).
22. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
