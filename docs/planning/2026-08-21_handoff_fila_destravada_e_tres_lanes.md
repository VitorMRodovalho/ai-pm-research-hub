# Handoff 21/08: fila destravada duas vezes, e tres lanes abertas

> Medido ao vivo em 21/08/2026 (UTC). **Re-medir antes de agir.** Repositorio PUBLICO:
> sem nome de pessoa e sem identificador de candidato.

---

## 1. Estado da fila

`main` em **`fe268cf2`**.

| PR | o que e | estado |
|---|---|---|
| **#1904** | data do card le as atribuicoes (#1903) | rebaseada, **2 checks vermelhos por causa ALHEIA** |
| **#1905** | cron do card de jornada (outra lane) | **draft**, vermelha por causa alheia |
| **#1894** | arranque de 21/08 | 1 vermelho, mesma causa |

**O que trava TODAS:** uma linha de `gate_attempts` criada em producao em **21/08 14:18:47**
(`_issue_interview_booking_token_core`, sem ator, barrada por `GATE_NO_PEER_REVIEW`). Reprova 2
testes da familia **#1636** em qualquer branch.

Confirmado dos dois lados que **nenhum cron a explica**: os que rodam perto batem em `:15`, `:20`,
`:23`, `:25`, `:28`, e nenhum emite token de entrevista. Sobra chamada manual sem rastro de ator.

**O desbloqueio e o allowlist de `gate_attempts.id` do #1636.** Sem dono.

📌 **O guard reporta `application_id`, o allowlist guarda `gate_attempts.id`.** Sao colunas
diferentes: "o ID que falhou nao esta na lista" NAO prova ofensor novo. Cruze pelas duas chaves.

## 2. Mergeado nesta sessao, zero bypass

| PR | entrega |
|---|---|
| **#1897** | `DENO_NO_PACKAGE_JSON=1`: o check das EFs parou de resolver a arvore npm do frontend |
| **#1902** | os 2 defeitos de `get_portfolio_items` + os 5 `.sql` + tipos + alvo estavel do #1113 |
| **#1899** | (outra lane) drift de flag/tag + card de jornada |

**A listagem de portfolio voltou a funcionar**: 94 itens onde antes era excecao em toda chamada.

## 3. Issues abertas nesta sessao

- **#1895** a tela de selecao deriva TUDO de um eixo pessoal; quem entrevista nunca ve o
  consolidado; **145 RPCs de leitura** pedem capacidade de GP. ⚖️ **Decisao do PM ja tomada:**
  comite (`evaluator`/`lead`) + `view_pii` le todo o dossie. **Isso destrava a varredura.**
- **#1896** o check `deno` resolvia a arvore do frontend (corrigido)
- **#1901** `get_portfolio_items`: dois defeitos em serie (corrigido)
- **#1903** a data do card lia a coluna legada: **51 pessoas, 154 cards** (PR #1904)
- **#1906** cron de agenda rara nao se recupera: **53 dos 68 ativos**

## 4. Tres lanes abertas, cada uma no proprio worktree

| lane | worktree | escopo |
|---|---|---|
| **video** | `.claude/worktrees/lane-video-shorts` | Lideranca #10 (`f77a91d2`): sem youtube, sem recording, sem ata, status ainda `scheduled`. Depois: shorts do ciclo. Prompt commitado na branch. |
| **auditoria CI** | `.claude/worktrees/lane-ci-audit` | 16 workflows, 3 required, 611 testes, `validate` ~13 min. Diagnostico, NAO conserto. Prompt commitado. |
| **#1904** | `scratchpad/wt-1903` | so falta a fila destravar |

⚠️ **A arvore principal e COMPARTILHADA.** Em 20/08 um checkout de outra sessao passou por cima de
edicao em andamento; salvou-se por auto-stash, que levou junto **300 arquivos nao rastreados**.
Trabalhe em worktree e nao troque a branch da arvore principal.

## 5. Pendencias com nome

- **5 commits so existem nesta maquina**, em 3 branches sem remoto:
  `feat/1153-volunteer-term-signing-sync` (2), `feat/1209-credly-keyword-tuning` (2),
  `feat/1148-curation-xp-backfill` (1). Empurrar ou decidir descartar.
- **`stash@{0}`** ("Teleport auto-stash") ainda e copia redundante dos deliverables nao rastreados.
  O conserto do #1903 que estava la **ja esta commitado**, entao essa parte nao depende mais dele.
- **Tres candidaturas com ZERO avaliacao**, uma travada em `interview_pending` (medido 21/08 14:35).
  O lembrete original citava duas; sao tres.
- **#1881 segue aberto** e e a raiz do card de XP: o gatilho vigia as 3 colunas, mas o corpo ainda
  exige transicao de status. A ordem natural na tela (marcar done, depois marcar entregavel) nao
  paga. **Vai repetir.**
- **Follow-up da outra lane na #1906**: tornar a escrita da reconciliacao CONDICIONAL (so escrever
  quando algum dos 8 passos mudou; tirar o timestamp da `description`; nao mencionar `assignee_id`
  no `SET`). Medido: 0,26 s para 12 tribos, entao o intervalo semanal nao existe por custo.

## 6. Armadilhas medidas hoje

- **`npm test` local nao emite TAP.** Node 24 usa reporter `spec` (`✔`/`✖`/`ℹ`). Filtro que procura
  `not ok` volta VAZIO mesmo com falha. Use:
  `npm test 2>&1 | grep -E '^[[:space:]]*(not ok|✖)|^(#|ℹ) (fail|pass|tests|skipped)'`
- **Carregue o `.env`** (`set -a; . ./.env; set +a`): medimos **744 skipped** local contra **1** na
  CI. `fail 0` com 744 skipped nao e suite verde.
- **`deno-version: v2.x` FLUTUA.** Reproduzir com outra minor PASSA e inocenta o repo por engano.
  Leia no log do job qual versao o runner instalou.
- **Ao consertar portao, injete o defeito e prove que ele ainda REPROVA.** Verde por conserto e
  verde por vacuo tem a mesma cor.
- **`git ... | tail -1 && echo ok`** reporta o sucesso do `tail`, nao do `git`. Cheque `$?` do
  comando certo (isso produziu 5 "removido" falsos hoje).
