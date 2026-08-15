# Prompt de arranque — o prazo do #1710 e o corte seguinte do #1780

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-15_handoff_1780_fase1_medida_tres_cortes_entregues.md`
> Mapa da Fase 1: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **15/08/2026** e vários se
movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num
commit, numa issue ou numa pergunta ao PM.

Três regras de varredura que já custaram caro, e uma nova:

- **Uma listagem não sustenta afirmação de ausência.** Vale para `gh run list --limit`, `LIMIT` em
  SQL e `gh pr checks` — esta última **cresceu de 7 para 11 linhas** durante a espera do CI na
  sessão passada. Espere os pendentes; não conclua verde numa lista curta.
- **Ausência de par só é conclusiva se o carimbo cobre a janela inteira.**
- **Varra `pg_proc`, não o repositório** — e conte quantas funções têm o nome antes de confiar nele.
- 🆕 **Conte pelo predicado INTEIRO da policy, não pela capacidade que a issue nomeia.** Na sessão
  passada isso inflou 3 pessoas onde havia 1: a policy tinha três ramos e duas passavam por
  `rls_is_superadmin()`. Escolha o sujeito da sonda excluindo **todos** os ramos, e confirme dentro
  da própria transação que ele é mesmo o caso que você pensa estar medindo.

---

## Estado (15/08, fim do dia)

`main` em **`e3e82f48`**. **Zero PRs abertas.** A sessão fechou **4 merges com zero bypass**
(#1785 12/12 · #1787 12/12 · #1788 11/11 · #1789 11/11).

Em produção, fora de PR (são atos, não código, todos com antes/depois medidos):

- **5 migrations** aplicadas por `apply_migration`, cada uma com arquivo local no timestamp da linha
  de tracking e **md5 normalizado conferido** contra o corpo vivo
- EF `nucleo-mcp` deployada **duas vezes**; `/health` responde **`ef_version: 2.100.0`**
- `check_schema_invariants()` **sem nenhuma violação**

Fechadas na sessão: **#1784** (gate confidencial nas tabelas-filhas do card) e **#1778** (autoria do
card vira predicado único). O EPIC **#1780 segue aberto** de propósito: a Fase 1 entregou o mapa, e a
Fase 2 tem mais cortes.

---

## ⏰ ITEM 1 — #1710, e o prazo é 24/08 (faltam 9 dias em 15/08)

O cron `attendance-seal-window-daily` está **ativo** (`40 11 * * *`), medido em 15/08.

**A primeira execução sela e grava faltas.** O teto foi medido em 14/08 projetando 24/08, e está no
handoff daquele dia — **não recite aquele número**. Ele **encolhe** a cada presença registrada por um
líder até lá.

**O que fazer:** re-medir **na véspera** (23/08), pelos dois caminhos independentes (o retorno da
função e a consulta externa que reproduz coorte + carência), e só então levar o número ao PM.

**Como ensaiar:** transação abortada, recuando o `floor_date`; para projetar 24/08 sem esperar,
deslocar a carência para 4 dias (mesmo corte). O ensaio devolve chaves diferentes do ato
(`events_would_seal` vs `events_sealed`) de propósito. Ensaio antes do piso devolve
`skipped: before_floor` — recuar o `floor_date` **dentro** da transação abortada.

⚠️ **Pendência do PM que continua de pé:** a decisão registrada é "correção pelo líder da tribo", e há
**células que nenhum líder de tribo alcança** (membros sem tribo, visíveis só na grade geral, ou seja,
só para GP). Quantas, re-medir. Decidir com o PM **antes** de 24/08.

✅ **Já fechado, não re-investigar:** zero faltas ficariam sem superfície; `unseal_event_attendance`
**existe**; o selo grava **só `present=false`**, com `ON CONFLICT DO NOTHING`, e nunca sobrescreve.

⚖️ **DECISÕES do PM sobre #1710/#1726, NÃO re-litigar:** selo automático com janela e aviso · 86
ativos, janela 14 dias, correção pelo líder da tribo · exige dry-run e reversão por evento. A
comunicação **já foi enviada**.

---

## ITEM 2 — #1779, o corte seguinte do #1780

A Fase 1 confirmou que é **caso único** no domínio: varridas todas as `proname` duplicadas em
`public`, só `get_board_activities` significa duas coisas. **As duas assinaturas seguem vivas**
(conferido em 15/08).

| assinatura | devolve |
|---|---|
| `(p_board_id, p_limit)` | o **log** de lifecycle (ação, status anterior/novo, motivo, ator) |
| `(p_board_id, p_assignee_filter, p_status_filter, p_period_filter)` | as **tarefas** (texto, responsável, data, baseline, forecast) |

O MCP chama a do log; a das tarefas é usada **só** pelo frontend. **Não existe porta agregada de
tarefas no semântico** — para saber quem é responsável por quê e até quando, é card a card.

O escopo proposto na issue tem quatro itens (expor as tarefas, desfazer a colisão de nome, alinhar o
vocabulário, contrato que prove a distinção). **Levar ao PM antes de escrever**: renomear a de log
mexe em consumidor vivo, e o alias tem custo de manutenção.

⚠️ **Antes de mexer em qualquer uma das duas:** `SELECT count(*) FROM pg_proc WHERE proname='X'` — foi
essa regra que existe exatamente para esta classe. E `DROP + CREATE` (não `CREATE OR REPLACE`) se
mudar tipo ou número de parâmetros.

---

## ITEM 3 — a classe do #1778 nas tabelas vizinhas

O #1778 fechou a superfície do checklist, **não a classe**. Medido em 15/08, seguem decidindo por
capacidade organizacional sem olhar o recurso, no comando `ALL`:

- `board_item_assignments.assignments_write_leaders`
- `board_item_tag_assignments.tag_assignments_write_leaders`
- `board_item_checklists.checklists_write_leaders` (a UI não a usa mais, mas a porta do PostgREST segue)
- `public_publications.pub_admin_manage_v4` — **fora do domínio board/card**, mesma redação

Consequência da que importa: quem tem `write_board` e **não** enxerga uma iniciativa confidencial
ainda pode **escrever** papéis e tags nos cards dela. A leitura foi fechada no #1784; a escrita não.

⚠️ **O caminho já está pronto:** `can_manage_card_checklist` mostra a forma (capacidade OU vínculo com
o recurso, com o gate do #785 **dentro**). Reusar o predicado ou criar o irmão é decisão de escopo.

---

## ITEM 4 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`,
  conferindo na linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'`.
  ⚠️ **Não despachar para testar** — re-medir a idade dos convites pendentes antes de sugerir.
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até
  uma linha carimbar reserva. Exigir `instrumented = true` **e** `booking_token_md5` na linha nova.
  Não provocar despacho: o cron gera linhas instrumentadas sozinho.

