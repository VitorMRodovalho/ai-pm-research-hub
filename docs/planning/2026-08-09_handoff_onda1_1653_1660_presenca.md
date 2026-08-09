# Handoff - Onda 1 (presença): #1653 e #1660, os dois primeiros passos

> Sessão de 09/08/2026. Arranque: `docs/planning/2026-08-09_PROMPT_ARRANQUE_ONDA1_PRESENCA.md`.
> Todo número aqui foi medido nesta sessão contra `ldrfrvwhxsmgaabwmaik`. Re-medir antes de usar:
> o denominador anda (era 89 no plano, 87 hoje).

---

## O que entrou

| issue | PR | estado |
|---|---|---|
| **#1653** evento de audiência global sumia da grade de tribo | **#1703** | mergeado, `863a6dc4` |
| **#1660** falta simples não era gravável | **#1704** | verde, aguardando merge |
| **#1705** `clear_member_attendance` sem chamador | - | aberta como follow-up do #1660 |

Decisões do PM aplicadas: as 6 famílias novas ganharam posição na sequência, o #233 foi
desbloqueado e o #727 retitulado. Detalhe abaixo.

---

## #1653 - a grade descartava o evento de todo mundo

`get_tribe_attendance_grid` tinha dois filtros de iniciativa em série. O primeiro abria exceção
para `geral`/`kickoff`/`lideranca`; o segundo (`e.initiative_id IS NULL OR i.legacy_tribe_id =
p_tribe_id`) a desfazia. Evento `geral` com `initiative_id` de rastreio aponta para iniciativa
avulsa, cujo `legacy_tribe_id` é NULL, e `NULL = p_tribe_id` é NULL para qualquer tribo.

O filtro de iniciativa só vale para o evento cuja audiência **é** a tribo:
`AND (e.type <> 'tribo' OR i.legacy_tribe_id = p_tribe_id)`.

### Antes e depois, com as duas RPCs de verdade

Painel contra grade, com o chamador impersonado por `request.jwt.claim.sub` numa transação de
leitura. **87 membros ativos**, **66 comparáveis** (os que aparecem na grade da própria tribo).

| medida | antes | depois |
|---|---:|---:|
| divergentes na tela | 42 | 26 |
| **divergência de contagem** | 42 | **0** |
| delta máximo | 25,0 pp | 0,5 pp |
| líderes divergentes (de 12) | 7 | 4 |

**Os 26 que sobram não são este defeito.** Numerador e denominador batem em 66 de 66; o que difere
é escala e arredondamento (grade a 2 casas em 0-1, painel a 1 casa em 0-100). Igualando a escala,
**0 de 66**. Isso é o #1656.

⚠️ **O aceite da épica precisa desta correção de redação.** Ele dizia "0 membros divergentes", que
o #1653 sozinho não alcança e não deveria alcançar. O que esta filha tinha de entregar é **0
divergência de contagem**.

---

## #1660 - a premissa da issue estava meio errada

A issue dizia que a plataforma **não consegue** gravar "faltou". Lendo o corpo vivo de
`mark_member_excused`, o ramo `ELSE` faz `UPDATE ... SET excused = false` e **não toca `present`**:
numa linha criada pelo ramo `IF`, desjustificar deixa `present=false, excused=false`.

Não era ausência de capacidade, era **contorno**: o ato direto apagava, e o único caminho para a
falta passava por afirmar uma justificativa que não existia. As 3 linhas de falta simples da base
são todas anteriores ao p199-c, com `excuse_reason` nulo e `updated_at > created_at`, que é a
assinatura desse caminho.

A distinção decidiu o escopo: "não dá" pediria capacidade nova; "só por contorno" pede que **o ato
direto volte a significar o nome dele**.

### O que mudou

| função | antes | depois |
|---|---|---|
| `mark_member_present(false)` | `DELETE` | grava `present=false, excused=false` |
| `clear_member_attendance` | não existia | desfaz o registro (o ato do p199-c, com nome próprio) |
| `admin_bulk_mark_attendance(false)` | `DELETE` em lote | grava falta em lote |
| `admin_bulk_mark_attendance(true)` | não gravava `present` | afirma `present = true` |

A última é **consequência da primeira, não escopo extra**: o ramo verdadeiro confiava no DEFAULT da
coluna e o `DO UPDATE` não tocava `present`. Inofensivo enquanto falta não existia como linha; a
partir da mudança, marcar o lote como presente deixaria ausente quem já tivesse linha de falta.

### Nenhuma mudança de front, e o porquê é o achado

