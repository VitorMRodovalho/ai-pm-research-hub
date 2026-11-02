# Data Sanitation Log

## 2026-03-12 — tribe_id / role / cycle_active cleanup

### Diagnostic (run 2026-03-12)

**Summary before sanitation:**
- 67 total members
- 56 with `tribe_id = NULL` (83%)
- 32 have a `tribe_selections` record but `members.tribe_id` was never synced
- 5 members with `is_active = false` but `current_cycle_active = true`
- 13 members with `operational_role = 'none'` (some should have real roles)

### Post-sanitation metrics

| Metric | Before | After |
|--------|--------|-------|
| Total members | 67 | 67 |
| With tribe_id set | 11 | **43** |
| Active without tribe | 42+ | **10** |
| Active with role=none | 13 | **2** |
| Inconsistent (inactive + cycle_active) | 5 | **0** |

---

### Fix 1: Sync tribe_id from tribe_selections (32 rows)

**Status:** APPLIED — 2026-03-12 16:00 UTC

```sql
UPDATE members m
SET tribe_id = ts.tribe_id, updated_at = now()
FROM tribe_selections ts
WHERE ts.member_id = m.id
  AND m.tribe_id IS NULL;
-- Result: 32 rows updated
```

---

### Fix 1b: member L — tribe_id correction (1 row)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
UPDATE members SET tribe_id = 2, updated_at = now()
WHERE name = 'member L' AND tribe_id = 8;
-- tribe_selections had tribe_id=2, members had stale tribe_id=8
```

---

### Fix 2: Correct operational_role for known roles (6 rows)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
-- Chapter liaisons
UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'member C' AND operational_role = 'none';

UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'member O' AND operational_role = 'none';

-- Sponsors (chapter presidents)
UPDATE members SET operational_role = 'sponsor', updated_at = now()
WHERE name IN (
  'member H',
  'member D',
  'member I',
  'member A'
) AND operational_role = 'none';
```

---

### Fix 3a: Deactivate departed members (2 rows)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
UPDATE members SET current_cycle_active = false, updated_at = now()
WHERE is_active = false AND current_cycle_active = true
  AND name IN ('member M', 'member J');
```

---

### Fix 3b: Reactivate founders (3 rows)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
UPDATE members SET is_active = true, operational_role = 'sponsor', updated_at = now()
WHERE name = 'member Q';

UPDATE members SET is_active = true, operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'member P';

UPDATE members SET is_active = true, updated_at = now()
WHERE name = 'member E' AND is_active = false;
```

---

### Fix 4: Sync trigger (prevents future drift)

**Status:** APPLIED — 2026-03-12 16:00 UTC

```sql
CREATE OR REPLACE FUNCTION public.sync_tribe_id_from_selection()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  UPDATE members SET tribe_id = NEW.tribe_id, updated_at = now()
  WHERE id = NEW.member_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_tribe_id ON tribe_selections;
CREATE TRIGGER trg_sync_tribe_id
  AFTER INSERT OR UPDATE ON tribe_selections
  FOR EACH ROW
  EXECUTE FUNCTION sync_tribe_id_from_selection();
```

---

### Fix 5: Governance Manual R2 — designations and cycles (2026-03-12)

**Status:** APPLIED — 2026-03-12 16:40 UTC (GP provided data from DocuSign Manual de Governança R2)

Most designations already existed. Only changes needed:

```sql
-- member Q: add ambassador (already had sponsor, founder)
UPDATE members SET designations = array_cat(
  COALESCE(designations, '{}'::text[]), ARRAY['ambassador']::text[]
), updated_at = now()
WHERE name = 'member Q' AND NOT (designations @> ARRAY['ambassador']);
-- 1 row

-- member L, member K, member N: add pilot-2024 to cycles
UPDATE members SET cycles = array_cat(
  COALESCE(cycles, '{}'::text[]), ARRAY['pilot-2024']::text[]
), updated_at = now()
WHERE name IN ('member L', 'member K do HUB Cerrado', 'member N')
  AND NOT (COALESCE(cycles, '{}'::text[]) @> ARRAY['pilot-2024']);
-- 3 rows
```

**Already correct (no update needed):**
- member E: already had `[ambassador, founder, curator]`
- member P: already had `[chapter_liaison, ambassador, curator]`
- member N: already had `[ambassador, founder, curator, co_gp]`
- Vitor Maia Rodovalho: already had `[ambassador, founder]` + `pilot-2024` in cycles

**Not in members table:** member B, member G (did not continue past pilot).

---

### Fix 6: Founder corrections — member F + member B (2026-03-12)

**Status:** APPLIED — 2026-03-12 21:30 UTC (GP confirmed member F = member G from governance manual)

```sql
-- member F: add pilot-2024 to cycles (already had founder designation)
UPDATE members SET cycles = array_cat(
  COALESCE(cycles, '{}'::text[]), ARRAY['pilot-2024']::text[]
), updated_at = now()
WHERE name = 'member F'
  AND NOT (COALESCE(cycles, '{}'::text[]) @> ARRAY['pilot-2024']);

-- member B: historical founder record (did not continue)
INSERT INTO members (name, email, operational_role, designations, cycles,
  is_active, current_cycle_active, chapter)
VALUES (
  'member B',
  'member person-1@example.invalid',
  'none', ARRAY['founder'], ARRAY['pilot-2024'],
  false, false, 'PMI-GO'
) ON CONFLICT DO NOTHING;
```

---

### Remaining (not sanitation issues)

- **10 active members without tribe_id**: Cross-tribe roles (liaisons, sponsors, GP) or haven't selected a tribe yet.
- member F: now identified as founder member G. Has `pilot-2024` + current cycles. `operational_role` still `none` — GP may assign later.
