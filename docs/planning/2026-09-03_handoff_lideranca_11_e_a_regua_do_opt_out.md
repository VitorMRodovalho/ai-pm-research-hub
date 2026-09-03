# Handoff 03/09/2026 (tarde): a Liderança #11, e o opt-out que promovia sem régua

> Números medidos entre 13h e 22h UTC de 03/09. Envelhecem sozinhos. Re-meça antes de decidir.

## Estado ao encerrar

`main b100431a` · lane `docs/lideranca-11-preparo` em `d176ffee` · **PR #2168 aberta e NÃO mergeada**
(10 checks verdes, 2 vermelhos) · janela de bypass em **2 de 2**, intocada, sem push direto.

**`main` está vermelha, e não foi PR nenhuma.** Ver "O vermelho é de dado" abaixo.

Uma migration aplicada: `20260903172106_2004_opt_out_nao_promove_de_submitted`. Arquivo local
**alinhado à tracking row** (o `apply_migration` carimba timestamp próprio; o meu era `...171500`).
Nenhuma Edge Function deployada.

Lane nova criada: `.wt-lideranca`. As outras duas seguem vivas: `.wt-campanha` (webinar 08/09) e
`.wt-cpmai` (TAP 11/09).

## O que foi entregue

**A página de condução da Liderança #11**, para Fernando e Fabricio, que conduziram sem o GP:
https://claude.ai/code/artifact/53824d61-5d5a-409c-8cf2-8d29d5eeafdb
(privada; só abre para quem receber o compartilhamento). Fonte em
`docs/planning/reuniao-lideranca-11.html`. Publicada às 16h20 e **republicada às 22h**, porque a
fila de ações mudou durante a própria sessão.

O diagnóstico que a organiza, medido nas transcrições e não na coluna `duration_actual` (que é
default 60 em quase tudo e mente): a **#10 durou 132 min contra 90 previstos**, e não por causa das
tribos. A rodada foi partida ao meio por um bloco estratégico de 37 min no minuto 29 e voltou só em
01:06. Quem ficou para o fim pagou: o líder da T14 falou **8 palavras** em 132 minutos. **Nenhuma
das 9 últimas reuniões teve pauta publicada.** GP e presidência somam **48,2%** da fala.