O front **já modela três estados e já pede o certo**: calcula `nextState: 'present' | 'absent'`,
chama `mark_member_present(false)` e mostra `❌ Ausente`. A UI dizia ausente, o banco apagava, e a
inferência por ausência (#1657) reconstruía "ausente" na releitura. **Duas falhas silenciosas
empilhadas que se cancelavam na tela** - por isso ninguém viu em três meses.

De quebra: a sequência `excused → absent` chamava `mark_member_excused(false)` logo depois do
`mark_member_present(false)`, ou seja, um `UPDATE` numa linha que o `DELETE` acabara de remover.
Zero linhas afetadas, em silêncio.

### Superfície contada antes de aplicar

| medida | valor |
|---|---:|
| funções em `public` que mencionam `attendance` | 95 |
| **inferem falta pela AUSÊNCIA de linha** | **33** |
| escrevem em `attendance` | 9 |
| dessas, apagam a linha | 4 |

As 33 continuam inferindo: agora elas veem faltas explícitas **além** das inferidas. Desfazer a
inferência é o **#1657**, o próximo da ordem.

---

## Método que se firmou nesta sessão

### Captura provada por md5, em vez de transcrição confiável

O corpo de `get_tribe_attendance_grid` tem 9.603 bytes. Ele não foi transcrito no escuro: o arquivo
é o corpo vivo com **uma** substituição ancorada, e o verificador **desfaz a substituição e compara
o md5 com o medido em produção antes do DDL**. Igualdade = transcrição byte a byte, e a única
diferença é a que se quis fazer. Depois de aplicar, o corpo vivo bate com o arquivo.

Os scripts ficaram em scratchpad porque são de uso único, mas o padrão vale a pena repetir:
**qualquer recaptura de função grande deve provar a fidelidade por hash, não por leitura.**

### Prova comportamental em produção que se desfaz sozinha

As duas triggers de `attendance` são SQL puro (nenhuma chama `pg_net`/`http`), então um bloco `DO`
que impersona, exerce a RPC, lê o resultado e termina em `RAISE EXCEPTION` prova o comportamento e
**não deixa rastro**:

```
mark_member_present(evento, membro, false)  ->  present=f excused=f reason_null=t
clear_member_attendance(evento, membro)     ->  {"success": true, "cleared": 1}, restantes=0
```

2.029 linhas e 3 faltas simples antes e depois. **Conferir as triggers antes de usar isto**: uma
que chame serviço externo não é desfeita pelo rollback.

### Guard de duas camadas, porque a estática sozinha não observa o mundo

As RPCs de presença resolvem o chamador por `auth.uid()` e recusam `service_role`, então não há
camada comportamental automatizável (mesma limitação declarada no #1476). A saída foi:

- **camada A**: asserções sobre a captura mais recente, com o ponteiro **derivado** de
  `loadLatestCaptures` - nunca um caminho de migration escrito à mão (lição do #1682/#569)
- **camada B**: compara o `body_md5` **vivo** com o md5 normalizado da captura sobre a qual a
  camada A roda

Com a B, a asserção estática deixa de ser uma afirmação sobre um arquivo. Provado por mutação nos
dois guards: **3 de 5** e **3 de 9** vermelhos, incluindo a camada viva nos dois casos.

### Três armadilhas de medição que apareceram e custariam caro

1. **A lógica de três valores mordeu a própria query de medição.** Contar `NOT (initiative_id IS
   NULL OR legacy_tribe_id = tid)` devolve zero para exatamente as linhas do defeito, porque o
   predicado é NULL, não falso. É o mesmo mecanismo do bug, dentro da ferramenta que o mede.
   `COALESCE(..., false)` antes de contar.
2. **Precedência de `AND`/`OR` num CTE de medição** deixou o filtro de data valendo só para o
   primeiro ramo e trouxe evento de fora do ciclo. O número "1 evento de liderança excluído" era
   artefato.
3. **A varredura leu o comentário como código.** `mark_member_present` **cita** `present=false`
   num comentário do p199-c, e a contagem de "quem grava falta" o classificou como escritor. Tirar
   comentário antes de asserir - e o guard novo faz isso na própria asserção.

---

## As três decisões do PM, aplicadas

1. **Ordem das 6 famílias: instrumento primeiro.** A posição foi gravada **na descrição do
   rótulo**, para aparecer onde o trabalho é escolhido e não só num documento:

   | rótulo | posição | abertas (bloqueadas) |
   |---|---|---:|
   | `onda:suite-ci` | Onda 6 | 11 (0) |
   | `onda:dados-metricas` | Onda 7 | 14 (2) |
   | `onda:admin-ui` | Onda 8 | 15 (1) |
   | `onda:comms` | Onda 9 | 12 (1) |
   | `onda:certificados` | Onda 10 | 10 (1) |
   | `onda:legal-ops` | Onda 11 | 19 (3) |

   `suite-ci` primeiro porque é a única sem bloqueada e é o instrumento com que toda onda prova o
   próprio aceite; `legal-ops` por último porque 3 das 19 dependem de terceiro.

2. **#233 desbloqueada.** Nenhum bloqueador nomeado desde 21/05, escopo já escolhido pelo PM na
   mesma data, fontes canônicas do escopo vivas. O rótulo mascarava "não começada". Mesma correção
   do #335 e do #989 na trilha (a).

3. **#727 retitulada.** O título dizia "farol 🔴 vencido **bloqueado**", falso desde 30/06, quando
   o #571 fechou. Os três itens do escopo estão executáveis.

---

---

# Adendo - o #1657 e o #1705 também fecharam nesta sessão (PR #1708)

## A regra

Sem linha num evento **não selado** passa a ser `unrecorded`, não `absent`. `seal_event_attendance`
materializa a linha de no-show, então **selar** é o ato que transforma omissão em ausência, e ele
tem dono (`manage_event`).

| medida | antes | depois |
|---|---:|---:|
| células acusando falta sem registro | **92** | **0** |
| membros afetados | 43 | 0 |
| rotulados `detractor` só por falta inferida | 2 | **0** |
| rotulados `at_risk` só por falta inferida | 5 | **0** |
| rate médio | 0,779 | 0,781 |

## O denominador quase virou a segunda mentira

Trocar a célula **sozinha** colapsaria o `rate`: não há **nenhuma** falta declarada no ciclo, então
o denominador `present + absent` viraria só `present` e **65 de 66** membros iriam a 100%, com a
média saltando para 0,985. Foi pego medindo depois de aplicar, não antes.

**A lição:** tirar a acusação de um lugar pode inflar a métrica no outro. Quem muda o significado
de um estado tem de medir o agregado na mesma volta, não só a célula.

## Três achados que valem mais que o conserto

**1. A defesa do p124 estava inerte, e o guard dela ficava verde.** O ramo
`COALESCE(erc.row_count,0)=0 THEN 'na'` saiu do corpo vivo na migration de **captura de deriva**
`20260802000001_p209_...`; o CTE continuou sendo calculado, alimentando um alias que nenhuma linha
lia. O guard só exigia que o CTE **existisse** em migrations posteriores. Uma captura de deriva
**oficializa** a perda: o trabalho dela é registrar o que está vivo, e se o vivo já perdeu a
defesa, a captura torna a perda oficial.

**2. Ler o corpo da RPC não diz o que o ATO faz.** Li `cancel_event_occurrence`, afirmei que não
tocava em `attendance`, e o corpo de fato não toca - o **trigger**
`trg_cleanup_attendance_on_event_cancel` toca, e apagou as 9 linhas do evento cancelado. O
resultado final era o pretendido (as 9 pessoas têm a presença real no Kick-off do mesmo dia,
verificado antes), mas o caminho não era o que descrevi. **Conferir os triggers da tabela antes de
prometer o que um ato faz.**

**3. Um guard escrito de manhã ficou obsoleto à tarde.** O teste do #1653 exigia o CTE do p124; o
#1657 o removeu com razão, e o guard ficou vermelho por trabalho **correto**. Corrigido para exigir
a **proteção**, não o formato dela.

## A Liderança #7 (09/07)

O GP confirmou que **não aconteceu**. Verificado antes de tocar: as 9 pessoas com linha lá têm
**todas** presença no Kick-off do mesmo dia, então 0 precisavam de migração. Cancelada por
`cancel_event_occurrence` (reversível), só esta ocorrência - a série tem 15, com 9 futuras
intactas.

## Próximo

**#1656** (escala e semântica), que decide o denominador definitivo e fecha os 26 divergentes por
arredondamento. Depois **#1655 → #1654**.

⚠️ **#1710** nasceu deste PR e é pré-requisito prático: `seal_event_attendance` não tem superfície
(**0 de 302** eventos selados). Enquanto ninguém sela, "sem registro" nunca vira falta - seguro,
mas a plataforma segue sem conseguir afirmar uma ausência em massa.

---

## Próximo (registro original, já superado acima)

**#1657**, a inferência: parar de inventar falta a partir de linha ausente, com as 33 leitoras
contadas e o par de eventos duplicados de 09/07 resolvido. É o passo que dá sentido ao #1660 -
enquanto a leitura inferir, a falta explícita e a inferida convivem sem se distinguir.

Depois, **#1656** (escala e semântica, que fecha os 26 divergentes de hoje) e então
**#1655 → #1654**.

### Vivo e não fechado

- **#1705**: `clear_member_attendance` existe e não tem chamador. O front não tem o ato "limpar
  registro" e a tool MCP `attendance_record` ainda declara no manifesto que *"present=false is a
  no-op by design"*, frase que o #1660 tornou falsa. Exige deploy de EF.
- **Reescrita de histórico** (PII) segue pendente, é ação do mantenedor, e o audit de bypass
  precisa ser avisado antes.
- **#334** (notificação LGPD Art. 48) segue `status:blocked` com bloqueador vivo.
