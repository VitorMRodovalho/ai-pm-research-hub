# ADR-0084: Showcase → Champion eligibility (nudge, not constraint)

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-05-16 (sessão p170) |
| Author | Vitor Maia Rodovalho (Assisted-By: Claude) |
| Migrations | `20260675200000` (helper RPC `get_recent_showcases_by_member`) |
| Cross-ref | [ADR-0081](./ADR-0081-gamification-config-driven-and-champions-ledger.md) (Showcase + Champion ledger) · [SEMANTIC_TAXONOMY.md](../reference/SEMANTIC_TAXONOMY.md) seção 6 · P162_GAP item #15 |
| Closes | P162_GAP_OPPORTUNITY_LOG item #15 (Showcase vs Champion semantic overlap) |

## Context

ADR-0081 estabeleceu duas mecânicas paralelas:
- **Showcase** — entrega visível registrada por membro/líder (case study, tool review, prompt seven, insight, awareness). Gera XP via 5 dedicated `showcase_*` slugs.
- **Champion** — reconhecimento manual do líder a membro/equipe em evento específico (general, tribe, deliverable surface). Gera XP via `champions_points` pillar.

P162_GAP item #15 levantou: **líder pode dar Showcase E Champion ao mesmo membro no mesmo evento sem aviso**. Sem constraint cross-mecânica → potencial double-counting + auditing incoerente cross-líderes.

Três opções consideradas (PM deliberação 2026-05-16):

### Option A — Independente (status quo)
Manter. Líder pode dar ambos sem restrição.
- Pros: máxima flex
- Cons: possível double-counting XP, audit incoerente

### Option B — Constraint exclusiva
DB CHECK: showcase no event ⇒ NÃO pode dar Champion (e vice-versa).
- Pros: cleanest semantics
- Cons: rígido demais; líderes podem não entender; requires retro-validation

### Option C — Showcase como eligibility/nudge para Champion ✅ ratified
Showcase é INPUT (signal de eligibilidade), não constraint. UI grant Champion mostra showcases recentes do membro target como **suggestion**: "Esse membro fez showcase X esta semana, considere Champion".
- Pros: preserve flex + cria funnel discoverable; não bloqueia
- Cons: implementação UI extra (mas one-time)

### Option D — Reverse funnel
Showcase só existe como output de Champion grant.
- Pros: drasticamente reduce orfaned showcases
- Cons: requires UI rework + remove showcase entry-point standalone

**Decisão:** Option C.

## Decision

### Semantic model

```
Member entrega → showcase registrado (input)
                ↓ (suggestion, não constraint)
Líder vê nudge ao tentar dar Champion
                ↓ (líder decide independently)
Champion granted (output reconhecimento)
```

**Princípios:**

1. **Showcase ≠ Champion eligibility automática.** Showcase é signal observable (líder pode considerar), não trigger automático de Champion.
2. **Nenhuma constraint DB.** Líder pode dar Champion sem haver showcase (e dar showcase sem Champion).
3. **Funnel observable via UI nudge.** Modal "Conferir Champion" mostra `Showcases recentes deste membro` quando recipient_id é informado.
4. **Audit visible.** Quando Champion granted depois de showcase do mesmo member/event, audit log captura o relationship via metadata (não FK rígido).

### Component 1 — Helper RPC

```sql
CREATE FUNCTION get_recent_showcases_by_member(
  p_member_id uuid,
  p_days int DEFAULT 30
) RETURNS TABLE (
  showcase_slug text,
  showcase_kind text,    -- 'case_study' | 'tool_review' | 'insight' | etc
  event_id uuid,
  event_title text,
  event_date date,
  registered_at timestamptz,
  xp_awarded int
)
```

Returns showcases registrados por/para o member nos últimos N dias. Used by UI nudge.

### Component 2 — UI nudge in award champion modal

`src/pages/admin/gamification.astro` modal "Conferir Champion":
- Field `recipient-id` populated → fetch `get_recent_showcases_by_member(recipient_id, 30)`
- Render section `📋 Showcases recentes deste membro (últimos 30d)` com cards:
  - showcase kind + event date + event title
  - tooltip "Considere se justifica Champion"
- Não obrigatório clicar; visual nudge apenas

### Component 3 — No DB constraint

Mantém schema atual. Audit log captures relationship organicamente:
- `champions_awarded.criteria_met` text[] pode incluir `'showcase_recent'` opcionalmente
- `champions_awarded.justification` texto livre captura "Dado por showcase X de 2026-05-10"

## Anti-patterns avoided

1. **Não criar `champion_eligibility` table** — over-engineering. Showcases já são source of truth (existem em `event_showcases` + `gamification_points`).
2. **Não bloquear via trigger** — viola "líder tem autonomia de reconhecimento". Champions são manuais por design (ADR-0081).
3. **Não auto-converter showcase em Champion** — semântica diferente (showcase = entrega registrada; Champion = reconhecimento subjetivo do líder).

## Consequences

- (+) Funnel discoverable sem restringir autonomia
- (+) Reduz Champions "esquecidos" pós-showcase relevante
- (+) Audit organicamente captura relationship via justification text
- (−) Líderes devem entender que showcase ≠ Champion automático (treinar)
- (−) UI nudge é one-time effort; mantenance baixo

## Migration plan

p170 (this session):
1. ✅ Migration `20260675200000` — helper RPC
2. ✅ UI nudge in `src/pages/admin/gamification.astro` modal
3. ✅ i18n keys for nudge section (PT/EN/ES)

Carry (future):
- Telemetry: track Champion grants que ocorreram dentro de 30d de showcase (audit trail)
- A/B: medir se nudge aumenta Champion rate

## Smoke matrix

| Cenário | Esperado |
|---------|----------|
| Open modal, recipient empty | Nudge section hidden |
| Type recipient_id (uuid valid) | Fetch recent showcases, render cards |
| Member sem showcases recent | Section vazia com "Nenhum showcase nos últimos 30d" |
| Submit Champion após ver showcase listed | Champion granted normally, sem block |
| Submit Champion sem ver showcase | Champion granted normally |

## References

- ADR-0081 (Champion ledger + 5 showcase slugs)
- SEMANTIC_TAXONOMY.md seção 6
- P162_GAP_OPPORTUNITY_LOG item #15
- p170 session handoff
