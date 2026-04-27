# ADR-0034: Partner attachments V4 conversion (Phase 2) — `manage_partner` reuse + drift signals #5 #6 closure

- Status: **Accepted** (2026-04-26 p66 — PM rubber-stamp Q1=SIM / Q2=Path D / Q3=SIM / Q4=p66)
- Data: 2026-04-26 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track — fecha 4 fns attachment partner.
  Phase 2 da conversão partner subsystem (Phase 1 fechada em ADR-0033).
- Implementation:
  - Migration `20260427125424_adr_0034_partner_attachments_phase2_v4_convert.sql` (4 fns)
  - Migration `20260427125429_adr_0034_partner_attachments_revoke_anon.sql` (defense-in-depth)
- Drift signals #5 #6: **CLOSED** — V3 chapter_match using operational_role
  (column-based) removed entirely. V4 manage_partner is single source of truth.
- Cross-references: ADR-0007, ADR-0011, ADR-0030/0031/0032/0033 (Opção B reuse precedents),
  audit doc Phase B' drift signals #5 #6, ADR-0033 Phase 1

---

## Contexto

Sequência ADR-0033 Phase 1. Fecha as 4 fns partner restantes (attachments)
PLUS resolve drift signals #5 e #6 sobre chapter scope semantics.

### As 4 funções afetadas

| Fn | Type | V3 ladder |
|---|---|---|
| `add_partner_attachment(...)` | Writer | SA OR manager/deputy OR designation curator |
| `delete_partner_attachment(uuid)` | Writer | SA OR manager/deputy OR designation curator |
| `get_partner_entity_attachments(uuid)` | Reader | GP/Curator (all) OR Leader (all) OR own-chapter (sponsor+chapter_liaison op_role) — NULL chapter = GP/Curator only |
| `get_partner_interaction_attachments(uuid)` | Reader | Same as above |

### Drift signals #5 #6 background (audit doc)

Track Q drift signal #5 e #6 surfaced em p52/p53: os attachment readers
usam V3 chapter_match com `operational_role IN ('sponsor', 'chapter_liaison')`
(column-based check, não designation-based). V4 não tem esse pattern —
sponsor é V4 engagement kind, chapter_liaison vai pelo chapter_board × liaison.

**Sinais permaneceram não-resolvidos em p53/p54 work**. ADR-0034 fecha-os
via decisão entre 2 caminhos:
- **Drop chapter scope** (sponsor + chapter_board × liaison veem all cross-chapter)
- **Preserve chapter scope** (Path Y secondary check)

### Privilege analysis — pre-apply numbers

**Group W2 (writers — add/delete_partner_attachment)**:
- **legacy = 4**: Vitor SA, Fabricio, Roberto curator, Sarah curator
- **V4 manage_partner = 10**: legacy 2 (Vitor, Fabricio) + 7 admin/governance (Ana,
  Felipe, Francisca, Ivan, Márcio, Matheus, Rogério) + Roberto chapter_board × liaison
- would_gain = 7 admin/governance roles
- would_lose = [Sarah] (curator drift, same precedent ADR-0030/0031/0033)

Trade-off material: V3 era 4 (admin + curator), V4 vira 10 (admin + governance roles).
Sponsors + chapter_board liaisons ganham capacidade upload/delete partnership docs.

**Group R2 (readers — get_*_attachments)**:
- **legacy_org = 10**: Vitor, Fabricio, Roberto, Sarah + 6 tribe_leaders
  (Ana Carla, Débora, Fernando, Hayala, Jefferson, Marcos)
- **V4 manage_partner = 10**: admin/governance only, sem tribe_leaders
- would_gain = 7 admin/governance (Ana, Felipe, Francisca, Ivan, Márcio, Matheus, Rogério)
- would_lose = [Sarah curator + 6 tribe_leaders] = 7

**Tribe_leaders losing partner attachment visibility** is a material UX regression
mas pode ser intencional: tribe_leaders historicamente tinham acesso amplo
a tudo, V4 está modernizando para roles mais apertados.

---

## Decisão (proposta) — multi-path

### Path A — Writers: reuse `manage_partner`

```sql
IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
  RETURN jsonb_build_object('error', 'permission_denied');
END IF;
```

Privilege expansion: 4 → 10 (7 admin/governance gain). Sarah loses (curator drift).

### Path D — Readers: reuse `manage_partner` + drop chapter scope

