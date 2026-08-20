# Handoff - #1877, auditoria da jornada de onboarding (worktree paralela)

**Data:** 2026-08-19, 21:55 a 22:25 UTC
**Worktree:** `../ai-pm-1877`, branch `audit/1877-jornada-onboarding`, nascida de `origin/main` `b0269e8c`
**Mandato:** auditar exercendo, agrupar, formular a decisao. **Nao desenhar.**
**Entregavel:** `docs/audit/EPIC_1877_MAPA_JORNADA_ONBOARDING.md`
**Banco:** somente leitura. **Zero escrita, zero migration, zero mudanca de codigo de produto.**

---

## O que a sessao de planejamento precisa decidir

### Decisao 1 - RESOLVIDA pelo PM em 19/08: o prazo tem a FORMA errada

O PM leu a auditoria e corrigiu o enquadramento. Nao e "o prazo de 22/07 ainda vale?". O prazo foi
desenhado como **data global de coorte**, como se todos entrassem ao mesmo tempo. O certo e um
prazo **relativo ao fim da jornada de cada candidato**, para a escolha de tribo nao ficar pendente
para sempre.

Medido, a premissa de coorte nao se sustenta: entradas por mes sao **35 · 4 · 4 · 31 · 13 · 7**
(marco a agosto), e **3 pessoas assinaram o Termo depois do prazo, as 3 sem tribo hoje**. O termo
mais recente e de 18/08, **27 dias** depois do prazo.

**O primitivo ja existe:** `onboarding_progress.sla_deadline` esta **100% preenchido nas 5 chaves
orfas do #1875**, com prazos escalonados por pessoa, alimentado por `seed_pre_onboarding_steps()`
via `now() + N days` (SLAs de 7/14/14/14/30). Esta **0% em `meet_tribe`**. Ou seja: **#1875, #873 e
o prazo de tribo sao a mesma conversa**, e as chaves orfas nao sao so divida.

**Restricao adicional do PM:** novos candidatos entram nas tribos com vaga, mas quem ja escolheu e
esta atuando **nao pode sair e entrar em outra**.

- **Isso ja esta no desenho.** Exercido sob um pesquisador que atua numa tribo: `eligible: false`,
  `ineligible_reason: "has_tribe"`, `tribes: []`. A guarda tem duas chaves (`members.tribe_id` **e**
  engajamento `volunteer` ativo). **Trocar o formato do prazo nao abre a porta da troca.**
- **Mas ha um buraco, e ele so aparece quando o prazo reabrir.** `can_self_leave` e verdadeiro
  sempre que a tribo tem mais de 1 voluntario, e **isso vale para 12 de 12 tribos e 66 de 66
  pessoas**. Sair e depois pedir outra e um caminho de dois passos. Hoje ele nao se materializa
  **porque o prazo global fechado esta agindo, por acidente, como a trava anti-troca**.
  **Reabrir sem guarda entrega a rotatividade que o PM quer evitar.**

**O que sobra para a sessao decidir:** (a) de que marco contam os dias e quantos; (b) o que
acontece quando o prazo pessoal vence (alocacao pelo GP? lembrete?); (c) **a guarda anti-troca, que
hoje nao existe e nao pode nascer do prazo**; (d) a lista continua sem vaga e sem video.

### Decisao 1-B (superada, mantida para historico): qual e o caminho oficial de entrada em tribo

O fluxo `tribe_request` **nao esta parado por desuso. Esta fechado por configuracao.**

`platform_settings.tribe_request_deadline = 2026-07-22T02:59:00Z`, e a janela esta **fechada ha
28 dias**. Exercido sob um membro que entrou em 15/08, `get_my_tribe_request_context()` devolve
`eligible: false`, `ineligible_reason: "window_closed"`. As notificacoes pararam em 20/07 porque
o prazo venceu em 22/07, nao porque alguem desistiu do fluxo.

