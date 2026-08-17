# Prompt de arranque — a reunião geral de 13/08, a véspera do #1710 e o portão legal do #905

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_905_E_1780.md` (o #1822 fechou e o
> ITEM 4 dele foi respondido).
> Handoff anterior: `docs/planning/2026-08-16_handoff_1822_dominio_nao_declarado.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **16/08/2026** e vários se movem
sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit, numa
issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** `gh api dependabot/alerts` **sem `--paginate`** já
  devolveu 0 abertos havendo 3.
- **`gh pr checks` cresce durante a espera.** Espere os pendentes; não conte linhas. (Na PR #1824 o total
  foi de 10 para 11 no meio da espera.)
- **Varra `pg_proc`, não o repositório** — e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo, sempre.
- **Um verificador que lê o diretório inteiro inclui o artefato que está sendo verificado.**
- **`replace_all` casa a string, não a intenção.** **Conte as ocorrências** e **diffe contra o original**.
- **Corrigir UM literal morto pode ser conserto INERTE.** Varra todas as colunas do predicado e **exerça
  o caminho real** antes de anunciar antes→depois.
- **"Zero linhas hoje" não é ausência de risco.** O número que decide é a **data da primeira mordida**.
- **Antes de implementar política declarada em tabela, procure quem já a executa.** **Cron inativo pode
  ser governança.**
- 🆕 🔴 **Estreitar o conjunto de candidatos para forçar unicidade não é resolver, é chutar.** No #1822,
  desambiguar a tabela de uma coluna contando **só as relações que têm domínio** produziu **51 violações
  e zero defeitos**. Antes de chamar a saída de achado, **confira no catálogo se o suposto dono admite a
  coluna**.
- 🆕 📌 **No predicado que CONTA, use só sinal do mesmo grão do que está sendo medido.** Trigger é de
  tabela, não de coluna. Sinal de grão maior é devolvido como informação, nunca no booleano do assert.
- 🆕 ⚠️ **Filtrar por EXTENSÃO perde arquivo cujo nome não tem extensão.** A gravação do Meet é
  `video/mp4` e o nome termina em `- Recording`, sem sufixo: um `--include "*.mp4"` passa por cima dela e
  a varredura conclui "não existe". Filtre por **MIME**, ou liste sem filtro.
- ⚠️ **Antes de escalar a gravidade, confira QUEM CHAMA.**

---

## Estado (16/08, noite)

`main` em **`a2dde3dd`**, **zero PRs abertas**, com **#1822** fechada (PRs #1823 12/12 e #1824 11/11,
nenhuma com `--admin`). Migration **`20260816225830`** aplicada com zero PRs abertas.
**Drift `0/0/0`** (`live_count` 1201 → 1202, zero órfãos). **43 invariantes, zero violações.**
EF `nucleo-mcp` segue em **`ef_version` 2.102.0** (não houve deploy nesta sessão).
⚠️ **Re-medir a janela de bypass** antes de qualquer `--admin`.

📌 **A varredura `data-retention-sweep-daily` estreou às 04:25 UTC de 17/08 — confira a primeira corrida
real logo no arranque:** `get_lgpd_cron_health` (impersonado) deve ter saído de `never_ran: true` para
`days_since_last_run` perto de zero, e `admin_audit_log` deve ter ganhado uma linha
`action = 'data_retention.sweep'` com `affected_total = 0` (nenhuma política morde antes de 09/09).
Se a corrida falhou, o painel só vira vermelho depois de **2 dias** de silêncio — não antes.

---

## 🎥 ITEM 1 — a reunião geral de 13/08: vídeo, ata, presentes, protagonistas e ações

**Escopo dado pelo PM em 16/08.** O evento é `Reunião Geral - 2026-08-13`,
id **`ed3a4c5a-553d-41c7-b01b-40e4145e85e9`**, 13/08 19:00, duração real **1h35** (último timestamp da
transcrição: `01:35:32`).

### O material já está em disco, fora do git

`_drive-docs/reuniao-geral-2026-08-13/` (git-ignored pelo `~/.config/git/ignore`, conferido por
`git check-ignore`):

| arquivo | tamanho | conteúdo |
|---|---|---|
| `notes-by-gemini.md` | 111 KB | Resumo, **Próximas etapas (10 itens já extraídos)**, Detalhes, e **transcrição completa com timestamps** (71 blocos) |
| `chat.txt` | 6,3 KB | log do chat da sessão |

⚠️ **Não precisa transcrever.** A transcrição do Gemini já existe e é carimbada por tempo — WhisperX
seria retrabalho. Os timestamps servem de base para capítulos ou cortes.

O vídeo **não precisa ser baixado**: 703.727.488 bytes legíveis direto em
`_drive/nucleo-ia-gp/Meet Recordings/Reunião Geral - Núcleo IA (quinzenal) - 2026／08／13 17:22 EDT - Recording`.

