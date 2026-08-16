# Prompt de arranque — a véspera do #1710, o portão legal do #905 e o resto do #1780

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_RETENCAO_E_1780.md` (#1812 e #1813 fecharam).
> Handoff anterior: `docs/planning/2026-08-16_handoff_1812_1813_retencao_e_destinatario.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **16/08/2026** e vários se movem
sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit, numa
issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** `gh api dependabot/alerts` **sem `--paginate`** já
  devolveu 0 abertos havendo 3.
- **`gh pr checks` cresce durante a espera.** Espere os pendentes; não conte linhas.
- **Varra `pg_proc`, não o repositório** — e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo, sempre.
- **Um verificador que lê o diretório inteiro inclui o artefato que está sendo verificado.**
- **`replace_all` casa a string, não a intenção.** **Conte as ocorrências** e **diffe contra o original**.
- **Corrigir UM literal morto pode ser conserto INERTE.** Varra todas as colunas do predicado e **exerça
  o caminho real** antes de anunciar antes→depois.
- 🆕 🔴 **"Zero linhas hoje" não é ausência de risco.** No #1812 as 6 políticas de retenção alcançavam
  **0 linhas cada** — só porque a plataforma tinha 155 dias e o horizonte mais curto era 90. O número que
  decide é a **data da primeira mordida** (`min(coluna de data da linha elegível) + horizonte`). Medido
  assim, virou prazo: 09/09.
- 🆕 🔴 **Antes de implementar política declarada em tabela, procure quem já a executa.** A linha de
  anonimização declarava 3 anos; o caminho revisado roda a 5 e a recomendação legal é 2/1. E o cron dele
  está **inativo de propósito**, atrás de portão de parecer. **Cron inativo pode ser governança.**
- 🆕 🔴 **Estreitar o conjunto de candidatos para forçar unicidade não é resolver, é chutar.** No #1822,
  desambiguar a tabela de uma coluna contando **só as relações que têm domínio** produziu **51 violações
  e zero defeitos** — o literal era de uma coluna sem `CHECK`, e sobrava o homônimo com domínio para levar
  a culpa. Antes de chamar a saída de achado, **confira no catálogo se o suposto dono admite a coluna**.
- 🆕 📌 **No predicado que CONTA, use só sinal do mesmo grão do que está sendo medido.** Trigger é de
  tabela, não de coluna: se entrar na base de um ratchet, ela cai quando a tabela ganha um trigger alheio.
  Sinal de grão maior é devolvido como informação, nunca no booleano que o teste assere.
- ⚠️ **Antes de escalar a gravidade, confira QUEM CHAMA.**

---

## Estado (16/08, fim da tarde)

`main` em **`28f8232d`**, com **#1812**, **#1813** e **#1819** fechadas (PRs #1815, #1816 e #1820, todas
12/12 sem `--admin`). Migrations **`20260816184810`**, **`20260816191212`** e **`20260816201138`**, cada
uma aplicada com zero PRs abertas e mergeada antes da seguinte. **Drift `0/0/0`** depois das três.
EF `nucleo-mcp` deployada: **`ef_version` 2.102.0** (era 2.101.0); smoke pós-deploy com `initialize`
HTTP 200 e `tools/list` com 342 tools, zero erro.
⚠️ **Re-medir a janela de bypass** antes de qualquer `--admin` (na medição de 16/08: 30 commits em 7 dias,
todos com `(#N)` de PR, zero eventos).

🟢 **(16/08, noite) #1822 fechada** pela PR #1823, 12/12 sem `--admin`. `main` em **`5d96fbf5`**, migration
`20260816225830` aplicada com zero PRs abertas, drift **0/0/0** (`live_count` 1201 → 1202), 43 invariantes
em zero. Handoff: `docs/planning/2026-08-16_handoff_1822_dominio_nao_declarado.md`. O **ITEM 4 abaixo já
foi medido** — leia antes de reabri-lo.