---

## Depois desses

- **#1783** — 8 alertas Dependabot (5 high) em 3 lotes; `astro` é **major 6→7**. ⚠️ **PR local de
  higiene, nunca mergear Dependabot** (#611). São **2 lockfiles** no repo.
- **Linha de base do #1784** — **10** tabelas-filhas de outros domínios seguem sem gate, todas com
  zero linhas confidenciais hoje. O contrato falha se aparecer uma nova; a base só encolhe.
- **Agregada de comentário e de anexo** — não existem nem em SQL (achado da Fase 1).
- **8 verbos de curadoria** sem porta MCP nenhuma: um ciclo inteiro de trabalho só alcançável pela
  tela. Escopo é do PM.
- **#1777** (o fluxo que gravou o papel divergente; o dado já está normalizado), **#1776**, **#1664
  fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do PM), **#1729**, **#1742**,
  **#1744**.
- **Onda E:** #1572 (P0), #1575, #1574, #1573, #1576, #1634, #1581, #1579.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **`apply_migration` recebe o SQL como STRING.** Feche o risco comparando
   `md5(regexp_replace(prosrc,'\s+',' ','g'))` do corpo vivo com o do arquivo — **e inclua as quebras
   de linha das bordas do `$function$`**. Funcionou nas 5 migrations da sessão passada; use.
2. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar, ou o gate ADR-0097 fica vermelho.
3. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs
   abertas** e mergeie antes de aplicar a próxima. Foi assim nas três PRs da sessão passada.
4. **Mudança de schema exige `npm run db:types` na MESMA PR.** ⚠️ **O script pode sair com `exit=1` e
   ainda assim escrever o arquivo** — na sessão passada ele **injetou uma linha de erro do PostHog no
   fim do `database.gen.ts`**. Rode `mktemp` + `gen types` separados, confira tamanho, sentinela
   (`export type Json`), **grepe o símbolo novo** e **olhe as últimas linhas**.
5. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
   migration, e prove com **sonda na porta** (chamar com a chave anon e exigir `status != 200`).
6. **`SECURITY DEFINER` contorna a RLS.** Rotear a UI para uma RPC resolve um bloqueio legítimo e
   **abre** o que a policy fechava: o gate do #785 tem de estar **dentro** da função. Foi assim que a
   escrita em card confidencial passou despercebida na auditoria e apareceu no CI.
7. **Guard que casa literal do corpo por regex quebra em silêncio ao refatorar.** Antes de unificar
   ramos, grepe os testes pelo literal. Na sessão passada o contrato w1 ficou vermelho por isso — e
   estava certo: a autoridade **tinha** mudado.
8. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
9. **Suíte offline (~55 s) é o gate barato:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` antes de acreditar no guard (`set -a;
   source ./.env; set +a`), e confira `gh run list` antes (o `validate` com DB não tolera execução
   concorrente — #1505).
10. ⚠️ **`Fecha #N` em português NÃO fecha a issue** — aconteceu na sessão passada, com a #1784
    ficando aberta depois do merge. Use `Closes #N` ou feche na mão. E o espelho: **nunca escrever
    `close #N` sem intenção de fechar, nem para CITAR o padrão.**
11. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
12. ⚠️ **`supabase` CLI aqui não está linkado:** passe `--project-ref ldrfrvwhxsmgaabwmaik` em
    `functions deploy` e em `gen types`, senão sai `LegacyProjectNotLinkedError`.
13. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de uma tool existente evita o problema;
    tool nova só aparece recarregando o catálogo.
14. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois** (padrão do
    #1728 e do #1784). Nome de pessoa não entra em issue, PR nem doc — conte a população, não a
    pessoa. Na conversa com o PM, sem problema.
