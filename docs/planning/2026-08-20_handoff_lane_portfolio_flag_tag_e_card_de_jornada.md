# Handoff - lane paralela: portfolio (flag/tag), card de jornada, GP x Presidencia

**Branch:** `claude/portfolio-cards-flags-tags-e7x1ar` · **PR:** #1899 (draft) · **Issue:** #1900
**Sessao:** 2026-08-20, ~21:45 a 00:00 UTC. Lane paralela a main, pedida pelo GP.

**Estado em uma linha:** as tres frentes estao entregues e medidas; a PR esta **vermelha**
por 5 falhas no `validate`, das quais **2 ja existem na main** e 3 seguem sem nome.

---

## 1. Checklist - feito x esperado

### Item 1 - entregaveis das tribos fora do portfolio (pedido original)

| Esperado | Feito | Estado |
| --- | --- | --- |
| Varrer todos os quadros das tribos | 181 cards nao arquivados, 14 iniciativas, 15 quadros | ✅ |
| Achar cards sem o flag de portfolio | **67** (34 com data-base ou entrega ja registrada) | ✅ |
| Achar cards sem tag de tipo | **30** itens de portfolio sem tag `tier=system`/`domain=board_item` | ✅ |
| Facilitar a visao no /admin/portfolio | 2 contadores no botao "Data sanity" + drill-down por RPC | ✅ |
| Corrigir os dados card a card | **NAO feito, de proposito** - tipificacao e conteudo do lider | ⏸ decisao do GP |

### Item 2 - card de jornada da tribo

| Esperado | Feito | Estado |
| --- | --- | --- |
| Recomendacao de abordagem | Card gerado por RPC, nao estatico; enquadramento de checklist, nao de faltas | ✅ aprovado pelo GP |
| Card com voce como dono e o lider junto | T6: dono `author` = Vitor, `contributor` = Messias | ✅ |
| Atividades = pendencias encontradas | 8 passos com a evidencia no proprio texto | ✅ |
| Verificar reuniao/link/gravacao/ata | J1-J5 cobrem os quatro | ✅ |
| Ata rende atualizacao pros cards | J5 mede `meeting_action_items` ligados a atas publicadas | ✅ |
| Faltas em excesso | **NAO entra no card** - decisao do GP (LGPD + tom) | ✅ por decisao |
| Rodar nas 14 tribos | So o piloto (T6) | ⏸ aguarda seu aval do tom |
| Cron semanal de reconciliacao | **Nao feito** | ⏸ proxima sessao |

### Item 3 - GP x Presidencia

| Esperado | Feito | Estado |
| --- | --- | --- |
| Diagnostico do quadro | 23 cards: 23 com responsavel, **20 com zero atividades**, **0 com baseline** | ✅ |
| Corrigir o que estiver claro | **NAO aplicado** - ver justificativa abaixo | ⚠️ ver secao 3 |
| Listar decisoes a arrumar | 34 acoes em tabela de triagem + 4 decisoes estruturais | ✅ |

---

## 2. O que esta no ar (aplicado no banco de producao)

Tres migrations, todas com arquivo versionado e corpo batendo byte a byte com `pg_proc`:

- `20260820215416_portfolio_flag_tag_gap_audit.sql`
  `portfolio_suggest_item_type(text, text[])` (heuristica IMMUTABLE, concorda com 30 dos
  31 cards que humanos ja tipificaram), `audit_portfolio_flag_tag_gaps(bool, int)`
  (SECDEF, `manage_platform`, drill-down por card), e 2 contadores novos em
  `admin_run_portfolio_data_sanity()`.
- `20260820223236_tribe_journey_card.sql`
  `tribe_journey_items(jsonb)`, `tribe_journey_health(uuid, int)`,
  `sync_tribe_journey_card(uuid, bool, int)` - reconciliador idempotente.
- `20260820224453_gate_785_confidential_on_new_secdef_readers.sql`
  gate `rls_can_see_initiative()` nos dois readers novos (ADR-0105, regra 5 do CLAUDE.md).

**Escrita em dado de producao:** 1 card criado (T6, quadro `118b55be`), com 8 atividades
e 2 atribuicoes. Nada mais foi escrito - nenhum flag de portfolio, nenhuma tag, nenhuma
atividade no quadro GP x Presidencia.

---

## 3. O que precisa de decisao do GP

**D1 - aplicar as correcoes de portfolio card a card.** Sequencia recomendada no relatorio:
T5 (14 de 17 cards) e T11 (18 de 27) primeiro, porque planejaram o ciclo inteiro em sprints
com data-base e nenhum entrou no portfolio - resolver com o lider de uma vez vale mais que
32 decisoes individuais. Depois os 34 de confianca alta. Gap B e o mais barato: 30 cards ja
no portfolio, 26 com sugestao inequivoca.

**D2 - rodar o card de jornada nas outras 13 tribos.** So depois de voce olhar o tom no
piloto da T6 (4 de 8 passos). Comando: `sync_tribe_journey_card(<initiative_id>, false)`.

