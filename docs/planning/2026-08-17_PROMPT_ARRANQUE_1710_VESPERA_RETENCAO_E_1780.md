# Prompt de arranque — a véspera do #1710, a retenção sem executor e o resto do #1780

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_1780_E_DIVIDA.md` (o #1809 fechou).
> Handoff anterior: `docs/planning/2026-08-16_handoff_1809_metade_compartilhada_fechada.md`
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
- **Um verificador que lê o diretório inteiro inclui o artefato que está sendo verificado.**
- **`replace_all` casa a string, não a intenção.** **Conte as ocorrências**, e **diffe contra o
  original** antes de aplicar.
- 🆕 🔴 **Corrigir UM literal morto pode ser conserto INERTE.** No #1809, o mesmo predicado tinha
  **dois** literais fora do domínio (`status` E `type`): trocar só o primeiro deixaria os contadores
  em zero, agora por outro motivo. **Varra todas as colunas do predicado, e EXERÇA o caminho real
  antes de anunciar antes→depois.** Quando nenhum literal do domínio serve como substituto, a
  pergunta vira "**qual tabela**" — procure quem ESCREVE o dado.
- 🆕 ⚠️ **Antes de escalar a gravidade, confira QUEM CHAMA.** Quase afirmei que a anonimização LGPD
  estava quebrada; a RPC morta não está em cron nenhum e os crons de LGPD são independentes.

---

## Estado (16/08)

`main` em **`5ccab55f`**. Migrations **`20260816143638`** e **`20260816143735`** aplicadas e
verificadas (**drift 0/0/0**, 44 invariantes em zero). **#1809 fechada** pela PR #1810 (12/12, sem
`--admin`). ⚠️ **Re-medir a janela de bypass** antes de qualquer `--admin`. Não recitar.

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

## 🆕 ITEM 2 — a retenção declarada que ninguém executa (achado do #1809)

Com a aposentadoria de `admin_run_retention_cleanup`, `data_retention_policy` fica com **6 políticas
ativas e ZERO executor**. Isso **já era verdade antes**, porque a função nunca chegou a rodar:

- `notifications` (delete 180d) e `data_anomaly_log` (delete 365d) — os dois únicos ramos `delete`,
  ambos citando coluna inexistente
- `selection_applications` (anonymize 1095d) — ramo com `applied_at`, coluna que não existe
- `visitor_leads` (delete 90d) — **nunca teve ramo nenhum**
- `attendance` e `board_lifecycle_events` (archive) — `cleanup_type='archive'` era `v_affected := 0`

**Decisão do PM:** a tabela ganha um executor honesto, ou as linhas saem dela? Uma tabela que declara
política que ninguém executa é pior que tabela vazia — parece controle.

🔔 **Junto disso:** `lgpd-anonymize-premember-monthly` está **INATIVO** (medido 16/08). É o cron
desenhado para anonimizar candidatura de pré-membro (5 anos). **Lacuna LATENTE, não viva:** 170
candidaturas, a mais antiga de **2025-08-11**, **zero** acima de 3 anos. **Re-medir antes de propor.**

---

## 🔔 ITEM 3 — o alerta sem destinatário (ainda NÃO corrigido)

O cron diário de consistência avisa os **leads** do comitê dos ciclos em andamento. Medido em 16/08:
**3 leads na plataforma inteira, todos em ciclos FECHADOS**; o `cycle4-2026` (o aberto) tem **zero**.

📌 O #1809 mostrou que esse mesmo fato-dado tinha uma **segunda** consequência, já corrigida: duas
RPCs de leitura sobre candidatura gateavam por `role IN ('lead','member')`, e com `'member'` morto o
predicado valia `lead` sozinho — os **5 evaluators (3 no ciclo aberto)** ficavam de fora. O gate foi
corrigido; **o destinatário do alerta continua sendo dado, não código.** Leve ao PM.

---

## ITEM 4 — o resto da classe: resolução por STATEMENT

Os dois ratchets cobrem a classe por **corpo inteiro**: `_audit_state_literal_domain` (#1805, coluna
de dono único) e `_audit_shared_state_literal_domain` (#1809, nome compartilhado, **562 pares, 20
colunas, 268 funções**). Ambos com base ZERO.

⚠️ **Ponto cego declarado:** função que referencia **duas ou mais** relações com a mesma coluna sai
da cobertura, de propósito (é o que evita resolver errado). `get_invitation_health` saiu assim — o
`canceled` morto dela foi achado por **leitura**, não pelo guard.

Fechar esse resto exige **resolver por STATEMENT** (qual tabela cada `UPDATE`/`DELETE`/`FROM`
alcança), não por corpo. Se for atacar: comece medindo quantas funções ambíguas têm o literal dentro
de um statement de tabela única.

---

## ITEM 5 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist; as outras
  seguem espalhadas.
- **8 verbos de curadoria sem porta MCP nenhuma. Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas decidem escrita só por capacidade. **Do #1784:** 10 filhas sem
  gate de leitura. Todas com zero linhas confidenciais hoje.

---

## ITEM 6 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`, conferindo
  na linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'` (cap 3, separado do cap
  1 do cron). ⚠️ **Não despachar para testar.**
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até
  uma linha carimbar reserva. **Não provocar despacho** — o cron gera linhas sozinho. Exigir
  `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## ITEM 7 — dívida conhecida, com dono

- **#1592** — barreira contra DDL nova. **468 de 1105** SECDEF alcançáveis por chamador anônimo
  (15/08). Todas gateiam por `auth.uid()` — profundidade, não porta aberta.
- **#1777**, **#1776**, **#1664 fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do
  PM), **#1729**, **#1742**, **#1744**, **#1728** (20 RPCs da mesma classe).
  **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.
- **#1205** só fecha com o William no `/profile` LOGADO.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO — nunca o fragmento da varredura.** Rota que
   funcionou no #1805 e no #1809 e **não transcreve nada**: prove por md5 normalizado que a captura
   no repositório é idêntica ao corpo vivo (`_audit_list_public_function_bodies()` do lado vivo,
   `tests/helpers/rpc-body-drift-parser.mjs` do lado do arquivo), edite **o arquivo** com
   substituição **contada**, e monte a migration por concatenação. **Diffe cada função contra o
   original antes de aplicar.**
2. 🆕 ⚠️ **Captura antiga pode usar `CREATE FUNCTION` sem `OR REPLACE`** — erra em função existente.
   Troque por `CREATE OR REPLACE`, que ainda **preserva as ACLs** em vez de reconceder a `PUBLIC`.
3. 🆕 🔴 **`ADD CONSTRAINT` com o nome que o Postgres já gerou sozinho bate `duplicate_object`, e um
   handler `WHEN duplicate_object THEN NULL` engole a MUDANÇA de domínio.** Migration verde, domínio
   parado — foi como `visitor_leads` passou meses com 3 RPCs levantando exceção em toda chamada.
   **Troca de domínio é `DROP CONSTRAINT IF EXISTS` + `ADD`, nunca `ADD` isolado.**
4. **`apply_migration` recebe o SQL como STRING.** Feche o risco rodando
   `scripts/audit-rpc-body-drift.mjs` depois: `drifted_definite` tem de voltar a **0**.
5. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local
   para casar; `migration repair` é desnecessário. **Duas chamadas com nomes DIFERENTES não geram
   fantasma** — o que gera é repetir o mesmo nome.
6. 📌 **Divida a migration quando uma parte for crítica e a outra cosmética.**
7. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs
   abertas** e mergeie antes de aplicar a próxima.
8. **Mudança de schema exige `npm run db:types` na MESMA PR** (o gate `gen-types-drift` pega). **RPC
   nova conta, e RPC removida também.**
9. 🆕 **Mexeu em descrição de tool no `nucleo-mcp/index.ts`? Regenere o manifesto:**
   `node scripts/generate-mcp-manifest.mjs` (o guard `mcp-manifest-fresh` pega).
10. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
    migration. (`CREATE OR REPLACE` de função **existente** preserva as ACLs.)
11. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
12. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE** — fronteira de palavra é `\y`. Com `\b` a varredura
    devolve **zero** e parece "nada a corrigir". E o Postgres **recusa contagem acima de 255**.
13. ⚠️ **Guard de texto acusa a própria documentação.** Separe prosa de SQL executável antes do
    assert (o filtro de `--` **não** pega blocos `COMMENT ON`); não apague a doc.
14. 📌 **Prove que o guard fica VERMELHO.** Plante a violação numa transação abortada. **E faça-o
    devolver todos os pares examinados com um booleano** — senão lista vazia não se distingue de
    cegueira.
15. 🆕 ⚠️ **Guard que ancora no PRIMEIRO `DROP FUNCTION` fica vermelho à toa** — migrations antigas
    fazem `DROP` + `CREATE` para recriar. Ancore no **último**.
16. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
17. **Suíte offline (~53 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` (`set -a; source ./.env; set +a`) e confira
    **zero skips**. Suíte com DB: ~10 min, **escreve em produção e não tolera concorrência com o CI**
    (#1505) — `gh run list` antes, e não dê push enquanto ela roda.
18. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E nunca escreva `close #N` sem
    intenção de fechar, **nem para CITAR o padrão**.
19. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
20. ⚠️ **O `git status` do início da sessão pode estar STALE.** `git fetch` antes.
    ⚠️ E há **dezenas de docs de planning não rastreados**: **nunca `git add -A`**, adicione por nome.
21. ⚠️ **`supabase` CLI aqui não está linkado** e **não há credencial de banco direto**:
    `--project-ref ldrfrvwhxsmgaabwmaik` onde o subcomando aceitar.
22. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de
    pessoa não entra em issue, PR nem doc — conte a população, não a pessoa.
23. ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para
    `service_role`.** Impersone em transação abortada: `set_config('request.jwt.claims', ...)`
    **antes** do `SET LOCAL ROLE`, e `RESET ROLE` antes de conferir o efeito.
24. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background** — o pipe segura toda a saída.
    Redirecione para arquivo.
25. ⚠️ **Um contract test que faz shell-out de lint pode TRAVAR em vez de falhar.** Rode os lints
    **antes**, separados (`npm run lint:client-scripts`, ~20 s).
26. 🆕 ⚠️ **`pgrep -f "<padrão>"` casa o PRÓPRIO watcher.** Um `until ! pgrep -f "astro build"; do
    sleep; done` rodando via `bash -c` tem a string no comando e se enxerga — o laço nunca sai e o
    build parece travado depois de terminar. Ancore em algo que não apareça no watcher
    (`node .*/\.bin/astro`). **O build leva ~4m30s: rode em background e confira o `Complete!` no log.**
27. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
