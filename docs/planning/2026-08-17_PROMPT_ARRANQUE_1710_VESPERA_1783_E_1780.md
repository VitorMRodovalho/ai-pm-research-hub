# Prompt de arranque — a véspera do #1710, os alertas do #1783 e o resto do #1780

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> Handoff anterior: `docs/planning/2026-08-15_handoff_1791_escrita_gateada_e_1779_nome_proprio.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **15/08/2026** e vários se
movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit,
numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** `gh pr checks` cresceu de **10 para 12 linhas**
  durante a espera do CI na sessão passada. Espere os pendentes.
- **Ausência de par só é conclusiva se o carimbo cobre a janela inteira.**
- **Varra `pg_proc`, não o repositório** — e conte quantas funções têm o nome antes de confiar nele.
- **Conte pelo predicado INTEIRO da policy, não pela capacidade que a issue nomeia.**
- 🆕 **Um guard verde fala de UM eixo.** O do #1784 derivava as filhas por chave estrangeira, o que é
  a forma certa, e ainda assim ficou verde o patch inteiro porque classificava só a **leitura**:
  quatro portas de INSERT seguiam abertas. Pergunte de que direção o verde está falando.
- 🆕 **Uma barreira que funciona por efeito colateral não é barreira.** O Postgres aplica as policies
  de SELECT ao UPDATE/DELETE que referencia colunas; o INSERT escapa porque não lê linha nenhuma. Um
  `DELETE` que apagou 0 pode ser o gate do vizinho, não o seu — exija o controle inverso na mesma
  transação.

---

## Estado (15/08, fim da tarde)

`main` em **`8e9b83c4`**. **Zero PRs abertas.** A sessão fechou **2 merges com zero bypass**
(#1792 e #1793).

Em produção, fora de PR: **4 migrations** (arquivo local renomeado para o timestamp da linha de
tracking; md5 normalizado conferido nas duas que criam função), EF `nucleo-mcp` em
**`ef_version 2.101.0`** / `/semantic` **0.16.0** / 54 tools, e `check_schema_invariants()` sem
violação.

Fechadas: **#1791** (gate confidencial na direção de ESCRITA) e **#1779** (log e tarefas deixam de
compartilhar nome). O EPIC **#1780 segue aberto** de propósito.

---

## ⏰ ITEM 1 — #1710, e o prazo é 24/08

O cron `attendance-seal-window-daily` está ativo (`40 11 * * *`), piso **24/08**, carência **14 dias**.

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que
reproduz coorte + carência, e o ensaio da própria função — e só então levar o número ao PM. Em 15/08
os dois batiam em **47 due · 4 pulados · 43 selam · 80 faltas · 40 pessoas**. ⚠️ **É teto, e encolhe
a cada presença registrada por um líder.**

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando
`grace_days` para dar o mesmo corte de **10/08 11:40Z** que 14 darão em 24/08, recuando também o
`floor_date` (senão volta `skipped: before_floor`), e terminando em `RAISE EXCEPTION` com o resultado.
A exceção aborta o bloco inteiro e o `UPDATE` volta sozinho. **Confira a config depois do ensaio.**

⚖️ **DECIDIDO pelo PM (15/08), NÃO re-litigar:** as células que nenhum líder de tribo alcança ficam
com o **GP, pela grade geral**. Eram **5 faltas em 2 pessoas**. Nada muda no código.
📌 **Ação da véspera:** levar ao GP a lista **nominal** dessas células — **na conversa, não em issue
nem em PR** (repo público).

✅ **Já fechado, não re-investigar:** zero faltas ficariam sem superfície · `unseal_event_attendance`
**existe** · o selo grava **só `present=false`**, com `ON CONFLICT DO NOTHING`.

---

## 🛡️ ITEM 2 — #1783, os 8 alertas Dependabot

5 high, em **3 lotes**. `astro` é **major 6→7** e fecha 3 alertas de uma vez; `extract-zip` e
`image-size` estão **sem patch**.

⚠️ **PR local de higiene, NUNCA mergear PR do Dependabot** (#611 — o `validate` deles falha para
sempre, por falta de secrets no run). São **2 lockfiles** no repo.

Re-medir a lista antes de agir: `gh api repos/VitorMRodovalho/ai-pm-research-hub/dependabot/alerts`.

---

## ITEM 3 — o resto do EPIC #1780

A Fase 1 mediu e três cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

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
  ⚠️ **Não despachar para testar.** Em 15/08 os 97 despachos sem reserva tinham média de **50,6 dias**
  e o mais antigo **80 dias** — re-medir antes de sugerir.
- **Funil, prazo 28/08.** Em 15/08: **97 linhas, 3 instrumentadas, 3 com token, 1 abertura, 0
  reservas.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até uma linha
  carimbar reserva. **Não provocar despacho** — o cron despachou em 15/08 e gera linhas sozinho.
  Exigir `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## Depois desses

**#1777** (o fluxo que gravou o papel divergente; o dado já está normalizado), **#1776**, **#1664
fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do PM), **#1729**, **#1742**,
**#1744**, **#1728** (20 RPCs da mesma classe, sem detalhe na issue).
**Onda E:** #1572 (P0), #1575, #1574, #1573, #1576, #1634, #1581, #1579.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. **`apply_migration` recebe o SQL como STRING.** Feche o risco comparando
   `md5(regexp_replace(prosrc,'\s+',' ','g'))` do corpo vivo com o do arquivo, **incluindo as quebras
   de linha das bordas do `$function$`**. Funcionou nas 4 migrations da sessão passada.
2. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar, ou o gate ADR-0097 fica vermelho. Nenhuma precisou de `migration repair`.
3. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs abertas**
   e mergeie antes de aplicar a próxima.
4. **Mudança de schema exige `npm run db:types` na MESMA PR.** O script tem a guarda do #1733
   (`mktemp` + sentinela), mas confira também tamanho, o símbolo novo e as últimas linhas.
5. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
   migration, e prove com **sonda na porta** — e com uma RPC pública de **controle**, senão um 401 por
   chave inválida passa por revogação bem-sucedida.
6. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
7. **A versão da superfície semântica tem QUATRO pins em arquivos que não se conhecem.** A lista
   dentro do teste do #1710 nomeia três; o quarto é o pin cruzado do próprio teste, e só aparece
   quando a suíte **inteira** roda offline.
8. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
9. **Suíte offline (~55 s) é o gate barato:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` antes de acreditar no guard (`set -a;
   source ./.env; set +a`), e confira `gh run list` antes (o `validate` com DB não tolera execução
   concorrente — #1505; o `check-invariants` fica na fila atrás dele).
10. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E o espelho: **nunca escrever
    `close #N` sem intenção de fechar, nem para CITAR o padrão.**
11. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
12. ⚠️ **`supabase` CLI aqui não está linkado:** `--project-ref ldrfrvwhxsmgaabwmaik` em
    `functions deploy` e em `gen types`.
13. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
14. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de
    pessoa não entra em issue, PR nem doc — conte a população, não a pessoa.
15. 🆕 ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para
    `service_role`.** Teste que afirme a forma do envelope chamando a função mede a falta de sessão.
    Derive do catálogo (`_audit_function_source`) ou impersone em transação abortada.
16. 🆕 ⚠️ **`pg_get_function_identity_arguments` devolve nome E tipo** (`p_board_id uuid, ...`).
