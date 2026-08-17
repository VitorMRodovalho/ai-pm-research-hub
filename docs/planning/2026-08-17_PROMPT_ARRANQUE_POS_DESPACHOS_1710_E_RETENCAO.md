# Prompt de arranque — verificar o que ficou em movimento, a véspera do #1710 e a estreia da retenção

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_RETENCAO_E_1826.md` (o ITEM 4 dele,
> o não commitado, foi mergeado na PR #1827).
> Handoff da reunião: `docs/planning/2026-08-17_handoff_reuniao_geral_13ago_publicada.md`
> Skill nascido na sessão: `.claude/skills/champion-metrics/`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **17/08/2026, 03:08 UTC** e
vários se movem sozinhos, alguns em questão de horas. Re-meça com tool call na mesma volta em que o
número entrar numa decisão, num commit, numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** Sem `--paginate` já devolveu 0 havendo 3.
- **`gh pr checks` cresce durante a espera.** Espere os pendentes; não conte linhas. (Na #1827 foram
  de 9 para 11 durante a espera.)
- **Varra `pg_proc`, não o repositório** — e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo, sempre.
- **`replace_all` casa a string, não a intenção.** Conte as ocorrências e diffe contra o original.
- **"Zero linhas hoje" não é ausência de risco.** O número que decide é a data da primeira mordida.
- **Cron inativo pode ser governança**, não esquecimento.
- **Se a API tem TETO, a ordem em que você chama VIRA o critério.** Pergunta de triagem: *"se eu
  chamar N+1 vezes, o que decide quem fica de fora?"*
- **Ranking sem teste de robustez é opinião com número.** Compare **conjunto**, não ordem.
- 🆕 🔴 **O conector CACHEIA `tools/list`, e o schema que ele te entrega pode estar DESATUALIZADO.**
  Em 16/08 o conector ofereceu `interview_manage` com 4 ações; o EF publicado tem **7**
  (`rescue_unbooked`, `block`, `unblock` estavam faltando). Eu quase declarei "não existe porta".
  **Antes de dizer que uma ação não existe, leia o `z.enum` em
  `supabase/functions/nucleo-mcp/index.ts`.** A chamada funciona mesmo com o schema em cache.
- 🆕 ⚠️ **Antes de agir sobre uma fila, veja se a MÁQUINA já a cobre.** Dos 12 candidatos elegíveis,
  4 estavam prestes a ser pegos pelo cron; despachá-los teria duplicado convite.
- 🆕 ⚠️ **Antes de escalar a gravidade, confira QUEM CHAMA** e **quem já foi rejeitado**: 7 das 19
  linhas do recorte eram candidaturas encerradas.

---

## Estado (17/08, 03:08 UTC)

`main` em **`2ad2cbbe`**, **zero PRs abertas**, **43 invariantes com zero violações**,
**zero eventos de bypass** na janela de 7 dias (todos os commits com `(#N)`).
EF `nucleo-mcp` em **`ef_version` 2.102.0**.
⚠️ O `/health` responde em `https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health`;
`nucleoia.vitormr.dev/mcp/health` devolve **404**.

Nenhuma migration, nenhuma mudança de schema nas duas últimas sessões.

---

## 🔴 ITEM 1 — verificar o que ficou em movimento (o mais perecível de todos)

A sessão de 16/08 disparou quatro coisas com efeito no relógio. **Conferir antes de qualquer outra
coisa**, porque as janelas passam.

### (a) 6 resgates manuais despachados em 17/08 02:45 UTC

Seis candidaturas `interview_pending` do ciclo 4, todas com o cap do cron já esgotado
(`interview_auto_rescue_count = 1`), receberam `interview_manage action='rescue_unbooked'`.
Só **dois** membros do comitê são elegíveis ao rodízio de `researcher` (os demais não têm URL de
agendamento, e um terceiro está com `can_interview = false`); resolva os nomes em
`selection_committee`, não aqui. Distribuição conferida: **4 para o entrevistador que estava com
zero conduzidas no ciclo, 2 para o outro** — um bloqueio curto no segundo desviou os dois primeiros
despachos, com `unblock` logo em seguida e **zero bloqueios ativos** ao fim.

Todas com `email_sent: true`, `dispatch_source='manual'`, cap 3 com 1 consumido, e **autor
preservado** no `admin_audit_log`.

📌 **Conferir agora:** alguma delas registrou `first_opened_at` ou, melhor, **`booked_at`**.

### (b) 3 candidaturas ficam elegíveis ao cron às 04:01 UTC, e o cron roda 15:30 UTC

Três candidaturas com `interview_auto_rescue_count = 0` saem da carência de 10 dias em
**17/08 04:01 UTC**. O `selection-unbooked-rescue-daily` roda **15:30 UTC**. Elas foram deixadas
**de propósito** para a máquina.

📌 **Conferir:** o cron pegou as 3, e **não** houve convite duplicado com o lote manual.
Uma quarta só sai da carência em **25/08**.

### (c) #1586 — a condição de fecho foi satisfeita

A issue estava aberta esperando a **primeira chamada real** de `rescue_unbooked` com `actor_id` não
nulo e `dispatch_source='manual'`. Aconteceu seis vezes em 17/08 02:45 UTC, como trabalho real
pedido pelo PM, **não como teste**.

📌 **Conferir as 6 linhas de audit e FECHAR a #1586** se confirmarem.

### (d) A varredura de retenção estreia 04:25 UTC de 17/08

Às 03:08 UTC ainda tinha **zero corridas** (`admin_audit_log` com `action='data_retention.sweep'`).

📌 **Conferir:** `get_lgpd_cron_health` **impersonado** sai de `never_ran:true`, e o audit ganha
**uma** linha com `affected_total = 0` (nenhuma política morde antes de **09/09**).
⚠️ RPC que resolve o chamador por `auth.uid()` devolve "Not authenticated" para `service_role`:
impersone em transação abortada, `set_config('request.jwt.claims', ...)` **antes** do
`SET LOCAL ROLE`, e `RESET ROLE` antes de conferir o efeito.
🔴 **Se a corrida falhou, o painel só vira vermelho depois de 2 dias de silêncio.**

---

## ITEM 2 — os 2 aprovados e já ativos, bloqueado no PM

Duas candidaturas do ciclo 4 estão `approved`, os candidatos **já são membros ativos**, e nenhum dos
dois passou por entrevista. Eles têm `cutoff_approved_email_sent_at` **nulo** e status `approved`,
o que os deixa **fora do cron de resgate para sempre** (o filtro é `status='interview_pending'`), e
faz `rescue_unbooked` recusá-los.

⚖️ **Decidido pelo PM (16/08):** agendar direto com `interview_manage action='schedule'` nomeando
em `interviewer_ids` **o entrevistador que já acumulava as conduzidas do ciclo** (o mesmo que ficou
com 2 dos 6 resgates). Com isso o total da rodada fecha **4 a 4** entre os dois elegíveis.

📌 **Falta apenas data e hora de cada um.** Não inventar horário de compromisso com pessoa real:
pedir ao PM ou combinar com o entrevistador antes. **Os nomes estão na plataforma, não aqui.**

---

## ⏰ ITEM 3 — #1710, prazo 24/08

Config conferida em 17/08 (re-conferir):

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08 (a véspera), pelos dois caminhos independentes** — a consulta externa que
reproduz coorte + carência, e o ensaio da própria função — e só então levar o número ao PM.
⚠️ **É TETO, e encolhe a cada presença registrada.** Última medição conhecida (15/08): 43 selam,
80 faltas, 40 pessoas. **Não recitar.**

**Como ensaiar sem esperar:** bloco `DO` que desloca `grace_days` para dar o mesmo corte que 14 darão
em 24/08, **recuando também o `floor_date`** (senão volta `skipped: before_floor`), terminando em
`RAISE EXCEPTION`. **Confira a config depois.**

🆕 ⚠️ **A coorte MUDOU em 16/08:** a presença da geral de 13/08 subiu de 31 para 45, com **14 linhas
cobertas por líder**. Não reaproveitar recorte anterior a 16/08.

⚖️ **Decidido (15/08):** células fora do alcance de líder ficam com o **GP pela grade geral**.
📌 Lista **nominal** ao GP **na conversa, não em issue nem PR** (repo público).

---

## ITEM 4 — funil de entrevistas, prazo 28/08

Medido em 17/08 03:08 UTC: **103 linhas, 9 instrumentadas, 1 abertura, 0 reservas.**
As instrumentadas saltaram de 3 para 9 por causa dos 6 resgates manuais, e **todas as 9 têm
`booking_token_md5`** — ou seja, hoje uma reserva **é mensurável**.

🔴 **Nenhum número de conversão é publicável** enquanto `booked_at` for 0.
⚠️ **Não provocar despacho para testar.** O cron gera linhas sozinho.

---

## ITEM 5 — #1664 e #1614: a tela que o PM reclama de novo

**#1664 aberta**, criada em 07/08 a partir de reclamação do PM sobre o cartão *"Reservas de
entrevista sem candidatura"* no topo da aba Pipeline de `/admin/selection`. Reclamada **de novo em
16/08**, sobre o mesmo print.

Re-medido em 17/08, e **nada se moveu** desde a classificação de 13/08: **36** não resolvidas,
**31** acionáveis, **11** do endereço do próprio operador, **36 de 36** já com `suppressed_at`
(o `log cortado` de toda linha), 23 e-mails distintos, 1 endereço sintético `@example.com`.

A contradição central: o cartão ocupa o topo da aba de **avaliação** cobrando reparo de um conjunto
onde a supressão **já foi aplicada em 100% das linhas**.

📌 A raiz é a **#1614** (o endereço com que a pessoa **agenda** nunca é capturado), **adiada por
decisão do PM em 05/08**. Reabrir a decisão é conversa com o PM, não conserto unilateral.

---

## ITEM 6 — o portão legal do SPEC #905, prazo 30/09

Cron `lgpd-anonymize-premember-monthly` **inativo de propósito** (`active=false`, `15 4 1 * *`),
dormante atrás do checklist **R1–R5**, com prazo de ativação em **2026-09-30**.

R1–R5 são decisões **de fora da engenharia**: ratificar a janela de retenção (recomendação legal:
2 anos rejeitado / 1 ano desistente, contra os 5 anos do comando atual), limitar no tempo a exclusão
da coorte #935, mapear e purgar os **binários externos de vídeo** (fora do alcance do SQL), confirmar
a **base legal Art. 11 I** para voz/vídeo, e as entradas de RoPA.

⚠️ **Re-medir pelo anchor da própria função, nunca por `created_at`.**
📌 O guard do #1812 exige que o horizonte da tabela seja igual ao argumento do job.

---

## ITEM 7 — #1826, aberta em 16/08

**Seleção por métrica: tornar o critério um dado e abrir a rota de decisão no MCP.**
`type:feature`, `priority:low`, `mcp-server`, `meeting-notes`.

- **Fase A:** `champions_awarded` **não tem coluna de comentário**; a métrica mora como texto dentro
  de `justification`. Guardar estruturado (`jsonb`) torna a seleção auditável entre reuniões.
- **Fase B:** o MCP cobre o **ato** (`award`/`revoke`) e não a **decisão**. Falta `action='rank'` e o
  teto exposto no envelope, **derivado do corpo da RPC**.
- **Fase C:** ingestão da transcrição, que destrava o cálculo server-side.

📌 Conversa com o **EPIC #1780**: aqui a porta que **muda estado** existe e a que **informa a
decisão** falta, que é a ordem mais perigosa das duas.

---

## ITEM 8 — #1822: a triagem das 56 é decisão do PM

`_audit_undeclared_state_domain()` fixou a base: **270 colunas examinadas, 208 com domínio, 6 por
FK, 56 sem guarda** em 44 tabelas (16/08). O ratchet só encolhe.

📌 **Decisão:** quais das 56 merecem `CHECK`. Nem todas devem — `admin_audit_log.action` é
vocabulário que cresce de propósito. Declarar domínio sobre dado vivo tem risco próprio (o ensaio
bateu em linha de `pilots` fora do domínio). **A lista sai da própria RPC.**

---

## ITEM 9 — o resto da classe do #1805/#1809: resolução por STATEMENT

**Já medido, não refazer:** **377 pares em 294 funções** — 91 inertes, 48 com uma só relação com
domínio, **238 de ambiguidade real**. 🔴 **O atalho dos 48 foi ensaiado e não existe** (51 violações,
zero defeitos). Os 238 só saem por **resolver por STATEMENT**. Não há caminho barato.

---

## ITEM 10 — #1814, o `archive` sem destino (aberta de propósito)

Duas políticas `cleanup_type='archive'` sem destino de arquivamento na plataforma, ativas e
descobertas, na base declarada do ratchet (**base = 3**; a 4ª derruba o CI). Primeira mordida em
**2028-03-13** e **2029-03-05**. Sem urgência.
⚠️ Pontos de gamificação leem histórico de presença: tirar linhas pode mudar cálculo retroativo.

---

## ITEM 11 — o resto do EPIC #1780

Quatro cortes saíram (#1778, #1784, #1791, #1779). Segue aberto: agregada de comentário e anexo
**não existe nem em SQL**; **4 definições de autoridade** para a mesma ação; **8 verbos de curadoria
sem porta MCP** (escopo é do PM); bases que só encolhem, **7** filhas de escrita e **10** de leitura.

---

## ITEM 12 — dívida conhecida, com dono

- **#1592** — barreira contra DDL nova. **468 de 1105** SECDEF alcançáveis por anônimo (15/08);
  todas gateiam por `auth.uid()` (profundidade, não porta aberta).
- **#1777**, **#1776**, **#1664 fase 2**, **#1762**, **#1729**, **#1742**, **#1744**, **#1728**.
  **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.
- **#1205** só fecha com o membro do caso acessando o `/profile` **LOGADO** (nome está na issue).
- **Follow-ups:** #1004, #1008, #1403 (~set/2026), #1494, classe B do #1487, 20 termos não-GO.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO — nunca o fragmento da varredura.** Prove por md5
   normalizado que a captura no repositório é idêntica ao corpo vivo
   (`scripts/audit-rpc-body-drift.mjs`, `drifted_definite = 0`), extraia o bloco **do arquivo**,
   substituição **contada**, **diffe**, e monte a migration por concatenação.
2. ⚠️ **Captura antiga pode usar `CREATE FUNCTION` sem `OR REPLACE`.** Troque por `CREATE OR
   REPLACE`, que **preserva as ACLs**.
3. 🔴 **`ADD CONSTRAINT` com nome auto-gerado + `WHEN duplicate_object THEN NULL` engole a MUDANÇA de
   domínio.** Troca de domínio é `DROP CONSTRAINT IF EXISTS` + `ADD`.
4. **`apply_migration` recebe o SQL como STRING** e **cria a linha de tracking com timestamp
   PRÓPRIO** — renomeie o arquivo local; `migration repair` é desnecessário.
5. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com zero PRs abertas.
6. **Mudança de schema exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
7. **Mexeu em descrição de tool? Regenere o manifesto** (`node scripts/generate-mcp-manifest.mjs`)
   e **confira o `ef_version` ANTES de deployar**. Pós-deploy o smoke inclui **`tools/list`**.
   ⚠️ `deno` **não está instalado nesta máquina**; quem roda lint/check é o CI.
8. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** `REVOKE ... FROM PUBLIC, anon` na MESMA migration.
9. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 vai **dentro** da função.
10. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE** — fronteira de palavra é `\y`.
11. 📌 **Prove que o guard fica VERMELHO** numa transação abortada, **e faça-o devolver todos os itens
    examinados com um booleano** — senão lista vazia não se distingue de cegueira.
12. **Teste novo entra nas DUAS whitelists do `package.json`.**
13. **Suíte offline (~57 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass.** Suíte com DB: ~13 min, **escreve em produção e não tolera concorrência**.
14. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`, e nunca escreva o padrão sem
    intenção de fechar, **nem para citá-lo**.
15. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` e confirme com
    `git merge-base --is-ancestor origin/main HEAD`. E **nunca `git add -A`**: adicione por nome.
16. ⚠️ **Repo é PÚBLICO.** Nome de pessoa não entra em issue, PR nem doc — **conte a população**.
    Rode a varredura de nome próprio antes de publicar (fez-se em 16/08, zero nos 5 arquivos).
17. ⚠️ **RPC com `auth.uid()` devolve "Not authenticated" para `service_role`.**
18. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background** — o pipe segura a saída.
19. ⚠️ **O build leva 2m30s–4m40s: rode em background e confira o `Complete!`.**
20. ⚠️ **Drive: barra fullwidth (`／`), gravação do Meet SEM extensão, doc nativo com 0 bytes pelo
    mount** (só `rclone cat`). E `~/.local/bin/rclone` (1.74), nunca o do apt.
21. ⚠️ **A capacidade pode estar FORA do repo.** O ferramental de YouTube vive em
    `~/projects/_pmo/youtube/`, apontado pelo header de `scripts/refresh-youtube-playlists.mjs`.
    A playlist sai do SSOT `src/data/youtube-playlists.ts` por **chave semântica**.
22. ⚠️ **A gravação CONTINUA depois do encerramento da pauta.** Antes de publicar, leia o **fim** da
    transcrição procurando o handoff aos líderes. O corte sai da faixa **`mov_text`** embutida
    (`ffmpeg -map 0:s:0 -c:s srt`), corte com `-t <fim> -map 0 -c copy`, e **prove por grep** que os
    marcadores do trecho restrito voltam zero.
23. ⚠️ **YouTube não substitui arquivo** — corrigir é sempre item novo. **E a API mente por
    propagação:** `videos.list` já devolvia 0 enquanto `playlistItems.list` ainda mostrava.
24. 🆕 🔴 **O conector cacheia `tools/list`.** Leia o `z.enum` em `nucleo-mcp/index.ts` antes de dizer
    que uma ação não existe.
25. 🆕 ⚠️ **`rescue` e `rescue_unbooked` são casos COMPLEMENTARES.** `rescue` exige status
    `interview_scheduled` e levanta **`P0023`** fora disso; `rescue_unbooked` exige
    `interview_pending`. Chamar o errado falha nos doze.
26. 🆕 🔴 **Despacho em LOTE quebra o rodízio.** `now()` é da transação, os `dispatched_at` empatam, o
    LRD não consegue alternar e o desempate por `member_id` manda **tudo para uma pessoa só**.
    Despache **um a um** e confira `resolved_evaluator_id` a cada volta.
27. 🆕 🔴 **SQL direto por `service_role` registra ato humano como 'cron' com actor nulo.** Use a porta
    MCP, que preserva o autor no `admin_audit_log`.
28. 🆕 📌 **`interview_manage action='block'/'unblock'`** (#1590 onda C) é a alavanca declarada para
    tirar alguém do rodízio por período. Prefira janela curta com `ends_on` explícito e **prove que a
    fila mudou** antes de despachar.
