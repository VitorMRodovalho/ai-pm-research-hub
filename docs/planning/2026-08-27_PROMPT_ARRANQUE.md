# Prompt de arranque - main, depois da #2008

Copie o bloco abaixo como primeira mensagem da nova sessao.
Escrito 26/08 a noite. Substitui o `2026-08-26_PROMPT_ARRANQUE_pos_1998.md`, ja consumido.

---

Leia `MEMORY.md`, depois `docs/planning/2026-08-26_handoff_1997_sem_conta_serie_propria.md`.

**Estado medido em 26/08 a noite:** main em `810c951f`, **fila VAZIA** (zero PR aberta), zero
bypass, arvore limpa, CI da main **verde** e deploy concluido. Nao ha DDL em voo.
⚠️ **Confira com `git log --oneline -1` e `gh pr list` antes de usar** - estado de fila e relogio,
nao fato.

## O que a sessao anterior entregou

- **#2008 mergeada** (`810c951f`, migration `20260826144210`): a #1997 parou de cobrar quem nao tem
  conta. `detect_onboarding_overdue` ganhou serie propria + link publico + **um aviso por PESSOA**;
  `get_application_onboarding_pct` parou de filtrar por uma chave que **0 das 899** linhas carregam
  (a coluna "Onboarding" do `/admin/selection` era `-` para **as 71** candidaturas); nova
  `get_onboarding_blocked_cohort()`; e o botao "Entrar" de `/workspace` e da home, que **nao fazia
  nada**, voltou a abrir o modal. Guard de 11 testes.
- **#1995 investigada a fundo**, integral no comentario da issue. Nao virou codigo de proposito.
- **Cinco issues novas**: #2009, #2010, #2011, #2012, #2013.
- **Incidente operacional resolvido a mao**: entrevista da Anastasia Kukova (25/08 20h, Fernando)
  registrada por `schedule_interview` impersonando o lead, sem bypass.

## ⏰ O que tem relogio, em ordem de urgencia

1. **29/08, 11h BRT - a Anastasia leva outro "vamos remarcar sua entrevista?"** se o Fernando nao
   tiver pontuado ate la. Nem `schedule_interview` nem `submit_interview_scores` escrevem
   `interview_status`; o que para o cron e a candidatura virar `final_eval`, o que so acontece
   quando ele pontua. **Cheque isso primeiro:** se `interview_status` ainda for `needs_reschedule`
   e a nota nao tiver entrado, avise o PM antes das 11h.
2. **27/08, 08h40 BRT: o selo de presenca grava** (#1948). Decisao mantida: **gravar as 77 e
   corrigir depois**, em 3 passos, ou os tres ou nenhum. Efeito 77 -> 66. O cron dispara sozinho.
3. **28/08** funil · **09/09** 1a mordida da retencao · **30/09** portao da anonimizacao.

## Duas decisoes do PM ja tomadas, nao re-litigar

- **Farhad**: vale a candidatura de **lider** (`c9c2058d-...`, `approved`, cycle4-2026) - foi por ela
  que saiu o convite de aceite pelo VEP. A de `researcher` esta `rejected` e nao gera jornada.
- **Roberto Macedo**: e **curador**, nao pertence a tribo. Deu apoio pontual a tribo 8 como
  `observer/curator`, e o engajamento **ja esta gravado assim**. `members.tribe_id = NULL` e o valor
  CERTO. Nao ha backfill a fazer, e o "residuo 67 vs 66" era **erro de contagem**, nao dado sujo.

## Decisoes que ainda travam codigo

| # | pergunta | por que trava |
|---|---|---|
| **#1997** | mandar o e-mail de recuperacao **so ao Farhad**, com que texto? | acao sobre pessoa real. Os outros 2 sao **dia-1** (aprovados 26/08 01:35, ja receberam boas-vindas) e o **Hector saiu** (`offboarded`) |
| **#2004** | "Aguardando Entrevista" e lista de **tarefa** ou de **merito**? | se e formato, conserta-se a TELA; se e fase, aperta-se o PORTAO. Consertos opostos |
| **#2001** | as 44 linhas `volunteer/consent` viram `contract`? | afirma que existe termo assinado: **juridico**. O guard (baseline 104, catraca) pode ir na frente |
| **#1995** | (b) `Y=0` para 11 pessoas e estado legitimo ou falha da #2009? (c) a tela lista **12** ou **28**? | (b) decide se a tela mostra vazio ou defeito; (c) decide o default |
| **#2009** | catalogar as 5 chaves orfas, ligar o seeder, ou unificar? | ligar o seeder cria linhas e **XP retroativo** para quem ja esta no ciclo |

## Proximo passo sugerido: #2012, e depois #2013

**Por que a #2012 primeiro.** E pequena, cirurgica, tem **desenho pronto** (a #1972 resolveu a mesma
classe do outro lado) e destrava trabalho humano que hoje nao vira dado. Nao precisa de decisao do
PM. E o incidente que a gerou e de ontem, com nome e sobrenome.