**Ajustes de dado aplicados** (executam a ação de 06/08, "varrer os cards e marcar o que for
artefato como reportável"):

| ajuste | delta |
|---|---|
| cards de tribo marcados como item de portfólio | 62 → **95** |
| tags de tipo do catálogo `system`/`board_item` aplicadas | **+66** |
| entregas concluídas que receberam o XP pendente | **18** (560 pts, 15 pessoas) |
| `occurred_at` carimbado na data real da entrega | 17 |
| gap de confiança alta restante | **0** |

Os **41 cards sem data-base** ficaram como mesa de decisão dos líderes, respeitando o princípio
declarado na migration `20260820215416`: tipificar entregável é conteúdo do líder, não automação.

**Sua fila de ações de liderança caiu de 18 para 11** (vencidas de 10 para 5), e a série de 82 para
75 abertas, com as fechadas indo de 8 para 15. Quatro encerradas contra evidência medida, uma
migrada para a #2151, duas viradas em issues próprias com a ressalva de que o defeito continua.

## O vermelho é de dado, e são duas causas

`main` estava verde às 13:00 (`60c13855`) e vermelha às 15:21 (`b100431a`), **sem commit no meio**.
As quatro asserções vermelhas se reduzem a duas causas:

**Causa 1, a promoção sem régua (#2004).** Às 13:44:48.599305, uma candidatura real teve 5 pilares
gravados `opted_out` e foi promovida de `submitted` para `interview_pending` **no mesmo
microssegundo** (transação única), rodando como `anon`. Cinco segundos depois o despachante tentou
4x emitir o token de agendamento, recusado nas quatro por `GATE_NO_PEER_REVIEW`. Derruba o ratchet
do #2004 (subiu de 1 para 2) e o guard do #1636 (tentativa de portão sem ator, registrado em #2171).

**Causa 2, a virada de presença das 16:28.** Seis linhas de presença de um único membro viradas
para ausente em ~50 segundos, com `edited_by` e `marked_by` nulos e **nenhuma linha de auditoria na
janela**. Deixou o marco `first_attendance` dele apontando para alguém com 11 linhas e zero
`present=true`. Derruba `AC_first_attendance_milestone_has_attendance` e `#1948 vivo`. **A origem
não foi atribuída**: verifiquei que minhas chamadas na janela foram todas `meeting_actions`, que não
escreve presença, e que rodava automação de fundo com ator nulo (`alert_sweep_run` 16:25,
`event.created`/`deleted` 16:30, `arm9.inactivity_detection_run` 16:31).

**Não afrouxe nenhum dos quatro guards.** Os quatro estão acusando corretamente.

## O conserto da régua, e por que o guard mudou junto

A decisão de 28/08 (opção C) restringiu a origem da promoção a `submitted`. A medição que a
embasou, transcrita no cabeçalho do guard, dizia:

```
(null)                8 transições, 8 já tinham avaliação
interview_scheduled   1 transição,  1 já tinha avaliação
submitted             1 transição,  0 tinham avaliação   <- o caso da issue
```

Foram removidas as **quatro origens nunca exercidas** e mantida a **única que produzia o defeito**.
O portão passou a barrar onde a avaliação já começou e a liberar onde ela não começou.

Agora o opt-out **não promove de origem nenhuma**: registra a escolha nos 5 pilares em qualquer
status e deixa rastro da não-promoção em `admin_audit_log`.

O guard também mudou, e isso pede revisão de quem for reler. Ele afirmava a **forma do IF**, e um
guard textual não distingue "promover a partir da lista" de "recusar a partir da lista": as duas
escrevem a mesma string em direções opostas. Agora ele exige a **ausência** do que só existe para
promover, medindo o corpo **sem comentários** (senão casaria o próprio texto que explica o
anti-padrão). Provado por **duas injeções de defeito**, arquivo restaurado byte-idêntico nas duas
(sha256 conferido): reintroduzir a promoção reprova; condicionar a escolha do candidato a status
reprova; árvore limpa dá 3 de 3.

## Seis pendências, e nenhuma está parada em código

| pendência | estado medido | quem destrava |
|---|---|---|
| **A candidatura travada** (#2004, metade 2) | ratchet em **2** | GP: avaliação objetiva ou destravamento explícito |
| **A virada de presença das 16:28** | invariante AC em **1** violação | decidir se foi correção legítima; se foi, o marco cai junto |
| **Webinar de PI** | `planned` em **28/05**, ação `open` | GP: data real ou cancelar |
| **Série da Tribo 14** | ação `open`; 15 linhas quarta vs 15 títulos segunda | Paulo: qual é o dia real |
| **`agenda_url` / `agenda_text` do evento #11** | **vazios** | uma chamada, quando quiserem |
| **PR #2168** | 10 verdes, 2 vermelhos | destrava sozinha quando as duas primeiras saírem |

Sobre a Tribo 14: **não existe buraco em 23/09**. A sequência dos títulos está completa; quem está
torto é a data da linha, e é ela que a agenda e o cálculo de presença leem. Eu ia criar o evento e
não criei justamente por isso.

## Issues desta sessão

Abertas: **#2169** (flag de entregável some ao recarregar), **#2170** (card concluído em vermelho),
**#2171** (as 4 tentativas sem ator), **#2175** (o gatilho de XP da #1880 que alarga o `UPDATE OF`
mas mantém a guarda de transição no corpo, então marcar card já `done` nunca paga).

Comentadas: **#2004** (a investigação completa, com a cadeia carimbada), **#2171** (reclassificada
como sintoma do #2004), **#2166** e **#2167** (as do CI Monitor, agora com causa), **#588** (cinco
lições de sessão, três de framework).

Nenhuma fechada.

## Duas notas de higiene

**A PR #2168 mistura duas metades**: a página da reunião e o `fix(#2004)`. Ficaram juntas porque a
segunda nasceu investigando a primeira e a migration já estava aplicada quando isso ficou claro.
Separar exige force-push e aval do dono.

**A página é um artifact privado.** Enquanto não for compartilhada pelo menu de share, quem receber
o link não abre. Isso quase custou a reunião: percebi às 22:17, com ela já em curso.

## A regra da sessão

> **Estreitar uma lista pela medição de USO pode preservar exatamente a origem do defeito.**

Frequência de uso e culpa são eixos diferentes. Uma tabela de "quantas vezes cada origem apareceu"
diz onde há superfície, não onde há defeito. Ao estreitar, cruze sempre com a coluna que marca qual
entrada produziu o incidente, e desconfie quando o que sobra é o caso da issue. Salvo em memória
como `reference-restringir-a-lista-pela-medicao-pode-manter-a-origem-do-defeito`, com arquivamento
de uma entrada para respeitar o teto de 200 linhas do índice.

O corolário prático de duas escritas evitadas hoje: **re-medir imediatamente antes de aplicar não é
cerimônia.** Contei 39 cards e apliquei 33 porque um líder arquivou 19 no meio da medição; e quase
criei um evento para tapar um buraco que não existia.
