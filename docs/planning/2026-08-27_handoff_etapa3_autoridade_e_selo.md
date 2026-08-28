# Handoff — etapa 3 de autoridade, selo de presença e higiene de board

**Medido em 27/08/2026, entre 01h00 e 13h00 BRT.** Todo número aqui saiu de consulta feita naquela
janela. A base se moveu **três vezes** durante a sessão (ver "A base é um alvo móvel"), então
**re-meça antes de decidir**. Handoff não é medição.

> ⚠️ Arquivo em repo PÚBLICO. Sem nome de pessoa, sem detalhe de presença individual, sem exposição
> medida do advisory privado. Se precisar do caso a caso, ele está no banco e no GHSA-jpq5.

---

## 1. Entregue e mergeado

**Etapa 3 do procedimento de escopo de capacidade** (o advisory GHSA-jpq5 descreve as etapas):

| action | antes | depois | perderam acesso | PR |
|---|---:|---:|---:|---|
| `write_board` | 69 | 72 | **0** | #1979 (#1977) |
| `manage_event` | 14 | 16 | **0** | #1992 (#1990) |

`can()` segue **intocada**. A cláusula permissiva dela é a etapa 4 e só sai depois da Onda B.

Superfície resourceless restante, re-medida em 27/08:

| action | 2 args | `NULL,NULL` | total |
|---|---:|---:|---:|
| `manage_member` | 166 | 3 | **169** |
| `manage_event` | 46 | 0 | 46 |
| `view_pii` | 19 | 1 | **20** |
| `write` | 4 | 0 | 4 |
| `write_board` | 2 | 0 | 2 |
| `award_champion` | 2 | 0 | 2 |

---

## 2. A sonda tinha um terceiro furo

A sonda de 2 argumentos **subconta**: `can(x, 'acao', NULL, NULL)` é resourceless no efeito, porque
a cláusula permissiva dispara em `p_resource_id IS NULL`, e escapa de qualquer regex que espere o
parêntese logo depois do literal. Mesma família do cast `::text` e do consumo por alternância.

**Sonde as três formas**, uma action por vez, e com o primeiro argumento proibido de conter vírgula
fora de parênteses.

---

## 3. A armadilha que quase custou a lane do `manage_event`

`can_by_member` recebe **member id**. `_can_anywhere` recebe **person id**. Os dois são `uuid`.

| forma | passam (de 94 ativos) |
|---|---:|
| `can_by_member(m.id, ...)` (antes) | 14 |
| `_can_anywhere(m.person_id, ...)` | 16 |
| `_can_anywhere_by_member(m.id, ...)` | 16 |
| **`_can_anywhere(m.id, ...)` (troca ingênua)** | **0** |

`members.person_id = members.id` em **0 de 94**. A troca ingênua **compila**, não dá erro de tipo, e
esvazia em silêncio. A substituição é **por call site**, olhando qual id a linha tem em mãos.

As duas formas corretas **não são equivalentes**: `_by_member` resolve por
`persons.legacy_member_id` e alcança **92 dos 94**. Empataram em 16 porque os 2 não alcançados não
têm a capacidade **hoje** — empate por coincidência, não equivalência.

O guard que pega isso **tem de ser estático** (camada D do `1990-manage-event-portao-resourceless`):
no vivo, `false` por id errado é indistinguível de `false` por não ter a capacidade.

---

## 4. Selo de presença: disparou, e o critério do #1948 era maior que o registrado

O cron `attendance-seal-window-daily` (11h40 UTC / 08h40 BRT, `floor_date` 2026-08-27) disparou em
ponto e gravou tudo num único carimbo.

| | |
|---|---:|
| eventos elegíveis | 56 |
| eventos selados | 51 |
| não selados (coorte vazia, todos `tribo`) | 5 |
| **linhas de falta** | **80** |
| pessoas afetadas | 38 |

O handoff anterior dizia 77. Foram 80. **A #1948 estimava 9 faltas indevidas em 3 pessoas; eram 17
em 4.** A issue foi **fechada em 27/08 12h47** e as 17 estão justificadas.

### O predicado correto é COMPOSTO, e a issue não tinha isso

Decisão do PM nesta sessão:

- **evento de tribo** → exige aceite **naquela tribo** anterior ao evento
- **evento geral ou de liderança** → exige entrada como **membro** anterior ao evento

Medido: pelo critério de membro dá 17; pelo de aceite em tribo dá 5; a união é 17 (as 5 estão
contidas). **Mas o critério de tribo é o que importa para o próximo lote:** há pessoas aceitas em
tribo em 26 e 27/08 com reuniões dessa tribo em 19 e 26/08 ainda fora da janela do selo. Um
predicado só de membro **não pega** esses casos.

Cuidado extra: há vínculo de tribo com status `expired`. O predicado precisa olhar a **janela** do
vínculo, não só a existência, senão quem saiu da tribo volta a ser cobrado por ela.

