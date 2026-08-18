# Prompt de arranque: a entrevista de hoje, a véspera do #1710 e o CI que trava

> Colar depois do `/clear`.
> **Modelo: Opus 5 (auto, não pinar). Effort: `xhigh`.**
> **Supersede** `docs/planning/2026-08-18_PROMPT_ARRANQUE_ENTREVISTAS_VIVAS_E_IMPORT_VEP.md`
> (o ITEM 2 dele foi entregue; o ITEM 7 foi **reatribuído** — ver ITEM 6 abaixo).
> Handoff da madrugada: `docs/planning/2026-08-17_handoff_noite_1838_fechado_1834_reatribuido.md`

---

## Regra zero

**Nada deste documento pode ser recitado.** Todo número foi medido em **18/08/2026, entre 04:30 e
11:50 UTC**. Re-meça com tool call na mesma volta em que o número entrar numa decisão, num commit,
numa issue ou numa pergunta ao PM.

Regras de varredura que já custaram caro, as três últimas ganhas nesta madrugada:

- **Uma listagem não sustenta afirmação de ausência.**
- **Varra `pg_proc`, não o repositório**, e leia o corpo antes de confiar na varredura.
- **A lista da issue não é a classe.** Derive do catálogo, sempre.
- **`replace_all` casa a string, não a intenção.** Conte as ocorrências e diffe.
- **"Zero linhas hoje" não é ausência de risco.** O que decide é a data da primeira mordida.
- **O carimbo do TRANSPORTE não é o carimbo do FATO.**
- 🆕 🔴 **Descartar hipótese com a ferramenta da CAMADA ERRADA e publicar o descarte.** Eu afirmei
  numa issue que "pool travado está descartado" com base em `pg_stat_activity` limpo. Mas
  `pg_stat_activity` vê **backends do Postgres**, e a pergunta era sobre a **fila do pooler**. Um
  pooler saturado devolve 504 sem uma única conexão longa do outro lado. **Antes de publicar um
  descarte, pergunte de que camada é a ferramenta e de que camada é a hipótese.**
- 🆕 🔴 **Guard estático com janela de N linhas empresta a checagem do handler VIZINHO** e fica
  verde por acidente. Corte o trecho na **próxima chamada**. E casar o literal (`data.error`)
  acusa quem renomeia no destructure — aceite **qualquer identificador**.
- 🆕 ⚠️ **Guard que PROÍBE um padrão acusa a própria documentação.** A proibição de
  `CREATE FUNCTION` sem `OR REPLACE` casou 4 vezes, todas no cabeçalho que **explica** a regra.
  Rode a proibição sobre o SQL **sem comentários**.
- 🆕 ⚠️ **`npm run db:types` faz no-op com exit 0** quando o PostgREST ainda serve schema em cache.
  Depois de DDL, **confira o CONTEÚDO** (`grep` do nome novo), nunca o código de saída.

---

## Estado (18/08, 11:50 UTC)

