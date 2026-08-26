# Prompt de arranque - main, depois da #1998

Copie o bloco abaixo como primeira mensagem da nova sessao.
Escrito 26/08. Substitui o `2026-08-26_PROMPT_ARRANQUE_pos_noite.md`, que ja foi consumido.

---

Leia `MEMORY.md`, depois `docs/planning/2026-08-26_handoff_1998_fechada_legal_basis_nao_e_vinculo.md`.

**Estado medido em 26/08:** main em `6340f342` quando este arranque foi escrito (este proprio
doc entra logo acima). **Fila VAZIA**, zero bypass, arvore limpa, CI verde. Nao ha DDL em voo.
⚠️ **Confira o SHA com `git log --oneline -1` antes de usar** - estado de fila e relogio, nao fato.

## O que a sessao anterior entregou

- **#2002 fechou a #1998**: a reconciliacao VEP parou de usar `legal_basis` (base legal LGPD) como
  prova de vinculo. `vep_only` 5 -> 0, denominador 73 -> 78, `researcher/cycle3-2026` de delta -4
  para 0. Guard novo em `tests/contracts/1998-reconciliacao-vep-sem-legal-basis.test.mjs`.
- **#2003** levou o handoff.
- **#2001 aberta**: `engagements.legal_basis` nao e governado por nada.
- **#2004 aberta**: candidato em "Aguardando Entrevista" com ZERO avaliacao objetiva.
- **#2007 aberta**: token do LinkedIn venceu 23/08 e a serie parou. O alerta disparou **11x sem
  alcancar ninguem**, o log de ingestao **so registra sucesso**, a tela diz "Permanente" para o
  Instagram que vence **26/09**, e **17 sinais ja ingeridos** nao sao lidos por RPC nenhuma.
- **#2006 mergeada**: `database.gen.ts` acompanhando o PostgREST 14.17 (ver armadilha abaixo).
- Licoes da sessao registradas na **#588** (`[LL]`), em seis, agrupadas por onde mudam o framework.

## Proximo passo sugerido: #1997

**Tem gente esperando, e o custo humano ja e visivel.** 9 de 20 sem `auth_id`. O **Farhad
Abdollahyan** e **lider**, tem **16 passos de onboarding atribuidos, 0 feitos, e nenhuma conta** -
e ele reapareceu na #1998 do outro lado, como `OfferNotExtended` no `platform_only` da
reconciliacao. Ou seja: dois paineis diferentes apontando a mesma pessoa travada.

⚠️ **O e-mail que saiu em 25/08 aos 4 aprovados manda acessar `/onboarding`, e ele nao consegue
abrir essa tela.** Ele tambem tem **duas candidaturas, uma `approved` e uma `rejected`** - confira
qual vale antes de criar acesso.

Nao envolve DDL obrigatoriamente, entao nao entra na fila de serializacao de cara. **Mas re-meca
antes de agir**: `auth_id` e conta sao dado vivo.

## As quatro que ficam, na ordem

| # | gancho | tamanho |
|---|---|---|
| **#1995** | admin sem visao de alocacao x termo x onboarding; o denominador **varia por template** (3, 6, 7, 12, 16 passos observados) | feature de verdade |
| **#1996** | `No Memberships` do PMI virando `NULL`: negativa definitiva indistinguivel de "nao medi". **40 candidaturas** buscaram e vieram vazias | ingestao + backfill |
| **#1999** | editar membro tem 2 RPCs com garantias diferentes, e a tela de lista grava `is_superadmin` **direto na tabela**, sem auditoria | higiene |
| **#2001** | `legal_basis` nao governado: **104 linhas ativas** divergem do catalogo | **guard primeiro** |

## Duas issues que pedem DECISAO antes de codigo

⚠️ **Nao comece a codar nenhuma das duas sem resposta do PM.** As duas leituras possiveis exigem
trabalho diferente, e escolher errado joga fora o trabalho inteiro.

**#2001 - o backfill e JURIDICO.** Trocar as 44 linhas de `volunteer` de `consent` para `contract`
afirma que existe termo de voluntariado assinado, e o catalogo marca `requires_agreement = true`
para esse kind. A pergunta *"essas 44 assinaram?"* precisa de resposta antes de qualquer `UPDATE`.
Sugerido passar pelo `legal-counsel` do council. **O guard, esse sim, pode ir na frente**: invariante
`engagements x engagement_kinds` com baseline **104** e catraca so para baixo, padrao #1932.

**#2004 - pode ser rotulo, nao defeito.** `opt_out_all_pillars` (o link de token onde o candidato
escolhe entrevista ao vivo em vez do video) promove `submitted -> interview_pending` sem olhar
avaliacao nenhuma. Se a intencao e *"esta pessoa precisa de entrevista ao vivo"*, o dado esta certo
e quem mente e a **tela**, que chama isso de "Aguardando Entrevista" no mesmo balde de quem passou o
corte - e o conserto e **separar os dois estados**, nao apertar o portao. Se a intencao e *"passou a
fase objetiva"*, o portao do #1613 precisa cobrir tambem a entrada em `interview_pending`.

