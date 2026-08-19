# EPIC #1877 - Mapa da jornada de onboarding (auditoria, nao redesenho)

> **Escopo:** auditar exercendo, agrupar o que ja existe aberto, e formular a decisao pendente.
> **Nao ha desenho de melhoria aqui, por mandato da issue.**
>
> **Todas as medicoes: 2026-08-19, entre 21:55 e 22:20 UTC**, contra o banco de producao,
> por `execute_sql` somente-leitura e por impersonacao (`set_config` da claim antes de
> `SET LOCAL ROLE authenticated`). **Re-medir antes de agir.** Nenhum numero deste documento
> pode ser recitado numa decisao futura sem nova consulta.
>
> **Metodo do "exercido":** as RPCs da jornada foram chamadas *sob a identidade do membro*
> (impersonacao), e o que a tela renderiza foi derivado do componente alimentado com esse
> payload exato. Nao houve sessao de navegador com credencial real. Onde a distincao importa,
> esta anotada.

---

## 0. As seis perguntas da Diretoria, respondidas

Resposta curta primeiro. A evidencia de cada uma esta na secao indicada.

| # | pergunta | resposta | onde |
|---|---|---|---|
| 1 | O candidato sabe escolher tribo? | **Nao, e hoje nem pode.** A tela de escolha existe, mora em `/workspace` e a jornada nao aponta para ela. Alem disso a janela de pedido esta **fechada por prazo ha 28 dias** | 1 |
| 2 | Tem acesso as tribos que tem vaga? | **Nao.** O payload traz so `tribe_id` e `title`. **3 das 12 ofertadas ja estao lotadas** e a capacidade so e checada no envio; outras **2 tribos com 16 vagas** estao inativas e nao aparecem | 3.1 |
| 3 | Tem acesso aos videos? | **Nao, embora os videos existam.** **12 de 12 tribos ativas tem `video_url` preenchido**, e a tela de escolha nao mostra nenhum | 3, lacuna 5 |
| 4 | Ao escolher, recebe alerta de que o lider precisa aprovar? | **O alerta existe** (`tribe_request_reviewed`, 39 linhas). **Ninguem chega nele**, porque nao ha como escolher com a janela fechada | 1 |
| 5 | O lider recebe alerta da necessidade de aprovacao? | **Existe** (`tribe_request`, 40 linhas). Mesma causa: sem pedido, sem alerta | 1 |
| 6 | O painel mostra membresia, filiacao e capitulo? E diz ao nao filiado que filiar-se e beneficio? | **Parcial.** A escolha entre multiplos capitulos funciona (variante `choose`, exercida), mas vive em `/workspace`, fora do checklist. **Ao nao filiado nao mostra nada**: ele cai no bucket `no_application` e o componente retorna sem renderizar | 3, lacunas 2 a 4 |

**O padrao das seis:** quatro delas ("existe?") tem resposta **sim, existe e esta construido**. O
que falta nao e capacidade, e **alcance**: as pecas estao em `/workspace`, e a jornada nunca
aponta para la. Desenhar por cima disso constroi a segunda copia.

---

## 1. A correcao mais importante: o fluxo de tribo nao esta "parado", esta FECHADO

A #1877 registra que `tribe_request` e `tribe_request_reviewed` pararam em 20/07 e levanta a
hipotese de desuso ou de alocacao administrativa ter virado o caminho de fato.

**A medicao diz outra coisa.** Existe um portao de prazo explicito:

| fato | valor medido |
|---|---|
| `platform_settings.tribe_request_deadline` | **`2026-07-22T02:59:00Z`** |
| `now()` na hora da medicao | `2026-08-19 22:04 UTC` |
| janela | **fechada ha 28 dias** |

`request_tribe_assignment(p_tribe_id, p_message)` levanta excecao quando `now() > deadline`, e
`get_my_tribe_request_context()` devolve `eligible: false` com `ineligible_reason: 'window_closed'`.

Exercido sob a identidade de um membro que entrou em **15/08** (ativo, papel `researcher`, sem tribo):

```json
{ "eligible": false, "ineligible_reason": "window_closed",
  "deadline": "2026-07-22T02:59:00+00:00", "pending": null, "current_tribe_id": null }
```

**Consequencia para a pergunta 4 e 5 da Diretoria:** os dois alertas existem, o codigo que os
dispara existe, e **nenhum candidato consegue chegar neles hoje** - nao por defeito, mas porque
a janela de pedido esta encerrada por configuracao. As notificacoes pararam em 20/07 porque o
prazo venceu em 22/07.

