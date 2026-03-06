# Wave 2 — Migration Guide
## S8 (i18n) + S9 (CPMAI Showcase) + S12 (Mobile Nav)

---

## Files Included (drop-in replacements)

### ✅ Ready to drop in (replace existing files):

```
src/i18n/pt-BR.ts          ← expanded: +150 keys (internal pages, roles, data labels, CPMAI)
src/i18n/en-US.ts           ← expanded: same keys translated
src/i18n/es-LATAM.ts        ← expanded: same keys translated
src/i18n/utils.ts           ← new: getRoleLabel(), getRoleLabelsMap(), getLangFromURL()

src/data/kpis.ts            ← BREAKING: label → labelKey (i18n key)
src/data/quadrants.ts       ← BREAKING: label/title/subtitle → labelKey/titleKey/subtitleKey
src/data/tribes.ts          ← BREAKING: name/description/deliverables → key-based + resolveTribe()

src/lib/supabase.ts         ← updated: Member type + getLocalizedRoleLabel()
src/layouts/BaseLayout.astro ← updated: injects role-labels-data JSON for client JS

src/components/nav/Nav.astro           ← updated: hamburger menu + i18n JS strings
src/components/sections/KpiSection.astro     ← updated: uses labelKey
src/components/sections/QuadrantsSection.astro ← updated: uses i18n keys
src/components/sections/CpmaiSection.astro   ← NEW: CPMAI showcase (S9)

src/pages/index.astro       ← updated: includes CpmaiSection
src/pages/en/index.astro    ← updated: includes CpmaiSection
src/pages/es/index.astro    ← updated: includes CpmaiSection
```

---

## Integration Steps

### Step 1: Replace i18n files
Copy all 4 files from `wave2/src/i18n/` → `src/i18n/`. These are backward-compatible (all existing keys preserved, new keys added).

### Step 2: Replace data files (⚠️ BREAKING)
The data files now use i18n keys instead of hardcoded strings. You MUST also update every component that imports them.

**kpis.ts**: `k.label` → `t(k.labelKey, lang)`
**quadrants.ts**: `q.label` → `t(q.labelKey, lang)`, `q.title` → `t(q.titleKey, lang)`, etc.
**tribes.ts**: Use `resolveTribe(tribe, lang)` or `resolveTribes(lang)` to get translated data.

### Step 3: Update TribesSection.astro
This is the most complex change. The current TribesSection directly accesses `tribe.name`, `tribe.description`, etc. With the new data file, you need to resolve tribes first:

```astro
---
import { TRIBES, resolveTribes } from '../../data/tribes';
import { QUADRANTS } from '../../data/quadrants';
import { t, type Lang } from '../../i18n/utils';

interface Props { lang?: Lang; }
const { lang = 'pt-BR' } = Astro.props;

const tribes = resolveTribes(lang);
// Now use tribes[i].name, tribes[i].description, etc. (already translated)
---
```

Replace every `{t.name}` with the resolved tribe's `.name`, `{t.description}` → `.description`, etc.
The `t` variable in `{TRIBES.filter(...).map(t => ...)}` should be renamed to avoid conflict with the i18n `t()` function. Suggest using `tribe` instead.

### Step 4: Update index pages
Replace all 3 index pages (/, /en/, /es/) with the provided versions that include `<CpmaiSection>`.

### Step 5: Replace Nav component
The new Nav.astro includes:
- Mobile hamburger menu (visible below `lg:` breakpoint)
- Mobile menu drawer with all navigation links
- i18n'd client-side JS strings (login, logout, profile, etc.)
- Role labels read from DOM JSON element

### Step 6: Replace BaseLayout
The new BaseLayout injects a `<script id="role-labels-data">` JSON element that client JS reads for localized role names.

### Step 7: Replace supabase.ts
Updated Member type includes `cpmai_certified`, `credly_badges`, `credly_url` fields.
New `getLocalizedRoleLabel()` function reads from DOM i18n data.

---

## DB Changes Needed (Supabase)

### For S9 (CPMAI Showcase):
Add column to members table if not already present:

```sql
ALTER TABLE members ADD COLUMN IF NOT EXISTS cpmai_certified BOOLEAN DEFAULT false;
```

The CpmaiSection queries:
```sql
SELECT id, name, photo_url, chapter, credly_badges, credly_url
FROM members
WHERE current_cycle_active = true
AND (cpmai_certified = true OR credly_badges @> '[{"category":"cpmai"}]')
```

---

## Internal Pages i18n (Remaining Work)

The internal pages (attendance, profile, artifacts, gamification, admin) still have hardcoded PT-BR strings in their client-side JS. The translation keys are now defined in the i18n files. The recommended migration pattern:

1. Each page should inject translated strings as a hidden JSON element:
```astro
---
const pageI18n = JSON.stringify({
  loading: t('attendance.loading', lang),
  events: t('attendance.events', lang),
  // ... all strings used in client JS
});
---
<script id="page-i18n" type="application/json" set:html={pageI18n}></script>
```

2. Client JS reads from it:
```js
const i18n = JSON.parse(document.getElementById('page-i18n')?.textContent || '{}');
// Use i18n.loading instead of 'Carregando...'
```

3. Create `/en/attendance.astro` and `/es/attendance.astro` wrappers:
```astro
---
import BaseLayout from '../../layouts/BaseLayout.astro';
const lang = 'en-US' as const;
---
<BaseLayout title={t('attendance.meta', lang)} activePage="attendance" lang={lang}>
  <!-- Same content as root attendance.astro but with lang prop -->
</BaseLayout>
```

This pattern applies to all internal pages. It's a systematic but repetitive task — each page needs its hardcoded strings extracted to the i18n JSON element.

---

## Mobile Fixes (S12)

The Nav hamburger menu handles the core mobile navigation issue. Additional mobile fixes to verify:

- [ ] RosterModal: add `max-h-[80vh] overflow-y-auto` to modal content on mobile
- [ ] Tribe selection cards: ensure they stack properly on 375px
- [ ] Gamification leaderboard: add horizontal scroll wrapper on mobile
- [ ] Test all pages at 375px, 768px, 1024px widths

---

## Summary Checklist

- [ ] Copy i18n files (4 files)
- [ ] Copy data files (3 files) — ⚠️ update all consuming components
- [ ] Copy KpiSection.astro
- [ ] Copy QuadrantsSection.astro
- [ ] Update TribesSection.astro (manual, see Step 3)
- [ ] Copy CpmaiSection.astro (new)
- [ ] Copy Nav.astro (hamburger + i18n)
- [ ] Copy BaseLayout.astro
- [ ] Copy supabase.ts
- [ ] Copy 3 index pages
- [ ] Add cpmai_certified column to DB
- [ ] Test /en/ and /es/ index routes
- [ ] Test mobile hamburger menu
- [ ] Begin internal page i18n (attendance, profile, etc.)
