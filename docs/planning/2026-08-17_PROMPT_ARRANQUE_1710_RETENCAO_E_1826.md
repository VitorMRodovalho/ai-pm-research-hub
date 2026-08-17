# Prompt de arranque — a véspera do #1710, a estreia da retenção, o funil de 28/08 e o #1826

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_REUNIAO_13AGO_1710_E_905.md` (o ITEM 1 dele,
> a reunião geral de 13/08, foi entregue por inteiro).
> Handoff anterior: `docs/planning/2026-08-17_handoff_reuniao_geral_13ago_publicada.md`
> Mapa da Fase 1 do EPIC: `docs/audit/EPIC_1780_FASE1_MAPA_BOARD_CARD.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **17/08/2026, 02:25 UTC** e
vários se movem sozinhos. Re-meça com tool call na mesma volta em que o número entrar numa decisão,
num commit, numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** `gh api dependabot/alerts` **sem `--paginate`**
  já devolveu 0 abertos havendo 3.
- **`gh pr checks` cresce durante a espera.** Espere os pendentes; não conte linhas.
- **Varra `pg_proc`, não o repositório** — e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo, sempre.
- **Um verificador que lê o diretório inteiro inclui o artefato que está sendo verificado.**
- **`replace_all` casa a string, não a intenção.** **Conte as ocorrências** e **diffe contra o
  original**. (Funcionou em 16/08: script que exige casamento exato de 1 por par e aborta fora disso.)
- **Corrigir UM literal morto pode ser conserto INERTE.** Varra todas as colunas do predicado.
- **"Zero linhas hoje" não é ausência de risco.** O número que decide é a **data da primeira mordida**.
- **Antes de implementar política declarada em tabela, procure quem já a executa.** **Cron inativo
  pode ser governança.**
- **Estreitar o conjunto de candidatos para forçar unicidade não é resolver, é chutar.**
- **No predicado que CONTA, use só sinal do mesmo grão do que está sendo medido.** Trigger é de tabela,
  não de coluna.
- **Filtrar por EXTENSÃO perde arquivo cujo nome não tem extensão.** Filtre por MIME.
- 🆕 🔴 **Se a API tem TETO, a ordem em que você chama VIRA o critério de seleção.** No 13/08 concedi
  reconhecimentos na ordem em que lembrei dos nomes; o teto barrou os dois últimos, e medido depois
  **a última vaga tinha ficado com o 5º colocado em todos os eixos**. Cada chamada devolvia `ok:true`.
  Pergunta de triagem: *"se eu chamar N+1 vezes, o que decide quem fica de fora?"*
- 🆕 ⚠️ **Publicar mídia gravada exige conferir o FIM, não a duração.** Ver ITEM 12.
- 🆕 📌 **Métrica gravada em campo de prosa é registro, não é dado.** Decida onde o critério vai morar
  **antes** de calculá-lo.
- 🆕 📌 **Ranking sem teste de robustez é opinião com número.** Re-pontue variando pesos e publique em
  quantas combinações o **conjunto** do top-N se mantém. Compare conjunto, não ordem.
- ⚠️ **Antes de escalar a gravidade, confira QUEM CHAMA.**

---

## Estado (17/08, 02:25 UTC)

`main` em **`a5793a35`**, **zero PRs abertas**, **43 invariantes com zero violações**.
**Zero eventos de bypass na janela de 7 dias** (69 commits em `main`, **todos** com `(#N)` no assunto;
nenhum push direto). Nenhuma migration nem mudança de schema na sessão de 16/08.
EF `nucleo-mcp` em **`ef_version` 2.102.0**, medido ao vivo.

🆕 **O `/health` responde em `https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health`.**
`https://nucleoia.vitormr.dev/mcp/health` devolve **404** (a rota do domínio custom é o transporte MCP,
não o health). O mesmo payload mostra as três superfícies: `/mcp` 342 tools, `/semantic` 54, `/actions`.

⚠️ **Não rastreados, criados em 16/08 e aguardando decisão do PM:**
`.claude/skills/champion-metrics/` e `docs/planning/2026-08-17_handoff_reuniao_geral_13ago_publicada.md`.
**Nunca `git add -A`** — há dezenas de docs de planning não rastreados; adicione por nome.

---

## ⏰ ITEM 1 — #1710, prazo 24/08. É o item de maior risco de data.

