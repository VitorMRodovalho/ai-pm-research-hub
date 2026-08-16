# Handoff — 15/08/2026 (madrugada): a #1797 mergeou, o #1572 fechou, e o contador nasceu apontando para o ciclo errado

> Sessão anterior: `docs/planning/2026-08-15_handoff_1783_onda_fechada_em_dois_lotes_e_1797_em_espera.md`
> Arranque da próxima: `docs/planning/2026-08-16_PROMPT_ARRANQUE_1801_E_1710_VESPERA.md`

---

## Estado ao fechar

`main` em **`961fc229`**. **Zero PRs abertas.** **Zero alertas Dependabot.** **Zero bypass na janela
de 7 dias** (todos os commits PR-backed; o `a61879f2` de 08/08 saiu da janela).

**4 merges na sessão, zero bypass:** #1798 (docs) · #1797 (astro 7) · #1799 (#1572) · #1802 (#1801).

Worker deployado em produção, versão **`20339768`**, com smoke conferido: o texto novo aparece no
HTML servido por `nucleoia.vitormr.dev/admin/selection`.

| issue | desfecho |
|---|---|
| **#1783** | **FECHADA** — a #1797 mergeou e os 3 alertas do astro zeraram (8 → 0 na onda inteira) |
| **#1572** | **FECHADA** — aceite antecipado virou estado explícito com justificativa |
| **#1801** | **ABERTA de propósito** — 1 de 10 funções corrigida; a triagem das outras 9 é o trabalho |
| **#1592** | números re-ancorados: **468 de 1105** SECDEF alcançáveis por chamador anônimo |

---

## ⚖️ Decisão do PM: mergear a #1797 agora, não esperar 24/08

A recomendação registrada era segurar. O PM decidiu o contrário, aceitando trocar astro, adapter,
integração react e bundler dentro da janela do selo do #1710. Mergeada com base re-sincronizada
(a branch estava `BEHIND`; rebase, CI re-rodado, 11/11).

⚠️ **Segue valendo, e não deve ser vendido diferente:** a #1797 **não** fecha a classe do
`image-size`. A cópia vendorizada dentro do astro tem o mesmo laço ICNS sem guarda em 6.4.8, 7.1.0 e
7.2.2.

---

## ⚖️ Decisão do PM: #1572 por justificativa, não por gate de N avaliações

O ciclo se chama "Aceite Antecipado", então aprovar sem lastro é intencional por desenho. O defeito
era a ausência de trilha.

**Medido em 15/08, antes da mudança:**

| ciclo | decididas com ZERO avaliação | com alguma trilha em log |
|---|---|---|
| `cycle2-2025` | 6 aprovadas + 2 rejeitadas | **0** |
| `cycle3-2026` | 3 aprovadas + 3 rejeitadas | 5 de 6 |
| `cycle4-2026` | 1 rejeitada | 1 |

E `min_evaluators = 2` **declarado nos 4 ciclos**, sem nada que o consultasse no momento da decisão.

**O que entrou:** `early_acceptance_at` / `_by` / `_reason` na candidatura (o carimbo **é** a flag,
sem booleano espelho, com CHECK exigindo autor e motivo de 20+ caracteres) · portão em
`admin_update_application` e `finalize_decisions`, contando avaliação de **qualquer tipo** ·
`admin_decide_dual_track` repassando a justificativa para as duas pontas (assinatura 4 → 5, DROP +
CREATE) · `decided_without_evaluation` em `get_selection_health` · painel na tela de seleção.

**Dois defeitos pré-existentes que o portão tornaria alcançáveis, corrigidos junto:**

1. `admin_decide_dual_track` guardava os retornos das duas pontas e **nunca os conferia**: uma ponta
   com `{"error":...}` virava `success: true` e a tela dizia "Decisões aplicadas".
2. `finalize_decisions` engolia falhas no `EXCEPTION WHEN OTHERS` e devolvia só um `approved` menor,
   sem dizer quais ficaram de fora. Agora devolve `refused[]`.

---

## 🔴 O erro da sessão: o contador nasceu apontando para o ciclo errado

