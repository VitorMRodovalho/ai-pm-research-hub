# Data Sanitation Log

## 2026-03-12 — tribe_id / role / cycle_active cleanup

### Diagnostic (run 2026-03-12)

**Summary:**
- 67 total members
- 56 with `tribe_id = NULL` (83%)
- 32 have a `tribe_selections` record but `members.tribe_id` was never synced
- 5 members with `is_active = false` but `current_cycle_active = true`
- 13 members with `operational_role = 'none'` (some should have real roles)

---

### Fix 1: Sync tribe_id from tribe_selections (32 rows)

**Status:** READY — safe, non-destructive (fills NULL only)

```sql
-- Sets members.tribe_id from tribe_selections where it's currently NULL
-- Does NOT overwrite existing tribe_id values
UPDATE members m
SET tribe_id = ts.tribe_id, updated_at = now()
FROM tribe_selections ts
WHERE ts.member_id = m.id
  AND m.tribe_id IS NULL;
-- Expected: 32 rows affected
```

**Special case — Andressa Martins:**
- `members.tribe_id = 8`
- `tribe_selections.tribe_id = 2`
- **GP must decide** which is correct. Not touched by Fix 1 (her tribe_id is not NULL).

**Verification:**
```sql
SELECT count(*) FROM members WHERE tribe_id IS NULL;
-- Before: 56, After: should be 24 (56 - 32)
```

---

### Fix 2: Correct operational_role for known roles (6 rows)

**Status:** PENDING GP APPROVAL

```sql
-- Chapter liaisons (confirmed in governance docs)
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

**Verification:**
```sql
SELECT name, operational_role FROM members
WHERE name IN (
  'Ana Cristina Fernandes Lima', 'Rogério Peixoto',
  'Felipe Moraes Borges', 'Matheus Frederico Rosa Rocha',
  'Márcio Silva dos Santos', 'Francisca Jessica de Sousa de Alcântara'
);
```

---

### Fix 3: Correct is_active / current_cycle_active inconsistency

**Status:** PENDING GP APPROVAL (partial)

**Safe to run (clearly inactive):**
```sql
UPDATE members SET current_cycle_active = false, updated_at = now()
WHERE is_active = false AND current_cycle_active = true
  AND name IN ('Cristiano Oliveira', 'Herlon Alves de Sousa');
-- 2 rows
```

**GP decision required:**
| Name | Notes |
|------|-------|
| Ivan Lourenço | Founder? Should `is_active` be flipped to true? |
| Roberto Macêdo | Founder? Should `is_active` be flipped to true? |
| Sarah Faria Alcantara Macedo | Founder? Should `is_active` be flipped to true? |

---

### Fix 4: Sync trigger (prevents future drift)

**Status:** READY — creates a trigger so tribe_selections changes auto-update members.tribe_id

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

**Verification:**
```sql
-- Test: update a tribe_selection and check members.tribe_id follows
SELECT m.name, m.tribe_id, ts.tribe_id as sel_tribe
FROM members m
JOIN tribe_selections ts ON ts.member_id = m.id
WHERE m.name = 'Daniel Bittencourt';
```