Isto **nao e** um defeito a consertar. E uma **decisao de processo em vigor** que ninguem
reafirmou depois que o ciclo de entrada continuou recebendo gente. Ver secao 5.

---

## 2. Mapa por passo, com o que o membro ve

Catalogo real: `onboarding_steps` tem **11 passos** - 7 gerais e 4 exclusivos de `tribe_leader`.
`get_my_onboarding()` conta contra esse catalogo (o membro exercido ve **4 de 7**).

| # | passo | o que renderiza para quem NAO tem tribo | conclusao (populacao) |
|---|---|---|---|
| 1 | `code_of_conduct` | botao "Li e aceito", conclui na hora | 70/97 = **72,2%** |
| 2 | `complete_profile` | link para `/profile` | 85/100 = **85,0%** |
| 3 | `volunteer_term` | link para `/volunteer-agreement` | 83/96 = **86,5%** (ver 2.2) |
| 4 | `vep_acceptance` | botao "Marcar como feito" | 80/97 = **82,5%** |
| 5 | `meet_tribe` | **NADA. Zero botoes.** (ver 2.1) | 71/97 = **73,2%** |
| 6 | `start_trail` | so link para `/gamification`, sem botao de marcar | 20/98 = **20,4%** (ver 2.3) |
| 7 | `first_meeting` | link para `/attendance` | 101/112 = **90,2%** |

Passos de lider (13 linhas cada): `leader_capture_video` 4 (30,8%), `leader_refine_theme` 3,
`leader_review_tribe` 3 (23,1%), `leader_roadmap` 2 (15,4%).

### 2.1 O passo 5 e beco sem saida, e a causa e dupla

Ja estava registrado que `{s.step_id === 'meet_tribe' && member?.tribe_id && (...)}` esconde o
botao sem `tribe_id`. O que **nao** estava registrado e por que nao cai no fallback generico:
`meet_tribe` esta em `BESPOKE_CTA_STEPS`, e o fallback (`!BESPOKE_CTA_STEPS.has(s.step_id)`)
traz justamente o botao **"Marcar como feito"**. Sendo bespoke, o passo perde as duas saidas:
nao renderiza o CTA proprio (falta `tribe_id`) e nao renderiza o generico (esta na lista).

**Populacao exposta hoje:** **11 membros ativos** com `meet_tribe` pendente e sem `tribe_id`
(22 linhas se incluir `alumni` e `inactive`). Dos 94 ativos, **28 nao tem `tribe_id`**.

