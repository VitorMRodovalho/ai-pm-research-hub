# Prompt de arranque: entrevistas vivas, o import do VEP e a véspera do #1710

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-17_PROMPT_ARRANQUE_POS_CRON_1530_E_VESPERA_1710.md`
> (o ITEM 1 dele, a corrida do cron das 15:30, foi cumprido: 2 resgates, zero duplicados).
> Handoff da sessão: `docs/planning/2026-08-17_handoff_tarde_1833_mergeada_1834_import_vep.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **17/08/2026, entre 14:30 e
17:00 UTC**. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit,
numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro:

- **Uma listagem não sustenta afirmação de ausência.**
- **Varra `pg_proc`, não o repositório**, e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo, sempre.
- **`replace_all` casa a string, não a intenção.** Conte as ocorrências e diffe.
- **"Zero linhas hoje" não é ausência de risco.** O que decide é a data da primeira mordida.
- **Se a API tem TETO, a ordem em que você chama VIRA o critério.**
- **O conector CACHEIA `tools/list`.** Leia o `z.enum` em `nucleo-mcp/index.ts` antes de dizer que
  uma ação não existe.
- **Amostre os VALORES antes de classificar pelo nome da coluna.**
- **Driver de saúde que lê o AGENDADOR não vê a falha.** *"Se o job rodar e quebrar todo dia, este
  sinal acende?"*
- 🆕 🔴 **Caminho em LOTE não herda as garantias da RPC canônica.** Antes de confiar num import,
  pergunte **quais garantias moram na RPC que ele não chama**. Auditoria é a mais fácil de notar e
  raramente é a única.
- 🆕 🔴 **O carimbo do TRANSPORTE não é o carimbo do FATO.** 83 linhas com `updated_at` no mesmo
  minuto eram sincronização de decisões tomadas ao longo de dez meses. Antes de ler um agrupamento
  temporal como evento, **procure o carimbo de origem**.
- 🆕 ⚠️ **Espaçamento de carimbo separa LOTE de LAÇO, não humano de máquina.** Idêntico ao
  microssegundo = transação única. Espaçado de 1 a 2 segundos = laço por linha, que tanto um humano
  clicando quanto um import produzem.
- 🆕 ⚠️ **Comparar hash exige normalização byte-idêntica dos DOIS lados.** Use o helper do projeto
  (`tests/helpers/rpc-body-drift-parser.mjs`); um `trim` a mais fabrica falso drift.

---

## Estado (17/08, 21:10 UTC)

