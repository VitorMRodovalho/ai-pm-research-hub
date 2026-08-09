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

## Próximo

1. **Trilha (b) da Onda 0**: agrupamento. Sete clusters candidatos no plano, com a regra de que
   épica só existe com **causa comum** ("consertar a causa fecha as filhas?"). As labels de onda
   agora dão o recorte para essa conversa.
2. **Ordenar as 6 famílias novas** na sequência das ondas. A maior (legal-ops, 19) é a que mais
   depende de terceiro.
3. Onda 0.5 (superfície pública) e depois Onda 1 (presença).

⚠️ **Este handoff não foi commitado.** Push direto na `main` conta como evento de bypass
(janela de 7 dias em 1 de 2), e a classe já tem registro retroativo no #1567.