> O comentario no proprio arquivo promete `"so no step is ever a dead-end"`. A promessa vale
> para os passos de lider (#1103), que foi o caso que a motivou; ela nunca cobriu este.

### 2.2 `volunteer_term` tem DOIS numeros, e a diferenca e semantica

| criterio | resultado |
|---|---|
| `status = 'completed'` (o que a tela conta) | 83/96 = **86,5%** |
| `completed_at IS NOT NULL` | 91/96 = **94,8%** |

A diferenca sao **8 linhas com `status = 'skipped'` e `completed_at` carimbado**, todas de
backfill (`p234_322_backfill_no_agreement_path`, `p234_322_offboarding_extension`), ou seja,
pessoas **dispensadas** do termo. Contar por carimbo conta dispensa como conclusao.

**Regra que sai daqui:** neste schema, `completed_at` nao implica conclusao. Qualquer metrica de
onboarding tem de filtrar por `status`, nunca pela presenca do carimbo. Isto vale para toda a
familia de metricas da jornada, nao so para este passo.

### 2.3 `start_trail` a 20,4% nao e abandono, e detector desligado

O passo nao tem botao de marcar (esta em `BESPOKE_CTA_STEPS`, entao so renderiza o link para
`/gamification`). A **unica** via de conclusao e `auto_detect_onboarding_completions()`, cujo
criterio e existir linha em `gamification_points` com `category = 'trail'`.

| fato | valor medido |
|---|---|
| membros com ponto `category='trail'` | **58** |
| `start_trail` concluidos hoje | **20** |
| **elegiveis nao marcados** | **38** |
| ultima conclusao de `start_trail` | **2026-04-09** |
| ultimo ponto `trail` registrado | **2026-08-16** |
| `auto_detect_onboarding_completions` em `cron.job` | **nenhuma ocorrencia** (67 crons ativos) |
| chamadas no codigo de produto | **nenhuma** (so aparece em `database.gen.ts`) |

A trilha esta viva (ponto mais recente em 16/08); o detector rodou pela ultima vez em abril e
nao tem agendamento nem chamador. **38 pessoas ja fizeram a trilha e o passo continua pendente
para elas.** O passo mais abandonado da jornada e, na verdade, o pior instrumentado.

> Cuidado ao projetar o "depois": o `INSERT ... ON CONFLICT` tambem **cria linha** para quem nao
> tem, entao o denominador se move junto. O numero seguro e "38 elegiveis nao marcados", nao um
> percentual projetado.

### 2.4 Cinco chaves orfas (#1875), confirmadas

`accept_terms`, `join_whatsapp`, `kick_off`, `platform_access`, `profile_complete`: **24 linhas
cada, 120 no total, zero conclusoes, nenhuma no catalogo `onboarding_steps`**. Status observados
sao `pending` e `overdue`, ou seja, `detect_onboarding_overdue` (cron ativo, `0 13 * * *`) **marca
como atrasada** etapa que nenhuma tela mostra e que ninguem pode concluir.

---

## 3. As 7 lacunas do prompt de arranque, respondidas

**1. Exercer a jornada logado, com membro sem tribo.** Feito, secao 2. Ve 7 passos, 4 concluidos,
`meet_tribe` pendente **sem nenhum botao**.

**2. `EntryChapterNudge` esta montado? Dispara quando? Para quem?** Montado **apenas em
`/workspace`** (`src/pages/workspace.astro:147`). Sai calado, sem renderizar, quando:
`operational_role === 'guest'` (**8 ativos**), `member_status !== 'active'`, ja existe
`entry_chapter_code`, ou **`affils.length === 0`**. Tem 4 variantes: `profile_private`,
`no_fetch`, `not_affiliated` e `choose`.

**3. Filiacao e capitulo na jornada, e escolha entre multiplos capitulos.** A escolha existe e
funciona: exercido sob um membro com 2 afiliacoes BR e sem capitulo de entrada, o diagnostico
devolveu `bucket: "ambiguous"` com `active_br_codes: ["PE","RS"]` e ambas com `is_entry: null`,
o que cai na variante **`choose`**. **Coorte: 13 ativos com multiplas afiliacoes; 8 sem
`entry_chapter_code`.** Mas isso vive em `/workspace`, **fora** do checklist da jornada.

**4. O nao filiado e informado de que filiar-se e beneficio?** **Nao, e ha um caminho morto.**
Exercido sob um membro ativo sem nenhuma afiliacao, o diagnostico devolveu
**`bucket: "no_application"`**, que **nao esta** em `PMI_BUCKETS`; o fluxo cai no passo 2, encontra
`affils.length === 0` e **retorna sem renderizar nada**. A variante `not_affiliated` existe no
componente e e produzida por `classify_entry_chapter()`, mas so e alcancada por quem **tem
candidatura casada**. Detalhe da causa: `get_my_entry_chapter_diagnosis()` casa a candidatura por
**`lower(sa.email) = lower(v_member.email)` apenas**.

| medicao (com controle, sobre 94 ativos) | valor |
|---|---|
| sem candidatura casada por e-mail (caem em `no_application`) | **21** |
| desses, **achaveis por `pmi_id`** | **1** |
| desses, sem candidatura por nenhuma das duas chaves | 20 |
| ativos sem nenhuma linha de afiliacao | **3** |

O "1" e exatamente a classe do **#1863** (juncao por e-mail esconde vinculo que o identificador
forte acha), agora medida dentro da jornada.

**5. Ha video de tribo que ajude a escolher?** **Existe, e o seletor nao o mostra.** As **12
tribos ativas tem `video_url` preenchido (12 de 12)**. O payload de
`get_my_tribe_request_context()` traz **somente `tribe_id` e `title`** - sem video, sem tema, sem
lider, sem agenda, sem vaga. A pessoa escolheria **pelo nome**.

**6. Por que `start_trail` esta em 20,4%.** Respondido na secao 2.3: detector sem agendamento.

**7. Por que `tribe_request` parou em 20/07.** Respondido na secao 1: **prazo vencido em 22/07**,
nao defeito e nao mudanca de processo registrada.

### 3.1 Achado adicional nao previsto: a lista de tribos ignora vaga

O teto e `tribe_capacity_limit() = 8`. A lista devolvida ao candidato **nao filtra por vaga**:

| situacao | tribos |
|---|---|
| ofertadas no seletor | **12** |
| **ofertadas e ja lotadas (8/8)** | **3** (Radar Tecnologico, ROI & Portfolio, PMO Inteligente) |
| existentes porem `is_active = false`, com 0 membros e 8 vagas cada | **2** (Agentes Autonomos, TMO & PMO do Futuro) |

`request_tribe_assignment` **checa capacidade so no envio**. Com a janela aberta, 1 em cada 4
escolhas possiveis levaria a uma recusa no ultimo passo. E ha **16 vagas dormentes** invisiveis.

