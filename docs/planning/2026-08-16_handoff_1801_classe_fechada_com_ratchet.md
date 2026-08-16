# Handoff — 16/08/2026: a classe do #1801 fechou inteira, com ratchet de linha de base zero

> Sessão anterior: `docs/planning/2026-08-15_handoff_1797_mergeada_e_1572_com_o_ciclo_certo.md`
> Arranque desta: `docs/planning/2026-08-16_PROMPT_ARRANQUE_1801_E_1710_VESPERA.md`
> Arranque da próxima: `docs/planning/2026-08-17_PROMPT_ARRANQUE_1710_VESPERA_1805_E_1780.md`

---

## Estado ao fechar

`main` em **`2d2902f6`**. **Zero PRs abertas. Zero alertas Dependabot. Zero bypass na janela de 7
dias** (todos os commits PR-backed). **1 merge, 12/12 checks verdes**, sem `--admin`.

| issue | desfecho |
|---|---|
| **#1801** | **FECHADA** — a classe inteira, não só as 9 que faltavam |
| **#1805** | **ABERTA** — achado de passagem, fora do escopo de propósito |

⚠️ **Todo número abaixo foi medido em 16/08 e vários se movem sozinhos. Re-meça, não recite.**

---

## O que a triagem mudou no tamanho do problema

A issue listava 10 funções. A varredura sobre `pg_proc` achou **12**, e a leitura uma a uma separou
defeito de ordenação legítima. **Duas não estavam na lista de ninguém:**

- **`get_entry_chapter_diagnosis`** — não constava da issue;
- **o ramo `last` do `get_chapter_selection_summary`** — a issue citava essa função como *referência
  de quem já faz certo*. E faz, **no ramo `open`**, que filtra `status='open'`. O ramo `last` não
  filtra nada.

E **quatro** candidatas eram falso positivo (`check_application_score_consistency`,
`link_my_credly_badge`, `get_cycle_renewal_radar`, `nucleo_contract_cohort_cycle_id`): ali o
`created_at` / `LIMIT 1` é de `selection_applications`, e o ciclo entra por chave estrangeira.

**Não mexidas, por leitura e não por descuido:** `get_selection_cycles` LISTA ciclos;
`compute_ai_calibration_weekly` e `recompute_all_active_pert_cutoffs` iteram em LOOP sem `LIMIT`, e
ali a ordenação é ordem de iteração, não escolha.

---

## Antes → depois, medido pelo caminho real do chamador

Impersonação em transação abortada, não inspeção estática:

| superfície | antes (`cycle2-2025`) | depois (`cycle4-2026`) |
|---|---:|---:|
| funil — `get_selection_pipeline_metrics` | 8 candidaturas | **81** |
| calibração — `get_evaluator_calibration_stats` | **0** avaliações / **0** avaliadores | **238 / 2** |
| diversidade — `get_diversity_dashboard` | 8 / 6 aprovados | **81 / 57** |
| ranking — `get_selection_rankings` | **lista vazia** (0/0) | **56** pesquisador + **10** líder |
| diagnóstico — `get_entry_chapter_diagnosis` | 6 linhas | **57** |
| `get_chapter_selection_summary.last` | 30/11/2025 | **30/06/2026** |

O painel de calibração rodava sobre um ciclo com **zero avaliações**; a tela de ranking do admin
devolvia **lista vazia**.

---

## A ordenação canônica ganhou dono: `selection_active_cycle_id()`

Três chaves: `status='open'` → `open_date` (a data do **fato**) → `created_at` (último desempate,
nunca o critério).

📌 **Por que ORDENAR e não filtrar por `status='open'`:** o domínio do CHECK é
`('draft','open','evaluation','interview','decision','closed')`. Um ciclo que avance de `open` para
`evaluation` **deixaria de existir** para um filtro puro; ordenando, degrada para o mais recente por
`open_date` em vez de devolver NULL.

---

## Duas entradas que precisam da justificativa junto

- **`get_chapter_selection_summary`** — o defeito estava **dormente**: a tela só renderiza `last`
  quando não há ciclo aberto, e hoje há. Acordaria sozinho quando o `cycle4-2026` fechar.
- **`get_my_pending_evaluations`** — **zero mudança hoje** (medido: antes e depois resolvem o mesmo
  `cycle4-2026`, porque filtra por `phase='evaluating'`). Entrou porque `created_at` era a primeira
  chave de desempate, a divergência phase × status **já existe no dado** (`cycle2-2025` está
  `closed` com phase `planning`), e o portão de autorização logo abaixo é **escopado no ciclo
  escolhido** — "qual ciclo" também decide "quem pode ler". O portão do #298 segue intacto e testado.

