# Handoff de 15/09: o crédito de presença fecha, e um guard acha um erro de desenho meu

> **Nada aqui é medição.** Carimbado em 15/09, ~11h BRT. **Re-meça antes de decidir.**
> Repositório público: este documento não nomeia ninguém, por norma.

**Estado ao encerrar, para COMPARAR:** `main 8549c46d` · PR **#2304** aberta (2 commits) ·
issues deste arco: **#2286, #2291, #2292, #2295, #2296, #2297, #2300, #2301, #2302**.

---

## 0. O que foi fechado

| PR | issue | o quê |
|---|---|---|
| #2299 | — | adendo ao handoff de 14/09 |
| #2303 | **#2302** | o `String(err)` sai do corpo da EF que declarava nunca ecoar PII |
| #2304 (aberta) | **#2292** | o crédito de presença passa a ter uma regra só |

Fora do repo: o bloco de ponteiro entrou nos **três** arquivos de instrução global
(`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, `~/.codex/AGENTS.md`), com md5 idêntico, e
está commitado e pusheado em `claude-config-global`.

---

## 1. A lição que vale mais que as entregas

**Um guard do repo achou um erro de DESENHO meu, não de código — e o desenho era o que a
issue pedia.**

A #2292 propunha, em letra, "fazer a limpeza de presença remover o XP". Implementei isso. O
`tests/contracts/1087-wave3-ledger-append-only.test.mjs` reprovou: `gamification_points` é um
**ledger append-only** (onda 3 da #1087), e o comentário do próprio guard diz que o carve-out
de `DELETE` é apagamento por Art. 18 da LGPD, *"never for a business revoke"*.

O padrão certo já existia no repo, em `revoke_agenda_block_xp`: **estorno**, linha de pontos
negativos. Efeito idêntico no placar, história preservada.

⚠️ **Uma issue pode pedir algo que uma invariante já proíbe.** Antes de implementar a direção
que a issue nomeia, procure se existe guard sobre a tabela que ela manda mexer. Um
`grep -rl "<tabela>" tests/contracts/` teria achado o `1087-wave3` em um passo.

E o dobro disso: **eu ofereci ao dono uma decisão com a opção errada marcada como
recomendada.** Ele escolheu apagar as 224 duplicatas; a norma do repo preferia estorno. A
alternativa que ele tinha na tela ("marcar, não apagar") era a alinhada. Descobri depois.

---

## 2. O erro de verificação que deixou isso chegar ao CI

O commit `657aff08` afirma "npm test: 3673 testes, 0 falhas". **É falso.**

`npm test` é `test:structural && test:behavioural` — **dois** blocos, **dois** sumários. Meu
laço de espera terminava no PRIMEIRO `duration_ms`, lia o sumário do bloco 1 e chamava de
suíte. O bloco 2 tinha **19 falhas**.

⚠️ **O número era real; o escopo dele não era o que eu disse.** É a mesma classe de
`reference-pipe-engole-o-codigo-de-saida-da-suite`, uma camada acima: não o exit code, mas o
*marcador de término*. Espere por `grep -c '^ℹ duration_ms' >= 2`, não pelo primeiro.

Das 19: **2 eram minhas**, **17 eram contenção**. A invariante
`M_application_score_consistency` apareceu violada por uma fixture `__1636_synthetic__`
criada às 04:17:54 — exatamente quando a minha rodada local e a do CI escreviam no MESMO
banco. Re-medido depois: 44 invariantes, 0 violações, sem eu ter feito nada.

⚠️ **Não rode a suíte DB-aware local enquanto o CI roda.** As duas escrevem fixtures em
produção e uma invalida a invariante da outra.

E um acerto que vale registrar: meu `DELETE` da fixture apagou **0 linhas**, porque o
predicado era de igualdade exata e eu tinha lido o nome truncado em 18 caracteres (o real tem
48). Um `LIKE` teria apagado uma linha que **não precisava** ser apagada — o estado já tinha
sarado sozinho. Predicado exato falha barulhento; predicado frouxo acerta o alvo errado.

---

## 3. A #2292, e o que a medição mudou na issue

A issue dizia "não há conserto óbvio". A medição tornou-o óbvio:

| medida | n |
|---|---|
| grupos (pessoa, evento) com mais de um crédito | **224** |
| deles com exatamente 1 linha de cada formato | **224** (100%) |
| grupos de qualquer outra forma | **0** |
| linhas de formato evento **sem** par | **0** |

**Toda linha que a RPC escreveu na vida é a segunda cópia de um crédito que a EF já tinha
dado.** Não era formato legado convivendo com o novo; era a duplicata inteira. A causa é a
assimetria: a RPC checa os dois formatos e grava o antigo, a EF só conhece o novo.

A issue nomeava **duas** divergências entre RPC e EF. São **cinco**: filtro de cancelado,
filtro de `e.type`, critério de de-duplicação, origem dos pontos (catálogo vs constante), e
formato gravado de `ref_id`.

⚠️ E a issue supunha que de-duplicar por (pessoa, evento) exigiria **mudar o significado de
`ref_id`**. Não exige: continua-se gravando `ref_id = attendance.id`; só o predicado de
de-duplicação é que passa a resolver o polimorfismo com `COALESCE(a2.event_id, gp.ref_id)`.

---

## 4. A investigação das 22 órfãs: a premissa de "irrecuperáveis" caiu

O handoff de 14/09 registrou que as órfãs seriam irrecuperáveis, porque 21 das 22 têm vários
eventos elegíveis na mesma data. **Verdade sobre a inferência, falso sobre a evidência:** o
backup não precisa desambiguar, ele lê o `event_id`.

| fonte | recuperadas |
|---|---|
| artefato GitHub `db-backup-20260822_230738` | **12** |
| objeto R2 `backup_20260727_000211.sql.gz` | **9** |
| janela 29/07–03/08 (rotina ainda semanal) | **1 não recuperada** |

**21 das 22 são presença apagada por CANCELAMENTO**, em 4 reuniões (uma de liderança em
09/07, três de uma mesma tribo em 05/08, 12/08 e 19/08). A 22ª é limpeza individual num
evento que segue vivo.

Controles, para que os números não passem por vacuidade: o corte 12/10 no dump de 22/08 bate
**exatamente** com a data de criação de cada linha; só **3** das 12 aparecem no dump de
16/08, que são exatamente as 3 criadas até lá; uma órfã já provada aparece no dump de 03/08
(1 linha) e uma criada depois não (0 linhas).

⚠️ **O R2 é o que salvou 9 delas.** O GitHub guarda 30 artefatos (hoje, 16/08 em diante); o
R2 não poda nada. E a chave do objeto de julho saiu do **log do run**, porque o nome do
artefato correspondente já tinha sido removido. Os runs de 19/07, 27/07 e 02/08 concluíram
`failure` por um passo de limpeza cosmético — **o dump e a cópia para o R2 passaram**.

---

## 5. Estado do passivo de XP

- **224 duplicatas apagadas** (2.240 pontos, 40 pessoas), autorizado pelo dono. Predicado
  auto-protetor: só alcança linha de formato evento **com parceira viva**. Nenhuma caía no
  ciclo corrente (`cycle_4`, desde 09/07; elas vão de 10/2025 a 05/2026).
- **A exclusão é reversível**: as 224 estão íntegras no dump de 22/08, com todas as colunas.
- **As 22 órfãs seguem intocadas**, com o mapa evento-a-evento no comentário da issue.

---

## 6. DUAS DECISÕES PENDENTES DO DONO

1. **As 22 órfãs, agora com endereço.** A política escolhida ("depende do motivo") aplicada
   ao passado seria: repontar as 21 de cancelamento para os seus eventos (medido: cria **0**
   duplicatas, e elas saem do balde de órfãs, o que melhora o ratchet da #1537) e estornar a
   1 de correção. 14 pessoas, 220 pontos, todas no ciclo corrente.
2. **As 224, na forma do ledger.** Apagadas conforme a decisão, mas a norma do repo prefere
   estorno. Restaurar do backup e estornar deixaria o placar igual e o ledger íntegro. É
   trabalho pequeno e reversível nos dois sentidos.

---

## 7. Comandos para re-medir antes de decidir

```bash
git fetch --all && git log --oneline -1 origin/main
gh pr list --state open
gh run list --workflow=codeql-baseline.yml --limit 3   # #2197: ele lê a análise anterior
```

```sql
-- o medidor novo, com controle positivo na mesma leitura
SELECT * FROM public._audit_attendance_xp_duplicates();

-- as invariantes (sample_id de fixture = contenção, não defeito)
SELECT * FROM public.check_schema_invariants() WHERE violation_count > 0;
```

```bash
# a suíte inteira tem DOIS blocos — espere pelos DOIS
npm test > /tmp/t.log 2>&1; grep -c '^ℹ duration_ms' /tmp/t.log   # precisa dar 2
grep -E '^ℹ (tests|pass|fail)' /tmp/t.log
```

---

## 8. Prompt de arranque sugerido

> Ler `docs/planning/2026-09-15_handoff_credito_de_presenca_e_o_ledger_que_eu_nao_sabia.md`.
> Re-medir a seção 7 antes de decidir. A #2304 pode estar aberta ou mergeada: se mergeada,
> republicar a EF `sync-attendance-points` (`--use-api`, ver #2277). A seção 6 tem duas
> decisões do dono. Depois delas, a fila é **#2296** (taxonomia dos 86 badges do Credly) e as
> **camadas vazias** da #2297 — os dois bloqueadores que sobraram para o desenho da métrica
> de ranking. **Não** desenhar segmentação antes disso.

---

## 9. Divergência achada no handoff anterior, para não a repetir

O handoff de 14/09 diz que a proposta de segmentação deixaria "chapter_liaison (10), guest
(7) e sponsor (5)" sem camada. Medido hoje em `members.designations`, nos **três**
denominadores (137 totais / 99 ativos / 96 ativos no ciclo), dá sempre o mesmo:
**curator 0, comms_team 0, chapter_liaison 4, guest 0, sponsor 5**.

Ou seja: não são duas camadas vazias, são **três** (curator, comms_team e guest), e os
números de chapter_liaison e guest do handoff não batem com nenhum recorte de
`designations` — devem ter vindo de outra fonte (provavelmente `engagements`), que não foi
registrada. **Re-derive antes de usar**, e anote a fonte junto com o número.

---

## 10. Adendo — o que veio DEPOIS da primeira versão deste documento

A seção 6 listava duas decisões pendentes. **As duas foram decididas e aplicadas.** A #2304
foi mergeada (`ccfcce22`) e a EF `sync-attendance-points` republicada.

### O que o dono decidiu, e o que foi feito

**1(A) — as 22 órfãs.** 21 repontadas para os 4 eventos cancelados, provadas por leitura de
dump; `ref_kind` derivado para `event` pelo trigger. A 22ª (limpeza individual, não
cancelamento) repontada para o único evento elegível do dia e **estornada** — o saldo dela
fica zero, então repontar não afirma mérito, só permite ao ledger dizer a que reunião a linha
se referia. O texto do estorno declara que o evento foi **inferido**, não lido de backup.

**2(B) — as 224.** Restauradas do dump de 22/08 com os **ids originais** (diffáveis contra o
backup), `reason` e `created_at` reconstruídos do próprio evento, mais 224 estornos de −10.

⚠️ **A parte perigosa foi o `occurred_at` do estorno.** Com o default (`now()`), os −2.240
cairiam no ciclo corrente e tirariam pontos de 40 pessoas HOJE. Cada estorno carrega o
`occurred_at` do crédito que reverte. Medido depois: **0 estornos dentro do cycle_4**.

### O padrão que emergiu: QUATRO leitores migraram de LINHA para SALDO

Este é o achado reutilizável da sessão, e ele só apareceu porque o append-only foi aplicado
de verdade:

| leitor | contava | passou a |
|---|---|---|
| de-duplicação do worker | existência de linha | `HAVING SUM(points) > 0` |
| medidor de duplicata (1ª versão) | linhas positivas > 1 | — |
| medidor de duplicata (2ª versão) | — | saldo acima de UM crédito |
| guard behavioural do #1470 | soma crua de pontos | soma só de `points > 0` |

⚠️ **Num ledger append-only, todo leitor escrito antes de existirem estornos lê o mecanismo
de correção como se fosse o defeito.** O do #1470 é o exemplo mais claro: ele somava pontos
crus em duas janelas de 7 dias, os estornos negativos derrubaram a janela de `created_at`
para **−897**, e a desigualdade se inverteu sem que nada de errado tivesse acontecido.

Ao introduzir estorno numa tabela, **procure todo mundo que conta linha ou soma cru** antes
de aplicar o dado.

### O vermelho que NÃO era meu, e quase foi lido como se fosse

A rodada 1 do CI reprovou na unidade (defeito real meu, o #1470). A rodada 2 reprovou no
`Smoke Test Routes` com `Expected /admin/selection to contain "id=sel-denied"`, precedido de
um erro do vite resolvendo `BaseLayout.astro`.

**Duas rodadas vermelhas seguidas na mesma PR puxam para "eu quebrei mais alguma coisa".** O
que separou foi cruzar a mensagem com a do run que a **#2300** já citava: é idêntica, sobre
outro código, na `main`. Diagnóstico completo (com a tabela de rodadas) no comentário da
#2300. O conserto da #2279 não alcança este caso: lá o dev server morre, aqui ele **não**
morre — sobe, responde 200 nas outras rotas, e falha só a resolução de um script.

### A fixture presa, e por que a limpeza falhou

`check-invariants` reprovou por `__1636_synthetic__ ...`, viva desde 04:17:54. O guard do
#1636 diz literalmente que apagar é o conserto pontual; foi apagada com predicado EXATO
(id + nome completo + e-mail) e confirmada por consulta nova: 185 candidaturas, 0 sintéticas.

⚠️ **A causa: a suíte DB-aware local e a do CI escreveram no MESMO banco no mesmo minuto.**
É a família da #2275. Não rode `npm test` local enquanto o CI roda.

E um quase-erro que vale mais que o conserto: a **primeira** tentativa de apagar essa fixture
apagou **0 linhas**, porque usei igualdade exata contra o nome que eu tinha lido **truncado
em 18 caracteres** (o real tem 48). Um `LIKE` teria "funcionado" — e teria apagado uma linha
que naquele momento não precisava ser apagada, porque o estado já tinha sarado sozinho.
**Predicado exato falha barulhento; predicado frouxo acerta o alvo errado.**

### Exercer a EF provou o caminho, e produziu 31 créditos

Depois do deploy, exerci a EF (não só confiei no "Deployed Functions"): HTTP 200,
`points_created: 31`, `points_per_attendance: 10` — o 10 vindo do catálogo prova que o
caminho novo (EF → worker → `gamification_rules`) está de pé.

Os 31 foram auditados antes de aceitar: **0** caíram sobre estorno (nenhuma correção foi
desfeita), **0** de evento cancelado (o filtro novo funciona), tipos só `geral` e `tribo`.

⚠️ E uma falsa pista que custou três medições: a faixa ia até **18/08**, o que parecia um mês
de sync quebrado. O `cron.job_run_details` diz `succeeded` nas 9 rodadas — mas `"1 row"` é o
`net.http_post` ter sido **enfileirado**, não a EF ter creditado. E `net._http_response` não
ajuda: retém **6 horas** (125 linhas), então o zero ali era retenção, não ausência.

A resposta veio pela outra ponta: **22 das 31 linhas de PRESENÇA foram criadas em 14/09 e
15/09**, depois do último cron (11/09). Os eventos de 18/08 aparecem porque a presença foi
**registrada tarde**, não porque o sync falhou. Não houve apagão.

### Estado final, medido

`duplicated_pairs=0` · `duplicated_points=0` · órfãs não rotuladas **0** · `ref_kind` nulo em
toda a tabela **0** · balde `orphan` intacto em 40 (42 no total, o congelado da #1537 não se
moveu) · **44 invariantes, 0 violações** · contratos 2292 + 1537 + 1087-wave3 + 785:
**69 testes, 0 falhas** · PR #2304 com **13 checks verdes**.