Em qualquer das duas leituras, **a tela precisa distinguir quem tem `objective_score_avg IS NULL`**
dentro do balde de entrevista: hoje ele desaparece no meio dos 7 que passaram.

## O que tem relogio

- ⏰ **27/08 08h40 BRT: o selo de presenca grava** (#1948). Decisao mantida: **gravar as 77 e
  corrigir depois**, em 3 passos, ou os tres ou nenhum. Efeito 77 -> 66. O cron dispara sozinho, nao
  aplicar DDL na vespera.
- ⏳ Radar Tecnologico 13/07 segue o unico item de presenca aberto.
- ⏰ **28/08** funil · **09/09** 1a mordida da retencao · **30/09** portao da anonimizacao.
- 🆕 `operational-role-reconcile-daily` (`jobid 90`, `4 0 * * *`): **ausencia de linha em
  `admin_audit_log` e o esperado** - ele so grava quando houve mudanca ou erro.

## Numeros que SE MOVEM, nao recite

Medidos 26/08. Re-meça antes de usar qualquer um em decisao, PR ou memoria.

| medida | valor |
|---|---:|
| pessoas com `volunteer` ativo (distintas) | **78** |
| idem, so `contract` / ambos / so `consent` | 34 / **39** / **5** |
| linhas ativas divergindo do catalogo de base legal | **104** |
| `vep_only` da reconciliacao | **0** |
| `platform_only` | **5**, todas acionaveis |
| em `interview_pending` no cycle4 | **8**, sendo **1 com zero avaliacao** |

⚠️ **`gh issue list --limit N` trunca em silencio.** Use limite acima do total conhecido e confira
se bateu no teto.

## Armadilhas medidas em 26/08

- **`Fecha #N` NAO fecha issue.** O GitHub so reconhece `Closes`/`Fixes`/`Resolves`, em ingles. A PR
  #2002 mergeou verde e a #1998 ficou aberta. **A convencao do repo e `Closes #N`** - confira numa PR
  recente com `gh pr view <n> --json body` antes de escrever a sua.
- **Simulacao parcial mente no DEPOIS, nao so no antes.** Simulei os dois lados da reconciliacao em
  separado e o numero bateu com o esperado; a funcao real deu outro, porque um `FULL OUTER JOIN`
  reclassifica um lado pelo outro. **Exercite a funcao viva** (impersonando com `set_config`, e
  `set_config` ANTES do `SET LOCAL ROLE`), ou replique a cadeia inteira.
- **Contar LINHAS quando a tela conta PESSOAS infla o defeito.** Uma issue afirmou "44 invisiveis";
  eram 5. Rode o `count(DISTINCT <entidade>)` que a tela usa **e** meca a sobreposicao entre grupos.
- **Largar um filtro troca quem o `DISTINCT ON` elege.** O filtro tambem era desempate implicito:
  tirar so ele reclassificaria 39 das 73 pessoas. Antes de tirar clausula de um `WHERE` que alimenta
  `DISTINCT ON`/`LIMIT 1`, conte quantos grupos **trocam de eleito**, nao so quantos entram.
- **`curl` para a Management API do Supabase e barrado pelo classificador.** O caminho e o MCP
  `apply_migration`, e o preco dele e transcrever o corpo na chamada. **O antidoto e medir**:
  compare o md5 normalizado vivo com o do arquivo local depois de aplicar. Isso transforma "espero
  ter copiado certo" em fato.
- **Teste novo tem DOIS registros obrigatorios**, `test:behavioural` e `test:contracts`. Os guards
  #1109 e #1908 pegam a falta. `node scripts/classify-test-suite.mjs --check` decide o balde.
- **O `gen-types-drift` pode ficar vermelho sem ninguem ter mexido em schema.** Em 26/08 ele reprovou
  uma PR que so adiciona um `.md`: o Supabase subiu o **PostgREST 14.4 -> 14.17** do projeto por
  baixo, e `database.gen.ts` carrega essa versao. **Leia o diff antes de investigar o seu proprio
  codigo** - se for so a linha `PostgrestVersion`, o conserto e regenerar. E regenere com a CLI que
  a **CI pina** (`SUPABASE_CLI_VERSION` no workflow), nao com a instalada local: versao diferente
  reporta drift falso. Confira por `grep` na linha, nunca pelo exit code do `db:types`.
- **`gh run list` devolve `conclusion=""` para run em andamento, nao `null`.** Monitor que define
  vermelho por negacao inventa vermelho. **Enumere os estados terminais.**

## Higiene

`MEMORY.md` em **~24.5k de 24.985**. A sessao anterior recuperou folga encurtando linhas do
READ-FIRST para gancho e mandando o integral para arquivos-topico. **Continue nesse mecanismo**, e
procure por CONTEUDO antes de criar arquivo de memoria novo - o namespace e compartilhado entre
lanes.
