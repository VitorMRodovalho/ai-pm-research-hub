# Handoff para o time — Conciliação de Gamificação (Showcases + Champions) · Ciclo 3

**Para:** time da plataforma `ai-pm-research-hub` (revisão + validação)
**De:** conciliação assistida via MCP `nucleo-ia` (sessão do PMO/Pai), 2026-07-02/03
**Escopo:** protagonismo das Reuniões Gerais + palestras + entregáveis do **Ciclo 3 (2026/1)**, a partir do canal YouTube do Núcleo cruzado com os registros da plataforma.
**Working doc (inventário técnico completo):** `docs/reports/gamification-c3-conciliation-inventory-2026-07-02.md` (mesmo diretório)

> **Por que revisar:** as escritas abaixo foram feitas via MCP e **retornaram sucesso individualmente**, mas a verificação do rollup (`get_member_cycle_xp`) sugere que o XP pode estar **caindo no balde errado** (ver §3). Antes de comunicar pontuação aos membros, validar §3.

---

## 1. O que foi GRAVADO (ledger de auditoria)

Total: **15 showcases** (`register_showcase`) + **3 champions de entregável** (`award_champion`). Nenhuma escrita de `talk`, `youtube_url` ou champion `general` foi feita (ver §5).

### 1a. Showcases — preenchimento de gaps (reuniões que tinham 0 showcase)
| record_id | event | data | membro | member_id | tipo | XP |
|---|---|---|---|---|---|---|
| `0f655508` | `5f4b01be` | 05-07 | Marcos Klemz | `c204ac61` | case_study | 25 |
| `5ec290e0` | `5f4b01be` | 05-07 | Thiago Freire | `279684f3` | tool_review | 20 |
| `60bc6287` | `5f4b01be` | 05-07 | Fernando Maquiaveli | `c8b930c3` | tool_review | 20 |
| `5134b0ec` | `5f4b01be` | 05-07 | Ana Carla Cavalcante | `63b87315` | case_study | 25 |
| `da38f4e2` | `5f4b01be` | 05-07 | João Coelho Júnior | `293fcaf8` | case_study | 25 |
| `b3be07fb` | `5f4b01be` | 05-07 | João Uzejka dos Santos | `d29c42fd` | awareness | 15 |
| `d8557b7b` | `a029ce54` | 06-18 | Rodolfo Santana | `60ffebc2` | case_study | 25 |
| `d7e543e3` | `a029ce54` | 06-18 | Leonardo Chaves | `8f171d94` | tool_review | 20 |
| `05beb383` | `a029ce54` | 06-18 | Ricardo França | `c562af94` | awareness | 15 |
| `5c3017a9` | `a029ce54` | 06-18 | Fernando Maquiaveli | `c8b930c3` | awareness | 15 |
| `18a1e6ca` | `a029ce54` | 06-18 | Marcos Klemz | `c204ac61` | awareness | 15 |
| `02beb41f` | `f8a7787b` | 03-12 | Ana Carla Cavalcante | `63b87315` | tool_review | 20 |

### 1b. Showcases — passe fino (protagonista da ata sem showcase, em reuniões que já tinham outros)
| record_id | event | data | membro | member_id | tipo | XP |
|---|---|---|---|---|---|---|
| `6aa53caf` | `ba2b9bf9` | 03-26 | Fabrício Costa | `92d26057` | tool_review | 20 |
| `30b8a5d0` | `deb3de2b` | 04-23 | Fabrício Costa | `92d26057` | awareness | 15 |
| `23c10244` | `9ea5fc3c` | 06-04 | Fabrício Costa | `92d26057` | awareness | 15 |

### 1c. Champions de entregável (`surface=deliverable`, `context_kind=artifact` = meeting_artifacts)
| champion_id | ata (context_id) | data | destinatário | member_id | critérios | pts |
|---|---|---|---|---|---|---|
| `6d8bab65` | `df735a51` | 03-30 | Débora Moura | `a8c9af17` | qualidade_acima_baseline, inovacao_tecnica | 50 |
| `45b186c7` | `76c39319` | 03-23 | Débora Moura | `a8c9af17` | qualidade_acima_baseline, inovacao_tecnica | 50 |
| `d7708aef` | `dcded397` | 04-06 | Jefferson Pinto | `622ab18b` | qualidade_acima_baseline, impacto_pmi | 50 |

> **Decisão de escopo:** a ata Geral 04-09 (`c1a8e1c5`, creator Vitor) **NÃO** foi premiada — o próprio Vitor (gestor da comunidade) pediu para não se autopontuar. Além disso a ata tem `initiative` NULL, o que poderia falhar na checagem de autoridade.

---

## 2. Como a conciliação foi feita (método, para auditabilidade)

- **Recorte:** `cycle_3`, 2026-03-01 → hoje (via `get_current_cycle`, ao vivo).
- **Fonte de protagonismo:** `event_showcases` já registrados (autoritativo) + `get_event_detail` (ata + attendance) das 10 Reuniões Gerais. O parse das descrições do YouTube foi só o gatilho; o registro seguiu a **ata/plataforma**.
- **Dedup:** cada gap era reunião com `showcase_count=0`; cada item do passe fino foi em evento onde o membro **não** tinha showcase; cada champion usou `context_id` de ata sem champion prévio (o cap de 1/contexto teria bloqueado). Não houve repontuação.
- **Régua (grounded em `gamification_rules`):** showcase case_study 25 · tool_review/prompt_week 20 · quick_insight/awareness 15. Champion deliverable base 40 + 5/critério, cap 60.

---

## 3. ⚠️ PROVÁVEL ISSUE — XP pode estar indo para o balde errado