Config **conferida no banco em 17/08 02:25 UTC** (re-conferir):

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que reproduz
coorte + carência, e o ensaio da própria função — e só então levar o número ao PM.
⚠️ **É TETO, e encolhe a cada presença registrada por um líder.** Última medição conhecida (15/08):
43 selam, 80 faltas, 40 pessoas. **Não recitar — re-medir.**

**Como ensaiar sem esperar:** bloco `DO` que faz `UPDATE` em `platform_settings` deslocando `grace_days`
para dar o mesmo corte que 14 darão em 24/08, **recuando também o `floor_date`** (senão volta
`skipped: before_floor`), e terminando em `RAISE EXCEPTION` com o resultado. **Confira a config depois.**

⚖️ **DECIDIDO pelo PM (15/08), NÃO re-litigar:** as células que nenhum líder de tribo alcança ficam com
o **GP, pela grade geral**. Nada muda no código.
📌 **Ação da véspera:** levar ao GP a lista **nominal** dessas células — **na conversa, não em issue nem
em PR** (repo público).

🆕 **Cuidado novo, vindo do fecho de 13/08:** a presença daquela reunião subiu de 31 para 45 porque 14
membros foram **cobertos por líder** com base em prova documental. `registered_by` distingue cobertura
de auto-check-in, e **o #1710 raciocina sobre a coorte de presenças**. Re-meça depois dessa mudança;
não reaproveite recorte anterior a 16/08.

---

## 🔔 ITEM 2 — a primeira corrida da varredura de retenção (imediato)

O cron `data-retention-sweep-daily` (`25 4 * * *`, **ativo**) tinha, às **02:25 UTC de 17/08**,
**zero corridas** (`admin_audit_log` com `action='data_retention.sweep'` = 0, `max(created_at)` nulo).
A estreia é **04:25 UTC de 17/08** — ou seja, provavelmente **já aconteceu** quando esta sessão abrir.

**Conferir no arranque:**
- `get_lgpd_cron_health` **impersonado** deve ter saído de `never_ran: true` para `days_since_last_run`
  perto de zero. ⚠️ RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para
  `service_role`: impersone em transação abortada, `set_config('request.jwt.claims', ...)` **antes** do
  `SET LOCAL ROLE`, e `RESET ROLE` antes de conferir o efeito.
- `admin_audit_log` deve ter ganhado **uma** linha `action = 'data_retention.sweep'` com
  `affected_total = 0` (nenhuma política morde antes de **09/09**).

🔴 **Se a corrida falhou, o painel só vira vermelho depois de 2 dias de silêncio.** Não espere o
vermelho para investigar.

📅 Calendário de mordidas: `notifications` **09/09**, `visitor_leads` 03/10, `data_anomaly_log` 2027,
archive 2028/2029.

---

## ITEM 3 — funil de entrevistas, prazo 28/08

Última medição conhecida (15/08): 97 linhas, 3 instrumentadas, 1 abertura, 0 reservas. **Re-medir.**

🔴 **Nenhum número de conversão é publicável** até uma linha carimbar `booked_at`. Exigir
`instrumented = true` **e** `booking_token_md5` na linha nova.
⚠️ **Não provocar despacho para testar** — o cron gera linhas sozinho.

🔁 **#1586 fica ABERTA de propósito:** fecha na primeira chamada **real** de
`interview_manage action='rescue_unbooked'`, conferindo na linha nova do audit `actor_id` **não nulo**
e `dispatch_source='manual'` (cap 3, separado do cap 1 do cron).

---

## ITEM 4 — o não commitado de 16/08 é decisão do PM

A sessão de 16/08 fez **zero commits, zero PRs, nenhuma migration**. Ficaram em disco:

- `.claude/skills/champion-metrics/` — SKILL.md + 2 scripts, já exercidos de ponta a ponta contra a
  transcrição real (reproduziram 26 falantes, 429 turnos, 13.832 palavras e o mesmo top-3).
- `docs/planning/2026-08-17_handoff_reuniao_geral_13ago_publicada.md`.

Suíte offline passou em 16/08: **6.482 testes, 0 falhas, 732 skips**, ~57 s. **Re-rodar antes da PR.**

📌 **Perguntar ao PM se abre a PR.** Se abrir: branch de `origin/main` explícito, teste novo (se
houver) nas **duas** whitelists do `package.json`, e `Closes` só se for para fechar.

