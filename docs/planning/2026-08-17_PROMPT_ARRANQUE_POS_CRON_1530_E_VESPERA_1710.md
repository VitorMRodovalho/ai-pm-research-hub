# Prompt de arranque: a corrida do cron, o funil e a véspera do #1710

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_POS_DESPACHOS_1710_E_RETENCAO.md`
> (o ITEM 1 dele foi verificado inteiro; a #1586 fechou).
> Handoff da sessão: `docs/planning/2026-08-17_handoff_item1_verificado_1586_fechada_1829_aberta.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **17/08/2026, entre 03:31 e
05:30 UTC**, e vários se movem sozinhos. Re-meça com tool call na mesma volta em que o número
entrar numa decisão, num commit, numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.** Sem `--paginate` já devolveu 0 havendo 3.
- **`gh pr checks` cresce durante a espera.** Espere os pendentes; não conte linhas.
- **Varra `pg_proc`, não o repositório**, e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo, sempre.
- **`replace_all` casa a string, não a intenção.** Conte as ocorrências e diffe contra o original.
- **"Zero linhas hoje" não é ausência de risco.** O que decide é a data da primeira mordida.
- **Cron inativo pode ser governança**, não esquecimento.
- **Se a API tem TETO, a ordem em que você chama VIRA o critério.**
- **Ranking sem teste de robustez é opinião com número.** Compare **conjunto**, não ordem.
- **O conector CACHEIA `tools/list`.** Antes de dizer que uma ação não existe, leia o `z.enum` em
  `supabase/functions/nucleo-mcp/index.ts`. A chamada funciona mesmo com o schema em cache.
- **Antes de agir sobre uma fila, veja se a MÁQUINA já a cobre.**
- 🆕 🔴 **Amostre os VALORES antes de classificar pelo nome da coluna.** As 56 do #1822 pareciam
  estado de ciclo de vida; **11 são UF**, e `pilots.scope` guarda um parágrafo.
- 🆕 🔴 **Driver de saúde que lê o AGENDADOR não vê a falha.** Pergunta de triagem: *"se o job
  rodar e quebrar todo dia, este sinal acende?"* (foi assim que nasceu a #1829).

---

## Estado (17/08, 05:30 UTC)

`main` em **`508ce10d`**, **zero PRs abertas**, **43 invariantes com zero violações**,
**zero eventos de bypass** na janela de 7 dias. EF `nucleo-mcp` em `ef_version` **2.102.0**.
⚠️ O `/health` responde em `https://ldrfrvwhxsmgaabwmaik.supabase.co/functions/v1/nucleo-mcp/health`;
`nucleoia.vitormr.dev/mcp/health` devolve **404**.

**Nenhuma migration e nenhuma mudança de schema nas três últimas sessões.**

---

## 🔴 ITEM 1: a corrida do cron das 15:30 UTC de 17/08

Três candidaturas em `interview_pending` saíram da carência às 04:01 UTC e estavam elegíveis ao
`selection-unbooked-rescue-daily` (`30 15 * * *`). Foram deixadas **de propósito** para a máquina.

📌 **Conferir:** o cron pegou as 3, e **não** houve convite duplicado com o lote manual de 02:45.
A pré-condição já foi provada (as 6 manuais têm `auto_count = 1` e só voltam à carência em
**27/08**; uma quarta candidatura só sai da carência em **25/08**), então o que falta é o desfecho.

Onde olhar: `admin_audit_log` com `action='selection.unbooked_rescue_cron_run'` traz
`rescued_count`, `refused_count`, `error_count` e as recusas com `gate_failed_code`.
⚠️ **Recusa de gate NÃO é erro**: este cron roda em modo `full`, e recusar quem não tem análise
de IA é o desfecho esperado.

## ITEM 2: os 2 aprovados e já ativos, bloqueado no PM

Duas candidaturas do ciclo 4 estão `approved`, os candidatos **já são membros ativos** e nenhum
passou por entrevista. Com `status='approved'` e `cutoff_approved_email_sent_at` nulo, eles ficam
**fora do cron de resgate para sempre**, e `rescue_unbooked` os recusa.