**D3 - triagem dos 34 checkboxes do GP x Presidencia.**
`docs/governance/GP_PRESIDENCIA_COMENTARIOS_PARA_ATIVIDADES.md`, coluna `Manter?`.
**Por que nao apliquei:** os comentarios sao de 03/08 e 06/08 e ha supersessao dentro do
proprio quadro - o de 06/08 do card `[9]` revoga parte do de 03/08 ("Ivan APROVOU... bola
agora com o Aaron"). Transcrever os 34 hoje criaria duplicatas e ressuscitaria acoes ja
concluidas. So quem acompanhou o quadro nas ultimas duas semanas sabe o estado real.

**D4 - baseline em quadro de governanca.** 0 dos 23 cards tem. Se e intencional, o quadro
fica fora do portfolio por definicao e isso precisa estar escrito - hoje nao esta.

**D5 - responsavel real dos cards parados.** ~8 cards marcados "PARKED - sem retorno do
Ivan", follow-up vencido ha semanas, mas o assignee e o GP. Manter assim mede a coisa
errada; reatribuir mede a certa mas muda a leitura politica. Decisao sua, nao de dado.

**D6 - iniciativas nao-tribo.** Com `--all` (workgroups, comites, congressos) o gap A vai a
**127 de 369 cards**. Pode ser intencional (o portfolio e de pesquisa), mas nao esta escrito.

---

## 4. Aviso de CI para a sessao principal

**4.1 - a main ja esta vermelha sozinha.** Run `32420730142`, no proprio tip da main
(`72319b0`): `# pass 6979 / # fail 2`. O passo de testes rodou de 21:43:39 a 21:54:48, e a
primeira migration desta lane entrou as **21:54:16** - 32 segundos antes do fim. As 2
falhas sao anteriores. A main vem alternando verde/vermelho o dia todo (falhou 19/08 23:36,
passou 00:54, falhou 01:44, passou 02:23 e 05:18, falhou 21:42), o que sugere guard
DB-aware dependente de estado.

**4.2 - as 3 falhas restantes desta PR seguem sem nome.** A API do Actions devolve so os
ultimos ~45KB do log, que sao o cleanup do git; as linhas `not ok` ficam no meio de uma
saida TAP de ~7.000 testes. Tentados: log do job, log do run com `failed_only`, anotacoes
do check run (vazias). Mitigacao aplicada no commit `90d3be2`: os dois contract tests novos
foram movidos para o **fim** da ordem de execucao, para que a saida deles caia dentro da
cauda que a API entrega. **A leitura desse log e o proximo passo.**

**4.3 - o que ja foi descartado como causa,** cada um medido contra o banco vivo:
`785-secdef-reader-confidential-gate` (zero ofensores, zero entradas obsoletas),
`965-secdef-public-grant-drift` (nenhuma funcao nova entra na varredura), body-drift Phase C
(as 6 funcoes batem), orfas (as 6 capturadas em migration), e as tres catracas de
`schema_migrations` (`empty_statements` segue 41, as 3 versoes tem arquivo).

---

## 5. Armadilhas confirmadas nesta lane

1. **`apply_migration` do MCP registra a versao com timestamp proprio.** O padrao do repo
   e renomear o arquivo local para o timestamp da linha registrada, nao criar outro
   (mesmo desfecho de #1883 e #1890).

2. **DDL no banco compartilhado antes de commitar a captura derruba o `validate` de TODAS
   as branches**, inclusive PRs so de docs. A ordem certa e commitar a captura junto com o
   `apply_migration`, nao depois. Custou ~13 min de fila vermelha nesta sessao.

3. **`generate_typescript_types` do MCP NAO substitui a CLI.** Ele omite o schema
   `graphql_public`; usar a saida dele apagaria 25 linhas sem relacao com a mudanca. Aplicar
   so as entradas novas ao arquivo versionado.

4. **Digitar a migration no tool call diverge do `.sql`.** Duas das seis funcoes ficaram com
   `md5(prosrc)` diferente da captura porque a versao digitada perdeu comentarios - a classe
   exata que o gate Phase C pega. Conferir com hash normalizado antes de commitar.

5. **`board_items.source_type` e dominio fechado** (`internal|external_partner|external_event`)
   e descreve a ORIGEM do trabalho. Nao serve de marcador de automacao - a primeira versao
   tentou e bateu no CHECK. O marcador foi para `tags`.

6. **Guard de "nao use X" precisa olhar codigo, nao prosa.** O teste que proibe ler
   `attendance` reprovava no proprio comentario que explica a decisao; passou a limpar
   comentarios SQL antes de checar.

---

## 6. Estado da entrega

- 4 commits, PR #1899 draft, **10 de 11 checks verdes** no head `90d3be2`
  (CodeQL, gen-types-drift, check-invariants, check-advisors, browser_guards,
  visual_dark_mode, analyze, deno, issue_reference_gate, Cloudflare).
- `validate` pendente - e o unico vermelho, e o motivo de a PR nao estar pronta.
- Local: `npx astro build` limpo, `npm test` 6160 pass / 0 fail / 744 skip.
- Check-in automatico armado para reler o log do `validate` quando fechar.

**Nao mergear enquanto o `validate` nao for explicado.** As 3 falhas nao identificadas
podem ser dos 6 testes DB-gated escritos aqui - que pulam local e so rodam na CI, ou seja,
nunca executaram de verdade em lugar nenhum.