Cuidado que ela pede: o alargamento vale para **registrar a entrevista que a pessoa conduziu**, e
**nao** para agendar entrevista de terceiros. E aproveite para **logar a recusa de autoridade** -
hoje ela acontece antes do `_log_gate_attempt` e nao deixa rastro nenhum, o que torna o proprio
bloqueio invisivel para quem investiga.

**#2013 na sequencia** porque compartilha a vizinhanca e um dos consertos e o mesmo campo
(`interview_status` que nunca se limpa). Ela tem 5 itens de aceite independentes; o mais barato e
o de maior efeito e **limpar `interview_status` quando a entrevista e registrada ou pontuada**, que
sozinho tira 8 candidatos de um balde de cobranca - dois deles ja **aprovados com nota**.

## Numeros que SE MOVEM, nao recite

Medidos 26/08. Re-meça antes de usar em decisao, PR ou memoria.

| medida | valor |
|---|---:|
| candidatos em `needs_reschedule` no cycle4 | **8** (todos desde 19/08) |
| deles, ja `approved` **com nota** de entrevista | **2** (Rafael 95, Thiago 88) |
| despachos de link de agendamento, janela **instrumentada** | 37 |
| ... abertos / viraram agendamento | **14 (38%) / 5 (14%)** |
| pessoas sem `auth_id` com jornada ativa | 4, mas **so 1 acionavel** (Farhad) |
| denominadores distintos de onboarding entre 95 ativos | **8** (0,1,3,6,7,11,12,16) |
| ativos sem tribo (`kind='volunteer'`) | 28, dos quais **12 precisam de termo** |

## Armadilhas medidas em 26/08

- **`instrumented` antes de dividir.** `selection_dispatch_url_log` tem essa coluna e **94 dos 131
  despachos nao foram medidos**. A leitura ingenua da "4% de conversao, 89% nunca abertos"; a
  correta da **38% e 14%**. Diagnostico **oposto**: canal saudavel, cadencia doente. Vale para
  qualquer tabela de evento - **procure o marcador antes da primeira divisao.**
- **"Pertence a X" nao e "aparece ligado a X".** Contei "tem tribo" como "tem engajamento ativo em
  iniciativa `research_tribe`" e varri junto um **curador**. O discriminador e o `kind` do
  engajamento (`volunteer`), nao a iniciativa. Um unico falso positivo bastou para eu reportar um
  resIduo que nao existe.
- **A recusa por autoridade pode nao ir ao log.** Em `schedule_interview` o `RAISE EXCEPTION` de
  autoridade vem **antes** do `_log_gate_attempt`. Ausencia de linha em `gate_attempts` **nao**
  prova que ninguem tentou.
- **`BEGIN; ... ROLLBACK;` num unico `execute_sql` FUNCIONA** para exercitar funcao que escreve,
  e nao e o mesmo mecanismo do `Prefer: tx=rollback` (que **nao** e honrado) nem do DO-block com
  SAVEPOINT (que vaza). Guarde o retorno em `CREATE TEMP TABLE ... AS`, porque funcao e inspecao no
  MESMO statement devolvem o snapshot pre-escrita. **Confira depois com consulta NOVA.**
- **Guard que julga codigo tem de descartar comentario.** A primeira versao do guard da #1997
  reprovou a propria migration, porque o comentario que EXPLICA a correcao cita o token proibido.
- **Queda do GitHub Actions (26/08 15:11 UTC).** Jobs mortos apos exatamente 15 min com `steps=0`
  aparecem como **fail**, e nao sao veredito sobre o codigo. `startup_failure` idem. Quando voltar,
  o GitHub **nao** re-despacha sozinho e um workflow pode nunca ter sido criado para o SHA -
  re-rodar os antigos nao resolve. **Fechar e reabrir a PR** recria tudo no mesmo commit.
- **O ruleset e o portao, nao a branch protection.** `gh api .../branches/main/protection` devolve
  404 ("Branch not protected") e mesmo assim a PR fica `BLOCKED`. Os obrigatorios estao em
  `gh api repos/.../rulesets/21186263`: **`validate`, `browser_guards`, `deno`, `structural`**.
  Um obrigatorio **AUSENTE** trava a PR em "Expected" para sempre - trate ausente como pendente,
  nunca como aprovado.
- **`Fecha #N` NAO fecha issue.** So `Closes`/`Fixes`/`Resolves`, em ingles. A convencao do repo e
  `Closes #N` numa linha propria do corpo da PR.

## Higiene

`MEMORY.md` em **24.916 de 24.985** - folga de 69 bytes, apertado. A sessao anterior recuperou
espaco movendo blocos estaveis do READ-FIRST para arquivos-topico
(`reference-db-aware-tests-serial-concurrency` e
`reference-escada-de-papel-tem-DOIS-lados-e-o-adr0023-exige-paridade`), deixando gancho.
**Continue nesse mecanismo**, e procure por CONTEUDO antes de criar arquivo novo - o namespace e
compartilhado entre lanes.