**Sintoma.** As 18 escritas retornaram `success` com `xp_awarded`/`points_awarded` corretos. Mas o rollup por membro (`get_member_cycle_xp`, ao vivo 2026-07-02) **não** reflete isso nos baldes esperados:

| membro | cycle_showcase | cycle_artifacts | cycle_bonus | cycle_points | rank |
|---|---|---|---|---|---|
| Ana Carla (`63b87315`) | **15** | 0 | 195 | 420 | 7º |
| Fabrício (`92d26057`) | **0** | 0 | 85 | 285 | 9º |
| Débora (`a8c9af17`) | **0** | 0 | 375 | 515 | 2º |

**Por que parece errado:**
- Ana Carla tem **6 showcases** no ciclo (incluindo os de hoje) mas `cycle_showcase` mostra **15** (≈ um único item).
- Fabrício ganhou 3 showcases hoje + já tinha 1 (04-09) e mostra `cycle_showcase = 0`.
- O grosso do XP está em **`cycle_bonus`** (Débora 375, Ana Carla 195), que não deveria ser o destino de showcase/champion.

**Hipóteses a investigar (time):**
1. `register_showcase` / `award_champion` estão **escrevendo o XP no bucket errado** (ex.: `bonus` em vez de `showcase`/`artifacts`) — bug de roteamento na RPC.
2. Ou o rollup `get_member_cycle_xp` **agrega showcase/champion dentro de `bonus`** por design, e os campos `cycle_showcase`/`cycle_artifacts` medem outra coisa — nesse caso, é doc/nomenclatura, não bug.
3. Ou há **lag de materialização** da view de XP (o `cycle_showcase` não atualizou pós-escrita).

**Ação sugerida:** conferir, no hub via `execute_sql`, a fonte de verdade do XP (tabela de `gamification_ledger`/eventos de pontos) para esses 3 member_ids, e a definição da view/materialized que alimenta `get_member_cycle_xp`. Se for o caso 1, é issue de correção de RPC; casos 2/3 são doc/refresh. **Não comunicar ranking aos membros até isso fechar.**

---

## 4. Ambiguidades / dados a confirmar

| # | Item | Situação | Encaminhamento |
|---|---|---|---|
| A | **Ricardo França** = `c562af94` | `full_name` na base grava **"Ricardo Santos"** (email `r_frana@…`) | Vitor confirmou que é o Ricardo França. Corrigir o `full_name` no cadastro? |
| B | **Sávio** (05-21, CPMAI) | Convidado **externo** (organizado por Fabrício), não é membro | Correto **não** pontuar (não-atribuível). Nenhuma ação. |
| C | **"Maia" vs Mayanna** (03-26, podcasts NotebookLM) | Showcase pré-existente atribui "NotebookLM podcasts" a **Ana Carla**; a ata do 03-26 fala em **"Maia"** (= Mayanna Duarte, comms). Possível **misatribuição** de um showcase antigo. | **Revisar:** o showcase de podcast do 03-26 é da Ana Carla ou da Mayanna? (não foi alterado nesta conciliação) |
| D | **Thiago** | Dois na base: Thiago Freire (`279684f3`, T4) e Thiago Dieb (`36631e37`, guest). Usado o **Freire** (confirmado por Vitor). | OK. |
| E | **João** | Dois: João Coelho Jr (`293fcaf8`) e João Uzejka (`d29c42fd`). Desambiguado por evidência de showcase/ata evento a evento. | OK. |

---

## 5. O que NÃO foi tocado (pendências)

| Item | Motivo | Próximo passo |
|---|---|---|
| **`talk` 25 XP** (palestrantes SESTEC 06-03 + Painel ANSI 07-01) | **Não há tool MCP** para registrar `talk`; a rota é o engajamento `speaker` da iniciativa do webinar | Confirmar/aplicar a rota do `talk` (PR #1075) — palestrantes: Fernando ×2, Hayala, Sarah, Marcos, Jefferson, Fabrício |
| **`youtube_url` NULL** em 3 eventos (05-21 `43135439`, 06-04 `9ea5fc3c`, 06-18 `a029ce54`) | `update_event_instance` não cobre o campo | `execute_sql` no hub (SQL pronto no working doc §5) para vincular as gravações |
| **Champion `general`** (≤3/reunião) | Depende de seleção do gestor | Vitor indica os destaques por reunião (a ata de 05-21 já sugere Ana Carla, Fernando, Fabrício) |

---

## 6. Perguntas abertas para o time

1. **§3 é bug de RPC ou de rollup?** (bloqueante para comunicar ranking) — qual é a fonte de verdade do XP e a view que `get_member_cycle_xp` lê?
2. **Item C (§4):** o showcase de podcast NotebookLM do 03-26 está no membro certo?
3. **`talk`:** a rota do webinar já credita os 25 XP automaticamente a partir do engajamento `speaker`, ou precisa de um passo manual?
4. Os **25 showcases pré-existentes** (não criados aqui) já foram auditados alguma vez, ou vale um passe de sanidade junto?
5. Padronizar `full_name` "Ricardo Santos" → "Ricardo França"?

---

## 7. Resumo de impacto (se o XP estiver no bucket certo)

- **+290 XP** de showcase distribuídos (12 gaps + 3 passe fino).
- **+150 pts** de champion de entregável (Débora 100, Jefferson 50).
- Membros mais impactados: Ana Carla (+65), Marcos Klemz (+40), Fernando (+35 showcase), Fabrício (+50 showcase), Débora (+100 champion).
- Cobertura de showcase das 10 Reuniões Gerais do Ciclo 3: de 7/10 para **10/10**.
