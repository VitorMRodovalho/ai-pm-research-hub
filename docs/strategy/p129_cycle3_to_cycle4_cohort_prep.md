# Cycle 3 → Cycle 4 Cohort Prep (p129 S1 — Action 4)

**Sessão**: p129 S1
**Data**: 2026-05-09
**Mandato PM Vitor**: separar candidates do cycle 3 para tomar decisão sobre cohort movement antes do Caminho 3 (Cycle 4 launch prep)

## Resumo

Total de 40 candidates no cycle 3 (`d28313d4-569a-4c58-9eae-7e84c5da29b1`).

| Categoria | Count | Ação |
|---|---|---|
| KEEP_CYCLE_3 — decisões já tomadas | 5 | manter (immutável: approved/rejected/withdrawn) |
| KEEP_CYCLE_3 — test journey | 1 | João Uzejka — extend formal aceite via plataforma |
| MOVE_TO_CYCLE_4 — submitted/none/0-1 evals | 25 | mover para cycle 4 cohort |
| REVIEW_CASE_BY_CASE — interview scheduled | 9 | discussão por candidato (alguns têm interview eval) |

---

## KEEP_CYCLE_3 (decisão tomada — 5 + 1 = 6)

| Nome | Chapter | Role | Status | Notas |
|---|---|---|---|---|
| **João Uzejka dos Santos** | (sem) | researcher | `interview_pending` (just advanced p129) | **Test journey** — extender formal aceite via plataforma; PM teste fluxo restante |
| Ana Carla Cavalcante | PMI-CE | leader | approved | já membro ativo |
| Hayala Curto | PMI-MG | leader | approved | já membro ativo |
| Marcos Antunes Klemz | PMI-MG | leader | approved | já membro ativo |
| Adalberto Neris | (sem) | leader | rejected | decisão tomada |
| Maria Araújo (1) | PMI-CE | leader | withdrawn | candidate retirou |

## MOVE_TO_CYCLE_4 (25)

Todos `status='submitted'` + `interview_status='none'` + 0 evals (com 1 exceção: João Coelho Júnior tem 1 obj_eval).

| Nome | Chapter | Role | Notas |
|---|---|---|---|
| Alexandre Fortes | PMI-MG | researcher | |
| Ana Karina Girao Rodrigues | PMI-CE | researcher | |
| Ana Pacheco | (sem) | researcher | |
| Andre Abreu | PMI-PE | researcher | |
| Blenda Amorim | (sem) | researcher | |
| Carla Rosa | PMI-MG | researcher | |
| Claudio Sousa | PMI-MG | researcher | |
| Cristiano de Oliveira Santos Filho | PMI-DF | researcher | |
| DJEIMIYS WILLIAN WILLE | PMI-RS | researcher | |
| Edinan Soares | PMI-MG | researcher | |
| [REDACTED-332-NAME] | PMI-RS | researcher | |
| Hector Rigon | (sem) | researcher | |
| herlon alves de sousa | PMI-CE | leader | (note: Herlon CPMAI sponsor — special case?) |
| Jessé Filipe Viana da Silva | PMI-RS | researcher | |
| **João Coelho Júnior** | PMI-CE | researcher | 1 obj_eval (final_score=173) — tem entrevista marcada hoje |
| Luan Garcia Rodrigues | PMI-RS | researcher | |
| Luana Andrade | PMI-MG | researcher | |
| LUIZ RAMOM TEIXEIRA CARVALHO | PMI-CE | researcher | (note: cancelou entrevista ontem) |
| Matheus Teixeira | PMI-RIO | researcher | 1 obj_eval + 1 int_eval — tem score! |
| MERY HERRMANN | PMI-CE | researcher | |
| Rafael Bellotti | PMI-RS | researcher | |
| THAYANNE MONTEIRO | PMI-CE | researcher | |
| Tiele Lara | (sem) | researcher | |
| William Junio (researcher) | (sem) | researcher | |

## REVIEW_CASE_BY_CASE (9 — interview_status='scheduled')

Estes têm entrevista marcada mas não realizada. Alguns têm interview eval registrada (caso especial).

| Nome | Chapter | Role | Obj evals | Int evals | Notas |
|---|---|---|---|---|---|
| Bruna Lima Zomer | PMI-RS | researcher | 0 | 0 | (cancelou) |
| Bruna Soares | PMI-MG | researcher | 0 | 0 | (cancelou) |
| Cristiano Nunes | PMI-MG | researcher | 1 | 0 | |
| Danilo Nascimento | PMI-CE | researcher | 1 | 0 | |
| Flavio Oliveira | PMI-PR | researcher | 0 | 0 | |
| Luciana Carpes Pranke | PMI-PR | researcher | 1 | 0 | (cancelou) |
| Luíse Quintana | PMI-RS | researcher | 0 | 0 | |
| **Marcio Pimenta** | PMI-RJ | researcher | 1 | **1** | tem interview eval! |
| **Maria Araújo (2)** | PMI-CE | researcher | 1 | **1** | tem interview eval! (DUPLICATE aplicação? mesma email da withdrawn leader acima) |
| William Junio (leader) | (sem) | leader | 0 | 0 | (segunda aplicação do mesmo email — tem researcher MOVE_TO_CYCLE_4 acima) |

## Observações

1. **Maria Araújo aparece 2x** com mesmo email (`leticia.araujov@gmail.com`) — uma withdrawn (leader) + uma submitted/scheduled (researcher). Provável duplicate por mudança de track. Verificar.
2. **William Junio aparece 2x** com mesmo email — uma submitted researcher + uma submitted leader scheduled. Verificar.
3. **Marcio Pimenta + Maria Araújo (researcher)**: têm interview eval REGISTRADA mesmo com `interview_status='scheduled'`. Estranho — provavelmente foi feita avaliação informal sem mark_interview_status. Investigar.
4. **Herlon alves de sousa** (PMI-CE leader) — é o sponsor do CPMAI Cycle 3. Caso especial — confirmar se ele é candidate normal ou se aplicação é placeholder.
5. **João Coelho Júnior**: tem entrevista MARCADA pra HOJE 19:00 (Calendar event). Score 173 partial. Pode ter interview hoje + decisão same-day.

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
- Bruna Lima Zomer / Bruna Soares / Luciana Pranke (cancelaram entrevista) → mover cycle 4 (re-agendar) ou rejeitar?
- Marcio Pimenta + Maria Araújo (têm interview eval) → finalizar decisão cycle 3 já?
- Outros 4 sem evals → mover cycle 4

### Decisão E — Duplicates resolution
Maria Araújo + William Junio com 2 aplicações cada. Manter qual? Eliminar duplicate?

## Itens deferred (não-bloqueantes para Caminho 3)

- T-16 retention 1825→730 dias (Material change Política IP)
- T-15 external_reviewer engagement_kind
- PERT cutoff feature impl (depende decisão PM em design doc)
