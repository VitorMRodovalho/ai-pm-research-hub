# Prompt de arranque — Fase 1 do EPIC #1780 (auditoria) e o prazo do #1710

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`. Comece em PLAN MODE.**
> Handoff anterior: `docs/planning/2026-08-14_handoff_1710_medido_1587_fechado_1586_com_autor.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **14/08/2026** e vários se
movem sozinhos — dois se moveram durante a própria sessão que os mediu. Re-meça com tool call na
mesma volta em que o número entrar numa decisão, num commit, numa issue ou numa pergunta ao PM.

Três regras de varredura que custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** Vale para `gh run list --limit`, `LIMIT` em
  SQL e `gh pr checks` (a lista ENCOLHE durante um rebase).
- **Ausência de par só é conclusiva se o carimbo cobre a janela inteira.** Antes de dizer "não foi o
  cron", prove que o carimbo de execução existe em todo o período examinado.
- **Varra `pg_proc`, não o repositório** — e conte quantas funções têm o nome antes de confiar nele.

---

## Por que começar em PLAN MODE

A Fase 1 do EPIC #1780 é **auditoria, não correção**. Em 14/08 uma única queixa de campo revelou
**três causas independentes** numa tarde, o que é o argumento do EPIC: o domínio não tem quem o
observe sistematicamente. Se a sessão corrigir o primeiro achado, ela não chega ao terceiro.

Plan mode força medir antes de propor. Saia dele **só** depois que o PM aprovar o corte — e aí sim
escreva relatório e correções.

---

## Estado (14/08, fim do dia)

`main` em **`fc87e1c9`**. **Zero PRs abertas.** A sessão fechou 2 merges (#1774 12/12, #1775 11/11)
com **zero bypass**.

Em produção desde então, **fora de PR** (são atos, não código — todos com antes/depois medidos):

- backfill do cache do #1587 (97 linhas)
- migration `20260814154021` — `interview_manual_rescue_count` + `selection_rescue_unbooked_invite`
- EF `nucleo-mcp` deployada, `/health` responde **`ef_version: 2.98.0`**
- engajamento do Aftershow de uma curadora encerrado em 16/07 (sai da coorte do selo, **segue curadora**)
- **24 engajamentos `volunteer/participant` normalizados para `researcher`** (destravou 24 pessoas)

---

## ⏰ ITEM 1 — #1710, e o prazo é 24/08

O cron `attendance-seal-window-daily` está **ativo** (`40 11 * * *`), piso **24/08**, carência 14 dias.

**Medido em 14/08, projetando 24/08:** 47 eventos devidos, 43 selados, **80 faltas em 40 pessoas**
(era 82/41 antes de a curadora sair da coorte). Pior caso 7 numa pessoa; 9 pessoas com 3 ou mais.

⚠️ **É TETO, não previsão.** Toda presença registrada por um líder até lá tira uma linha da conta.
**Re-medir na véspera** — e o número certo só existe no dia.

**Como ensaiar:** transação abortada, recuando o `floor_date`; para projetar 24/08 sem esperar,
deslocar a carência para 4 dias (mesmo corte). O ensaio devolve chaves diferentes do ato
(`events_would_seal` vs `events_sealed`) de propósito.

✅ **Já fechado, não re-investigar:** o cuidado de coorte da issue foi medido — **zero** faltas
ficariam sem superfície (75 na grade de tribo, 65 na geral). `unseal_event_attendance` **existe**. O
selo grava **só `present=false`**, com `ON CONFLICT DO NOTHING`, e nunca sobrescreve.

⚖️ **DECISÕES do PM sobre #1710/#1726, NÃO re-litigar:** selo automático com janela e aviso · 86
ativos, janela 14 dias, correção pelo líder da tribo · exige dry-run e reversão por evento. A
comunicação **já foi enviada**.

---

## ITEM 2 — EPIC #1780, Fase 1: a auditoria

**Não propor solução nesta fase.** A saída é um mapa medido; o corte é decisão do PM.

As cinco varreduras, na ordem em que uma alimenta a seguinte:

1. **Sobrecargas.** `pg_proc` por `proname` duplicado no domínio board/card/checklist. O #1779 achou
   uma por acidente (`get_board_activities` significando *log* numa assinatura e *tarefas* na outra);
   a pergunta é quantas mais existem.
2. **Portas quebradas.** Para cada entidade (board, card, checklist, comentário, anexo, drive):
   existe leitura **agregada** e leitura no **varejo**? Qual falta? (É a forma do #1671 e do #1779.)
3. **Gates sem recurso.** Toda policy e RPC de escrita do domínio que decide por capacidade
   organizacional **sem olhar o recurso** — a classe do #1778, e a mesma do #1590 e do #1728.
4. **Divergência UI × MCP.** Onde a mesma palavra significa coisas diferentes ("Atividades" é
   checklist item na UI e log no MCP) e onde a mesma ação tem autoridade diferente nos dois caminhos.
5. **Cobertura.** Que operações a UI oferece e o semântico não tem (o #1588, escopado a board/card).

**Nas issues novas, o contexto já está medido:** #1777 (a regressão de 4 dias; o **dado** já foi
normalizado, o **fluxo** que a causou segue aberto), #1778 (a RLS que ignora autoria), #1779 (a
sobrecarga). As 13 anteriores estão agrupadas em 4 temas no corpo do EPIC.

⚠️ **Ao medir autoridade, exerça o caminho.** `can_by_member` prova a capacidade, não o portão.
Impersone e tente a escrita real em transação abortada — e o `set_config` vem **antes** do
`SET LOCAL ROLE`, senão o teste mede "não autenticado" e parece falta de permissão.

---

## ITEM 3 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`,
  conferindo na linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'`.
  ⚠️ **Não despachar para testar:** medido em 14/08, os 10 convites pendentes têm **0 a 8 dias**
  (nenhum acima de 21). Re-convidar agora é insistência, não operação. Esperar envelhecer.
- **Funil, prazo 28/08.** O carimbo de **abertura** saiu do vácuo em 14/08 (despacho do cron às
  15:00, candidato abriu às 16:04). Falta **`booked_at`**. **Nenhum número de conversão pode ser
  publicado** até uma linha carimbar reserva. Não provocar despacho: o cron está gerando linhas
  instrumentadas sozinho.

---

## Depois desses

- **#1776** — as duas derivações de "researcher" discordam (`v_member_operational_tiers` mapeia o
  `role` e ignora o `kind` da iniciativa; `get_member_tribe` exige `research_tribe`). Hoje atinge 1
  pessoa; é o mecanismo que permite estar na coorte de presença sem grade.
