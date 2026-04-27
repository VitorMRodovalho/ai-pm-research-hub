# ADR-0033: Partner subsystem V4 conversion — Phase 1 reuse `manage_partner` + Phase 2 deferred

- Status: **Accepted (Phase 1)** (2026-04-26 p66 — PM rubber-stamp Phase 1 only / manage_platform / defer signals / p66)
- Data: 2026-04-26 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track — fecha 4 fns partner subsystem
  via reuso `manage_partner` (Opção B precedent). 4 fns attachment-related
  deferred to Phase 2 com decisão PM.
- Implementation (Phase 1):
  - Migration `20260427123844_adr_0033_partner_phase1_v4_convert.sql` (4 fns)
  - Migration `20260427123849_adr_0033_partner_phase1_revoke_anon.sql` (defense-in-depth)
- Privilege expansion outcome (Phase 1):
  - legacy=11 → v4=10
  - would_gain = []
  - would_lose = [João Uzejka — chapter_liaison designation sem V4 engagement,
                  same drift pattern as ADR-0030]
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (V4 auth pattern),
  ADR-0027/0031/0032 (Opção B reuse precedents),
  audit doc Phase B' drift signals #5 #6

---

## Contexto

Sequência ADR-0029/0030/0031/0032. Partner subsystem foi sinalizado pelo
audit doc como precisando de `manage_partner_global` (cross-chapter reads).
Discovery em p66 next-tier revelou que a **action `manage_partner` JÁ
EXISTE** com ladder adequado:

```
volunteer × {co_gp, manager, deputy_manager} (organization)
sponsor × sponsor (organization)
chapter_board × liaison (organization)
```

Match excelente para 4 das 8 fns V3 partner-related. As outras 4 (attachments)
têm complexidade adicional (curator + chapter scoping + leader visibility)
que merece tratamento separado.

### As 8 funções partner V3-gated descobertas

#### Group P1 (Phase 1 deste ADR — 4 fns, V3 ladder match `manage_partner`)

| Fn | V3 ladder | Match V4 manage_partner |
|---|---|---|
| `admin_manage_partner_entity(12-arg upsert)` | SA OR manager/deputy OR designations(sponsor, chapter_liaison) | ✅ exato |
| `admin_update_partner_status(uuid, text, text)` | SA OR manager/deputy OR designations(sponsor, chapter_liaison) | ✅ exato |
| `get_partner_pipeline()` | SA OR manager/deputy OR designations(sponsor, chapter_liaison) | ✅ exato |
| `auto_generate_cr_for_partnership(uuid)` | **SA only** (is_superadmin = true) | ⚠️ ladder muito broad — proposta usa `manage_platform` (narrower) |

#### Group P2 (Phase 2 — DEFERRED, 4 fns attachments)

| Fn | V3 ladder | Complexidade |
|---|---|---|
| `add_partner_attachment(...)` | SA OR manager/deputy OR designations(curator) | curator inclusion |
| `delete_partner_attachment(uuid)` | SA OR manager/deputy OR designations(curator) | curator inclusion |
| `get_partner_entity_attachments(uuid)` | GP/Curator (todos) OR Leader (todos) OR ChapterStakeholder(sponsor+chapter_liaison + own-chapter) | 4-tier visibility com chapter scope |
| `get_partner_interaction_attachments(uuid)` | Same as above (mesma tier) | Same |

**Por que defer Phase 2**: curator é V3 designation sem V4 engagement (drift
correction same as ADR-0030 Sarah). E visibility tier multi-nível (leader
gets all + chapter_stakeholder gets own-chapter) precisa per-resource scope
checks parecidos com ADR-0032 mas mais sutis. PM rubber-stamp não é trivial.

### Drift signals #5 #6 status

Conforme audit doc Phase B' p52-53: os drift signals #5 e #6 surfaced
em p52/p53 reportavam que partner readers usavam V3 `chapter_match` com
`operational_role IN ('sponsor', 'chapter_liaison')` (column check, não
designation). Esse pattern existe nos 2 attachment readers (Phase 2), não
em Group P1.

**Phase 1 deste ADR NÃO endereça drift signals #5 #6** — eles ficam para
Phase 2 que mexe nos attachment readers. Phase 1 apenas converte writers
e pipeline reader (que não têm o drift).

### Custo de não fazer Phase 1

- 4 fns V3 permanecem.
- Phase B'' tally trava.
- get_partner_pipeline + writers ficam em V3 quando V4 já tem ladder cabendo.

---

## Decisão (proposta) — Phase 1 only

### 1. Convert `admin_manage_partner_entity` → reuse `manage_partner`

```sql
DECLARE v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'authentication_required');
  END IF;

  IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
    RETURN jsonb_build_object('success', false, 'error', 'permission_denied');
  END IF;

  -- (rest of body — entity CRUD)
END;
```

### 2. Convert `admin_update_partner_status` → reuse `manage_partner`

