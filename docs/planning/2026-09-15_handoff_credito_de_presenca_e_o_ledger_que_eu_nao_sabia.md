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