**Por que e urgente:** ha registro de que uma alocacao foi revertida em favor de "ele escolhe a
tribo dele apos o onboarding", e a escolha esta fechada. **11 membros ativos** estao no passo 5
sem tribo e sem nenhum botao.

Tres saidas, na secao 5 do documento. **Recomendo nao escolher antes da Decisao 2**, porque
reabrir a janela hoje entrega uma lista ruim.

### Decisao 2 - o que o candidato ve ao escolher

O payload do seletor traz **somente `tribe_id` e `title`**. Nao traz vaga, video, tema, lider nem
agenda. Medido:

- teto por tribo: **8**
- **3 das 12 ofertadas ja estao lotadas** (8/8) e a capacidade so e checada no envio
- **2 tribos existem com `is_active = false`, 0 membros e 8 vagas cada**: 16 vagas dormentes
- **12 de 12 tribos ativas tem `video_url` preenchido**, e o seletor nao mostra nenhum

Ou seja: a resposta a pergunta 3 da Diretoria ("tem acesso aos videos?") e **o video existe,
gravado, e a tela de escolha nao o usa**.

### Decisao 3 - o nao filiado deve ouvir alguma coisa?

Exercido sob um ativo sem afiliacao: diagnostico devolve `bucket: "no_application"`, que nao esta
em `PMI_BUCKETS`, e o `EntryChapterNudge` **retorna sem renderizar nada**. A variante
`not_affiliated` existe no componente e e produzida por `classify_entry_chapter()`, mas so e
alcancada por quem tem candidatura casada. **Decidir se isso e codigo morto ou lacuna.**

---

## O que pode ser feito sem esperar decisao nenhuma

Tres itens independentes do caminho de tribo, todos com populacao medida:

1. **`auto_detect_onboarding_completions()` nao esta em nenhum dos 67 crons ativos** e nao e
   chamada por codigo de produto. E a **unica** via de conclusao do `start_trail`, que nao tem
   botao de marcar. **58 membros tem ponto `category='trail'`** (o mais recente em 16/08), so
   **20 tem o passo concluido**, ultima conclusao em **09/04**. **38 pessoas destravadas** ao
   religar. Isto explica os 20,4% inteiros: nao e abandono, e detector desligado.
2. **`meet_tribe` esta em `BESPOKE_CTA_STEPS`**, entao alem de nao renderizar o CTA proprio sem
   `tribe_id`, tambem perde o fallback generico, que e justamente o botao "Marcar como feito".
   **11 ativos** sem saida hoje.
3. **Metrica do `volunteer_term` tem dois valores.** 83/96 por `status` (**86,5%**, o que a tela
   conta) e 91/96 por `completed_at` (**94,8%**). A diferenca sao **8 linhas `skipped` com carimbo
   de conclusao**, de backfill de dispensa. **Neste schema `completed_at` nao implica conclusao.**
   A tabela do prompt de arranque publicou 94,8%; o numero do produto e 86,5%.

---

## Triagem das 19 issues, resumo

- **Entram no escopo (11):** #1875, #1014, #873, #1277 (nucleo) - #1356, #809, #1777 (tribo) -
  #1863, #1866, #1867, #1581 (filiacao)
- **Fundir (2):** **#1095 na #1866** (mesma ideia, formulacao antiga); **#1580** so sobrevive se o
  descasamento com periodo de servico for tratado a parte
- **Provavelmente obsoletas, re-medir (2):**
  - **#1852** ("VEP parada ha 4 meses") **nao se sustenta**: afiliacao `pmi_vep` mais recente
    criada em **15/08** e verificada em **17/08**; dos 55 ativos que entraram apos 30/04, **52 tem
    afiliacao**, 3 nao. Reduzir aos 3, ou fechar.
  - **#1219** ("criar 2 tribos novas"): as duas nomeadas **ja existem, ativas**, com 2 e 4
    membros. Retitular para o "mecanismo canonico" e anexar as 2 tribos inativas de 16 vagas.