⚠️ **Três armadilhas de nome, medidas em 16/08:**
1. O Drive troca `/` por `／` (**barra fullwidth**) nos nomes — grep ingênuo por data falha.
2. O arquivo do Meet **não tem extensão**; ferramenta que decide por sufixo (ffmpeg, whisper) precisa de
   cópia renomeada.
3. O doc nativo do Google volta com **0 bytes pelo mount**. Só `rclone cat` traz o conteúdo — e o nome no
   remote leva o `.md` que o rclone acrescenta na exportação, que o mount também mostra.

### A forma-alvo, tirada da geral de 30/07 que já está fechada

| campo | 30/07 (referência) | 13/08 (a fazer) |
|---|---|---|
| `recording_url` | `https://youtu.be/…` | vazio |
| `recording_type` | `youtube` | vazio |
| `youtube_url` | mesmo link | vazio |
| `minutes_text` | 14.473 chars | vazio |
| `minutes_url` | não usado | não usado |
| `minutes_posted_at` | carimbada | não |
| `suggested_champion_ids` | **5** | **0** |
| `curation_status` | `published` | `published` (já) |
| `attendance` | 54 linhas — 51 presentes, 3 ausentes | 34 linhas — **31 presentes, 3 ausentes** |

Portas prontas na plataforma: `meeting_minutes` (ata), `attendance_record` (presentes),
`champion_award` (protagonistas), `meeting_actions` (ações a monitorar), `event_write` (campos do evento).

### ⚠️ O buraco da conferência de presença

**Não existe Meeting Report do Google para 13/08.** A pasta `Meeting Reports` para em **09/07**, e o que
ela guarda é `YouTube analytics.csv`, **não lista de presença**. Ou seja: as 31 presenças não têm relatório
oficial contra o que reconciliar. As fontes disponíveis são o `chat.txt` e a transcrição (quem falou), que
sub-contam por natureza — quem assistiu calado não aparece.

📌 **Levar ao PM antes de mexer:** 31 presentes contra 51 na geral anterior é queda grande. Decidir se
(a) fica como os líderes registraram, (b) complementa pelo chat e transcrição assumindo o sub-conteo, ou
(c) reabre para registro. **Não selar o roster antes dessa decisão** — `roster_sealed_at` está nulo nas
duas reuniões, então selar agora seria estrear o carimbo justamente na que tem dúvida.

⚠️ **Repo é público, e este material é cheio de nome de gente.** Ata, ações e protagonistas entram na
**plataforma**, não em issue nem em PR. Nada de `_drive-docs/` pode ser citado com nome em documento
versionado.

---

## ⏰ ITEM 2 — #1710, prazo 24/08. Segue o item de maior risco de data.

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

## ITEM 3 — o portão legal do SPEC #905, com prazo de 30/09

O cron `lgpd-anonymize-premember-monthly` está **inativo de propósito**: o SPEC #905 o registrou dormante
atrás de um checklist de parecer legal (**R1–R5**), com prazo máximo de ativação sugerido em **2026-09-30**.

R1–R5 são decisões **de fora da engenharia**: ratificar a janela de retenção (recomendação legal: 2 anos
rejeitado / 1 ano desistente, contra os 5 anos do comando atual), limitar no tempo a exclusão da coorte
#935, mapear e purgar os **binários externos de vídeo** (não alcançáveis por SQL — precisa de EF ou
runbook), confirmar a **base legal Art. 11 I** para coleta de voz/vídeo, e as entradas de RoPA.

**Lacuna é LATENTE, não viva:** medido pelo anchor da própria função, **0 candidatos a 5 anos e 0 a 3
anos**, sobre 170 candidaturas. ⚠️ **Re-medir pelo anchor, nunca por `created_at`** — o `created_at`
mínimo é 2026-03-14, a data da migração da plataforma, não do fato.

📌 **Levar ao PM:** os R1–R5 são dele (ou de assessoria). O guard do #1812 já exige que o horizonte
declarado na tabela seja igual ao argumento do job — ratificar a janela move os dois juntos.

---

## ITEM 4 — #1822: a triagem das 56 é decisão do PM

`_audit_undeclared_state_domain()` fixou a base: **270 colunas examinadas, 208 com domínio declarado,
6 por FK, 56 sem guarda** em 44 tabelas. O ratchet só encolhe, e **o #1822 não declarou domínio em nada**.