---

## ITEM 5 — o portão legal do SPEC #905, prazo 30/09

O cron `lgpd-anonymize-premember-monthly` está **inativo de propósito** (confirmado em 17/08:
`active = false`, `15 4 1 * *`). O SPEC #905 o registrou dormante atrás de um checklist de parecer
legal (**R1–R5**), com prazo máximo de ativação em **2026-09-30**.

R1–R5 são decisões **de fora da engenharia**: ratificar a janela de retenção (recomendação legal:
2 anos rejeitado / 1 ano desistente, contra os 5 anos do comando atual), limitar no tempo a exclusão da
coorte #935, mapear e purgar os **binários externos de vídeo** (não alcançáveis por SQL — precisa de EF
ou runbook), confirmar a **base legal Art. 11 I** para coleta de voz/vídeo, e as entradas de RoPA.

**Lacuna é LATENTE, não viva.** ⚠️ **Re-medir pelo anchor da própria função, nunca por `created_at`** —
o `created_at` mínimo é a data da migração da plataforma, não do fato.

📌 O guard do #1812 exige que o horizonte declarado na tabela seja igual ao argumento do job: ratificar
a janela move os dois juntos.

---

## ITEM 6 — #1826, aberta em 16/08 (nova)

**Seleção por métrica: tornar o critério um dado e abrir a rota de decisão no MCP.** `type:feature`,
`priority:low`, `mcp-server`, `meeting-notes`.

O achado que a originou: `award_champion` tem teto no corpo da função (`general` 3, `tribe` 2,
`deliverable` 1, mais 3 por concedente), e **o teto só se descobre batendo em `per_event_cap_reached`**.
A descrição da tool não o menciona.

- **Fase A (barata):** `champions_awarded` **não tem coluna de comentário**. A métrica de 13/08 está
  gravada como texto entre colchetes dentro de `justification`. Guardar estruturado (`jsonb`) torna a
  seleção auditável e comparável entre reuniões.
- **Fase B:** o MCP cobre o **ato** (`award`/`revoke`) e não a **decisão**. Falta `action='rank'` de
  leitura e o teto exposto no envelope, **derivado do corpo da RPC** e não duplicado como literal.
- **Fase C (cara):** ingestão da transcrição, que é o que destrava o cálculo server-side.

📌 Conversa com o **EPIC #1780**: lá são verbos de curadoria sem porta MCP; aqui a porta que **muda
estado** existe e a que **informa a decisão** falta, que é a ordem mais perigosa das duas.

---

## ITEM 7 — #1822: a triagem das 56 é decisão do PM

`_audit_undeclared_state_domain()` fixou a base: **270 colunas examinadas, 208 com domínio declarado,
6 por FK, 56 sem guarda** em 44 tabelas (medido 16/08). O ratchet só encolhe, e o #1822 **não declarou
domínio em nada**.

📌 **Decisão:** quais das 56 merecem `CHECK`. Nem todas devem — `admin_audit_log.action` é vocabulário
que cresce de propósito. E declarar domínio sobre dado vivo tem risco próprio: o ensaio bateu em linha
de `pilots` fora do domínio na primeira tentativa (lição do #1587). **A lista sai da própria RPC.**

---

## ITEM 8 — o resto da classe do #1805/#1809: resolução por STATEMENT

**Já medido no #1822, não refazer:** o ponto cego tem **377 pares em 294 funções** — 91 inertes, 48 com
uma só relação com domínio, **238 de ambiguidade real**.

🔴 **O atalho dos 48 foi ensaiado e não existe** (51 violações, zero defeitos). Sobram os **238**, e
fechá-los exige **resolver por STATEMENT** (qual tabela cada `UPDATE`/`DELETE`/`FROM` alcança), não por
corpo. Não há caminho barato.

---

## ITEM 9 — #1814, o `archive` sem destino (aberta de propósito)

`cleanup_type='archive'` declara duas políticas e não há destino de arquivamento na plataforma. Seguem
ativas e descobertas, na base declarada do ratchet `_audit_retention_policy_coverage()` (**base
declarada = 3**; a 4ª derruba o CI). Primeira mordida em **2028-03-13** e **2029-03-05** — sem urgência.

⚠️ **Risco de produto:** pontos de gamificação leem histórico de presença (`sync-attendance-points`).
Tirar linhas da tabela quente pode mudar cálculo retroativo.

---

## ITEM 10 — o resto do EPIC #1780

A Fase 1 mediu e quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto:

- **Agregada de comentário e de anexo não existe nem em SQL** — não é falta de porta MCP, é falta da
  função. Decidir com o PM se entra.
- **4 definições de autoridade para a mesma ação** — o #1778 unificou a do checklist.
- **8 verbos de curadoria sem porta MCP nenhuma. Escopo é do PM.**
- **Linha de base do #1791:** 7 filhas decidem escrita só por capacidade. **Do #1784:** 10 filhas sem
  gate de leitura. Todas com zero linhas confidenciais hoje.

---

## ITEM 11 — dívida conhecida, com dono

- **#1592** — barreira contra DDL nova. **468 de 1105** SECDEF alcançáveis por chamador anônimo
  (15/08). Todas gateiam por `auth.uid()` — profundidade, não porta aberta.
- **#1777**, **#1776**, **#1664 fase 2**, **#1762** (corrigir muda quem recebe candidato → precisa do
  PM), **#1729**, **#1742**, **#1744**, **#1728** (20 RPCs da mesma classe).
  **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.
