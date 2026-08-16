# Prompt de arranque — a véspera do #1710, o resto do #1780 e a dívida

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_1805_E_1780.md` (o #1805 fechou).
> Handoff anterior: `docs/planning/2026-08-16_handoff_1805_classe_fechada_com_ratchet_de_dominio.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **16/08/2026** e vários se
movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit,
numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** `gh api dependabot/alerts` **sem
  `--paginate`** já devolveu 0 abertos havendo 3.
- **`gh pr checks` cresce durante a espera.** Espere os pendentes; não conte linhas.
- **Varra `pg_proc`, não o repositório** — e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** #1801: listava 10, o catálogo tinha 12. #1805: listava 3, o
  catálogo tinha 4. **Derive do catálogo, sempre.**
- **Varredura por literal de coluna não diz de QUAL tabela é a coluna.** A saída: varrer só colunas
  cujo NOME tem **dono único** no schema — aí alias nenhum muda a resposta (é como o #1805 fechou).
- 🆕 ⚠️ **Um verificador que lê o diretório inteiro inclui o artefato que está sendo verificado.**
  Meu diff de conferência veio VAZIO porque a migration nova que eu tinha acabado de escrever
  ordenava por último e virou "a captura mais recente". **Exclua explicitamente o arquivo em teste.**
- 🆕 ⚠️ **`replace_all` casa a string, não a intenção.** 6 ocorrências do mesmo predicado, uma com
  indentação diferente: a substituição pegou 5 e ficou calada. **Conte as ocorrências no teste**, em
  vez de checar presença; e **diffe contra o original** antes de aplicar.

---

## Estado (16/08)

`main` em **`924b7efd`**. Migrations **`20260816040023`** e **`20260816040153`** aplicadas e
verificadas (**drift 0/0/0**). **#1805 fechada** pela PR #1807 (12/12, sem `--admin`).
⚠️ **Re-medir a janela de bypass** antes de qualquer `--admin`. Não recitar.

---

## ⏰ ITEM 1 — #1710, prazo 24/08. É o item de maior risco de data.

Config **conferida em 15/08** (re-conferir no banco):

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que
reproduz coorte + carência, e o ensaio da própria função — e só então levar o número ao PM.
⚠️ **É TETO, e encolhe a cada presença registrada por um líder.** Última medição (15/08):
**43 selam, 80 faltas, 40 pessoas**, dois caminhos batendo. **Não recitar — re-medir.**

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando
`grace_days` para dar o mesmo corte que 14 darão em 24/08, **recuando também o `floor_date`** (senão
volta `skipped: before_floor`), e terminando em `RAISE EXCEPTION` com o resultado. A exceção aborta e
o `UPDATE` volta sozinho. **Confira a config depois do ensaio.**

⚖️ **DECIDIDO pelo PM (15/08), NÃO re-litigar:** as células que nenhum líder de tribo alcança ficam
com o **GP, pela grade geral**. Nada muda no código.
📌 **Ação da véspera:** levar ao GP a lista **nominal** dessas células — **na conversa, não em issue
nem em PR** (repo público).

✅ **Já fechado, não re-investigar:** zero faltas ficariam sem superfície · `unseal_event_attendance`
**existe** · o selo grava **só `present=false`**, com `ON CONFLICT DO NOTHING`.

---

## 🔔 ITEM 2 — o alerta sem destinatário (achado do #1805, NÃO corrigido)

O cron diário de consistência avisa os **leads** do comitê dos ciclos em andamento. Medido em 16/08:
**3 leads na plataforma inteira, todos em ciclos FECHADOS**; o `cycle4-2026` (o aberto, 81
candidaturas) tem **zero**.

O #1805 corrigiu o **escopo** (o ciclo em `evaluation` voltou a ser visto). O **destinatário** é
outro problema, e é **dado, não código**. Leve ao PM: alguém precisa receber `role='lead'` no ciclo
ativo, ou o alerta precisa de um destinatário de fallback (GP). **Re-medir antes de propor.**

---

## ITEM 3 — a metade `status` da classe do #1805, ainda sem varredura honesta

O ratchet `_audit_state_literal_domain()` cobre **91** colunas de estado com **dono único** — base
ZERO, 262 pares, 38 colunas, 151 funções. **`status` está fora de propósito**: existe em ~50 tabelas
com domínios próprios, e a varredura textual devolveu **58 candidatos**, quase todos com o literal
pertencendo a uma tabela vizinha.

Para fechar essa metade é preciso **resolver alias por consulta** (que tabela cada alias designa),
não por regex. Se for atacar: comece medindo quantas funções têm alias resolvível sem ambiguidade
(uma única tabela com coluna `status` referenciada no corpo) — essas dão para fechar já.

---

## ITEM 4 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist; as outras
  seguem espalhadas.
- **8 verbos de curadoria sem porta MCP nenhuma. Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas decidem escrita só por capacidade. **Do #1784:** 10 filhas sem
  gate de leitura. Todas com zero linhas confidenciais hoje.

---

## ITEM 5 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`, conferindo
  na linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'` (cap 3, separado do cap
  1 do cron). ⚠️ **Não despachar para testar.**
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até
  uma linha carimbar reserva. **Não provocar despacho** — o cron gera linhas sozinho. Exigir
  `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## ITEM 6 — dívida conhecida, com dono

- **#1592** — barreira contra DDL nova. **468 de 1105** SECDEF alcançáveis por chamador anônimo
  (15/08). Medido de passagem: `get_my_pending_evaluations`, `get_selection_pipeline_metrics` e
  `get_selection_rankings` têm `EXECUTE` para PUBLIC **e** `anon`; `get_chapter_selection_summary`
  para `anon`. Todas gateiam por `auth.uid()` — profundidade, não porta aberta.
- **#1777**, **#1776**, **#1664 fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do
  PM), **#1729**, **#1742**, **#1744**, **#1728** (20 RPCs da mesma classe).
  **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.
- **#1205** só fecha com o William no `/profile` LOGADO.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO — nunca o fragmento da varredura.** Rota que
   funcionou no #1805 e **não transcreve nada**: prove por md5 normalizado que a captura no
   repositório é idêntica ao corpo vivo (`_audit_list_public_function_bodies()` do lado vivo,
   `tests/helpers/rpc-body-drift-parser.mjs` do lado do arquivo), edite **o arquivo**, e monte a
   migration por concatenação.
2. **`apply_migration` recebe o SQL como STRING.** Feche o risco rodando
   `scripts/audit-rpc-body-drift.mjs` depois: `drifted_definite` tem de voltar a **0**.
3. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar; `migration repair` é desnecessário. **Duas chamadas com nomes DIFERENTES não geram
   fantasma** — o que gera é repetir o mesmo nome.
4. 🆕 📌 **Divida a migration quando uma parte for crítica e a outra cosmética.** No #1805 a função do
   caminho de aprovação foi para uma migration própria, fora do raio da outra.
5. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs
   abertas** e mergeie antes de aplicar a próxima.
6. **Mudança de schema exige `npm run db:types` na MESMA PR** (o gate `gen-types-drift` pega). **RPC
   nova conta** — ela entra em `src/lib/database.gen.ts`.
7. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
   migration. (`CREATE OR REPLACE` de função **existente** preserva as ACLs.)
8. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
9. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE** — fronteira de palavra é `\y`. Com `\b` a varredura
   devolve **zero** e parece "nada a corrigir".
10. ⚠️ **A ganância do RE inteiro vem do PRIMEIRO quantificador com preferência.** Use janela
    limitada — e o Postgres **recusa contagem acima de 255**.
11. ⚠️ **Guard de texto acusa a própria documentação.** Separe prosa de SQL executável antes do
    assert (o filtro de `--` **não** pega blocos `COMMENT ON`); não apague a doc.
12. 📌 **Prove que o guard fica VERMELHO.** Plante a violação numa transação abortada. Um guard que
    nasce verde é indistinguível de um guard cego. **E faça-o devolver todos os pares examinados com
    um booleano** — senão lista vazia não se distingue de cegueira.
13. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`), no início.
14. **Suíte offline (~53 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` (`set -a; source ./.env; set +a`) e confira
    **zero skips**. Suíte com DB: ~10 min, **escreve em produção e não tolera concorrência com o CI**
    (#1505) — `gh run list` antes, e não dê push enquanto ela roda.
15. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E nunca escreva `close #N` sem
    intenção de fechar, **nem para CITAR o padrão**.
16. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
17. ⚠️ **O `git status` do início da sessão pode estar STALE.** `git fetch` / `git ls-files` antes.
    ⚠️ E há **dezenas de docs de planning não rastreados** de sessões antigas: **nunca `git add -A`**,
    adicione os arquivos da mudança por nome.
18. ⚠️ **`supabase` CLI aqui não está linkado** e **não há credencial de banco direto** (`psql` existe,
    senha não): `--project-ref ldrfrvwhxsmgaabwmaik` onde o subcomando aceitar.
19. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de
    pessoa não entra em issue, PR nem doc — conte a população, não a pessoa.
20. ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para
    `service_role`.** Impersone em transação abortada: `set_config('request.jwt.claims', ...)`
    **antes** do `SET LOCAL ROLE`, e `RESET ROLE` antes de conferir o efeito.
21. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background** — o pipe segura toda a saída.
    Redirecione para arquivo.
22. ⚠️ **Um contract test que faz shell-out de lint pode TRAVAR em vez de falhar.** Rode os lints
    **antes**, separados (`npm run lint:client-scripts`, ~20 s).
23. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
