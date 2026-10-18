# Cycle 3 → Cycle 4 Cohort Prep (p129 S1 — Action 4)

**Sessão**: p129 S1
**Data**: 2026-05-09
**Mandato PM Vitor**: separar candidates do cycle 3 para tomar decisão sobre cohort movement antes do Caminho 3 (Cycle 4 launch prep)

> **Nomes trocados por identificador opaco em 17/10/2026 (#1694).** Cada candidato virou um código (C01 a C37); a mesma pessoa mantém o mesmo código nas duas linhas em que aparece. A correspondência entre código e pessoa não fica no repositório.

## Resumo

Total de 40 candidates no cycle 3 (`d28313d4-569a-4c58-9eae-7e84c5da29b1`).

| Categoria | Count | Ação |
|---|---|---|
| KEEP_CYCLE_3 — decisões já tomadas | 5 | manter (immutável: approved/rejected/withdrawn) |
| KEEP_CYCLE_3 — test journey | 1 | C01 — extend formal aceite via plataforma |
| MOVE_TO_CYCLE_4 — submitted/none/0-1 evals | 25 | mover para cycle 4 cohort |
| REVIEW_CASE_BY_CASE — interview scheduled | 9 | discussão por candidato (alguns têm interview eval) |

---

## KEEP_CYCLE_3 (decisão tomada — 5 + 1 = 6)

| Nome | Chapter | Role | Status | Notas |
|---|---|---|---|---|
| **C01** | (sem) | researcher | `interview_pending` (just advanced p129) | **Test journey** — extender formal aceite via plataforma; PM teste fluxo restante |
| C02 | PMI-CE | leader | approved | já membro ativo |
| C03 | PMI-MG | leader | approved | já membro ativo |
| C04 | PMI-MG | leader | approved | já membro ativo |
| C05 | (sem) | leader | rejected | decisão tomada |
| C06 (1) | PMI-CE | leader | withdrawn | candidate retirou |

## MOVE_TO_CYCLE_4 (25)

Todos `status='submitted'` + `interview_status='none'` + 0 evals (com 1 exceção: C20 tem 1 obj_eval).

| Nome | Chapter | Role | Notas |
|---|---|---|---|
| C07 | PMI-MG | researcher | |
| C08 | PMI-CE | researcher | |
| C09 | (sem) | researcher | |
| C10 | PMI-PE | researcher | |
| C11 | (sem) | researcher | |
| C12 | PMI-MG | researcher | |
| C13 | PMI-MG | researcher | |
| C14 | PMI-DF | researcher | |
| C15 | PMI-RS | researcher | |
| C16 | PMI-MG | researcher | |
| o candidato afetado (#332) | PMI-RS | researcher | |
| C17 | (sem) | researcher | |
| C18 | PMI-CE | leader | (note: patrocinador de programa parceiro — special case?) |
| C19 | PMI-RS | researcher | |
| **C20** | PMI-CE | researcher | 1 obj_eval (final_score=173) — tem entrevista marcada hoje |
| C21 | PMI-RS | researcher | |
| C22 | PMI-MG | researcher | |
| C23 | PMI-CE | researcher | (note: cancelou entrevista ontem) |
| C24 | PMI-RIO | researcher | 1 obj_eval + 1 int_eval — tem score! |
| C25 | PMI-CE | researcher | |
| C26 | PMI-RS | researcher | |
| C27 | PMI-CE | researcher | |
| C28 | (sem) | researcher | |
| C29 (researcher) | (sem) | researcher | |

## REVIEW_CASE_BY_CASE (9 — interview_status='scheduled')

Estes têm entrevista marcada mas não realizada. Alguns têm interview eval registrada (caso especial).

| Nome | Chapter | Role | Obj evals | Int evals | Notas |
|---|---|---|---|---|---|
| C30 | PMI-RS | researcher | 0 | 0 | (cancelou) |
| C31 | PMI-MG | researcher | 0 | 0 | (cancelou) |
| C32 | PMI-MG | researcher | 1 | 0 | |
| C33 | PMI-CE | researcher | 1 | 0 | |
| C34 | PMI-PR | researcher | 0 | 0 | |
| C35 | PMI-PR | researcher | 1 | 0 | (cancelou) |
| C36 | PMI-RS | researcher | 0 | 0 | |
| **C37** | PMI-RJ | researcher | 1 | **1** | tem interview eval! |
| **C06 (2)** | PMI-CE | researcher | 1 | **1** | tem interview eval! (DUPLICATE aplicação? mesma email da withdrawn leader acima) |
| C29 (leader) | (sem) | leader | 0 | 0 | (segunda aplicação do mesmo email — tem researcher MOVE_TO_CYCLE_4 acima) |

## Observações

1. **C06 aparece 2x** com mesmo email (`redacted-047@example.com`) — uma withdrawn (leader) + uma submitted/scheduled (researcher). Provável duplicate por mudança de track. Verificar.
2. **C29 aparece 2x** com mesmo email — uma submitted researcher + uma submitted leader scheduled. Verificar.
3. **C37 + C06 (researcher)**: têm interview eval REGISTRADA mesmo com `interview_status='scheduled'`. Estranho — provavelmente foi feita avaliação informal sem mark_interview_status. Investigar.
4. **C18** (PMI-CE leader) — é patrocinador de um programa parceiro. Caso especial — confirmar se ele é candidate normal ou se aplicação é placeholder.
5. **C20**: tem entrevista MARCADA pra HOJE 19:00 (Calendar event). Score 173 partial. Pode ter interview hoje + decisão same-day.

## Decisões PM pendentes para Caminho 3 (sessão dedicada)

### Decisão A — Bulk move methodology
Como mover candidates cycle 3 → cycle 4? Opções:
- **A1**: UPDATE direct `cycle_id` em selection_applications (preserva history em mesmo row)
- **A2**: Cancel cycle 3 application + INSERT cycle 4 (history split, novo row, perde evals do cycle 3 OU duplica)
- **A3**: Status especial `migrated_to_next_cycle` + new row cycle 4 (preserve via linked_application_id)

**Recomendação**: A3 — usa `linked_application_id` que já existe no schema. Audit trail claro.

### Decisão B — Cycle 4 cycle_id
Existe cycle 4 já? Se não, criar primeiro:
```sql
INSERT INTO selection_cycles (cycle_code, cycle_label, ...) VALUES (...);
```

### Decisão C — Re-aplicar PERT cutoff feature?
Conforme discussão PM: aplicar nova régua dinâmica baseada no cycle 3 active members. Ver `PERT_cutoff_feature_design.md` (próxima entrega).

### Decisão D — REVIEW_CASE_BY_CASE 9 candidates
Cada um precisa de decisão individual:
- C30 / C31 / C35 (cancelaram entrevista) → mover cycle 4 (re-agendar) ou rejeitar?
- C37 + C06 (têm interview eval) → finalizar decisão cycle 3 já?
- Outros 4 sem evals → mover cycle 4

### Decisão E — Duplicates resolution
C06 + C29 com 2 aplicações cada. Manter qual? Eliminar duplicate?

## Itens deferred (não-bloqueantes para Caminho 3)

- T-16 retention 1825→730 dias (Material change Política IP)
- T-15 external_reviewer engagement_kind
- PERT cutoff feature impl (depende decisão PM em design doc)