Sobre o passo 5 prometer "lider, agenda, WhatsApp": das 12 ativas, **todas tem lider e WhatsApp**,
mas "agenda" tem quatro leituras diferentes - **4** sem `meeting_schedule`, **7** sem
`meeting_time_start`, **6** sem `meeting_link`, **2** sem nenhum dos dois campos de horario.
Qualquer alvo de "publicar agenda" precisa dizer **qual campo** conta.

---

## 4. Triagem das 19 issues agrupadas

Todas verificadas como **OPEN** em 19/08.

### 4.1 Entra no escopo do redesenho (nucleo)

| issue | por que entra | relacao |
|---|---|---|
| **#1875** | 120 linhas orfas marcadas `overdue` por cron; e o denominador da jornada | confirmada integralmente |
| **#1014** | convite direcionado para aceitos sem conta. **Medido: 12 ativos sem `auth_id`**, dos quais 4 entraram em agosto, 5 sao `guest`, e **4 ja tem linhas de `onboarding_progress` semeadas sem poder logar** | pre-requisito de tudo: sem conta, nenhum passo existe |
| **#873** | jornada de pre-termo para guests. **8 ativos sao `guest`** e o `EntryChapterNudge` sai calado para todos eles; **5 desses 8 nem tem `auth_id`** | mesma coorte do #1014 |
| **#1277** | gaps de entrada/candidatura (ghosts, leads) | mesma raiz do #1014: entrada sem conta |

### 4.2 Entra no escopo (tribo)

| issue | por que entra |
|---|---|
| **#1356** | `set_tribe_whatsapp`; o passo 5 promete "lider, agenda, WhatsApp" e a agenda tem 4 definicoes |
| **#809** | onboarding de lider em pre-deploy; os 4 passos `leader_*` estao entre 15,4% e 30,8% |
| **#1777** | filiacao a tribo sem `write_board`; e a consequencia da alocacao administrativa (secao 5) |

### 4.3 Entra no escopo (filiacao e capitulo)

| issue | por que entra |
|---|---|
| **#1863** | **medida dentro da jornada**: 1 dos 21 sem match por e-mail e achavel por `pmi_id` |
| **#1866** | auto-verificar quem tem evidencia; 19 ativos com afiliacao nao verificada |
| **#1867** | denominador no digest; os **3 ativos sem nenhuma linha** nao aparecem em contagem nenhuma |
| **#1581** | inconsistencia de capitulo em aceite antecipado; toca `entry_chapter_code` (8 ativos nulos) |

### 4.4 Mesma coisa que outra, candidatas a fundir

- **#1866 + #1095** - ambas sao "automatizar a verificacao de filiacao". A #1095 (04/07) e a
  formulacao antiga; a #1866 (19/08) e a mesma ideia ja com o padrao invertido e mais recente.
  **Recomendacao: fundir na #1866 e fechar a #1095 como superseded.**
- **#1580 + #1095** - "alerta de vencimento breve" e literalmente um dos tres itens da #1095.
  **Recomendacao: manter #1580 so se o descasamento com periodo de servico for tratado a parte;
  senao, absorver.**

### 4.5 Provavelmente obsoletas, re-medir antes de fechar

- **#1852** ("filiacao de capitulo do VEP parada ha 4 meses"): **nao se sustenta hoje**. Afiliacao
  `pmi_vep` mais recente **criada em 15/08** e **verificada em 17/08**; 101 afiliacoes VEP no
  total. Dos **55 ativos que entraram apos 30/04, 52 tem afiliacao** e **3 nao tem**.
  **Recomendacao: reduzir ao caso dos 3, ou fechar.**
- **#1219** ("criacao governada de 2 tribos novas"): as duas tribos nomeadas **ja existem e estao
  ativas** - Dados em Projetos de IA (id 13, 2 membros) e Fluencia em IA (id 14, 4 membros). O
  entregavel de criacao esta feito; resta so o "mecanismo canonico documentado".
  **Recomendacao: retitular para o mecanismo, e anexar o achado novo das 2 tribos inativas com
  16 vagas dormentes (secao 3.1).**

### 4.6 Fica fora deste escopo

| issue | por que sai |
|---|---|
| **#1171** | arquivar EFs dormentes; higiene, sem efeito na jornada vivida |
| **#1358** | governanca de papel (`chapter_liaison`); vizinho, nao jornada |
| **#1876** | reenvio de convite de agendamento; e do ciclo seletivo, antes da jornada |
| **#617** | ThoughtSpot; explicitamente gated em outro trilho |