`main` em **`23b2e135`**, **zero PRs abertas**, **43 invariantes com zero violações**.
Migrations novas da madrugada: `20260817234948` (#1834) e as quatro `202608181018xx`/`202608181021xx` (#1838).
Bypass: **1 evento** na janela de 7 dias (a #1843, justificada na PR). Orçamento 2.
Issues: **209 abertas**. **#1834 fechada** em 18/08; **#1842**, **#1844** e **#1848** abertas na madrugada.

---

## 🔴 ITEM 1: a entrevista de HOJE, e a de amanhã

| quando (UTC) | quando (BRT) | status |
|---|---|---|
| **18/08 23:00** | **20:00** | `scheduled` |
| 19/08 21:30 | 18:30 | `scheduled` |
| 24/08 23:30 | 20:30 | `scheduled` |

📌 **Marcar o desfecho** com `interview_manage action='mark'` (`completed` \| `noshow` \| `cancelled`).
É o único item da lista que **expira**.

⚠️ **`mark` carimba `conducted_at` com AGORA, não com o horário da entrevista.** Já são **16 de 99**
entrevistas com condução em dia diferente do agendamento, distância máxima **64 dias**. Qualquer
métrica sobre `conducted_at` lê a data do REGISTRO. **Sem issue ainda.**

⚠️ **O envelope do `mark` relata `application_status` que ele NÃO gravou** (devolveu
`interview_done` para uma linha que continuou `approved`). O banco fica certo; quem lê o envelope,
não. **Sem issue ainda.**

🔴 Enquanto a **#1614** não sair, **toda reserva nova é invisível** e só chega por print do PM. O
procedimento medido: resolver a candidatura pelo e-mail, **conferir se o cron a alcança** antes de
tudo (senão ela recebe convite duplicado), e registrar com `action='schedule'`, que é silencioso.

## ⏰ ITEM 2: #1710, prazo 24/08 — **5 dias**

Config conferida em 17/08 e intacta:

```
platform_settings['attendance.seal_window'] = {"floor_date": "2026-08-24", "grace_days": 14}
cron attendance-seal-window-daily · 40 11 * * * · active = true
```

📌 **Re-medir em 23/08, a véspera, pelos DOIS caminhos independentes**, e só então levar ao PM.
⚠️ **É TETO e encolhe a cada presença registrada.** A medição de 15/08 (43 selam, 80 faltas, 40
pessoas) **não serve mais**: a coorte mudou em 16/08.

⚠️ **A terceira entrevista é 24/08, o MESMO dia do prazo.** Não deixe os dois para a mesma sessão.

⚖️ **Decidido:** células fora do alcance de líder ficam com o GP pela grade geral; lista **nominal**
vai ao GP **na conversa, nunca em issue nem PR**.

## 🔔 ITEM 3: funil de entrevistas, prazo 28/08 — 9 dias

Medido agora: **105 linhas, 11 instrumentadas, 1 reserva medida.**

📌 **Nenhum número de conversão é publicável sem o denominador explícito.** A instrumentação começou
no meio do ciclo, e há **2 reservas reais para 1 medida**. Publicar "1 em 11" diz conversão falsa.
**Não provocar despacho para testar:** o cron gera linhas sozinho.

## 🔴 ITEM 4: #1844, o CI que trava — e que corrompe o sinal de bypass

Três corridas do `validate` morreram no teto de **95 min** (norma: 13 a 18), e o `check-invariants`
caiu com `PGRST003`. Causa medida: **504 de pool**, um teste levando **61 segundos** sozinho.

Um defeito **identificado**: o `check-invariants` roda **fora do `wait-for-db-lane`**, então disputa
o mesmo pooler que o `validate` na mesma PR. A causa raiz da saturação **continua não identificada**
— a 4ª corrida passou em 19 min sem eu mudar nada.

📌 Três saídas na issue, e a mais barata é trazer o `check-invariants` para a lane. Uma quarta:
**nenhum teste DB-aware deveria esperar 61 s** — `AbortSignal.timeout()` converte a mesma falha em
vermelho legível (já aplicado ao teste do #1834, commit `7b65072a`).

⚠️ **O script de conferência do `bypass-protocol.md` produz falso positivo**: ele lê o `validate` do
**commit de merge**, e por isso lista a #1840 como suspeita — ela estava 11/11 verde no merge, e o
que ficou `cancelled` foi a corrida **pós-merge na `main`**.

## ITEM 5: #1838, a metade que sobrou

✅ **Entregue (PRs #1840 e #1845):** a tela deixou de confirmar gravação recusada (eram **5** pontos
cegos, não 1), e as 6 RPCs foram destravadas — leitura para qualquer papel do comitê, **escrita só
para `evaluator`/`lead`**. Verificado por impersonação: antes 6 de 6 barradas; depois o avaliador
passa nas 6 e o observador é barrado nas 2 escritas.

📌 **Fica aberto o defeito 2:** a superfície tem **TRÊS** convenções de recusa (corpo com `error`,
corpo com `success:false`, `RAISE` com 400). Tratamento genérico acerta uma e erra as outras.

⚠️ **A página `/admin/vep-reconciliation` tem gate de rota próprio** ("é admin"). Destravar as 3
RPCs dela **não garante que o avaliador chegue lá**. Não ampliei rota por conta própria.

## ITEM 6: #1834 fechada — e o que dela ficou aberto na #1848

✅ **Fechada e retitulada em 18/08**, para *"status de candidatura sem carimbo próprio nem histórico,
e escrita direta sem rastro"*. O título anterior culpava o `import_vep_applications`, e o corpo vivo
desmente: escreve um só status (`'submitted'`), não tem `UPDATE` da tabela, nunca cita `'approved'`.
A janela de 13:03-13:05 eram **152 linhas pré-existentes** com decisões espalhadas por 5 meses,
escritas por **SQL direto com `service_role`** — nenhuma função rodou, então nenhuma função auditou.

✅ **Item 1 da proposta entregue** (PR #1843): trigger de tabela, **172 linhas de base** com
`changed_at` NULO de propósito, alcançando as 20 funções que escrevem status **e** a escrita direta.

🆕 **Item 2 NÃO foi entregue e virou a #1848:** detectar o vínculo ausente **no ato da gravação**, em
vez de deixar o invariante `R_approved_application_has_member` descobrir horas depois, como CI
vermelho numa PR sem relação. Medido em 18/08: das **98** aprovadas, **3 resolvem só pelo e-mail
alternativo** — a mesma forma do caso que travou o CI em 17/08. Hoje o invariante está em zero
violações, mas isso é propriedade do DADO, não da estrutura.

📌 A distinção que separa os dois itens, e que vale para o próximo caso: **auditar registra que
aconteceu; validar decide se pode acontecer.** Um trigger de auditoria que recusa escrita vira
gargalo, então a #1848 propõe **anomalia, não exceção** — barrar transformaria o caso legítimo
(e-mail alternativo ainda não cadastrado) em bloqueio operacional.

## ITEM 7: #1842, o ratchet que não existe

`cache_is_stale` tem `COMMENT` dizendo que existe "para o ratchet medir", e **zero consumidores**.
Medido agora: **11** (o piso registrado no fechamento do #1587 era 9). Composição: 6 de cache `none`,
5 de contradição real, **3 dizendo `scheduled` onde a canônica diz `cancelled`**.

## ITEM 8: o que está ficando para trás, medido

**209 issues abertas**, em 13 ondas. Distribuição de idade: 21 novas, 73 entre 8-30 dias,
**108 entre 31-90**, **7 acima de 90**.

As **7 mais velhas** (104 a 118 dias), nenhuma tocada:

- **#92** (118d) — integração de calendário Núcleo ↔ GCal/Outlook. 🔴 **É a raiz estrutural da
  #1614**, que nesta semana custou 2 reservas invisíveis, 11 registros de ruído e 1 gate de CI.
- **#96, #95** (118d, comms) · **#93** (118d, APM + WhatsApp MCP)
- **#109, #108** (111d) — backfill que depende de ação do PM
- **#132** (104d, legal-ops)

Filas paradas:

- **`onda:0` tem 3 abertas**, incluindo **#588 `[LL]` com 70 dias** — o intake do PMO de portfólio.
  A madrugada de 17-18/08 gerou várias lições reusáveis e **nenhuma foi para lá**.
- **`onda:0.5` tem 7**, uma com 90 dias (#165), duas com 68 (#632, #634).
- **18 issues sem label de onda** — invisíveis a qualquer recorte por onda.
- Milestone **"Julho 2026 — Viradas de Ciclo"**: 3 abertas, prazo era **16/07**, **um mês vencido**.

## ITEM 9: o resto, com dono

- **#1664** sem movimento: 36 não resolvidas, 31 acionáveis, 36 de 36 já suprimidas. Raiz é a #1614.
- **#1829** — painel de retenção fica verde com a varredura falhando. Latente.
- **#1822** — as **56** colunas de estado sem domínio, triadas em 5 classes. A de geografia não é
  caso de `CHECK`; conserto é FK para `chapter_registry`, **item próprio ainda sem issue**.
- **#1805 / #1809** — **238 pares de ambiguidade real**. 🔴 **O atalho dos 48 foi ensaiado e não
  existe. Não refazer a medição.**
- **#1592** — 468 de 1105 SECDEF alcançáveis por anônimo (15/08).
- **#1205** — só fecha com o membro do caso acessando o `/profile` LOGADO.
- **#905** — portão legal R1 a R5, prazo **30/09** (42 dias).
- As **10 ações** da reunião de 13/08 seguem **sem prazo**, e `roster_sealed_at` segue **nulo**, com
  **45 de piso**.

---

## Ordem sugerida

1. **Marcar as entrevistas** (hoje 23:00 UTC e amanhã) — único item que expira.
2. **23/08: re-medir o #1710** pelos dois caminhos.
3. **Decidir a #1844** — enquanto o CI trava, toda PR vira candidata a bypass, e restam **1 de 2**.
4. **Alimentar a #588** com as lições acumuladas; o laço do PMO está parado há 70 dias.
5. **Triar as 18 sem onda e as 7 acima de 90 dias**, começando pela **#92**.

⚠️ **Dois achados desta madrugada seguem SEM issue**, e somem se ninguém os abrir: o `mark`
carimbando `conducted_at` com a hora do REGISTRO (16 de 99 já divergem, máx. 64 dias), e o envelope
do `mark` relatando `application_status` que ele não gravou.

---

## Armadilhas da vizinhança

1. ⚠️ **`CREATE OR REPLACE` exige o corpo INTEIRO.** Prove por md5 normalizado que a captura é
   idêntica ao vivo, extraia o bloco **do arquivo**, substituição **contada**, **diffe**, e monte a
   migration por concatenação. 📌 **Aplique em LOTES** e confira o md5 de cada um antes do seguinte:
   foi assim que 33 mil caracteres saíram com **drift zero**.
2. ⚠️ **Captura antiga pode usar `CREATE FUNCTION` sem `OR REPLACE`.** Troque — `OR REPLACE`
   **preserva as ACLs**.
3. **`apply_migration` cria a linha de tracking com timestamp PRÓPRIO**: renomeie o arquivo local
   para esse timestamp, e `migration repair` é desnecessário. **A CLI do Supabase não está linkada.**
4. **DDL aplicada ANTES do merge deixa toda branch aberta vermelha.** Aplique com zero PRs abertas.
5. **Mudança de schema exige `npm run db:types` na MESMA PR** — e **confira por `grep`**, não pelo
   exit code (ver Regra zero).
6. **Teste novo entra nas DUAS whitelists do `package.json`.**
7. **Suíte offline (~54 s) é o gate barato:**
   `env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u PUBLIC_SUPABASE_URL npm run test:contracts`.
   ⚠️ **Skip ≡ pass.** Suíte com DB roda local com `set -a; . ./.env; set +a`.
8. ⚠️ **`Fecha #N` em português NÃO fecha a issue.** Use `Closes #N`, e nunca escreva o padrão sem
   intenção de fechar, **nem para citá-lo**.
9. ⚠️ **Branch nova nasce do HEAD, não da main.** `git checkout -b <nome> origin/main` e confirme com
   `git merge-base --is-ancestor origin/main HEAD`. **Nunca `git add -A`.**
10. ⚠️ **Repo é PÚBLICO.** Nome, e-mail e identificador de pessoa não entram em issue, PR nem doc.
    **Conte a população.**
11. ⚠️ **RPC com `auth.uid()` devolve "Not authenticated" para `service_role`.** Impersone em
    transação abortada, `set_config('request.jwt.claims', ...)` **antes** do `SET LOCAL ROLE`.
    📌 Para capturar exceção por papel, use tabela TEMP com `GRANT INSERT ... TO authenticated` —
    `RAISE NOTICE` não volta pelo `execute_sql`.
12. 📌 **Prove que o guard fica VERMELHO** numa transação abortada, e faça-o devolver **todos** os
    itens examinados com um booleano, senão lista vazia não se distingue de cegueira.
13. ⚠️ **O build leva 2m30s a 4m40s: rode em background e confira o `Complete!`.**
14. 🔴 **Despacho em LOTE quebra o rodízio.** `now()` é da transação e os `dispatched_at` empatam.
15. 🔴 **SQL direto por `service_role` registra ato humano como 'cron' com actor nulo.** Use a porta
    MCP. Vale também para `member_add_alternate_email`, que **não audita**.
16. ⚠️ **`rescue` e `rescue_unbooked` são casos COMPLEMENTARES**, com pré-condições opostas.
17. ⚠️ **Drive:** barra fullwidth (`／`), gravação do Meet **sem extensão**, doc nativo **0 bytes**
    pelo mount (só `rclone cat`). E `~/.local/bin/rclone` (1.74), nunca o do apt.
18. ⚠️ **A capacidade pode estar FORA do repo.** O ferramental de YouTube vive em
    `~/projects/_pmo/youtube/` (venv `~/.venvs/youtube`, `token.json` OAuth vivo).
19. 🔴 **A API do YouTube mente por propagação nos DOIS sentidos.** Não conclua falha, releia depois.
    E **`videos.update` com `part='snippet'` substitui o snippet INTEIRO.**