- **#1205** só fecha com o membro do caso acessando o `/profile` **LOGADO** (o nome está na issue).
- **Follow-ups:** #1004, #1008, #1403 (~set/2026), #1494, classe B do #1487, 20 termos não-GO.

---

## ITEM 12 — o que ficou da reunião de 13/08 (fechada, mas com pendências do PM)

Entregue: ata **22.081 chars**, **10 ações**, presença **45** (48 linhas), **3 champions metrificados**
+ 5 confirmados, vídeo publicado com 37 capítulos na playlist `PLanpm8h-DzgQ`.

📌 **Pendências do PM:** as **10 ações estão sem prazo** (a reunião não declarou nenhum), e
`roster_sealed_at` **segue nulo** nas duas gerais. **45 é PISO, não total** — quem assistiu calado não
deixa rastro, e **não existe Meeting Report do Google para 13/08** contra o que reconciliar.

🔴 **O erro que não pode repetir:** a primeira publicação subiu íntegra e ficou pública ~3 min com
**69,5 s do bloco reservado aos líderes**, incluindo chamada nominal. A gravação do Meet **não para
quando a pauta pública acaba**.

**O procedimento que funcionou, para reusar:**
1. Ler o **fim** da transcrição procurando o handoff ("aos líderes de tribo, quem puder ficar").
2. O corte **não sai** do índice da transcrição (blocos grossos demais): sai da faixa **`mov_text`**
   embutida no MP4 — `ffmpeg -map 0:s:0 -c:s srt` dá timing por legenda.
3. Cortar sem reencode: `-t <fim> -map 0 -c copy`.
4. **Provar por grep** que os marcadores do trecho restrito voltam **zero** no SRT do cortado.
5. Publicar como **não-listado** se ninguém revisou o fim.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO — nunca o fragmento da varredura.** Rota que
   funcionou no #1805/#1809/#1813: prove por md5 normalizado que a captura no repositório é idêntica ao
   corpo vivo (`scripts/audit-rpc-body-drift.mjs` com `drifted_definite = 0`), extraia o bloco **do
   arquivo**, aplique substituição **contada**, **diffe**, e monte a migration por concatenação.
2. ⚠️ **Captura antiga pode usar `CREATE FUNCTION` sem `OR REPLACE`.** Troque por `CREATE OR REPLACE`,
   que ainda **preserva as ACLs**.
3. 🔴 **`ADD CONSTRAINT` com nome auto-gerado bate `duplicate_object`, e `WHEN duplicate_object THEN
   NULL` engole a MUDANÇA de domínio.** Troca de domínio é `DROP CONSTRAINT IF EXISTS` + `ADD`.
4. **`apply_migration` recebe o SQL como STRING.** Feche o risco rodando `audit-rpc-body-drift.mjs`
   depois: `drifted_definite` tem de voltar a **0**.
5. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO.** Renomeie o arquivo local para
   casar; `migration repair` é desnecessário.