---

## O ratchet, e por que ele não é cego

`_audit_selection_cycle_resolution()` é derivado de `pg_proc`. Viola quem escolhe **uma** linha de
`selection_cycles` tendo `created_at` como **primeira** chave do `ORDER BY`; `created_at` como
último desempate é legítimo e não acusa.

**Linha de base ZERO, sem exceção a manter.** Validado nas duas direções:

1. contra o catálogo **pré-correção** acusava as 8 e liberava as 6 que já faziam certo, sem falso
   positivo;
2. plantando a violação numa transação abortada, acusou 1 e **nada persistiu**.

📌 O passo 2 é o que separa guard de decoração. **Um guard que nasce verde é indistinguível de um
guard cego** — prove que ele fica vermelho.

---

## Os quatro tropeços da sessão, que valem mais que o patch

1. 🔴 **Quase apliquei uma função inventada.** Transcrevi `_test_invariants_with_synthetic_breach` a
   partir do **trecho de 14 linhas** que a varredura mostrou. O que saiu era plausível e
   inteiramente falso: retorno `TABLE(...)` em vez de `jsonb`, códigos `'AC'` em vez de `'R'`/`'S'`,
   e um bloco `EXCEPTION` inexistente. **`pg_get_functiondef` completo antes de todo
   `CREATE OR REPLACE`** — o fragmento serve para TRIAR, nunca para ESCREVER.
2. ⚠️ **`\b` no ARE do Postgres é BACKSPACE**, não fronteira de palavra (isso é `\y`). O primeiro
   guard devolveu **zero linhas** e parecia dizer "nada a corrigir", com 8 funções defeituosas.
3. ⚠️ **A ganância do RE inteiro vem do PRIMEIRO quantificador com preferência**, então `\s+` antes
   de `[^;]*?` torna tudo guloso: a janela engoliu dois ramos numa medição só. Janela limitada
   (`{0,250}`; o Postgres recusa contagem acima de 255).
4. ⚠️ **O guard vermelhou no próprio `COMMENT ON`**, que ENSINA a não usar o padrão e por isso o
   cita literalmente. Corrigido separando prosa de SQL executável (o filtro de `--` do #1784 não
   pega blocos `COMMENT ON`), **não** apagando a documentação.

E um quinto, de método: tentei varrer a classe do #1805 por regex de literal e vieram **35 funções,
quase todas falso positivo** — o `status` casado era de `selection_applications` /
`selection_interviews` / `selection_leads`, que têm domínio próprio. **Não relatei a classe**;
relatei os 3 casos que li, e registrei na issue a forma de varredura que falhou.

---

## #1805 — o que ficou registrado e não corrigido

Literal de estado **fora do domínio do CHECK**, em ramo que nunca casa (calado):

- **`recompute_all_active_pert_cutoffs`** (cron): `phase IN ('evaluating','interviews','open_apps')`
  — **`open_apps` não existe**; o valor real é `applications_open`. Um ciclo com inscrições abertas
  nunca tem os cortes PERT recalculados por este cron. **É o mais concreto dos três.**
- **`compute_ai_calibration_weekly`** (cron): `status IN ('open','evaluating','decided','closed')` —
  `evaluating` e `decided` são vocabulário de `phase`; `draft`/`evaluation`/`interview`/`decision`
  nunca casam. Latente hoje (4 ciclos em `open`/`closed`).
- **`selection_consistency_report`**: `status IN ('open','active')` — `active` é literal morto.

---

## Conferência

- **md5 normalizado dos 10 corpos vivos contra o arquivo da migration: 10/10.**
- Suíte com DB: **6872 testes, 0 falhas, 1 skip**, 604 s. Offline: 6419, 0 falhas, 52 s.
- Build verde (4m25s). Lints verdes. CI **12/12**.
- ACLs das 7 funções substituídas **inalteradas**; as duas novas nascem fechadas.

⚠️ **Observado e NÃO corrigido (classe do #1592):** `get_my_pending_evaluations`,
`get_selection_pipeline_metrics` e `get_selection_rankings` carregam `EXECUTE` para PUBLIC **e**
`anon`; `get_chapter_selection_summary` carrega para `anon`. Todas gateiam internamente por
`auth.uid()`, então é profundidade e não porta aberta — mas é a superfície que o #1592 mede.

---

## Aberto ao fechar

**#1710** (véspera 23/08, prazo 24/08 — re-medir pelos DOIS caminhos) · **#1805** (novo) · resto do
**EPIC #1780** · **#1586** e o **funil de 28/08**, que só fecham com uso real · **#1592**.