⚖️ **Decidido pelo PM (16/08):** agendar direto com `interview_manage action='schedule'` nomeando
em `interviewer_ids` **o entrevistador que já acumulava as conduzidas do ciclo** (o mesmo que
ficou com 2 dos 6 resgates). Com isso a rodada fecha **4 a 4** entre os dois elegíveis.

📌 **Falta apenas data e hora de cada um.** Não inventar horário de compromisso com pessoa real.
**Os nomes estão na plataforma, não aqui.**

## ⏰ ITEM 3: #1710, prazo 24/08

Config conferida em 17/08 e **intacta**:

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08, a véspera, pelos dois caminhos independentes**: a consulta externa que
reproduz coorte mais carência, e o ensaio da própria função. Só então levar o número ao PM.
⚠️ **É TETO, e encolhe a cada presença registrada.** Última medição conhecida (15/08): 43 selam,
80 faltas, 40 pessoas. **Não recitar.**

**Como ensaiar sem esperar:** bloco `DO` que desloca `grace_days` para dar o mesmo corte que 14
darão em 24/08, **recuando também o `floor_date`** (senão volta `skipped: before_floor`),
terminando em `RAISE EXCEPTION`. **Confira a config depois.**

⚠️ **A coorte MUDOU em 16/08:** a presença da geral de 13/08 subiu de 31 para 45, com 14 linhas
cobertas por líder. Não reaproveitar recorte anterior a 16/08.
⚖️ **Decidido (15/08):** células fora do alcance de líder ficam com o **GP pela grade geral**, e a
lista **nominal** vai ao GP **na conversa, não em issue nem PR**.

## ITEM 4: funil de entrevistas, prazo 28/08

Medido em 17/08: **103 linhas, 9 instrumentadas, 1 abertura, 0 reservas.** As 9 têm
`booking_token_md5`, ou seja, hoje uma reserva **é mensurável**. As 6 mais recentes não abriram
nem reservaram nos primeiros 50 minutos.

🔴 **Nenhum número de conversão é publicável** enquanto `booked_at` for 0.
⚠️ **Não provocar despacho para testar.** O cron gera linhas sozinho.

## ITEM 5: #1829, aberta hoje

**O painel de retenção fica verde com a varredura FALHANDO.** O driver mede o agendador
(`max(start_time)` sem filtro de status) e não o trabalho; e como `_data_retention_sweep_cron()`
não tem handler, no modo de falha o `admin_audit_log` **não ganha linha**. Hoje é latente: a
estreia de 04:25 UTC foi `succeeded`, `affected_total = 0`, painel `green`.

📌 A correção proposta mais forte é **vermelho quando o job rodou e o audit não ganhou linha**,
porque pega também a falha silenciosa. Ler `last_status` sozinho não pega.

## ITEM 6: #1822, a triagem das 56 é decisão do PM

Base: **270 examinadas, 208 com domínio, 6 por FK, 56 sem guarda** em 44 tabelas. A sessão de
17/08 amostrou os valores e separou em cinco classes (detalhe no handoff): geografia disfarçada
de estado, vocabulário que cresce de propósito, autoridade V4, enumeração técnica fechada, e um
falso positivo (`pilots.scope`).

📌 **Decisão: quais das 56 merecem `CHECK`.** A classe 4 (enumeração técnica fechada) é a de
melhor razão custo/benefício. A classe 1 **não é caso de `CHECK`**.

🆕 ⚠️ **Item próprio, ainda sem issue: a geografia já está suja.** `persons.state` tem `Goiás` com
`GO` (13 linhas nas duas grafias) e três grafias de um mesmo lugar (`VA`, `Virginia`, `Virgínia`,
4 linhas); `members.state` tem `Goiás` (4) e `Setúbal` (1); `volunteer_applications.state` tem
`11` (2 linhas); `selection_applications.state` tem string vazia (1). O conserto é normalização
com FK para `chapter_registry`, não `CHECK`.

## ITEM 7: o portão legal do SPEC #905, prazo 30/09

Cron `lgpd-anonymize-premember-monthly` **inativo de propósito** (`active=false`, `15 4 1 * *`),
dormante atrás do checklist **R1 a R5**. São decisões de fora da engenharia: ratificar a janela de
retenção (recomendação legal 2 anos rejeitado / 1 ano desistente, contra os 5 anos do comando
atual), limitar no tempo a exclusão da coorte #935, mapear e purgar os **binários externos de
vídeo**, confirmar a **base legal Art. 11 I** para voz e vídeo, e as entradas de RoPA.