📌 **A varredura `data-retention-sweep-daily` estreia às 04:25 UTC de 17/08.** Vale conferir a primeira
corrida real: `get_lgpd_cron_health` (impersonado) deve sair de `never_ran: true` para
`days_since_last_run` perto de zero, e `admin_audit_log` deve ganhar uma linha
`action = 'data_retention.sweep'` com `affected_total = 0` (nenhuma política morde antes de 09/09).
Se a corrida falhar, o painel só vira vermelho depois de **2 dias** de silêncio — não antes.

---

## ⏰ ITEM 1 — #1710, prazo 24/08. Segue o item de maior risco de data.

Config **conferida no banco em 16/08** (re-conferir):

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que reproduz
coorte + carência, e o ensaio da própria função — e só então levar o número ao PM.
⚠️ **É TETO, e encolhe a cada presença registrada por um líder.** Última medição (15/08): **43 selam,
80 faltas, 40 pessoas**. **Não recitar — re-medir.**

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando `grace_days`
para dar o mesmo corte que 14 darão em 24/08, **recuando também o `floor_date`** (senão volta
`skipped: before_floor`), e terminando em `RAISE EXCEPTION` com o resultado. **Confira a config depois.**

⚖️ **DECIDIDO pelo PM (15/08), NÃO re-litigar:** as células que nenhum líder de tribo alcança ficam com o
**GP, pela grade geral**. Nada muda no código.
📌 **Ação da véspera:** levar ao GP a lista **nominal** dessas células — **na conversa, não em issue nem
em PR** (repo público).

---

## 🆕 ITEM 2 — o portão legal do SPEC #905, com prazo de 30/09

Achado do #1812. O cron `lgpd-anonymize-premember-monthly` está **inativo de propósito**: o SPEC #905 o
registrou dormante atrás de um checklist de parecer legal (**R1–R5**), com **prazo máximo de ativação
sugerido em 2026-09-30** — a **45 dias** da medição de 16/08.

R1–R5 são decisões **de fora da engenharia**: ratificar a janela de retenção (recomendação legal: 2 anos
rejeitado / 1 ano desistente, contra os 5 anos do comando atual), limitar no tempo a exclusão da coorte
#935, mapear e purgar os **binários externos de vídeo** (não alcançáveis por SQL — precisa de EF ou
runbook), confirmar a **base legal Art. 11 I** para coleta de voz/vídeo, e as entradas de RoPA.

**Lacuna é LATENTE, não viva:** medido pelo anchor da própria função, **0 candidatos a 5 anos e 0 a 3
anos**, sobre 170 candidaturas. ⚠️ **Re-medir pelo anchor, nunca por `created_at`** — o `created_at`
mínimo é 2026-03-14, a data da migração da plataforma, não do fato.

📌 **Levar ao PM:** os R1–R5 são dele (ou de assessoria), não da engenharia. O guard do #1812 já exige que
o horizonte declarado na tabela seja igual ao argumento do job — ratificar a janela move os dois juntos.

---

## ITEM 3 — #1814, o `archive` sem destino (aberta de propósito)

`cleanup_type='archive'` declara duas políticas e não há destino de arquivamento na plataforma. Elas
seguem **ativas e descobertas**, na base declarada do ratchet `_audit_retention_policy_coverage()`.
Primeira mordida em **2028-03-13** (board) e **2029-03-05** (presença) — **sem urgência**.

⚠️ **Risco de produto:** pontos de gamificação leem histórico de presença (`sync-attendance-points`).
Tirar linhas da tabela quente pode mudar cálculo retroativo. Confira antes de escolher entre armazenamento
frio genérico, tabela-espelho por origem, ou não arquivar.

---

## ITEM 4 — o resto da classe: resolução por STATEMENT ✅ **MEDIDO em 16/08 (#1822)**