6. 📌 **Divida a migration quando uma parte for crítica e a outra cosmética.**
7. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com **zero PRs abertas**.
8. **Mudança de schema exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`). RPC nova, RPC
   removida e coluna nova contam.
9. **Mexeu em descrição de tool no `nucleo-mcp/index.ts`? Regenere o manifesto:**
   `node scripts/generate-mcp-manifest.mjs`. **E confira o `ef_version` ANTES de deployar** contra o
   literal em `index.ts` — se estiverem IGUAIS, bumpe. Pós-deploy o smoke tem de incluir **`tools/list`**.
   ⚠️ `deno` **não está instalado nesta máquina**; quem roda `deno lint`/`check` é o CI.
10. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** O `REVOKE ... FROM PUBLIC, anon` vai na MESMA
    migration. (`CREATE OR REPLACE` de função **existente** preserva as ACLs.)
11. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 tem de estar **dentro** da função.
12. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE** — fronteira de palavra é `\y`. E o Postgres **recusa
    contagem acima de 255**.
13. ⚠️ **Guard de texto acusa a própria documentação.** Separe prosa de SQL antes do assert (o filtro de
    `--` **não** pega blocos `COMMENT ON`).
14. 📌 **Prove que o guard fica VERMELHO.** Plante a violação numa transação abortada, **e faça-o
    devolver todos os itens examinados com um booleano** — senão lista vazia não se distingue de cegueira.
15. 📌 **Ensaie o ramo que nunca rodou.**
16. **Teste novo entra nas DUAS whitelists do `package.json`** (`test` e `test:contracts`).
17. **Suíte offline (~57 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass:** rode o arquivo novo **com** `.env` e confira **zero skips**. Suíte com DB:
    ~13 min no CI, **escreve em produção e não tolera concorrência** (#1505).
18. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`. E nunca escreva o padrão de
    fechamento sem intenção de fechar, **nem para CITÁ-lo**.
19. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` explícito, e
    confira com `git merge-base --is-ancestor origin/main HEAD`.
20. ⚠️ **O `git status` do início da sessão pode estar STALE.** `git fetch` antes. E **nunca
    `git add -A`** — adicione por nome.
21. ⚠️ **`supabase` CLI aqui não está linkado**: `--project-ref ldrfrvwhxsmgaabwmaik` onde aceitar.
22. ⚠️ **Repo é PÚBLICO.** Achado de segurança se **corrige primeiro e descreve depois**. Nome de pessoa
    não entra em issue, PR nem doc — **conte a população, não a pessoa**. (Em 16/08 a varredura de nome
    próprio rodou antes de publicar issue, LL e handoff, e voltou zero nos três.)
23. ⚠️ **RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para `service_role`.**
24. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background** — o pipe segura toda a saída.
25. ⚠️ **Um contract test que faz shell-out de lint pode TRAVAR em vez de falhar.** Rode os lints antes.
26. ⚠️ **`pgrep -f "<padrão>"` casa o PRÓPRIO watcher.** **O build leva 2m30s–4m40s: rode em background
    e confira o `Complete!`.**
27. ⚠️ **O conector cacheia `tools/list`.** Ação nova dentro de tool existente evita o problema.
28. ⚠️ **Drive: barra fullwidth (`／`) nos nomes, gravação do Meet SEM extensão, doc nativo com 0 bytes
    pelo mount** (só `rclone cat`). E `~/.local/bin/rclone` (1.74), nunca o do apt.
29. 🆕 ⚠️ **A capacidade pode estar FORA do repo.** O ferramental de publicação no YouTube vive em
    `~/projects/_pmo/youtube/` (`upload.py`, `token.json` OAuth vivo, venv `~/.venvs/youtube`, pastas de
    precedente por reunião). O ponteiro está no **header de `scripts/refresh-youtube-playlists.mjs`**.
    A playlist sai do SSOT `src/data/youtube-playlists.ts` por **chave semântica**
    (`generalMeetings`), nunca por id colado. Varra `supabase/functions/` **e** `scripts/`, e siga
    ponteiros para `~/projects/_pmo/`.
30. 🆕 ⚠️ **YouTube não substitui arquivo** — corrigir é sempre vídeo novo. **E a API mente por
    propagação:** `videos.list` já devolvia 0 enquanto `playlistItems.list` ainda mostrava o item.
    Reconfira antes de declarar limpo, e remova o `playlistItem` órfão à mão.