---

## 5. A decisao pendente, formulada e NAO tomada

**Pergunta:** qual e o caminho oficial de entrada em tribo?

Hoje existem os dois, e **nenhum esta declarado como o oficial**:

- **Caminho A, pedido do membro (`tribe_request`).** Construido, testado, com notificacao aos dois
  lados, cancelamento (#1255) e portao de capacidade. **Esta desligado por prazo desde 22/07.**
- **Caminho B, alocacao administrativa.** E o que vem acontecendo. Nao passa por
  `request_tribe_assignment`, e **e a raiz do #1777** (24 pesquisadores sem `write_board`).

O que torna a decisao urgente e que **a plataforma esta contando com o caminho A sem que ele
exista**: ha registro de que a alocacao de um membro foi **revertida em favor de "ele escolhe a
tribo dele apos o onboarding"** - e a janela de escolha esta fechada ha 28 dias. **11 membros
ativos** estao parados no passo 5 sem tribo e sem botao.

As tres saidas, com o que cada uma exige:

| saida | o que precisa | efeito colateral conhecido |
|---|---|---|
| **A1. Reabrir a janela** (mover ou anular `tribe_request_deadline`) | uma decisao do PM, sem codigo | volta a valer o defeito 3.1: 3 das 12 ofertadas estao lotadas e o payload nao mostra vaga nem video |
| **A2. Janela por pessoa** em vez de data global | mudar o portao de `now() > deadline` para janela relativa a entrada | e desenho, fora do mandato desta issue |
| **B. Declarar a alocacao administrativa como oficial** | aposentar o caminho A, resolver o #1777, e mudar a copy do passo 5 | assume o custo de o membro nao escolher |

**Nao recomendo escolher sem antes decidir o 3.1**, porque reabrir a janela com a lista atual
entrega ao candidato 12 opcoes das quais 3 recusam no envio e 2 tribos vazias nao aparecem.

### Decisoes menores que nao dependem dessa

1. **Ligar `auto_detect_onboarding_completions`** em cron, ou chamar de algum ponto: destrava
   **38 pessoas** no passo 6. Independe do caminho de tribo.
2. **Tirar `meet_tribe` de `BESPOKE_CTA_STEPS`**, ou dar-lhe empty-state proprio: acaba o beco
   sem saida dos **11**. Independe do caminho de tribo.
3. **Padronizar a metrica em `status`, nunca em `completed_at`** (secao 2.2).
4. **Decidir se `no_application` deve falar com o nao filiado** ou se a variante `not_affiliated`
   e codigo morto (secao 3, lacuna 4).

---

## 6. Criterio de aceite proposto por item

Formulados para serem verificaveis, nao para prescrever solucao.

| item | criterio de aceite |
|---|---|
| beco sem saida do passo 5 | um membro ativo sem `tribe_id` renderiza **pelo menos uma** acao no passo 5; verificavel exercendo a jornada sob a identidade de um dos 11 |
| `start_trail` | `elegiveis_nao_marcados` (membros com ponto `trail` e sem passo concluido) cai a **0** e volta a 0 sozinho apos novo ponto |
| chaves orfas | `onboarding_progress` nao tem `step_key` fora de `onboarding_steps`; guard que falha se aparecer |
| metrica do termo | toda leitura de conclusao filtra `status='completed'`; as 8 linhas `skipped` nao contam como concluidas |
| lista de tribos | o payload do seletor carrega vaga e video, e tribo lotada nao e ofertavel, ou e ofertada marcada como cheia |
| nao filiado | um ativo sem afiliacao ve alguma coisa, ou fica registrado que por decisao nao deve ver |
| diagnostico por e-mail | o membro achavel por `pmi_id` deixa de cair em `no_application` |
| caminho de tribo | existe **um** caminho declarado oficial, e o outro esta desligado ou documentado como excecao |

---

## 7. O que NAO foi possivel medir

- **Sessao de navegador com credencial real.** A auditoria exerceu as RPCs sob a identidade do
  membro e derivou a renderizacao do componente com esse payload. Um passo de UI que dependa de
  estado so-cliente (por exemplo o `localStorage` de dispensa do `EntryChapterNudge`, TTL de 14
  dias) **nao foi exercido**.
- **Se os 11 do passo 5 chegaram a ver o seletor** antes de 22/07. Nao ha carimbo que separe
  "entrou antes e nao escolheu" de "entrou depois e nunca pode".
- **Por que o prazo foi definido em 22/07** e se alguem decidiu nao renova-lo. Nao ha
  `updated_at` em `platform_settings`, entao a data da decisao nao e recuperavel da tabela.