- **#1664 fase 2** — a fila de VÍNCULO (7 linhas / 6 pessoas com outro e-mail). Encosta na #1614.
- **#1762** — o rodízio concentra despachos quando o lote sai na mesma transação. **Corrigir muda
  quem recebe candidato → precisa do PM.**
- **Onda E:** #1572 (P0), #1575, #1574, #1573, #1576, #1634, #1581, #1579.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **`apply_migration` recebe o SQL como STRING.** Feche o risco de transcrição comparando
   `md5(regexp_replace(prosrc,'\s+',' ','g'))` do corpo vivo com o do arquivo — **e inclua as quebras
   de linha das bordas do `$function$`**, senão o hash difere por 2 caracteres e parece deriva.
2. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar, ou o gate ADR-0097 fica vermelho.
3. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha** e torna o trabalho inseparável
   em PRs. Decida o recorte antes de aplicar, e prefira aplicar sem outra PR esperando.
4. **Mudança de schema exige `npm run db:types` na MESMA PR.** O script falha em **silêncio** na
   cadeia com `&&`: rode `mktemp` + `gen types` separados, confira tamanho, sentinela
   (`export type Json`) e **grepe o símbolo novo**.
5. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
   migration, e prove com **sonda na porta** (chamar com a chave anon e exigir `status != 200`).
6. **Guard que casa literal do corpo por regex quebra em silêncio ao refatorar.** Antes de unificar
   ramos, grepe os testes pelo literal — foi o que preservou o contrato do #1598 no #1586.
7. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
8. **Suíte offline (~75 s) é o gate barato:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` antes de acreditar no guard, e confira
   `gh run list` antes (o `validate` com DB não tolera execução concorrente — #1505).
9. ⚠️ **Nunca escrever `close #N` / `fixes #N` / `resolves #N` sem intenção de fechar, nem para
   CITAR o padrão.** E o espelho: **`Fecha #N` em português não fecha nada.**
10. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
11. ⚠️ **O conector cacheia `tools/list`.** Tool nova só aparece recarregando o catálogo.
12. ⚠️ **Repo é PÚBLICO.** Nome de pessoa não entra em issue, PR nem doc — conte a população, não a
    pessoa. Na conversa com o PM, sem problema.
