# ADR-0035: Analytics dashboards V4 + no-gate hardening — `view_internal_analytics` reuse

- Status: **Accepted** (2026-04-26 p66 — PM rubber-stamp Q1=SIM / Q2=SIM / Q3=SIM / Q4=p66)
- Data: 2026-04-26 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion (2 fns) + Q-D-style no-gate hardening
  (2 fns) — total 4 fns em 1 ADR
- Implementation:
  - Migration `20260427134459_adr_0035_analytics_v4_and_no_gate_hardening.sql` (4 fns)
  - Migration `20260427134504_adr_0035_analytics_revoke_anon.sql` (defense-in-depth)
- Cross-references: ADR-0030 (view_internal_analytics action), ADR-0031/0032/0033
  (Opção B reuse precedents)

---

## Contexto

Sequência ADR-0030/0034. Discovery em p66 next-tier surfaced 2 V3-gated
analytics fns + 2 no-gate fns que devem ser tratadas em batch:

### Group V3 (V3-gated, convert to V4)

| Fn | V3 ladder | Path |
|---|---|---|
| `get_chapter_dashboard(p_chapter text)` | SA OR manager/deputy OR designations(sponsor, chapter_liaison) + own-chapter member | Path Y (preserve own-chapter clause como ADR-0030 exec_chapter_dashboard) |
| `get_diversity_dashboard(p_cycle_id uuid)` | SA OR manager/deputy OR designations(sponsor, chapter_liaison) | Pure V4 reuse view_internal_analytics |

### Group NoGate (security hardening)

| Fn | V3 ladder | Issue |
|---|---|---|
| `get_annual_kpis(p_cycle, p_year)` | **NO AUTH GATE** | SECDEF + zero auth check; anon can call |
| `get_cycle_report(p_cycle)` | **NO AUTH GATE** | Same — full cycle data accessible |

Audit doc Q-D charter classifies "no auth gate + intended for admin" as
drift signal pattern (#7 #8 from earlier sessions). Both fns são intended
admin-only (per MCP tool descriptions: "Admin/GP only"). Adding V4 gate
fecha security gap.

### Privilege expansion (verified pre-apply)

Para Group V3 (vs view_internal_analytics):
- legacy = 11, v4 = 10
- would_gain = []
- would_lose = [João Uzejka] — chapter_liaison designation drift (ADR-0030 precedent)

Para Group NoGate (currently zero-auth):
- legacy = ALL (qualquer authenticated user pode chamar)
- v4 = 10 (view_internal_analytics ladder)
- This is **privilege REDUCTION** (security hardening), not expansion.

---

## Decisão (proposta)

### 1. `get_chapter_dashboard` — Path Y view_internal_analytics + own-chapter

```sql
SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
FROM public.members m WHERE m.auth_id = auth.uid();
IF v_caller_id IS NULL THEN RETURN jsonb_build_object('error', 'authentication_required'); END IF;

-- Own-chapter access (any member sees own chapter dashboard)
-- OR view_internal_analytics (cross-chapter institutional roles)
IF v_caller_chapter = COALESCE(p_chapter, v_caller_chapter)
   OR public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
  v_chapter := COALESCE(p_chapter, v_caller_chapter);
ELSE
  RETURN jsonb_build_object('error', 'Unauthorized');
END IF;
```

### 2. `get_diversity_dashboard` — Pure V4 reuse

```sql
IF NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
  RAISE EXCEPTION 'Unauthorized: admin or sponsor required';
END IF;
```

### 3. `get_annual_kpis` — Add V4 gate (no-gate hardening)

```sql
SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'view_internal_analytics') THEN
  RAISE EXCEPTION 'Unauthorized';
END IF;
```

### 4. `get_cycle_report` — Add V4 gate

Same pattern as get_annual_kpis.

### 5. Defense-in-depth REVOKE FROM anon

```sql
REVOKE EXECUTE ON FUNCTION public.get_chapter_dashboard(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_diversity_dashboard(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_annual_kpis(integer, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_cycle_report(integer) FROM PUBLIC, anon;
```

---

## Implications

### Para a plataforma
- 4 fns adicionais V4. Phase B'' tally bumps 74 → 78 / 246 (~31.7%).
- 2 security holes (no-gate analytics) closed.
- Zero novo V4 action.

### Para members
- João Uzejka loses access to get_chapter_dashboard / get_diversity_dashboard
  (chapter_liaison drift, ADR-0030 precedent).
- Anon callers que dependiam de get_annual_kpis / get_cycle_report sem auth
  perdem acesso. Verified zero anon callers em src/.

### Para path A/B/C
- Path A/B/C neutros (consistente).

---

## Open Questions (para PM input)

### Q1 — Group V3 conversion (Opção B reuse)?

**Recomendação**: SIM. Same precedent ADR-0030/0031/0032/0033/0034.

### Q2 — `get_chapter_dashboard` Path Y own-chapter preservation?

V3 atual permite qualquer membro ver dashboard do próprio chapter. Preservar
via Path Y (igual ADR-0030 exec_chapter_dashboard).

**Recomendação**: SIM (consistente com ADR-0030 precedent).

### Q3 — Group NoGate hardening: usar `view_internal_analytics` action?

Ambas as fns retornam analytics-shape data (KPIs, cycle report). Match
limpo com view_internal_analytics audience.

**Recomendação**: SIM.

### Q4 — Implementation timing

Estimativa: ~30 min (4 fns simples).

**Recomendação**: p66 mesmo.

---

## Status / Next Action

- [x] PM ratifica ADR (Q1=SIM / Q2=SIM / Q3=SIM / Q4=p66) — 2026-04-26 p66
- [x] Migration conversão (4 fns) — `20260427134459`
- [x] Migration REVOKE FROM anon — `20260427134504`
- [x] Audit doc update — Phase B'' tally (74 → 78 / 246, ~31.7%) + 2 no-gate signals closed
- [x] Status ADR → `Accepted`

**Bloqueador**: nenhum.

### Outcome (post-apply)

- 4 fns convertidas: 2 V3→V4 reuse + 2 no-gate hardening.
- Zero novo V4 action (full reuse view_internal_analytics).
- João Uzejka loses get_chapter_dashboard / get_diversity_dashboard (drift).
- Anon callers de get_annual_kpis / get_cycle_report perdem acesso (security closure).
- Phase B'' tally: 74 → 78 / 246 (~31.7%).
- 2 no-gate security holes closed (drift signal class #7 #8 type).
