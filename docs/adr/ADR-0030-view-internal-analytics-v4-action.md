# ADR-0030: New V4 Action `view_internal_analytics` — Phase B'' Conversion

- Status: **Accepted** (2026-04-26 p66 — PM ratify Q1=A / Q2=Y / Q3=SIM / Q4=p66)
- Data: 2026-04-26 (p66)
- Autor: PM (Vitor) + Claude (proposal autônomo)
- Escopo: Phase B'' V3→V4 conversion track — fecha 2 fns + 1 helper V3 internal
  analytics (exec_chapter_dashboard, exec_role_transitions,
  can_read_internal_analytics)
- Implementation:
  - Migration `20260427012656_adr_0030_view_internal_analytics_v4_action.sql`
    (5 grants + helper + exec_chapter_dashboard convert)
  - Migration `20260427012700_adr_0030_view_internal_analytics_revoke_anon.sql`
    (REVOKE from PUBLIC, anon — defense-in-depth)
- Drift surfaced: Sarah Faria (curator-only) + João Uzejka (chapter_liaison
  designation sem V4 engagement) perdem access. Per ADR Path A: documented
  como expected drift correction.
- Cross-references: ADR-0007 (V4 authority), ADR-0011 (V4 auth pattern),
  ADR-0025 (manage_finance — sister), ADR-0026 (manage_comms — sister),
  ADR-0027 (governance readers — sister Opção B reuse)

---

## Contexto

Sequência de ADR-0025 + ADR-0026 + ADR-0027. Fecha mais 2 fns documentadas
em audit doc Phase B'' como out-of-scope V3 — ambas sob a categoria
"exec_* dashboards" surfaced em p66 next-tier discovery (Track C).

### As funções afetadas

**1. `exec_chapter_dashboard(p_chapter text)`** — chapter-level snapshot
   (members count by role, production metrics, attendance hours,
   certification stats). Caller: `src/pages/admin/chapter-report.astro`.

   V3 gate atual:
   ```sql
   IF NOT (
     v_is_admin
     OR v_role IN ('manager', 'deputy_manager')
     OR v_desigs && ARRAY['sponsor', 'chapter_liaison']
     OR v_chapter = p_chapter   -- own-chapter access for any member
   ) THEN
     RETURN jsonb_build_object('error', 'permission_denied');
   END IF;
   ```

   V3 set (org-portion, ignoring own-chapter): **11 active members**
   (Vitor SA + Fabricio + Ana + Felipe + Francisca + Ivan + João +
   Márcio + Matheus + Roberto + Rogério).

**2. `exec_role_transitions(p_cycle_code, p_tribe_id, p_chapter)`** —
   leadership conversion analytics across cycles. Caller:
   `src/pages/admin/analytics.astro` + MCP tool `get_role_transitions`.

   V3 gate atual: indireto via helper `can_read_internal_analytics()`.

   ```sql
   -- can_read_internal_analytics() body
   return v_caller.is_superadmin is true
     or public.can_by_member(v_caller.id, 'manage_member')
     or coalesce(v_caller.designations && ARRAY['co_gp', 'sponsor', 'chapter_liaison', 'curator'], false);
   ```

   V3 set: **12 active members** — superset de chapter_dashboard (11)
   + Sarah (curator).

### Por que precisa de nova action

Nenhuma das 8 actions existentes encaixa cleanly:

| Action | Cabe para internal analytics? |
|---|---|
| `manage_platform` | Próximo, mas perde sponsor + chapter_liaison + curator (legitimate analytics readers) |
| `manage_member` | Próximo, mas perde sponsor + curator |
| `manage_event` | Não — escopo evento |
| `manage_partner` | Não — escopo parceiros |
| `manage_finance` | Não — escopo financeiro |
| `manage_comms` | Não — escopo comms |
| `view_pii` | Não — leitura de PII direta, não agregados analytics |
| `write` / `write_board` | Não — operações de escrita |