- **Ficam fora (4):** #1171, #1358, #1876, #617

---

## Armadilhas confirmadas nesta worktree

1. **`onboarding_progress.step_key` nao tem FK para o catalogo.** Contar dali produz denominador
   que nao e o do produto (foi o erro ja registrado na #1875). O catalogo e `onboarding_steps`,
   e a PK dele e **`id`**, nao `step_key`.
2. **`members` usa `member_status`, nao `status`**; e `tribe_selections` **nao e** a tabela do
   fluxo de pedido (o pedido vive em `initiative_invitations` com `initiatives.kind='research_tribe'`).
3. **Contar sem filtrar `member_status`** mistura `alumni` e `inactive`: o passo 5 da **22** linhas
   no total e **11** entre ativos.
4. **Impersonacao:** `set_config('request.jwt.claims', ..., true)` **antes** de
   `SET LOCAL ROLE authenticated`, senao mede "nao autenticado".
5. **`platform_settings` nao tem `updated_at`**, entao a data em que o prazo foi decidido nao e
   recuperavel da tabela.

---

## Estado da entrega

- Documento de auditoria escrito, com as 7 lacunas do prompt de arranque respondidas e o
  criterio de aceite por item.
- **Nao rodei a suite completa** (armadilha 1 do prompt de arranque: o `validate` fala com
  producao e a lane serializa com a sessao principal do #1710). **Nao ha mudanca de codigo nesta
  branch**, so dois arquivos `.md`, entao nao ha teste que a PR precise exercer.
- **Aviso de fila:** se a sessao principal preferir, esta PR pode esperar o #1710 fechar.

---

## Aviso de CI para a sessao principal (20/08, 00:10 UTC)

**As duas PRs desta worktree estao com o `validate` vermelho, e nenhuma falha e de conteudo.**

- **PR #1879** (esta auditoria, dois arquivos `.md`)
- **PR #1883** (#1880, uma migration **nao aplicada**)

### O que aconteceu, medido

1. Um run do `validate` **na `main`** (23:36) ficou vermelho por **flake de saturacao**:
   `canceling statement due to statement timeout`, 81,7 s, sobre um invariante que mede **0
   violacoes**. Reportado no **#1844**, com um achado novo: a retentativa do #1851 cobre
   `PGRST003`, mas o que caiu foi **57014** do Postgres, classe nao coberta.
2. Esse run **segurou a faixa do banco** por cerca de 10 minutos.
3. As duas PRs, que eu subi com **2 segundos de diferenca** (erro meu), enfileiraram atras dele,
   esperaram **585 s cada** e morreram em `wait-for-db-lane` com **"falhei em ler a faixa apos 3
   tentativas"**. O fail-closed esta correto.
4. Re-disparei **uma so**, com **zero** runs em curso confirmado. Falhou igual, em **~1 minuto**,
   sem espera: **o guard nao conseguiu LER a faixa, com a faixa livre.** Reportado no **#1509**.

**Parei de re-disparar**, porque cada rerun adiciona polling ao mesmo endpoint que esta falhando.

### O que isso significa para o merge

O conteudo das duas PRs esta completo. Elas precisam de **um run limpo**, uma por vez, quando a
fila estiver drenada. **Sugestao: rodar a #1883 primeiro** (ela conserta o mecanismo que trava a
fila) e a #1879 depois.

⚠️ **Nao interprete esses vermelhos como defeito das PRs**, e nao tente consertar o `validate`
nelas: a causa esta em #1844 e #1509.

### Nota sobre a #1880

A violacao de dado **foi reparada as 23:01** por caminho direto, com **ator nulo** (assinatura de
`service_role`). Re-medido: **0 violacoes em 7 elegiveis**. **O dado foi reparado, o mecanismo nao.**
Sem a #1883, o proximo `portfolio_flag_changed` num card ja `done` recria a violacao e trava a fila
outra vez.
