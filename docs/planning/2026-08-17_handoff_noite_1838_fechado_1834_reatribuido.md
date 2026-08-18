# Handoff da noite de 17/08: o #1838 fechado, e o #1834 reatribuído

> Sessão de 21:40 a 00:25 UTC. Todo número aqui foi medido no intervalo. **Re-medir antes de usar.**
> Supersede o item 1 e o item 7 do arranque `2026-08-18_PROMPT_ARRANQUE_ENTREVISTAS_VIVAS_E_IMPORT_VEP.md`.

## Estado

`main` em **`4910ec6a`** depois da PR #1840. PR **#1843** aberta e aguardando `validate`.
Migration nova aplicada: **`20260817234948`**. Invariantes: **43, zero violações**, antes e depois.

---

## O que fechou

### PR #1840 (mergeada, 11 de 11 verde) — #1838, defeito 1

A tela de seleção confirmava gravação que a RPC recusou no corpo com HTTP 200. A varredura
pedida no escopo achou **5 pontos**, não 1:

| linha | RPC | o que dizia |
|---|---|---|
| 2675 | `update_application_contact` | "Contato atualizado" |
| 4587 | `manage_selection_committee` (remover) | "Membro removido do comitê" |
| 4643 | `admin_update_application` (lote de decisão) | a recusada entrava em `ok++` |
| 5919 | `admin_update_application` (lote de triagem) | a recusada entrava em `ok++` |
| 5659 | `get_selection_dashboard` por `cycle_code` | pintava **ciclo vazio** em vez de "sem permissão" |

