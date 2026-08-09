# Handoff - Onda 0, trilha (a): o estado do backlog, medido

> Trilha (a) do plano por ondas, entregue em 08/08/2026. O plano vive em `~/.claude/plans/`
> (fora do repo). Trilha (c), da PII, foi entregue em 08/08; a (b), de agrupamento, segue aberta.

`main` em `a61879f2`. Nenhuma mudança de código nesta trilha: o trabalho foi medição, fechamento
e marcação de backlog.

---

## Antes e depois

| | antes | depois |
|---|---:|---:|
| issues abertas | **198** | **189** |
| fechadas | 602 | **613** |
| `status:blocked` | 11 | **10** |
| abertas sem onda atribuída | 198 | **0** |

---

## O que a medição corrigiu do plano

**"30 abertas citadas em PR mergeado" era um recorte, não o universo.** Varrendo título e corpo de
**816 PRs mergeados** mais os commits da `main`, são **81**. As 30 estão todas dentro das 81.

**A classe que interessa é pequena.** Referência com palavra-chave de fechamento numa issue que
continua aberta: **3 candidatas, 2 reais** (#105 e #727, ambas com `Fecha #N`, que o GitHub não
reconhece). A terceira, #96, é falso positivo de **outra** classe: o PR dizia *"Does NOT close
#96"* e o regex do GitHub casou o `close #96` de dentro da frase, fechando a issue sozinho.

---

## Fechadas (11), todas com a medição publicada no comentário

| issue | prova |
|---|---|
| **#105** | `get_my_meetings` viva em prod, widget montado em `workspace.astro:222`, as 3 abas, contract test. Entregue em 03/07 e presa 36 dias por `Fecha #105` |
| **#1536** | gate existe e **roda no CI**, colapso executado com tabela de recuperação, balde ambíguo preservado com evidência |
| **#1584** | tokens de escopo `interview_booking`: **0 → 17**, todos desde 04/08 |
| **#1632** | decomposta em 4 filhas, as 4 fechadas |
| **#1002** | épica de julho com a janela encerrada; as 4 filhas abertas têm rastreio próprio |
| **#1525** | o conserto pousou no PR #1532; o resíduo virou #1696 |
| **#1679** | investigação respondida; os 4 defeitos recortáveis viraram #1697 |
| **#1361 #1434 #1493 #1564** | semanas limpas de bypass-audit (0 eventos), abertas contra a convenção do próprio repo (#469, #593, #837 já haviam sido fechadas assim) |

## Abertas como recorte (2)

- **#1696** - o helper de auditoria indisponível vira `return` silencioso. O #1525 trocou "vermelho
  sem defeito" por "verde por vacuidade", e a segunda classe não pede atenção de ninguém.
- **#1697** - os 4 defeitos do funil de curadoria, com causa comum: o passo final não alcança quem
  pode executá-lo (a fila é vista por 57, acionável por 18, designável por 3, anunciada a 3).

## Anotadas (14), quatro delas com o número da própria issue corrigido

- **#1610**: são **14** ferramentas de escrita classificadas como `permission: read`, não 3.
  `WRITE_HINTS` é ancorado em `^` e só casa prefixo verbal; a família semântica inteira é
  `<substantivo>_<verbo>` (`event_write`, `selection_decide`), então cai no default `read`.
- **#1354**: entregou **1 de 5** critérios. O contador da home foi de 96 para **67**, mas a
  categorização canônica e o seletor de público de campanhas seguem abertos.
- **#1601**: `event_write` ganhou `initiative_id`; gravação e `duration_actual` continuam sem
  parâmetro, então registrar a **realização** de um evento pelo MCP segue impossível.
- **#1556**: `p_member_id` continua na assinatura viva de `log_mcp_usage`.

Também anotadas: #727, #1183, #1310, #1340, #1528, #1592, e as três da revisão de bloqueio.

---

## As `status:blocked`: dois bloqueadores estavam mortos

- **#335** esperava a remediação de #221/#218, **ambas fechadas**. Rótulo removido; está
  desimpedida.
- **#989** esperava #987/#988, **ambas fechadas**. O que resta é gatilho de negócio (o primeiro
  ciclo real de curadoria), agora **medido** pelo #1679: zero revisões registradas. Rótulo mantido,
  bloqueador renomeado.
- **#233** carrega o rótulo **sem bloqueador nomeado** desde 21/05. Não fechada nem desmarcada:
  idade não é evidência, e a decisão é do PM.