Reusar `manage_member` quebraria sponsor + chapter_liaison + curator
analytics access (V3 atual).

### Custo de não fazer

- 2 fns V3 + 1 helper V3 permanecem.
- Phase B'' tally trava em ~31.5%.
- Fragmentação: nucleo-mcp tools de analytics dependem dessas fns;
  inconsistência V3/V4 entre tools.

---

## Decisão (proposta)

### 1. Adicionar nova V4 action `view_internal_analytics`

```sql
-- Migration target: 20260427xxxxxx_adr_0030_view_internal_analytics.sql

INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  -- Org-management ladder (matches manage_platform)
  ('volunteer', 'co_gp',          'view_internal_analytics', 'organization'),
  ('volunteer', 'manager',        'view_internal_analytics', 'organization'),
  ('volunteer', 'deputy_manager', 'view_internal_analytics', 'organization'),
  -- Sponsor (institutional analytics oversight)
  ('sponsor',   'sponsor',        'view_internal_analytics', 'organization'),
  -- Chapter board liaison (chapter-level analytics responsibility)
  ('chapter_board', 'liaison',    'view_internal_analytics', 'organization')
  ON CONFLICT (kind, role, action) DO NOTHING;
```

**Curator handling**: V4 backend (`engagement_kind_permissions` table) does
not have a curator kind/role. Curator continues as `members.designations[]`.
Two paths:
- **Path A (recommended)**: `view_internal_analytics` ladder gated purely
  via V4 engagement (drop curator). Drift correction — Sarah (only active
  curator) loses access to internal analytics. Per ADR-0026 batch 1 precedent
  (Mayanna comms_leader drift), this is documented but accepted.
- **Path B**: gate body includes `OR designations && ARRAY['curator']`
  fallback. Hybrid V3+V4 — preserves Sarah access, but pollutes V4 purity.

### 2. Convert `can_read_internal_analytics()` helper

```sql
CREATE OR REPLACE FUNCTION public.can_read_internal_analytics()
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT m.id INTO v_caller_id
  FROM public.members m
  WHERE m.auth_id = auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN false;
  END IF;

  RETURN public.can_by_member(v_caller_id, 'view_internal_analytics');
END;
$$;
```

### 3. Convert `exec_role_transitions`

Body mantém helper call (already V4 after step 2):
```sql
IF NOT public.can_read_internal_analytics() THEN
  RAISE EXCEPTION 'Internal analytics access required';
END IF;
```

Zero body change — helper conversion (step 2) cascades.

### 4. Convert `exec_chapter_dashboard`

```sql
-- V4 gate (replaces V3 mix of role + designation check + own-chapter)
SELECT m.id, m.chapter INTO v_caller_id, v_caller_chapter
FROM public.members m
WHERE m.auth_id = auth.uid();

IF v_caller_id IS NULL THEN
  RETURN jsonb_build_object('error', 'authentication_required');
END IF;

-- Org-wide internal analytics OR own-chapter access (preserves V3 behavior)
IF NOT (
  public.can_by_member(v_caller_id, 'view_internal_analytics')
  OR v_caller_chapter = p_chapter
) THEN
  RETURN jsonb_build_object('error', 'permission_denied');
END IF;
```

**Own-chapter clause preservation**: nav config `admin-chapter-report` has
`minTier: 'observer'` — chapter snapshot is intended as member-facing for
own chapter. Pure V4 conversion would regress this. Keep `OR chapter_match`
clause.

### 5. Privilege expansion safety check