⚠️ **Re-medir pelo anchor da própria função, nunca por `created_at`.**
📌 O guard do #1812 exige que o horizonte da tabela seja igual ao argumento do job (**1825**).

## ITEM 8: retenção viva

Cron `data-retention-sweep-daily`, `25 4 * * *`, **ativo e com 1 corrida bem sucedida**.
Primeira mordida: `notifications` em **09/09**, `visitor_leads` em 03/10, `data_anomaly_log` em
2027, `archive` em 2028 e 2029. **#1814** (archive sem destino) fica **aberta de propósito**, na
base do ratchet (**base declarada = 3**; a 4ª derruba o CI).

⚠️ Pontos de gamificação leem histórico de presença: tirar linhas pode mudar cálculo retroativo.

## ITEM 9: o resto, com dono

- **#1664** reclamada de novo em 16/08 e sem movimento: 36 não resolvidas, 31 acionáveis, 11 do
  operador, **36 de 36 já suprimidas**. Raiz é a **#1614**, adiada pelo PM em 05/08. Reabrir a
  decisão é conversa com o PM, não conserto unilateral.
- **#1826** (métrica de champions vira dado + rota de decisão no MCP): fases A, B e C.
- **EPIC #1780**: agregada de comentário e anexo não existe nem em SQL; **4** definições de
  autoridade para a mesma ação; **8** verbos de curadoria sem porta MCP; bases que só encolhem,
  **7** filhas de escrita e **10** de leitura.
- **#1805 / #1809**: **377 pares em 294 funções**, 91 inertes, 48 com uma só relação com domínio,
  **238 de ambiguidade real**. 🔴 **O atalho dos 48 foi ensaiado e não existe.** Não refazer a
  medição.
- **#1592** (barreira contra DDL nova): **468 de 1105** SECDEF alcançáveis por anônimo (15/08).
- **#1205** só fecha com o membro do caso acessando o `/profile` **LOGADO**.
- **#1777**, **#1776**, **#1728**, **#1729**, **#1742**, **#1744**, **#1762**, **#1664 fase 2**.
  **Onda E:** #1575, #1574, #1573, #1576, #1634, #1581, #1579.
- **Follow-ups:** #1004, #1008, #1403 (~set/2026), #1494, classe B do #1487, 20 termos não-GO.
- As **10 ações** da reunião de 13/08 seguem **sem prazo**, e `roster_sealed_at` segue **nulo**,
  com **45 de piso**.

---

## Armadilhas da vizinhança, com o preço que já custaram

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO, nunca o fragmento da varredura.** Prove por md5
   normalizado que a captura no repositório é idêntica ao corpo vivo
   (`scripts/audit-rpc-body-drift.mjs`, `drifted_definite = 0`), extraia o bloco **do arquivo**,
   substituição **contada**, **diffe**, e monte a migration por concatenação.
2. ⚠️ **Captura antiga pode usar `CREATE FUNCTION` sem `OR REPLACE`.** Troque por
   `CREATE OR REPLACE`, que **preserva as ACLs**.
3. 🔴 **`ADD CONSTRAINT` com nome auto-gerado mais `WHEN duplicate_object THEN NULL` engole a
   MUDANÇA de domínio.** Troca de domínio é `DROP CONSTRAINT IF EXISTS` mais `ADD`.
4. **`apply_migration` recebe o SQL como STRING** e **cria a linha de tracking com timestamp
   PRÓPRIO**: renomeie o arquivo local, e `migration repair` é desnecessário.
5. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com zero PRs abertas.
6. **Mudança de schema exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
7. **Mexeu em descrição de tool? Regenere o manifesto** (`node scripts/generate-mcp-manifest.mjs`)
   e **confira o `ef_version` ANTES de deployar**. Pós-deploy o smoke inclui `tools/list`.
   ⚠️ `deno` **não está instalado nesta máquina**; quem roda lint e check é o CI.
8. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** `REVOKE ... FROM PUBLIC, anon` na MESMA migration.
9. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 vai **dentro** da função.
10. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE**; fronteira de palavra é `\y`.
11. 📌 **Prove que o guard fica VERMELHO** numa transação abortada, **e faça-o devolver todos os
    itens examinados com um booleano**, senão lista vazia não se distingue de cegueira.