📌 **Decisão:** quais das 56 merecem `CHECK`. Nem todas devem — `admin_audit_log.action` é vocabulário
que cresce de propósito (o CHECK dele é regex de formato). E declarar domínio sobre dado vivo tem risco
próprio: o ensaio bateu em linha de `pilots` fora do domínio na primeira tentativa (lição do #1587).
A lista sai da própria RPC.

---

## ITEM 5 — o resto da classe do #1805/#1809: resolução por STATEMENT

**Já medido no #1822, não refazer:** o ponto cego tem **377 pares em 294 funções** — 91 inertes, 48 com
uma só relação com domínio, **238 de ambiguidade real**.

🔴 **O atalho dos 48 foi ensaiado e não existe** (51 violações, zero defeitos). Sobram os **238**, e
fechá-los exige **resolver por STATEMENT** (qual tabela cada `UPDATE`/`DELETE`/`FROM` alcança), não por
corpo. Não há caminho barato.

---

## ITEM 6 — #1814, o `archive` sem destino (aberta de propósito)

`cleanup_type='archive'` declara duas políticas e não há destino de arquivamento na plataforma. Seguem
**ativas e descobertas**, na base declarada do ratchet `_audit_retention_policy_coverage()`. Primeira
mordida em **2028-03-13** (board) e **2029-03-05** (presença) — **sem urgência**.

⚠️ **Risco de produto:** pontos de gamificação leem histórico de presença (`sync-attendance-points`).
Tirar linhas da tabela quente pode mudar cálculo retroativo.

---

## ITEM 7 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist.
- **8 verbos de curadoria sem porta MCP nenhuma. Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas decidem escrita só por capacidade. **Do #1784:** 10 filhas sem gate
  de leitura. Todas com zero linhas confidenciais hoje.

---

## ITEM 8 — o que fecha com uso real, não com código

- **#1586** fecha na primeira chamada real de `interview_manage action='rescue_unbooked'`, conferindo na
  linha nova do audit `actor_id` **não nulo** e `dispatch_source='manual'` (cap 3, separado do cap 1 do
  cron). ⚠️ **Não despachar para testar.**
- **Funil, prazo 28/08.** Falta `booked_at`. **Nenhum número de conversão pode ser publicado** até uma
  linha carimbar reserva. **Não provocar despacho** — o cron gera linhas sozinho. Exigir
  `instrumented = true` **e** `booking_token_md5` na linha nova.

---

## ITEM 9 — dívida conhecida, com dono

- **#1592** — barreira contra DDL nova. **468 de 1105** SECDEF alcançáveis por chamador anônimo (15/08).
  Todas gateiam por `auth.uid()` — profundidade, não porta aberta.
- **#1777**, **#1776**, **#1664 fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do PM),
  **#1729**, **#1742**, **#1744**, **#1728** (20 RPCs da mesma classe).
  **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.
- **#1205** só fecha com o William no `/profile` LOGADO.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO — nunca o fragmento da varredura.** Rota que funcionou
   no #1805, #1809 e #1813, e que **não transcreve nada**: prove por md5 normalizado que a captura no
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
   mergeie antes de aplicar a próxima.
8. **Mudança de schema exige `npm run db:types` na MESMA PR** (o gate `gen-types-drift` pega). **RPC nova
   conta, e RPC removida também. Coluna nova também.**
9. **Mexeu em descrição de tool no `nucleo-mcp/index.ts`? Regenere o manifesto:**
   `node scripts/generate-mcp-manifest.mjs`. **E confira o `ef_version` ANTES de deployar:**
   `curl .../nucleo-mcp/health` contra o literal em `index.ts` — se estiverem IGUAIS, bumpe, senão
   `/health` deixa de ser testemunha do deploy. Pós-deploy, o smoke tem de incluir **`tools/list`**, não
   só `initialize`. ⚠️ `deno` **não está instalado nesta máquina** — quem roda `deno lint`/`check` é o CI.
10. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
    migration. (`CREATE OR REPLACE` de função **existente** preserva as ACLs.)
11. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
12. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE** — fronteira de palavra é `\y`. E o Postgres **recusa
    contagem acima de 255**.
13. ⚠️ **Guard de texto acusa a própria documentação.** Separe prosa de SQL executável antes do assert (o
    filtro de `--` **não** pega blocos `COMMENT ON`).
14. 📌 **Prove que o guard fica VERMELHO.** Plante a violação numa transação abortada. **E faça-o devolver
    todos os itens examinados com um booleano** — senão lista vazia não se distingue de cegueira.
15. 📌 **Ensaie o ramo que nunca rodou.** Envelhecer linhas reais para dentro do corte numa transação
    abortada foi o que provou os `DELETE` do #1812; plantar tabela e constraint provou o ratchet do #1822.
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
28. 🆕 ⚠️ **Drive: barra fullwidth (`／`) nos nomes, gravação do Meet SEM extensão, doc nativo com 0 bytes
    pelo mount.** Ver ITEM 1. E `~/.local/bin/rclone` (1.74), nunca o do apt.