Drop V3 chapter_match logic. Sponsors/chapter_liaisons que tinham V4 engagement
manage_partner veem ALL attachments cross-chapter (closes drift signals #5 #6
via "drop scope" decision).

```sql
IF NOT public.can_by_member(v_caller_id, 'manage_partner') THEN
  RETURN '[]'::jsonb;
END IF;
RETURN ( /* fetch attachments */ );
```

Privilege adjustment:
- 7 admin/governance gain attachment visibility for ALL chapters
- 6 tribe_leaders + Sarah lose (drift correction)

### Path E — Readers (alternative): reuse `manage_partner` + preserve own-chapter clause

```sql
SELECT chapter INTO v_caller_chapter FROM public.members WHERE id = v_caller_id;
IF NOT (
  public.can_by_member(v_caller_id, 'manage_partner')
  OR (v_entity.chapter IS NOT NULL AND v_entity.chapter = v_caller_chapter)
) THEN
  RETURN '[]'::jsonb;
END IF;
```

But this preserves V3 own-chapter access for ALL members regardless of role —
broader than V3 (V3 only allowed own-chapter to sponsor/chapter_liaison).

**Path D is cleaner** (drift signals close + V4 simplification).

---

## Implications

### Para a plataforma
- 4 fns V3 a menos. Phase B'' tally bumps 70 → 74 / 246 (~30.1%).
- Drift signals #5 #6 fechados (Track Q audit doc cleanup).
- Zero novo V4 action.

### Para members
- Group W2: 7 admin/governance gain upload/delete attachments capability.
- Group R2: 7 lose visibility (6 tribe_leaders + Sarah).
- Drift correction precedent agora 6× (Mayanna×3, Sarah×3, João×3 — todos V3 designation sem V4 engagement).

### Para path A/B/C
- **Path A (PMI internal)**: positivo — partner governance tightened.
- **Path B (consultoria)**: positivo — multi-tenant clear roles.
- **Path C (community-only)**: ⚠️ tribe_leader UX regression (perdem partner attach view).

---

## Open Questions (para PM input)

### Q1 — Group W2 writers: aceito reuse `manage_partner` (Path A)?

Privilege expansion 4 → 10 (7 governance gain, Sarah loses).

**Recomendação**: SIM. Same Opção B precedent.

### Q2 — Group R2 readers: Path D (drop chapter scope) ou Path E (preserve)?

- Path D: drift signals #5 #6 fechados, V4 simplification, sponsors veem all cross-chapter.
- Path E: preserva own-chapter access para V4-engagement-less members (broad), V3+V4 hybrid.

**Recomendação**: **Path D** — cleanest, closes drift signals, consistent com p66.
Tribe_leaders losing access é regressão aceita per drift precedent.

### Q3 — Tribe_leaders losing partner attachment visibility: aceitável?

V3 deu tribe_leaders acesso amplo. V4 não inclui tribe_leader em manage_partner.
6 tribe_leaders perdem visibility.

**Recomendação**: SIM (drift correction). Se PM quer preservar, criar engagement
post-fact ou expandir manage_partner ladder (adicionar tribe_leader role) —
mas isso polui ladder com role-only-for-attachments.

### Q4 — Implementation timing

Phase 2 estimativa: ~45 min (4 fns simples reuse).

**Recomendação**: p66 mesmo OU defer p67.

---

## Status / Next Action

- [x] PM ratifica ADR (Q1=SIM / Q2=Path D / Q3=SIM / Q4=p66) — 2026-04-26 p66
- [x] Migration conversão Group W2 (2 writers) + Group R2 (2 readers Path D) — `20260427125424`
- [x] Migration REVOKE FROM anon — `20260427125429`
- [x] Audit doc update — Phase B'' tally + drift signals #5 #6 closed
- [x] Status ADR → `Accepted`

**Bloqueador**: nenhum.

### Outcome (post-apply)

- 4 fns V3 convertidas (add/delete attachment + 2 attachment readers).
- Zero novo V4 action (full reuse Opção B).
- Group W2: 7 admin/governance gain upload/delete; Sarah curator drift loss.
- Group R2: 7 admin/governance gain visibility; 6 tribe_leaders + Sarah lose.
- **Drift signals #5 #6 closed** — V3 chapter_match removed.
- Phase B'' tally: 70 → 74 / 246 (~30.1%).
- Partner subsystem 100% V4 (Phase 1 + Phase 2 = 8/8 fns).