Same pattern.

### 3. Convert `get_partner_pipeline` → reuse `manage_partner`

Same pattern.

### 4. Convert `auto_generate_cr_for_partnership` → reuse `manage_platform`

Body atual usa `is_superadmin = true` only. Proposed: use `manage_platform`
(narrower than manage_partner). Preserva intenção SA-only via V4 ladder
(volunteer × {co_gp, manager, deputy_manager} = 2 active members).

```sql
IF NOT public.can_by_member(v_caller_id, 'manage_platform') THEN
  RETURN jsonb_build_object('error', 'not_authorized');
END IF;
```

### 5. Privilege expansion safety check

```sql
WITH legacy AS (
  SELECT m.id, m.name FROM members m
  WHERE m.is_active = true
    AND (
      m.is_superadmin
      OR m.operational_role IN ('manager', 'deputy_manager')
      OR m.designations && ARRAY['sponsor', 'chapter_liaison']
    )
),
v4_manage_partner AS (
  SELECT m.id FROM members m
  WHERE m.is_active = true AND public.can_by_member(m.id, 'manage_partner')
)
SELECT
  (SELECT count(*) FROM legacy) AS legacy_count,
  (SELECT count(*) FROM v4_manage_partner) AS v4_count;
```

(executar pre-apply para confirmar; expected drift losses Mayanna/Sarah/João
seguindo precedent ADR-0030/0031)

### 6. Defense-in-depth REVOKE

```sql
REVOKE EXECUTE ON FUNCTION public.admin_manage_partner_entity(...) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_update_partner_status(...) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_partner_pipeline() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.auto_generate_cr_for_partnership(uuid) FROM PUBLIC, anon;
```

---

## Implications

### Para a plataforma
- 4 fns V3 a menos no backlog (Phase 1).
- Zero novo V4 action (full reuse — Opção B precedent).
- 4 fns attachment-related ainda V3 (Phase 2 deferred).

### Para members
- Mayanna (comms_leader designation, mas não em partner V3 ladder) — não afeta.
- Sarah (curator) + João (chapter_liaison designation) — drift losses similar
  a ADRs anteriores se ladders se cruzarem. Pre-apply check confirma.
- co_gp engagement (Sarah Faria has co_gp → tem manage_partner) — confere.

### Para path A/B/C
- Path A/B/C neutros (consistente com Opção B reuses anteriores).

---

## Open Questions (para PM input)

### Q1 — Phase 1 only OU 8 fns full now?

**Recomendação**: **Phase 1 only**. Phase 2 (attachments) tem complexidade
de curator inclusion + multi-tier visibility merece ADR separado (ADR-0034
proposto para sessão futura).

### Q2 — `auto_generate_cr_for_partnership` deve ser `manage_platform` OU keep `is_superadmin = true`?

V3 atual = pure SA. Proposed `manage_platform` = SA + manager + deputy_manager + co_gp.
Privilege expansion: SA(1) → manage_platform(2) — adds Vitor manager engagement
(de fato já é SA, então no-op real).

**Recomendação**: `manage_platform` (consistência V4 + zero real expansion).

### Q3 — Defer drift signals #5 #6 closure para Phase 2?

Drift signals #5 #6 estão nos attachment readers (Phase 2), não em Group P1.
Phase 1 não fecha esses signals; Phase 2 sim.

**Recomendação**: SIM, defer.

### Q4 — Implementation timing

Phase 1 estimativa: ~45 min (4 fns simples, mesma action reuse).

**Recomendação**: p66 mesmo OU defer p67.

---

## Status / Next Action

- [x] PM ratifica ADR (Phase 1 only / manage_platform / defer signals / p66) — 2026-04-26 p66
- [x] Migration conversão Group P1 (4 fns) — `20260427123844`
- [x] Migration REVOKE FROM anon — `20260427123849`
- [x] Privilege expansion validation (real numbers verified pre-apply)
- [x] Audit doc update — Phase B'' tally bumps (66 → 70 / 246, ~28.5%)
- [x] Status ADR → `Accepted (Phase 1)`
- [ ] **Phase 2 backlog**: ADR-0034 (futuro) — 4 attachment fns + drift signals #5 #6

**Bloqueador**: nenhum para Phase 1.

### Outcome (post-apply Phase 1)

- 4 fns V3 convertidas (admin_manage_partner_entity, admin_update_partner_status,
  get_partner_pipeline → manage_partner; auto_generate_cr_for_partnership →
  manage_platform).
- Zero novo V4 action (full reuse Opção B).
- João Uzejka loses (chapter_liaison designation drift, same as ADR-0030).
- Sarah Faria mantém access (V4 engagement volunteer × co_gp grants manage_partner).
- Phase B'' tally: 66 → 70 / 246 (~28.5%).
- 4 attachment fns ainda V3 — backlog ADR-0034 com drift signals #5 #6 closure.