📌 **A convenção `success:false` já estava coberta em 7 de 7 pontos** (#1594/#1595/#1598). O
flanco aberto era só o do `{'error': ...}`. A superfície tem **três** convenções de recusa, não
duas: corpo com `error` (8 RPCs), corpo com `success:false` (4), e `RAISE` com HTTP 400.

**Guard novo** (`tests/contracts/1838-…`): classe derivada das capturas de migration, 14 pontos
em 8 RPCs, provado vermelho. Duas armadilhas que a **primeira versão do guard** caiu e que valem
para o próximo guard estático deste tipo:

1. 🔴 **Janela de N linhas fixas empresta a checagem do handler vizinho.** O trecho tem de ser
   cortado na **chamada seguinte**. Com janela fixa o guard ficou verde por acidente em 2 pontos.
2. 🔴 **Procurar o literal `data.error` acusa código correto.** Os handlers renomeiam no
   destructure (`const { data: dashboard }`), e a primeira versão apontou 2 leituras corretas.

---

## 🔴 O achado da noite: o #1834 estava atribuído à função errada

O PM escolheu "fazer o import delegar para a RPC canônica". **Não havia o que delegar.**

`import_vep_applications`, corpo vivo idêntico à captura (md5 `0a4265…`, 8217 chars):

- escreve **um** status, `'submitted'`, hardcoded no `INSERT`;
- **não tem `UPDATE selection_applications`** no corpo inteiro;
- **nunca cita** o literal `'approved'`;
- **uma** sobrecarga só;
- a tela chama só ele, depois `loadDashboard()`.

### O que a janela de 13:03:46 a 13:05:50 UTC foi

| medição | valor |
|---|---|
| linhas com `updated_at` na janela | 153 |
| **criadas** ali | **1** |
| **pré-existentes**, só atualizadas | **152** (mais antiga criada em 14/03) |
| das 89 hoje `approved`, com carimbo de oferta | 30, espalhadas por **5 meses** (15/04 a 17/08) |

As 153 receberam `imported_at`, e **nenhuma função escreve `imported_at` por `UPDATE`** — nem EF
nem script no repo. Veio de **SQL direto com `service_role`**.

📌 **É por isso que não havia auditoria: nenhuma função rodou, então nenhuma função auditou.** A
ausência era real; a atribuição não.

### O defeito que sobrevive à correção

`selection_applications.status` **não tinha carimbo próprio nem histórico**. `updated_at` é o
relógio da LINHA e qualquer escrita o move. **20 funções escrevem `status`, só 6 auditam a
mudança** — entre as que não auditam está `admin_update_application`, o caminho principal do
admin.

### PR #1843 — o gate foi para a TABELA

`selection_application_status_history` + trigger `AFTER INSERT OR UPDATE` por linha, que alcança
as 20 funções **e** o SQL direto.

- `caller_context` guarda `auth_uid`, `session_user`, `jwt_role`. **Ensaiado em transação
  abortada:** a transição gravou `session_user=postgres`, `jwt_role` nulo, ator nulo — a
  assinatura da escrita direta, antes invisível.
- **Guarda de no-op provada no mesmo ensaio:** o segundo `UPDATE`, que tocou só `updated_at`,
  gerou **zero** linhas.
- **`CHECK` de honestidade no banco:** linha de trigger SEMPRE tem `changed_at`; linha semeada
  NUNCA tem. **172 linhas de base** com `changed_at` nulo, porque a data da decisão não existe.
- RLS ligada, **nenhuma policy de escrita**, sem grant de escrita.
- As duas colunas de status nascem com domínio, espelhando o `CHECK` da candidatura.

⚖️ **Pendente do PM:** retitular a issue #1834. Sugestão no comentário: "status de candidatura
sem carimbo próprio nem histórico, e escrita direta sem rastro".

---

## Outros achados, com número

### #1842 aberta — ratchet que não existe

`cache_is_stale` (da view do #1587) tem o `COMMENT` dizendo que existe "para o ratchet medir", e
**zero consumidores**: 0 funções, 0 crons, 0 testes. O valor andou de **9** (piso registrado no
fechamento do #1587) para **11**, e ninguém foi avisado. Composição medida: **6** linhas de cache
`none` para candidatura que tem entrevista, e **5** de contradição entre dois valores reais, das
quais **3** dizem `scheduled` onde a canônica diz `cancelled`. Família do #1829.

### Entrevista de 10/08 marcada `completed`

Era **a única** no banco inteiro com horário passado e desfecho não marcado. Tinha 1 avaliação de
entrevista gravada. Dois efeitos ao marcar:

1. ⚠️ **O envelope devolveu `application_status: "interview_done"` e a linha continuou
   `approved`.** Ele relata um status que não gravou. Não regrediu nada no banco (conferido:
   `status` e `updated_at` intactos), mas quem lê o envelope acredita no contrário.
2. ⚠️ **`conducted_at` foi carimbado com AGORA** (17/08 23:36), não com 10/08 22:30. Já são
   **16 de 99** entrevistas com condução em dia diferente do agendamento, distância máxima **64
   dias**. Métrica sobre `conducted_at` lê a data do REGISTRO. É a armadilha do `booked_at`, na
   coluna de condução. **Sem issue ainda.**

### `npm run db:types` faz no-op silencioso com exit 0

Depois de criar tabela, as duas primeiras rodadas do script devolveram **exit 0 sem mudar nada**,
porque o PostgREST ainda servia schema em cache. Só depois de `NOTIFY pgrst, 'reload schema'` e de
uma terceira tentativa a tabela entrou (+131 linhas). 📌 **Depois de DDL, confira que o tipo novo
entrou (`grep`), não confie no exit code.**

### `check-invariants` vermelho por contenção, não por violação

Na PR #1843 o job falhou com **HTTP 504 `PGRST003`, "Timed out acquiring connection from
connection pool"**, com o `validate` rodando ao mesmo tempo. Os **36 subtestes de invariante
passaram**. 📌 Ler a causa antes de tratar como regressão; a suíte com DB não tolera concorrência.

---

## Próxima sessão

1. 🔴 **ITEM 1 do arranque anterior segue de pé, e agora é HOJE:** entrevistas de **18/08 23:00
   UTC** e **19/08 21:30 UTC**, ambas registradas à mão. Marcar desfecho com
   `interview_manage action='mark'`. A de 24/08 segue agendada.
2. **PR #1843:** confirmar `validate` verde e re-rodar `check-invariants` (falhou por pool).
3. ⚖️ **#1838, decisão tomada e NÃO implementada:** capacidades por **participação no comitê do
   ciclo mais `view_pii`**. As 6 RPCs seguem barradas; hoje o avaliador ao menos **vê** a recusa.
4. **#1834:** retitular a issue.
5. Segue: #1710 (re-medir em **23/08**, prazo 24/08), funil (28/08), #1842, #1829, as 56 do #1822,
   #1614/#1664, #905 (30/09).