```sql
WITH legacy AS (
  SELECT id FROM members
  WHERE is_active = true
    AND (
      is_superadmin
      OR public.can_by_member(id, 'manage_member')
      OR designations && ARRAY['co_gp', 'sponsor', 'chapter_liaison', 'curator']
    )
),
v4 AS (
  SELECT m.id FROM members m
  WHERE m.is_active = true
    AND public.can_by_member(m.id, 'view_internal_analytics')
)
SELECT
  (SELECT count(*) FROM legacy) AS legacy_count,
  (SELECT count(*) FROM v4) AS v4_count,
  ARRAY(SELECT id FROM v4 EXCEPT SELECT id FROM legacy) AS would_gain,
  ARRAY(SELECT id FROM legacy EXCEPT SELECT id FROM v4) AS would_lose;
```

Aceito: `would_gain = []` AND (`would_lose = []` OR diferença explicada).

Esperado:
- legacy_count = 12 (V3 set incl curator Sarah)
- v4_count = 11 ou 12 (depende Path A/B)
- would_lose path A = [Sarah] (curator drift)
- would_lose path B = []

---

## Implications

### Para a plataforma
- **2 fns V3 + 1 helper a menos** no backlog Phase B''.
- **Granularidade de analytics**: action explícita facilita auditoria
  ("quem pode ver leadership conversion analytics?").
- **MCP consistency**: ferramentas analytics ficam V4-uniform.

### Para members
- Path A: Sarah (curator) perde acesso — drift correction.
- Path B: zero loss, mas hybrid V3+V4 no helper.

### Para path A/B/C optionality
- **Path A (PMI internal spinoff)**: positivo — analytics governance clara.
- **Path B (consultoria)**: positivo — multi-tenant pode ter dedicated
  analytics-only role (data analyst).
- **Path C (community-only)**: neutro.

---

## Open Questions (para PM input)

### Q1 — Curator deve ter `view_internal_analytics`?

**Path A** (drop): drift correction — ADR-0026 precedent. Sarah perde
acesso a analytics que talvez nunca usou. **Path B** (keep via designation
fallback): preserva acesso Sarah, mas pollutes V4 purity.

**PM decide**: Path A OU Path B.

### Q2 — Preservar own-chapter clause em `exec_chapter_dashboard`?

Atualmente qualquer membro vê dashboard do **próprio chapter**. Nav config
expone `/admin/chapter-report` com `minTier: 'observer'`.

**Path Y (preserve)**: V4 OR chapter_match. Comportamento atual mantido.
**Path Z (pure V4)**: drop own-chapter access. Apenas org-wide ladder vê.
Regressão member-facing.

**PM decide**: Path Y OU Path Z.

### Q3 — Migrar `can_read_internal_analytics()` helper?

Sim/Não — se sim, vira pure delegation para `can_by_member`. Se não,
helper permanece como hybrid V3+V4 (uso interno).

Recomendação: SIM (consistência total).

**PM decide**: SIM ou manter hybrid.

### Q4 — Implementation timing

ADR está em `Proposed`. Implementação requer:
- 1 migration adicionando 5 rows em `engagement_kind_permissions`
- 1 migration conversão de helper + 2 fns
- 1 contract test (rpc-v4-auth coverage)
- 1 audit doc update

Estimativa: ~1.5h.

**PM decide**: ratify + schedule p66 (mesma sessão) OU defer p67+.

---

## Status / Next Action

- [x] PM ratifica ADR (Q1=A / Q2=Y / Q3=SIM / Q4=p66) — 2026-04-26 p66
- [x] Migration `engagement_kind_permissions` rows + helper + fns — `20260427012656`
- [x] Migration REVOKE FROM anon — `20260427012700`
- [x] Audit doc update — Phase B'' tally bumps (67 → 70 / 213, ~32.9%)
- [x] Status ADR → `Accepted`

**Bloqueador**: nenhum. Ratificada e aplicada.

### Outcome (post-apply)

- 2 fns + 1 helper convertidos para V4 pure.
- Privilege expansion: legacy 12 → V4 10 (Sarah + João dropped per drift).
- Own-chapter clause em exec_chapter_dashboard preservado (Path Y).
- Tests + invariantes preservados.
- Phase B'' tally: 67 → 70 / 213 (~32.9%).