Os três ratchets cobrem a classe: `_audit_state_literal_domain` (#1805, coluna de dono único),
`_audit_shared_state_literal_domain` (#1809, nome compartilhado) e, desde o #1822,
`_audit_undeclared_state_domain` — a coluna que **não declara domínio nenhum**, e que por isso nenhum
dos outros dois alcança (base **56** de **270** examinadas).

**O ponto cego foi medido: 377 pares (função, coluna) em 294 funções**, contra 491 cobertos. Decompõe em
**91** sem nenhuma relação com domínio (já inertes), **48** com exatamente uma, e **238** de ambiguidade
real.

🔴 **O atalho dos 48 NÃO existe — ensaiado e morto.** Contar só as relações que carregam domínio devolveu
**51 violações e ZERO defeitos**: `type = 'selection_approved'` debitado de `certificates` e
`kind = 'volunteer'` de `member_emails`, porque `notifications.type` e `engagements.kind` não têm `CHECK`
nenhum. O `count(DISTINCT reloid) = 1` do #1809 é **justamente o que protege** contra isso — estreitar o
denominador para forçar unicidade inverte a proteção.

⚠️ **Sobra a ambiguidade real: 238 pares.** Fechar exige **resolver por STATEMENT** (qual tabela cada
`UPDATE`/`DELETE`/`FROM` alcança), não por corpo. Não há caminho barato; a medição acima já foi feita e
não precisa ser refeita.

📌 **Decisão pendente do PM:** quais das **56** colunas sem domínio declarado merecem ganhar `CHECK`. Nem
todas devem — `admin_audit_log.action` é vocabulário que cresce de propósito (regex de formato), e
declarar domínio sobre dado vivo tem risco próprio: o ensaio bateu em linha de `pilots` fora do domínio
na primeira tentativa. A lista sai de `_audit_undeclared_state_domain()`.

---

## ITEM 5 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist.
- **8 verbos de curadoria sem porta MCP nenhuma. Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas decidem escrita só por capacidade. **Do #1784:** 10 filhas sem gate
  de leitura. Todas com zero linhas confidenciais hoje.

---

## ITEM 6 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`, conferindo na
  linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'` (cap 3, separado do cap 1 do
  cron). ⚠️ **Não despachar para testar.**
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até uma
  linha carimbar reserva. **Não provocar despacho** — o cron gera linhas sozinho. Exigir
  `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## ITEM 7 — dívida conhecida, com dono

- **#1592** — barreira contra DDL nova. **468 de 1105** SECDEF alcançáveis por chamador anônimo (15/08).
  Todas gateiam por `auth.uid()` — profundidade, não porta aberta.
- **#1777**, **#1776**, **#1664 fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do PM),
  **#1729**, **#1742**, **#1744**, **#1728** (20 RPCs da mesma classe).
  **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.
- **#1205** só fecha com o William no `/profile` LOGADO.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO — nunca o fragmento da varredura.** Rota que funcionou
   no #1805, #1809 e **#1813**, e que **não transcreve nada**: prove por md5 normalizado que a captura no
   repositório é idêntica ao corpo vivo (`scripts/audit-rpc-body-drift.mjs` com `drifted_definite = 0`),
   extraia o bloco **do arquivo**, aplique substituição **contada** (script que aborta se a contagem não
   for 1), **diffe contra o original**, e monte a migration por concatenação.
2. ⚠️ **Captura antiga pode usar `CREATE FUNCTION` sem `OR REPLACE`** — erra em função existente. Troque
   por `CREATE OR REPLACE`, que ainda **preserva as ACLs**.
3. 🔴 **`ADD CONSTRAINT` com nome que o Postgres já gerou bate `duplicate_object`, e um handler
   `WHEN duplicate_object THEN NULL` engole a MUDANÇA de domínio.** Troca de domínio é
   `DROP CONSTRAINT IF EXISTS` + `ADD`, nunca `ADD` isolado.
4. **`apply_migration` recebe o SQL como STRING.** Feche o risco rodando `scripts/audit-rpc-body-drift.mjs`
   depois: `drifted_definite` tem de voltar a **0**.
5. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local para
   casar; `migration repair` é desnecessário.
6. 📌 **Divida a migration quando uma parte for crítica e a outra cosmética.**
7. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs abertas** e
   mergeie antes de aplicar a próxima. (Feito assim nas duas desta sessão.)
8. **Mudança de schema exige `npm run db:types` na MESMA PR** (o gate `gen-types-drift` pega). **RPC nova
   conta, e RPC removida também. Coluna nova também.**
9. **Mexeu em descrição de tool no `nucleo-mcp/index.ts`? Regenere o manifesto:**
   `node scripts/generate-mcp-manifest.mjs`. 🆕 **E confira o `ef_version` ANTES de deployar:**
   `curl .../nucleo-mcp/health` contra o literal em `index.ts` — se estiverem IGUAIS, bumpe (o guard em
   `tests/contracts/mcp-lgpd-retroactive-operator-tools.test.mjs` acompanha), senão `/health` deixa de ser
   testemunha do deploy e a prova vira grep de sentinela no bundle (lição do #1598, repetida no #1819).
   Pós-deploy, o smoke tem de incluir **`tools/list`**, não só `initialize`: a falha de Zod 3→4 deixa o
   `initialize` verde e derruba só a listagem. ⚠️ `deno` **não está instalado nesta máquina** — quem roda
   `deno lint`/`deno check` é o CI.
10. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
    migration. (`CREATE OR REPLACE` de função **existente** preserva as ACLs.)
11. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
12. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE** — fronteira de palavra é `\y`. E o Postgres **recusa
    contagem acima de 255**.
13. ⚠️ **Guard de texto acusa a própria documentação.** Separe prosa de SQL executável antes do assert (o
    filtro de `--` **não** pega blocos `COMMENT ON`).
14. 📌 **Prove que o guard fica VERMELHO.** Plante a violação numa transação abortada. **E faça-o devolver
    todos os itens examinados com um booleano** — senão lista vazia não se distingue de cegueira.
15. 🆕 📌 **Ensaie o ramo que nunca rodou.** Os três `DELETE` do #1812 nunca tinham apagado nada:
    envelhecer linhas reais para dentro do corte numa transação abortada foi o que provou que apagam o que
    devem. Idem o #1813, onde plantar uma anomalia provou as 2 notificações que antes eram 0.
16. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
17. **Suíte offline (~57 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` (`set -a; source ./.env; set +a`) e confira
    **zero skips**. Suíte com DB: ~13 min no CI, **escreve em produção e não tolera concorrência** (#1505).
18. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E nunca escreva o padrão de
    fechamento sem intenção de fechar, **nem para CITÁ-lo**.
19. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
20. ⚠️ **O `git status` do início da sessão pode estar STALE.** `git fetch` antes.
    ⚠️ E há **dezenas de docs de planning não rastreados**: **nunca `git add -A`**, adicione por nome.
21. ⚠️ **`supabase` CLI aqui não está linkado**: `--project-ref ldrfrvwhxsmgaabwmaik` onde aceitar.
22. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de pessoa
    não entra em issue, PR nem doc — conte a população, não a pessoa.
23. ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para `service_role`.**
    Impersone em transação abortada: `set_config('request.jwt.claims', ...)` **antes** do
    `SET LOCAL ROLE`, e `RESET ROLE` antes de conferir o efeito.
24. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background** — o pipe segura toda a saída.
25. ⚠️ **Um contract test que faz shell-out de lint pode TRAVAR em vez de falhar.** Rode os lints antes.
26. ⚠️ **`pgrep -f "<padrão>"` casa o PRÓPRIO watcher.** Ancore em algo que não apareça no watcher
    (`node .*/\.bin/astro`). **O build leva 2m30s–4m40s: rode em background e confira o `Complete!`.**
27. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
