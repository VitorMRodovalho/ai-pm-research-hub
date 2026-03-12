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

### Fix 1b: Andressa Martins — tribe_id correction (1 row)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
UPDATE members SET tribe_id = 2, updated_at = now()
WHERE name = 'Andressa Martins' AND tribe_id = 8;
-- tribe_selections had tribe_id=2, members had stale tribe_id=8
```

---

### Fix 2: Correct operational_role for known roles (6 rows)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
-- Chapter liaisons
UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'Ana Cristina Fernandes Lima' AND operational_role = 'none';

UPDATE members SET operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'Rogério Peixoto' AND operational_role = 'none';

-- Sponsors (chapter presidents)
UPDATE members SET operational_role = 'sponsor', updated_at = now()
WHERE name IN (
  'Felipe Moraes Borges',
  'Matheus Frederico Rosa Rocha',
  'Márcio Silva dos Santos',
  'Francisca Jessica de Sousa de Alcântara'
) AND operational_role = 'none';
```

---

### Fix 3a: Deactivate departed members (2 rows)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
UPDATE members SET current_cycle_active = false, updated_at = now()
WHERE is_active = false AND current_cycle_active = true
  AND name IN ('Cristiano Oliveira', 'Herlon Alves de Sousa');
```

---

### Fix 3b: Reactivate founders (3 rows)

**Status:** APPLIED — 2026-03-12 16:10 UTC (GP approved)

```sql
UPDATE members SET is_active = true, operational_role = 'sponsor', updated_at = now()
WHERE name = 'Ivan Lourenço';

UPDATE members SET is_active = true, operational_role = 'chapter_liaison', updated_at = now()
WHERE name = 'Roberto Macêdo';

UPDATE members SET is_active = true, updated_at = now()
WHERE name = 'Sarah Faria Alcantara Macedo' AND is_active = false;
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

### Remaining (not sanitation issues)

- **10 active members without tribe_id**: These members don't have a `tribe_selections` record — they may be cross-tribe roles (liaisons, sponsors, GP) or haven't selected a tribe yet.
- **2 active members with role=none**: Sarah Faria Alcantara Macedo (founder, role TBD by GP) and Antonio Marcos Costa.