Os outros 8 têm bloqueador vivo e nomeado: dependência de terceiro (#334, #574, #1025), fornecedor
externo (#1044, #942, #617) ou ação de owner (#108, #109).

---

## A marcação de onda, e o que ela revelou

**68 das 189 (36%) não cabiam em nenhuma das 6 ondas do plano.** Não eram avulsas: formavam
famílias. Decisão do PM em 08/08: promovê-las a ondas nomeadas. Resultado, verificado:
**189 de 189 com exatamente uma onda, nenhuma com duas.**

| onda sequenciada | issues | | família nova (sem posição na sequência) | issues |
|---|---:|---|---|---:|
| `onda:0` | 3 | | `onda:legal-ops` | 19 |
| `onda:0.5` | 7 | | `onda:admin-ui` | 15 |
| `onda:1` | 8 | | `onda:dados-metricas` | 13 |
| `onda:2` | 26 | | `onda:comms` | 12 |
| `onda:3` | 20 | | `onda:suite-ci` | 11 |
| `onda:4` | 13 | | `onda:certificados` | 10 |
| `onda:5` | 32 | | | |

Consulta: `gh issue list --state open --label "onda:1"`.

---

## O que se leva daqui

1. **Citada em PR mergeado não prova entrega.** O #1354 quase foi fechado por ter o sintoma
   resolvido e tinha 1 de 5 critérios. Conferir critério a critério, nunca pelo PR que cita.
2. **Classificar backlog por regex produz triagem falsa.** A primeira passada pôs
   `[bypass-audit] Week - 0 events` na onda de agenda (casou "events") e o conector Airmeet na de
   presença (casou "presença"). Um backlog que **parece** triado é pior que um não triado, porque
   ninguém volta a olhar. O mapa final é conferido título a título.
3. **Bloqueador morto não se anuncia.** Nada no GitHub avisa que a issue que te bloqueava fechou.
4. **A prova de entrega mora fora do repositório.** `admin_list_members` devolve `jsonb`, então
   nem a assinatura nem `pg_get_function_result` dizem o que ela entrega; foi preciso perguntar ao
   corpo vivo. Grepar o repo teria dado a resposta errada nos dois sentidos.

---

---

# Trilha (b): agrupamento por causa comum

Os 7 clusters candidatos do plano, submetidos ao teste *"consertar a causa fecha as filhas?"*.
**4 viraram épica, 1 virou épica parcial, 2 foram recusados.** Cada veredito tem a causa medida,
não inferida do tema.

| cluster | veredito | a causa, medida |
|---|---|---|
| **Presença** | ✅ épica **#1652**, 2 órfãs adotadas | #1660 é a raiz e estava fora da épica; #1657 é consequência direta |
| **Autossuficiência do MCP** | ✅ **#1588** promovida | o MCP foi montado **absorvendo tools existentes**, não cobrindo operações |
| **Agenda e recorrência** | ✅ épica nova **#1699** | `events.recurrence_group` **sem índice único**: nada impede a mesma ocorrência de nascer duas vezes. **2 pares vivos** hoje |
| **O número que a plataforma reporta** | ✅ épica nova **#1700** | `get_current_cycle()` existe e **0 de 133** corpos SQL a chamam |
| **Qualidade da suíte** | ✅ épica parcial: **#1533** promovida | "o resultado não distingue exercido de não-exercido". #1691 recusado, causa diferente |
| **Segurança de front** | ❌ recusado | 3 causas independentes; tema comum, não causa |
| **Ciclo seletivo** | ❌ recusado como épica | é **onda**, não épica: 14 abertas sem causa única |

## As duas épicas novas, e por que a causa é medida

**#1699 (série recorrente).** Os únicos índices únicos de `events` são a chave primária e um
parcial sobre `calendar_event_id`. Não existe chave de idempotência sobre a **ocorrência**
(`recurrence_group`, `date`), e o dano é presente: **2 pares repetidos** vivos, além dos 4 grupos
`(title, date)` do #1528. Consertar a chave fecha #1676 e #1528, e dá ao #1565 o discriminador
entre redefinição de dia e duplicata.

**#1700 (recorte temporal).** Este é o achado que muda a Onda 5:

| medida (08/08) | valor |
|---|---|
| `get_current_cycle()` existe e responde | sim: `cycle_4`, `is_current: true` |
| funções em `public` cujo corpo a chama | **0** |
| funções que mencionam `cycles` sem chamá-la | **133** |

⚠️ **Não é zero-uso por ausência de capacidade: é contorno.** A função é chamada, mas só de fora do
banco (`HomepageHero.astro` e a tool MCP homônima), e nasceu em `20260308230000_cycles_table.sql`,
antes da maior parte das funções que a ignoram. Por isso o cluster tem causa endereçável em vez de
uma lista de sintomas.

## As recusas, que valem tanto quanto as aceitações

**Segurança de front** (#1631, #1617, #1685): interpolação crua em sink, dependência sem patch e
rota indexável são três causas independentes. Agrupá-las criaria um guarda-chuva que ninguém fecha,
que é o que a trilha (b) veio desfazer. O instrumento certo já existe: o rótulo `onda:4`.

**Ciclo seletivo** (14 abertas): é onda, não épica.

**Recusas parciais dentro dos clusters aceitos**, cada uma registrada no comentário da épica:
#1675 e #1658 fora da épica de série (causa própria); #1604, #1661 e #1662 fora da de recorte;
#1610, #1672 e #1681 fora da do MCP.

---

## Próximo

1. **Ordenar as 6 famílias novas** na sequência das ondas. A maior (legal-ops, 19) é a que mais
   depende de terceiro.
2. Onda 0.5 (superfície pública) e depois Onda 1 (presença), onde a ordem de dependência já está
   registrada no #1652: #1653 → #1660 → #1657 → #1656 → #1655 → #1654.

⚠️ **Este handoff não foi commitado.** Push direto na `main` conta como evento de bypass
(janela de 7 dias em 1 de 2), e a classe já tem registro retroativo no #1567.