Vale registrar inteiro, porque a lição não é sobre este contador.

`get_selection_health` resolvia "ciclo ativo" por `ORDER BY created_at DESC LIMIT 1`. Mas
`created_at` é a data em que a **linha** foi escrita: o backfill do `cycle2-2025` entrou em
**2026-07-13** e fez de um ciclo **fechado de 2025** a linha mais nova da tabela.

Consequência: o contador do #1572 contava o `cycle2-2025`, que tem 6 aprovadas sem avaliação e
nenhuma justificada. O `health_signal` teria ficado **preso em amarelo** — exatamente o que o
comentário que eu mesmo escrevi na migration dizia evitar.

**É a causa 1 da #1586(b) reaparecendo.** Aquela correção já trazia a nota certa no corpo
(*"por STATUS, nunca por `created_at`"*); o que faltou foi varrer a classe. A varredura de agora
achou **10 funções** com a mesma resolução.

Corrigido em `get_selection_health` (#1802) e a classe registrada na **#1801**.

⚠️ **Nem todas as 10 são defeito.** `get_selection_cycles` LISTA ciclos e ordenar por `created_at`
ali é legítimo. O critério de triagem é *"esta função escolhe UM ciclo para chamar de ativo?"*, não
*"esta função cita `created_at`"*.

**Efeito colateral bom da correção:** a recusa por conflito de interesse (ADR-0109) nessa superfície
era avaliada contra o ciclo de 2025, então um candidato do ciclo **aberto** não era recusado. Agora é.

---

## Limites do que foi entregue, ditos de propósito

1. **O portão cobre APROVAÇÃO.** Rejeição sem avaliação é contada e exposta, **não bloqueada**.
   Estender é decisão do PM e mudaria o que o GP experimenta num ciclo aberto.
2. **Duas RPCs de reconciliação seguem movendo status sem o portão**, por desenho, porque não
   expressam decisão de mérito: `recompute_application_status` (`SET status = v_rec.canonical`) e
   `reconcile_vep_terminal_status` (`SET status = v_target`, espelha o `vep_status_raw`).
   **O portão não é universal.**

---

## Medições finais

| medida | valor |
|---|---|
| aprovadas sem avaliação no ciclo **ativo** (`cycle4-2026`) | **0** |
| rejeitadas sem avaliação no ciclo ativo | 1 |
| aprovadas sem avaliação, todos os ciclos | 9 |
| rejeitadas sem avaliação, todos os ciclos | 6 |
| `open_cycles` | 1 |
| suíte com DB | 6862 testes · 6861 pass · **0 falhas** · 1 skip · 616 s |
| suíte offline | 6411 testes · 0 falhas · ~53 s |

Com zero aprovadas sem lastro no ciclo aberto, o sinal não é puxado para amarelo por este critério.

---

## Como a DDL foi conferida (vale repetir)

- **md5 normalizado de cada corpo vivo contra o arquivo da migration.** Foram 4 na primeira e 1 na
  segunda, todos batendo. Fecha o risco de o payload digitado divergir do arquivo — que é real,
  porque `apply_migration` recebe **string**, não caminho.
- **Ensaio por impersonação em transação abortada**, exercitando o caminho inteiro em vez de só o
  estático: sem motivo e com 19 caracteres recusam com `early_acceptance_reason_required`; com
  motivo válido passa (`rejected → approved`, 7 passos de onboarding semeados), carimbo gravado com
  autor resolvido e 1 linha de log com `early_acceptance=true`. Nada persistiu: 0 carimbos, 0 logs,
  contagens intactas em 98/55.
- ⚠️ **A primeira leitura de conferência veio vazia e eu quase li como falha de gravação.** Era a
  RLS: eu lia a tabela **ainda como `authenticated`**. `RESET ROLE` antes da conferência.

---

## Aberto ao fechar

**#1801** (9 funções por triar + guard ratchet) · **#1710** (re-medir em 23/08 pelos dois caminhos;
lista nominal ao GP **fora** de issue e PR) · resto do **EPIC #1780** · **#1586** e o **funil de
28/08**, que só fecham com uso real · **#1592** (barreira contra DDL nova).
