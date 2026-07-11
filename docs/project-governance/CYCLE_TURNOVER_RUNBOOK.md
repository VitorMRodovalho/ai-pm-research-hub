# Runbook de virada de ciclo — C(n) → C(n+1)

**Escopo:** procedimento **reutilizável** para virar um ciclo de programa para o próximo, de forma governada e
idempotente. Nasceu do LL de arco #588 (a virada C3→C4 doeu por roll-forward manual + handoff sem protocolo +
líder sem workspace no kickoff) para que a C4→C5 e as seguintes **não repitam** essa dor.

**Refs:** EPIC #1002 (viradas de julho/2026) · #1104 (`admin_roll_cycle_membership`, entregue) · EPIC #1020
(protocolo de handoff — ondas #1293/#1294/#1295/#1296/#1297) · #809 (workspace de líder pré-kickoff, low) ·
`CYCLE3_CLOSURE_RUNBOOK_2026-07.md` (fechamento do ciclo que **sai**) · `CYCLE4_TURN_PLAN_2026-07.md` ·
`ACCESS_COHORT_FREEZE_2026-07-09_C3-C4.md` (freeze de acesso). LL #588.

> Aterrado ao vivo 2026-07-10. Identidades de membros + contexto pessoal ficam **fora** deste doc commitado
> (repo público, LGPD Art. 11) — as listas identificadas vivem na sessão do operador. **Re-aterrar os números a
> cada execução** (grounding GC — CLAUDE.md): eles mudam a cada ciclo.

---

## 0. SSOT — o que é fonte de verdade (não confundir os namespaces)

| Coisa | SSOT | Writer governado |
|---|---|---|
| Dimensão de **período** (código/label/início/fim/corrente) | tabela `cycles` | `admin_manage_cycle(p_action, ...)` |
| Filiação a **período** por membro (histórico por ciclo) | `member_cycle_history` | `admin_roll_cycle_membership(from, to, dry_run)` (#1104) |
| Namespace de **seleção** (ex. `cycle4-2026`) | `selection_cycles` / `selection_applications` | fluxo de aprovação de seleção |

⚠️ **`members.cycles[]` NÃO é filiação de período.** Esse array usa o namespace de **seleção**
(`selection_cycles.cycle_code`, ex. `cycle4-2026`), mantido pela aprovação de seleção — diferente do namespace de
**período** (`cycle_4`). **Decisão do owner (2026-07-10): a virada NÃO appenda `members.cycles[]`.** O SSOT de
filiação de período é `member_cycle_history`; nunca derivar coorte de período a partir de `members.cycles[]`
(ver `reference-members-cycles-unreliable-cohort-source`).

`cycles` colunas: `cycle_code, cycle_label, cycle_abbr, cycle_start, cycle_end, is_current, cycle_color,
sort_order, organization_id, created_at`.

---

## 1. A armadilha central — `cycle_end` ANTES do apply

`admin_roll_cycle_membership(from, to, false)`, no apply, faz **duas** coisas:
1. **Fecha** as rows abertas do `from_cycle` em `member_cycle_history`, gravando `cycle_end` **lido da dimensão
   `cycles`** (`from_cycle.cycle_end`).
2. **Insere** o snapshot da coorte continuante no `to_cycle`.

**Se `cycles.cycle_end` do ciclo que sai estiver NULL (que é o estado do ciclo corrente), o passo (1) é
PULADO** — as rows do `from_cycle` ficam abertas para sempre. Portanto:

> **Setar `cycles.cycle_end` do ciclo que SAI ANTES de chamar o apply.** Sem isso, o roll insere a nova coorte
> mas não fecha a anterior — as duas ficam abertas ao mesmo tempo.

`admin_roll_cycle_membership` **não** seta o `cycle_end` por conta própria (por design — a data de fim é decisão
de governança, não efeito colateral do roll). Esse é o passo que este runbook existe para não esquecer.

---

## 2. Estado aterrado (snapshot 2026-07-10 — re-aterrar antes de executar)

- Ciclo corrente: **`cycle_4`** (`is_current=true`), `cycle_start=2026-07-09`, **`cycle_end=NULL`**.
- `member_cycle_history` do `cycle_4`: **30 rows, todas ABERTAS** (`cycle_end IS NULL`).
- **`cycle_5` ainda NÃO existe** na dimensão `cycles`.
- Ciclos anteriores fechados: `cycle_3` (`cycle_end=2026-07-08`, 63 rows fechadas), `cycle_2`, `cycle_1`, `pilot`.

Ou seja, na próxima virada (C4→C5) os pré-requisitos são: (a) criar `cycle_5`; (b) setar `cycle_4.cycle_end`
antes do apply.

---

## 3. Definição da coorte continuante (o que o roll insere)

`admin_roll_cycle_membership` insere no `to_cycle` os **continuantes**, definidos como membro que, no momento da
virada:
1. está **ativo**;
2. tem **row ativa** (aberta) no `from_cycle` em `member_cycle_history`;
3. tem **engagement `volunteer` vigente em `to_cycle.cycle_start`** (`end_date` NULL ou `>= to_cycle.cycle_start`);
4. **ainda não tem row** no `to_cycle` (idempotência via `NOT EXISTS`).

Quem sai (offboard/não-renovação) **não** entra na coorte — por isso os handoffs de responsabilidade (§4, passo 2)
têm de ser resolvidos **antes** do roll, para que a coorte snapshot já esteja correta.

> `to_cycle.cycle_start` é lido da dimensão → o `cycle_(n+1)` precisa existir **com `cycle_start` setado** antes
> do dry_run já (senão o teste de vigência do engagement roda contra NULL).

---

## 4. Sequência de execução (a ordem importa)

Pré-condição: o **fechamento** do ciclo que sai já corre pelo `CYCLE3_CLOSURE_RUNBOOK` (selar presença, emitir
certificados de conclusão, exits agendados). Este runbook cuida da **virada de filiação + acesso**, não do
fechamento cerimonial.

1. **Pré-flight — aterrar (read-only).** Rodar as queries do §7. Confirmar: ciclo corrente, `cycle_end` do que
   sai (deve estar NULL antes), nº de rows abertas do `from_cycle`, e que o `to_cycle` (ainda) não existe.

2. **Resolver handoffs de responsabilidade (EPIC #1020).** Offboards + transições de líder da virada
   **colocados ou parked** ANTES do roll (inventário #1293 → park/place #1294 → sucessão de líder #1296).
   Enquanto o EPIC #1020 não estiver entregue, fazer o handoff **manualmente** conforme
   `CYCLE3_CLOSURE_RUNBOOK §4` (reatribuir `board_items` via `admin_offboard_member(p_reassign_to)`; trocar líder
   via `admin_change_tribe_leader`). Objetivo: a coorte continuante (§3) já reflete quem fica.

3. **Criar o ciclo que entra** (`is_current=false` ainda — o flip é no passo 6):
   ```sql
   SELECT admin_manage_cycle('create', 'cycle_5', 'Ciclo 5 (2027/1)', 'C5',
                             DATE '<cycle_start>', NULL, '<#hexcolor>', <sort_order>);
   ```
   `cycle_start` tem de estar correto (o roll o lê para o teste de vigência do engagement, §3).

4. **`dry_run` — conferir a coorte.**
   ```sql
   SELECT admin_roll_cycle_membership('cycle_4', 'cycle_5', true);  -- p_dry_run = true (default)
   ```
   Inspecionar a coorte continuante retornada. Bater contra a expectativa (ativos com engagement volunteer vigente
   menos os que saíram no passo 2). **Não prosseguir** se a contagem divergir do esperado.

5. **Setar `cycle_end` do ciclo que SAI** (a armadilha do §1) — no dia da virada (ou véspera):
   ```sql
   SELECT admin_manage_cycle('update', 'cycle_4', 'Ciclo 4 (2026/2)', 'C4',
                             DATE '2026-07-09', DATE '<cycle_end_do_C4>', '#06B6D4', 5);
   ```
   (`update` carrega os campos existentes + o novo `p_end`.)

6. **Apply — o roll de fato:**
   ```sql
   SELECT admin_roll_cycle_membership('cycle_4', 'cycle_5', false);  -- fecha rows abertas do C4 + insere coorte no C5
   ```
   Idempotente: re-rodar retorna 0 inseridos / 0 fechados.

7. **Flip do ciclo corrente:**
   ```sql
   SELECT admin_manage_cycle('set_current', 'cycle_5', NULL, NULL, NULL, NULL, NULL, NULL);
   ```
   (`set_current` seta `is_current=true` no alvo e `false` nos demais.) Junto: strings de UI Ciclo n→n+1
   (precedente #1101) e banners/kickoff.

8. **Reconciliação pós-virada (#1004 / #1297).** Rodar §7 de novo e confirmar os invariantes do §6. Rodar o
   relatório de handoffs pendentes (`get_pending_handoffs_report`, Onda E #1297) para nenhum handoff parked ficar
   vencido silencioso.

---

## 5. Gate — governança & GC-097

- Toda escrita é por **RPC governada** (`admin_manage_cycle`, `admin_roll_cycle_membership`, `admin_offboard_member`,
  `admin_change_tribe_leader`) — **nunca `UPDATE` cru** em `cycles`/`member_cycle_history` (rastro LGPD + gate
  `manage_platform`).
- As RPCs são SECDEF self-gated (`manage_platform`); anon revogado. Chamar sob contexto autenticado do operador GP.
- Não há migration nova nesta operação (as RPCs já existem) — é execução de dados, não DDL. Se alguma correção de
  RPC for necessária no caminho, seguir o ritual GC-097 completo (apply_migration + arquivo local byte-idêntico +
  `migration repair` + `NOTIFY pgrst` + **delete da phantom tracking-row**).

---

## 6. Invariantes de verificação (pós-apply)

- `member_cycle_history`: **`open_rows(from_cycle) = 0`** (todas fechadas com `cycle_end = from_cycle.cycle_end`).
- `member_cycle_history`: **`rows(to_cycle) = |coorte continuante|`**, todas abertas.
- `cycles`: exatamente **um** `is_current=true` (o `to_cycle`); `from_cycle.cycle_end` não-NULL.
- Nenhum membro ativo com engagement volunteer vigente **sem** row no `to_cycle` (senão a coorte foi subestimada —
  investigar antes de re-rodar).
- Handoffs (#1020): 0 posse órfã (`detect_orphan_assignees_from_offboards` = 0); 0 handoff parked vencido.

---

## 7. Queries de aterramento (read-only)

```sql
-- dimensão de ciclos
SELECT cycle_code, cycle_label, cycle_start, cycle_end, is_current FROM cycles ORDER BY sort_order;

-- estado das rows por ciclo
SELECT cycle_code, count(*) rows,
       count(*) FILTER (WHERE cycle_end IS NULL) open_rows,
       count(*) FILTER (WHERE cycle_end IS NOT NULL) closed_rows
FROM member_cycle_history GROUP BY cycle_code ORDER BY cycle_code;

-- coorte continuante esperada (espelha a lógica do roll; NÃO escreve)
-- (rodar com to_cycle.cycle_start já setado)
```

---

## 8. Acoplamento com #809 (workspace de líder pré-kickoff — low, deferido)

A virada só fica "redonda" se os **líderes que entram** chegam ao kickoff com a iniciativa já desenhada (tema,
descrição, cards de entregáveis, vídeo de apresentação). #809 propõe o **workspace draft** self-service para o
líder pretendido preparar isso antes do go-live — mas é **low e ainda uma questão de design** (self-service vs.
"PM monta offline + só pede o vídeo"). **Enquanto #809 não é priorizado, o caminho da virada é o manual:** a
liderança do projeto monta tema/descrição/cards offline e do líder pretendido pede-se o vídeo, vinculado à
iniciativa (precedente C4: iniciativa "Kickoff + Onboarding dos Líderes", board de cards de vídeo). Este runbook
apenas **registra o acoplamento**; a construção do workspace é o #809.

---

_Criado 2026-07-10 (sessão dev C5-prep, #809/#588). Reutilizável a cada virada — re-aterrar §2/§7 antes de
executar._
