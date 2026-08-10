# Handoff - #1710 passo 2, a elegibilidade da grade fala a lingua do selo (10/08/2026)

> Segundo handoff da mesma sessao. O primeiro e
> `docs/planning/2026-08-10_handoff_1655_fatia_grade_sem_tribo.md` (fatia do #1655, PR #1720).
> Este cobre a PR **#1722**.

## Regra zero

Todo numero aqui foi medido em **10/08/2026**. Re-medir com tool call na mesma volta em que o
numero entrar numa decisao, num commit, numa issue ou numa pergunta ao PM.

---

## Decisoes do PM nesta parte

Nao eram perguntas de codigo, eram de **regra de negocio**, e foi por isso que a solucao ficou
simples:

1. **Sponsor e chapter_liaison fora do tier operacional NAO sao cobrados de presenca em reuniao
   geral.** (14 pessoas, 40 celulas)
2. **Gestor sem tribo propria NAO e elegivel a reuniao de tribo.** (2 pessoas, 93 celulas)
3. **O cron sela apenas o ciclo corrente** (decidido antes, e reforcado pelo achado abaixo).

Ambas resolvidas por **restricao da elegibilidade da grade**, nao por expansao do selo.

## O risco que isto elimina

`seal_event_attendance` grava `present=false` para a coorte dele e carimba `roster_sealed_at`.
Com o carimbo preenchido, a grade resolve "sem linha" no ramo `ELSE` como `absent`. Se a coorte
da grade for **maior** que a do selo, selar acusa quem o selo nunca alcanca, **sem nenhum
registro**: a acusacao inferida que o #1657 removeu, voltando pela porta do selo e agora
carimbada de "roster fechado".

Medido antes do ajuste, selando os 53 eventos do ciclo:

| efeito | celulas | pessoas |
|---|---:|---:|
| linha REAL de falta (o efeito pretendido) | 121 | 53 |
| `absent` **sem nenhuma linha** (o defeito) | **133** | **16** |

As 133, decompostas, e as 16 pessoas eram **todas sem tribo**:

| papel | evento | celulas | pessoas | a grade dizia | o selo diz |
|---|---|---:|---:|---|---|
| `manager` | `tribo` | 93 | 2 | elegivel a TODA reuniao de tribo | elegivel a NENHUMA |
| `chapter_liaison` | `geral` | 25 | 9 | elegivel | fora do tier operacional |
| `sponsor` | `geral` | 15 | 5 | elegivel | fora do tier operacional |

## Antes e depois

| celulas, ciclo corrente (53 eventos) | antes | depois |
|---|---:|---:|
| so no selo | 0 | 0 |
| so na grade | 138, em 16 pessoas | **5, em 3** |
| dessas, **sem registro** | **133** | **0** |

As 5 que sobram sao **todas `present` com linha real**: nao existe mais nenhuma celula que o selo
possa transformar em falta por inferencia.

| estado, grade geral | antes | depois |
|---|---:|---:|
| `present` | 373 | **373** |
| `unrecorded` | 254 | 121 |
| `excused` | 13 | 13 |
| `absent` | 0 | 0 |
| `na` | 16.033 | 16.562 |

Coorte historica do #156 intacta: **2** ex-membros renderizados e **6** celulas com registro,
iguais antes e depois. Taxa: **4 subiram, 0 desceram, 79 iguais**, maior alta +66,7 pp.

## Tres armadilhas pagas aqui

⚠️ **1. `operational_role` NAO e `operational_tier`.** Filtrar por papel
(`NOT IN ('sponsor','chapter_liaison')`) teria excluido **2 dos 11 chapter_liaison, que ESTAO no
tier** e devem continuar sendo cobrados. O predicado certo e `v_member_operational_tiers`, que e
exatamente o que `seal_event_attendance` ja usa. **Ao alinhar duas coortes, copie o predicado da
coorte-alvo em vez de reescrever um equivalente.** O guard tem a inversa disso.

⚠️ **2. O ramo de exclusao engole o registro.** `WHEN NOT elegivel THEN 'na'` vem ANTES da
leitura da linha, entao restringir a elegibilidade apagaria da tela **5 presencas reais** (e
mantinha escondidas outras 3 que ja estavam), e zeraria a coorte historica: **0 de 34**
ex-membros estao no tier, mas **29 tem presenca registrada**. A correcao e uma condicao:
`WHEN NOT elegivel AND a.id IS NULL THEN 'na'`. **`na` significa "fora da conta", nunca "apague o
que aconteceu".** As duas mudancas se sustentam uma na outra e por isso sao um contrato so.

⚠️ **3. Denominador vazio vira 0%, e 0% acusa.** **12 pessoas** ficaram sem nenhuma celula
elegivel; o `COALESCE(...,0)` do contrato publicava **0%**, que le como "nao foi a nada" sobre
quem nao e cobrado. Corrigido no front sem mexer no contrato numerico: a coluna mostra `-` com
tooltip (`attendance.grid.noEligibleEvents`, nos 3 dicionarios), o CSV sai **vazio** (um `0` vira
media falsa na planilha) e a media dos KPIs corre so sobre quem tem taxa. Por isso
`overall_rate_pct` publica **74,7** (media dos 71 com taxa) e nao 63,9.

## O achado que fecha o entendimento das metricas

Duas taxas com o mesmo nome partem de universos diferentes:

- **primitiva** (`get_attendance_rate`, alimenta **XP/gamificacao** e o painel):
  `count(present) / count(nao justificadas)` **sobre as LINHAS que existem**;
- **grade**: `present / (present + absent + unrecorded)`, sobre a **matriz de elegibilidade**.

Com apenas **3** faltas simples em 2.020 linhas, a primitiva publicava **100,0%** de media para
as 83 pessoas ativas, enquanto a grade publicava **61,0%**. O 100% nao dizia "todo mundo foi a
tudo": dizia "so registramos quem foi", e era o numero que premiava as pessoas.

Simulando o selo nos 53 eventos, a primitiva cai de 100,0% para **exatamente o `avg_rate_pct` que
a grade ja publicava**: delta **0,0 pp em 10 das 12 tribos** e -0,1 nas outras duas. **O selo nao
cria verdade nova, faz o banco alcancar a tela.** A divergencia que sobrava (+64,4 pp, no grupo
sem tribo) era exatamente o diagnostico das 16 pessoas.

## Estado

- **PR #1722** aberta com o DDL ja em producao (`20260810153301`), `NOTIFY pgrst` enviado.
- Corpo derivado da captura anterior por **2 substituicoes ancoradas** com prova de reversao byte
  a byte; md5 do corpo vivo == arquivo local.
- Guard `tests/contracts/1710-elegibilidade-fala-a-lingua-do-selo.test.mjs`: **9 testes**, 4
  camadas, com a **inversa** de cada afirmacao e **mutacao verificada**.
- `npm test`: **6655 testes, 0 fail, 1 skip**. `check_schema_invariants()`: 43 / 0 violadas.
- ⚠️ `npm test` levou mais de 10 minutos: rodar em segundo plano, nunca numa chamada com teto.

---

# O que falta no #1710

🔴 **O selo nao alcanca 253 dos 301 eventos passados.** `_attendance_eligible_events(m.id, NULL)`
fixa a janela no **ciclo corrente**, entao em qualquer evento anterior a coorte e **0**: o cron
carimbaria "selado" gravando zero linhas. Conferido em tres eventos de 07-08/07, todos com coorte
0. A decisao do PM (selar so o ciclo corrente) ja cobre isso, mas **a tela precisa dizer que o
historico anterior nunca tera roster fechado**, senao parece pendencia eterna.

Escopo restante:

- [ ] **dry-run**: rodada em que o cron reporta o que faria, sem escrever
- [ ] **caminho de reversao** por evento (a RPC nao tem `unseal`; o carimbo
      `notes = '[roster_seal] ...'` e o que permite identificar e desfazer)
- [ ] janela (N dias) e aviso previo a quem sera marcado
- [ ] superficie para selar, com confirmacao dizendo quantas faltas serao gravadas
- [ ] a grade mostra se o evento esta selado, e desde quando
- [ ] tool MCP para selar, na familia do #1588
- [ ] contagem de eventos selados publicada depois de uma semana

Fatos uteis para desenhar o dry-run: as duas triggers de `attendance` sao `AFTER INSERT` e
**nenhuma chama servico externo**; `auto_complete_first_meeting` ja guarda `NEW.present = true`
no corpo (com comentario citando o selo), entao materializar falta **nao** completa onboarding.
Isso torna seguro um ensaio por `DO` + `RAISE EXCEPTION` em transacao abortada.

## Depois do #1710

1. **#1654** - fixar a coluna de nome nas 6 tabelas de presenca com scroll horizontal.
2. **#1218** - presenca orfa na reuniao de 08/07, residuo da Onda 0.
3. **#1655** segue aberta: unificacao dos 4 componentes, mais `src/pages/profile.astro`
   (1015, 1385), que calcula a propria taxa sem RPC.
4. **#1656** segue aberta com 3 dos 5 itens. O item 3 (nomear as tres semanticas na tela) ganhou
   material novo: com a primitiva em 100% e a grade em 61%, a tela precisa dizer que sao
   perguntas diferentes.
5. **#1652** (epica) fecha quando as filhas fecharem.