`main` em **`be526c13`**, **zero PRs abertas**, **43 invariantes com zero violações**,
**zero eventos de bypass** em 7 dias. EF `nucleo-mcp` em `ef_version` **2.103.0** (deployada e conferida pelo `/health`).
Migration mais recente: `20260817202155` (#1836).

---

## 🔴 ITEM 1: duas entrevistas vivas, e toda reserva nova depende de print

Há **3 entrevistas agendadas** no ciclo aberto: **18/08**, **19/08** e 24/08. As duas primeiras
foram registradas **à mão**, porque as reservas chegaram pelo calendário de agendamento de um
entrevistador e **a plataforma não as viu**.

📌 **Conferir:** as de 18/08 e 19/08 aconteceram, e marcar o desfecho com
`interview_manage action='mark'` (`completed` | `noshow` | `cancelled`).

🔴 **Enquanto a #1614 não for resolvida, toda reserva nova é invisível.** Ela só chega por print do
PM. Se aparecer uma, o procedimento medido é:

1. resolver a candidatura pelo e-mail do convidado (`selection_applications.email`);
2. **conferir se o cron a alcança** antes de qualquer coisa (`status='interview_pending'` mais
   `auto_rescue_count < 1` mais carência vencida), porque senão ela recebe convite duplicado;
3. registrar com `interview_manage action='schedule'` (é **silencioso**, não dispara e-mail),
   nomeando o entrevistador e convertendo o horário local para UTC.

⚠️ `schedule` **carimba `booked_at` sozinho** quando a linha de despacho é instrumentada. Isso é
bom, e cria uma armadilha de leitura: o carimbo é o do REGISTRO, não o da reserva.

## 🔴 ITEM 2: #1838, o avaliador barrado e a tela que confirma o que não gravou

Um **avaliador do comitê** (tem `view_pii`, não tem `manage_platform`, `manage_member` nem
`view_internal_analytics`) está barrado em **seis RPCs** das telas de seleção e de reconciliação do
VEP. Ele entrevista, e não opera as telas ao redor da entrevista.

🔴 **O grave não é o bloqueio, é a forma dele.** `update_application_contact` devolve
`{"error":"Unauthorized"}` com **HTTP 200**, e o handler só testa o erro de transporte:
a tela mostra **"Contato atualizado"**, fecha o modal e recarrega, sem ter gravado nada.

📌 **Conserto que não depende de decisão nenhuma:** ler `data.error`, e varrer os demais handlers
do arquivo pelo mesmo padrão. O handler de aprovação, poucas linhas acima, já faz certo.

⚖️ **Decisão do PM, separada:** as capacidades exigidas fazem sentido? `update_application_contact`
pede `manage_member`, que é ciclo de vida de membro (GP-only por LGPD), para editar o LinkedIn de um
**candidato**; `get_application_onboarding_pct` pede `manage_platform` para devolver **um inteiro**.
Caminho intermediário: gate por participação no comitê do ciclo mais `view_pii`.

⚠️ **Duas convenções de recusa na mesma tela:** três RPCs recusam no corpo com HTTP 200 e três
levantam exceção (HTTP 400). Tratamento genérico de erro acerta um e erra o outro.

## ITEM 3: o Apps Script conhece 3 endereços para um comitê de 7

O `teamEmails` do Apps Script tem **3 endereços**; o comitê do ciclo aberto tem **7 pessoas**.
Quem não está na lista é lido como **candidato**, e é isso que enche a fila da #1664: dois dos
"endereços institucionais" que apareciam lá são integrantes do comitê, e o endereço pessoal do
operador apareceu **11 vezes**.

📌 **Derive a lista do catálogo**, nunca de memória: `selection_committee` do ciclo aberto,
mais os alternativos em `member_emails`. O operador tem **três** endereços, e o que ele usa na
agenda não está registrado em lugar nenhum.

⚠️ **O script vivo mora no Google e só existe um snapshot no repositório**
(`docs/specs/p87-calendar-webhook-apps-script.md`). Compare antes de editar.

O conserto durável é o do #1614: **o script para de classificar** e manda todos os convidados, e o
servidor decide, porque o catálogo está no servidor. Enquanto isso não acontece, **incluir alguém
no comitê pelo admin não faz nada pelo script**, e o defeito só aparece semanas depois.

## ITEM 4: os três de oferta direta, só falta ratificar

O arranque anterior pedia data e hora para "2 aprovados já ativos nunca entrevistados". **A
pergunta não se aplica.** Hoje são 3, e o export do VEP mostra os três **Active na mesma vaga**,
com `submittedDateUtc` **nulo** e oferta estendida e aceita em julho.

Eles entraram por **oferta direta**, não pelo funil, então não havia etapa de entrevista a cumprir.
📌 **Falta apenas o PM ratificar** que oferta direta dispensa entrevista. Não marcar horário.

## ⏰ ITEM 5: #1710, prazo 24/08

Config conferida em 17/08 e intacta:

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

**Re-medir em 23/08, a véspera, pelos dois caminhos independentes** e só então levar ao PM.
⚠️ **É TETO e encolhe a cada presença registrada.** Última medição conhecida (15/08): 43 selam,
80 faltas, 40 pessoas. **Não recitar.** A coorte mudou em 16/08 (presença da geral de 13/08 subiu
de 31 para 45), então não reaproveitar recorte anterior.

⚖️ **Decidido (15/08):** células fora do alcance de líder ficam com o GP pela grade geral, e a
lista **nominal** vai ao GP **na conversa, não em issue nem PR**.

## ITEM 6: funil de entrevistas, prazo 28/08

Medido em 17/08: **105 linhas, 11 instrumentadas, 3 aberturas, 1 reserva medida.**

🔴 **Há 2 reservas reais e 1 medida.** A não medida tem convite anterior à instrumentação. E o
`booked_at` da medida guarda a hora do registro manual, com `first_opened_at` nulo apesar de a
pessoa ter aberto.

📌 **Nenhum número de conversão é publicável sem o denominador explícito.** Publicar "1 em 11" sem
dizer que a instrumentação começou no meio do ciclo, e que uma reserva real ficou de fora, diz
conversão falsa. **Não provocar despacho para testar:** o cron gera linhas sozinho.

## ITEM 7: #1834, o import do VEP

`import_vep_applications` grava estado em massa **sem passar pela RPC canônica**, e com isso pula
auditoria, vínculo de membro e sincronia da janela de autoridade. Os três efeitos foram medidos e
os dois últimos já derrubaram o CI uma vez.

📌 **Consequência operacional imediata: depois de cada import, rodar
`SELECT * FROM public.check_schema_invariants() WHERE violation_count > 0`.** Isso resolve a
detecção, não a causa.

⚖️ **Decisão do PM:** auditar a sincronização, carregar o carimbo de origem (o export traz
`acceptanceDateUTC` para 87 e `declinedDateUTC` para 50), ou fazer o import **delegar para a RPC
canônica**, que é a saída mais forte e provavelmente a mais barata no longo prazo.

⚠️ **Antes de editar a função:** ela teve drift recuperado na p176. Confirme por md5 normalizado
que a captura no repositório ainda é idêntica ao corpo vivo.

## ITEM 8: #1614, que virou gargalo ativo

Deixou de ser dívida adiada. Em um único dia ela custou **duas reservas invisíveis**, **11
registros de ruído** na fila da #1664 e **um gate de CI vermelho**.

A proposta medida está publicada na issue, em três camadas: completar a lista literal de e-mails do
Apps Script para destravar, **tirar a classificação do script** e devolvê-la ao servidor que tem o
catálogo, e filtrar por **organizador do comitê** em vez de título de calendário.

📌 **Reabrir a decisão de 05/08 é conversa com o PM**, não conserto unilateral.

## ITEM 9: #1829, o painel que fica verde com a varredura falhando

O driver mede o agendador (`max(start_time)` sem filtro de status) e não o trabalho, e
`_data_retention_sweep_cron()` não tem handler, então no modo de falha o audit não ganha linha.
Latente: a estreia de 17/08 às 04:25 foi `succeeded` com `affected_total = 0`.

📌 Correção mais forte proposta: **vermelho quando o job rodou e o audit não gravou**.

## ITEM 10: #1822, a triagem das 56 é decisão do PM

**270 colunas examinadas, 208 com domínio, 6 por FK, 56 sem guarda** em 44 tabelas, triadas em
cinco classes (detalhe no handoff de 17/08 madrugada). A classe de **enumeração técnica fechada**
é a de melhor razão custo/benefício. A classe de **geografia não é caso de `CHECK`**, e o dado dela
**já está sujo** (mesma localidade sob duas grafias, três grafias de um lugar, valor numérico
solto, string vazia). Conserto é FK para `chapter_registry`, e é **item próprio ainda sem issue**.

## ITEM 11: o resto, com dono

- **#1664** sem movimento: 36 não resolvidas, 31 acionáveis, **36 de 36 já suprimidas**. Raiz é a
  #1614. Os 11 do "endereço do operador" agora têm causa nomeada.
- **#1826** (métrica de champions vira dado e rota de decisão no MCP): fases A, B e C.
- **#1814** (`archive` sem destino), na base do ratchet de retenção (**base = 3**).
- **EPIC #1780**: agregada de comentário e anexo não existe nem em SQL; 4 definições de autoridade
  para a mesma ação; 8 verbos de curadoria sem porta MCP.
- **#1805 / #1809**: **238 pares de ambiguidade real**, só saem por resolução por STATEMENT.
  🔴 **O atalho dos 48 foi ensaiado e não existe.** Não refazer a medição.
- **#1592** (barreira contra DDL nova): 468 de 1105 SECDEF alcançáveis por anônimo (15/08).
- **#1205** só fecha com o membro do caso acessando o `/profile` **LOGADO**.
- **#905**, portão legal R1 a R5, prazo **30/09**.
- As **10 ações** da reunião de 13/08 seguem **sem prazo**, e `roster_sealed_at` segue **nulo**,
  com **45 de piso**.

---

## Armadilhas da vizinhança

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO.** Prove por md5 normalizado que a captura no
   repositório é idêntica ao corpo vivo, extraia o bloco **do arquivo**, substituição **contada**,
   **diffe**, e monte a migration por concatenação. Use o helper do projeto para normalizar.
2. ⚠️ **Captura antiga pode usar `CREATE FUNCTION` sem `OR REPLACE`.** Troque, que `OR REPLACE`
   **preserva as ACLs**.
3. 🔴 **`ADD CONSTRAINT` com nome auto-gerado mais `WHEN duplicate_object THEN NULL` engole a
   MUDANÇA de domínio.** Troca de domínio é `DROP CONSTRAINT IF EXISTS` mais `ADD`.
4. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO**: renomeie o arquivo local
   para esse timestamp, e `migration repair` é desnecessário.
5. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com zero PRs abertas.
6. **Mudança de schema exige `npm run db:types` na MESMA PR** (gate `gen-types-drift`).
7. **Mexeu em descrição de tool? Regenere o manifesto** e confira o `ef_version` ANTES de deployar.
   ⚠️ `deno` **não está instalado nesta máquina**; quem roda lint e check é o CI.
8. **`CREATE FUNCTION` concede EXECUTE a PUBLIC.** `REVOKE ... FROM PUBLIC, anon` na MESMA migration.
9. **`SECURITY DEFINER` contorna a RLS.** O gate do #785 vai **dentro** da função.
10. ⚠️ **No ARE do Postgres, `\b` é BACKSPACE**; fronteira de palavra é `\y`.
11. 📌 **Prove que o guard fica VERMELHO** numa transação abortada, e faça-o devolver **todos** os
    itens examinados com um booleano, senão lista vazia não se distingue de cegueira.
12. **Teste novo entra nas DUAS whitelists do `package.json`.**
13. **Suíte offline (~57 s) é o gate barato:**
    `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
    ⚠️ **Skip ≡ pass.** Suíte com DB: ~13 min, **escreve em produção e não tolera concorrência**.
    📌 Ela roda local com `set -a; . ./.env; set +a` e foi assim que a causa do CI vermelho apareceu
    quando os logs do GitHub estavam fora do ar.
14. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`, e nunca escreva o padrão sem
    intenção de fechar, **nem para citá-lo**.
15. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` e confirme
    com `git merge-base --is-ancestor origin/main HEAD`. **Nunca `git add -A`**: há dezenas de
    handoffs de julho não rastreados em `docs/planning/`.
16. ⚠️ **Repo é PÚBLICO.** Nome, e-mail e identificador de pessoa não entram em issue, PR nem doc.
    **Conte a população.** O export do VEP é git-ignored e a nota de minimização dele manda apagar
    as cópias locais depois do import.
17. ⚠️ **RPC com `auth.uid()` devolve "Not authenticated" para `service_role`.** Impersone em
    transação abortada, `set_config('request.jwt.claims', ...)` **antes** do `SET LOCAL ROLE`.
18. ⚠️ **NUNCA canalize a suíte por `| tail -N` em background**: o pipe segura a saída.
19. ⚠️ **O build leva 2m30s a 4m40s: rode em background e confira o `Complete!`.**
20. ⚠️ **Drive:** barra fullwidth (`／`), gravação do Meet **sem extensão**, doc nativo com 0 bytes
    pelo mount (só `rclone cat`). E `~/.local/bin/rclone` (1.74), nunca o do apt.
21. ⚠️ **A capacidade pode estar FORA do repo.** O ferramental de YouTube vive em
    `~/projects/_pmo/youtube/` (venv `~/.venvs/youtube`, `token.json` OAuth vivo).
22. ⚠️ **Corte as DUAS pontas de uma gravação.** E **capítulo com título parece decisão**, então
    não batize resto de material.
23. 🔴 **"YouTube não substitui arquivo" vale para SUBSTITUIR e não impede APARAR.** O editor do
    Studio apara mantendo URL, views, playlist e os campos do banco. É navegador, não API. O
    diálogo final avisa: **permanente e sem desfazer**. Processou em ~29 min.
24. 🔴 **A API do YouTube mente por propagação nos DOIS sentidos**, inclusive **relendo a descrição
    logo após o `update`**, que devolve o valor ANTIGO. Não conclua falha, releia depois.
25. ⚠️ **`videos.update` com `part='snippet'` substitui o snippet INTEIRO.** Leia o vivo e troque só
    o campo alvo.
26. ⚠️ **`rescue` e `rescue_unbooked` são casos COMPLEMENTARES.** `rescue` exige
    `interview_scheduled` e levanta `P0023` fora disso; `rescue_unbooked` exige `interview_pending`.
27. 🔴 **Despacho em LOTE quebra o rodízio.** `now()` é da transação e os `dispatched_at` empatam.
    Despache **um a um** e confira `resolved_evaluator_id` a cada volta.
28. 🔴 **SQL direto por `service_role` registra ato humano como 'cron' com actor nulo.** Use a porta
    MCP. Vale também para `member_add_alternate_email`, que **não audita**: prefira
    `member_emails action='add'`.
29. 🆕 ⚠️ **O GitHub caiu por mais de uma hora em 17/08** (503 em GraphQL e REST, escrita e logs;
    leitura funcionava). Repetidor **idempotente** resolve: confira se o artefato já existe antes de
    tentar de novo, para não duplicar comentário nem PR.
30. 🆕 📌 **Reparo de dado tem forma canônica.** Procure o **backfill idempotente na migration que
    criou o invariante** antes de inventar `UPDATE`. Meça alcance ANTES, rode, meça DEPOIS.