12. **Teste novo entra nas DUAS whitelists do `package.json`.**
13. **Suíte offline (~57 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass.** Suíte com DB: ~13 min, **escreve em produção e não tolera concorrência**.
14. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`, e nunca escreva o padrão sem
    intenção de fechar, **nem para citá-lo**.
15. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` e confirme
    com `git merge-base --is-ancestor origin/main HEAD`. E **nunca `git add -A`**: adicione por
    nome. ⚠️ Há **dezenas de handoffs de julho não rastreados** em `docs/planning/`; um `add -A`
    varreria todos.
16. ⚠️ **Repo é PÚBLICO.** Nome de pessoa não entra em issue, PR nem doc: **conte a população**.
    Identificador de membro ou de candidatura também não.
17. ⚠️ **RPC com `auth.uid()` devolve "Not authenticated" para `service_role`.** Impersone em
    transação abortada, `set_config('request.jwt.claims', ...)` **antes** do `SET LOCAL ROLE`.
    Funcionou assim em 17/08 para o `get_lgpd_cron_health`.
18. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background**: o pipe segura a saída.
19. ⚠️ **O build leva 2m30s a 4m40s: rode em background e confira o `Complete!`.**
20. ⚠️ **Drive:** barra fullwidth (`／`), gravação do Meet **sem extensão**, doc nativo com 0 bytes
    pelo mount (só `rclone cat`). E `~/.local/bin/rclone` (1.74), nunca o do apt.
21. ⚠️ **A capacidade pode estar FORA do repo.** O ferramental de YouTube vive em
    `~/projects/_pmo/youtube/` (venv `~/.venvs/youtube`, `token.json` OAuth vivo), apontado pelo
    header de `scripts/refresh-youtube-playlists.mjs`.
22. ⚠️ **A gravação continua depois do encerramento da pauta**, e **também começa antes dela**.
    **Corte as duas pontas.** O corte do fim sai da faixa `mov_text` (`ffmpeg -map 0:s:0 -c:s srt`);
    prove por grep que os marcadores do trecho restrito voltam zero.
23. 🆕 🔴 **"YouTube não substitui arquivo" vale para SUBSTITUIR, e não impede APARAR.** O editor
    do Studio apara mantendo URL, views, playlist e os campos do banco. É caminho de **navegador**
    (a Data API v3 não corta). O diálogo final avisa: **permanente e sem desfazer**, original só
    por Google Takeout. Processou em ~29 min.
24. 🆕 ⚠️ **No editor do Studio a roda do mouse NÃO rola a timeline**: quem rola é a barra
    horizontal da **página**. O campo de tempo aceita `H:MM:SS:Frames` e move o playhead, **mas a
    vista não o acompanha**, e a alça **não snapa** nele. O tooltip "New video length" é a leitura
    confiável.
25. 🆕 🔴 **A API do YouTube mente por propagação nos DOIS sentidos.** Já se sabia que
    `videos.list` devolve 0 enquanto `playlistItems.list` ainda mostra; agora também: **reler a
    descrição logo após o `update` devolve o valor ANTIGO**. Não conclua falha, releia depois.
26. 🆕 ⚠️ **`videos.update` com `part='snippet'` substitui o snippet INTEIRO.** Leia o vivo e troque
    só o campo alvo, senão apaga título e tags.
27. ⚠️ **`rescue` e `rescue_unbooked` são casos COMPLEMENTARES.** `rescue` exige
    `interview_scheduled` e levanta **`P0023`** fora disso; `rescue_unbooked` exige
    `interview_pending`.
28. 🔴 **Despacho em LOTE quebra o rodízio.** `now()` é da transação, os `dispatched_at` empatam, e
    o desempate manda tudo para uma pessoa só. Despache **um a um** e confira
    `resolved_evaluator_id` a cada volta.
29. 🔴 **SQL direto por `service_role` registra ato humano como 'cron' com actor nulo.** Use a porta
    MCP, que preserva o autor no `admin_audit_log`.
30. 📌 **`interview_manage action='block'/'unblock'`** é a alavanca declarada para tirar alguém do
    rodízio por período. Prefira janela curta com `ends_on` explícito e **prove que a fila mudou**.