**A correção da coorte (saída (d) da #1948) segue PENDENTE.** É DDL, e agora está liberada porque o
primeiro disparo já passou.

---

## 5. Higiene de board: uma hipótese refutada e uma em teste

**Refutada:** eu atribuí os cards parados a um descompasso entre ata e card. Medido: das 154 ações
de reunião, 31 têm card, e entre elas **zero divergência** nas duas direções. O único caso divergente
que existiu **fui eu que criei**, ao resolver uma ação sem mover o card, e fechei minutos depois.

**O buraco real é outro:** 123 das 154 ações (80%) não têm card. Mas **isso não é dívida** — decisão
do PM: reunião recorrente interna não precisa de card, já tem outras superfícies. O balde que merece
card é externo/parceria, ~27 de 154, e boa parte já tem.

**Em teste (hipótese, não conclusão):** as ações da Liderança #10 estavam todas num board de
*Kickoff*, não no board de quem executa. Foram redistribuídas em 27/08:

| destino | cards |
|---|---:|
| 8 boards de tribo | 14 |
| **Parcerias & Capítulos** (board novo) | 3 |
| Kickoff (plataforma, comms, insumo de reunião) | 9 |

**Pergunta a responder em ~1 semana:** elas estavam paradas por falta de execução ou de
visibilidade? Se andarem, era board errado.

Histórico que contextualiza: das reuniões de Liderança #3, #4, #8, #9 e #10, **só a #10 gerou
cards**. E #5, #6 e #7 não têm ação registrada nenhuma.

---

## 6. Achados sem issue

1. **`card_write` tem contrato incompleto, em dois pontos.** O enum documentado é
   `backlog|in_progress|review|done|archived` e **omite `todo`**, que existe, é usado em 89 cards e
   é aceito pela chamada. E **`move_to_board` rebaixa o status para `backlog` sem avisar** — não há
   nada na descrição sobre isso. Custou dois retrabalhos nesta sessão, o segundo depois de eu já
   conhecer o comportamento.
2. **`set_event_invited_members` não tem portão de capacidade.** Só checa `auth.uid() IS NULL`, e
   **apaga a lista inteira** (`DELETE ... WHERE event_id`) antes de inserir. Qualquer autenticado
   reescreve a lista de convidados de qualquer evento. A tabela está morta na prática: 1 linha, um
   evento, último uso 15/03.
3. **`attendance_record action='excuse'` não grava atribuição.** As 17 justificativas ficaram com
   `registered_by`, `marked_by` e `edited_by` **todos nulos**, embora o bloco de auditoria da
   ferramenta devolva `registered_by`. Contradiz o princípio do #1322, onde a atribuição é o que
   distingue auto-check-in de cobertura do líder.
4. **`get_recent_showcases_by_member` está em drift não sinalizado.** O corpo vivo diverge da única
   migration que a define (`20260675200000`), o drift **não está em allowlist nenhuma** e o
   `Phase C` **não acusa**. Editar a partir da captura reverteria produção.
5. **#1985 (aberta):** `rpc-v4-auth` não reconhece `can_org_by_member` como autoridade V4. Latente
   hoje; vira falso positivo com diagnóstico invertido no dia em que alguém somar um ramo V3.

---

## 7. Decisões que são do PM

- **Correção da coorte do selo** (DDL) — predicado composto da seção 4.
- **`view_pii`, etapa 3, 20 casos.** ⚠️ **Não é lote mecânico.** "Pode ver PII em algum lugar?" é a
  classe de exposição que a correção B fechou movendo para o portão **mais estrito**
  (`can_org_by_member`). `_can_anywhere` é provavelmente o helper **errado** na maioria. Decisão por
  item, com LGPD no meio.
- **Par de publicação do `write_board`** (2 casos, recurso anulável). Exigir escopo `organization`
  quando a iniciativa não resolve **tira dos 54** a criação de submissão sem tribo. Caminho frio:
  última escrita em 16/03.
- **§7 item 3, Path Y** do `_can_manage_event`. Liberado agora que o selo gravou.

---

## 8. A base é um alvo móvel, e isso mordeu três vezes

1. Contei 9 membros novos, depois 12. Três foram criados **durante a sessão**, às 01h31.
2. A #1948 dizia 9 faltas em 3 pessoas; o selo gravou 17 em 4.
3. **A outra sessão justificou 11 das 17 às 12h11**, meia hora antes de eu começar, e eu não sabia.
   Fiz as outras 6 às 12h42. Não houve colisão **por sorte**.

O item 3 acrescenta uma **quarta superfície compartilhada** entre lanes: árvore (`git worktree`),
banco (lease do #1961), memória (buscar por conteúdo antes de criar arquivo) e agora **dado de
produção**. As três primeiras têm mecanismo de proteção. **Escrita em dado de produção não tem
nenhum.** Antes de escrever em dado que outra lane possa estar tocando, meça o estado imediatamente
antes, e prefira o caminho por item ao caminho em lote.

---

## 9. Relógios

- **28/08** — funil.
- **08/09 20h** — webinar da Tribo 11 (frente própria, não desta lane).
- **09/09** — 1ª mordida da retenção.
- **15/09** — fecha a janela self-service de tribo.
- **30/09** — portão da anonimização.

Ações de reunião abertas com prazo vencido, medidas em 27/08: **63**, em 20 pessoas, sendo **33 com
mais de 30 dias** e a pior com 110. **41 das 63 não têm card** e **8 não têm dono**. Há ainda 66
ações abertas **sem prazo**, que não entram nessa conta por construção.
