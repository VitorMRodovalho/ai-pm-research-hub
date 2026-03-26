---
name: nucleo-ia-hub
description: >
  Use this skill for ALL work on the AI & PM Research Hub (Núcleo IA & GP) platform.
  This covers: Supabase RPC patterns, RLS-protected tables, auth.uid() vs members.id mapping,
  Astro 6 + React 19 island architecture, i18n trilingual requirements, Chart.js configuration,
  event governance schema, attendance system, and the pre-commit QA checklist.
  Activate whenever touching: SQL/RPCs, React components, Astro pages, i18n files,
  Supabase queries, Chart.js, events, attendance, or admin panel features.
---

# AI & PM Research Hub — Project Skill

## Stack
- **Framework:** Astro 6 (SSR on Cloudflare Workers) + React 19 islands
- **Styling:** Tailwind CSS 4
- **Database:** Supabase (PostgreSQL) — project ID: `ldrfrvwhxsmgaabwmaik`
- **Auth:** Supabase Auth (Google + LinkedIn + Microsoft (Azure) + Magic Link)
- **Hosting:** Cloudflare Workers
- **Live URL:** https://platform.ai-pm-research-hub.workers.dev
- **i18n:** 3 locales: PT-BR (default, no prefix), EN-US (`/en/`), ES-LATAM (`/es/`)
- **Charts:** Chart.js (NOT recharts)
- **DnD:** @dnd-kit
- **Rich text:** TipTap
- **Tables:** @tanstack/react-table

---

## CRITICAL RULE 1: auth.uid() ≠ members.id

Supabase Auth assigns its own UUID (`auth.uid()`). The `members` table has a DIFFERENT UUID (`members.id`). They are connected via `members.auth_id`.

```
auth.uid()     = 58675a94-eb44-483b-ab7d-9f8892e4fc3c  (Supabase Auth UUID)
members.id     = 880f736c-3e76-4df4-9375-33575c190305  (Application UUID)
members.auth_id = 58675a94-...  (links them)
```

**EVERY RPC that writes `created_by`, `updated_by`, `member_id`, or any FK to `members(id)` MUST:**
```sql
DECLARE v_member_id uuid;
BEGIN
  SELECT id INTO v_member_id FROM members WHERE auth_id = auth.uid();
  -- Use v_member_id, NEVER auth.uid() directly for members FK
```

**FK targets to verify before any INSERT:**
- `events.created_by` → `auth.users(id)` (uses auth.uid() directly)
- `board_items.assigned_to` → `members(id)` (needs member lookup)
- `attendance.member_id` → `members(id)` (needs member lookup)
- `attendance.edited_by` → `members(id)` (needs member lookup)
- When in doubt, CHECK: `SELECT ccu.table_name FROM information_schema.constraint_column_usage ccu JOIN information_schema.table_constraints tc ON tc.constraint_name = ccu.constraint_name WHERE tc.table_name = 'YOUR_TABLE' AND tc.constraint_type = 'FOREIGN KEY';`

---

## CRITICAL RULE 2: RLS deny-all tables (RPC-only access)

These tables have `rpc_only_deny_all` policy — direct `.from('table')` queries ALWAYS return empty:

```
board_source_tribe_map      member_cycle_history
board_taxonomy_alerts       onboarding_progress
campaign_recipients         selection_applications
knowledge_insights_log      selection_committee
selection_cycles            selection_diversity_snapshots
selection_evaluations       selection_interviews
```

**NEVER write:**
```javascript
// ❌ BROKEN — RLS blocks, returns []
const { data } = await supabase.from('selection_applications').select('*');
```

**ALWAYS write:**
```javascript
// ✅ CORRECT — SECURITY DEFINER RPC bypasses RLS
const { data } = await supabase.rpc('get_selection_dashboard');
```

There are 300+ SECURITY DEFINER functions. Before writing a new one, CHECK if one already exists:
```sql
SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname ILIKE '%keyword%';
```

---

## CRITICAL RULE 3: Column name cheat sheet

These columns have been confused repeatedly. ALWAYS verify against this list:

| Table | ❌ WRONG (commonly guessed) | ✅ CORRECT (actual) |
|-------|---------------------------|-------------------|
| events | scheduled_at | **date** (type: date) |
| events | event_type | **type** (type: text) |
| events | duration | **duration_minutes** (int) |
| members | full_name | **name** (text) |
| members | credly_username | **credly_url** (text) |
| members | active | **is_active** AND **current_cycle_active** (both exist, different meaning) |
| attendance | status | **present** (boolean) |
| selection_applications | objective_score | **objective_score_avg** (numeric) |
| selection_applications | motivation | **motivation_letter** (text) |
| selection_applications | experience_years | **seniority_years** (int) |

**Before writing SQL, ALWAYS verify columns:**
```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'YOUR_TABLE' ORDER BY ordinal_position;
```

---

## CRITICAL RULE 4: RPC creation pattern

**ALWAYS use DROP + CREATE, never CREATE OR REPLACE via dynamic DO blocks:**
```sql
DROP FUNCTION IF EXISTS my_function(param_types);
CREATE FUNCTION my_function(...)
RETURNS ... LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$ ... $$;
```

**After creating/modifying ANY RPC:**
```sql
NOTIFY pgrst, 'reload schema';
```

**Auth guard pattern (standard for all admin RPCs):**
```sql
DECLARE v_caller record;
BEGIN
  SELECT * INTO v_caller FROM members WHERE auth_id = auth.uid();
  IF NOT FOUND OR (
    v_caller.is_superadmin IS NOT TRUE
    AND v_caller.operational_role NOT IN ('manager','deputy_manager')
  ) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  -- ... rest of function
```

---

## CRITICAL RULE 5: Chart.js infinite loop prevention

**EVERY Chart.js canvas MUST have:**
1. Parent container with explicit height
2. `maintainAspectRatio: false` in options

```html
<!-- Container with fixed height -->
<div style="position: relative; height: 300px; width: 100%;">
  <canvas id="myChart"></canvas>
</div>
```

```javascript
new Chart(ctx, {
  type: 'bar',
  data: { ... },
  options: {
    responsive: true,
    maintainAspectRatio: false,  // ← PREVENTS INFINITE RESIZE LOOP
    // Dark mode colors:
    plugins: {
      legend: { labels: { color: isDark ? '#c2c0b6' : '#3d3d3a' } }
    },
    scales: {
      x: { ticks: { color: isDark ? '#c2c0b6' : '#3d3d3a' } },
      y: { ticks: { color: isDark ? '#c2c0b6' : '#3d3d3a' } }
    }
  }
});
```

**Dark mode detection:**
```javascript
const isDark = document.documentElement.classList.contains('dark') ||
  window.matchMedia('(prefers-color-scheme: dark)').matches;
```

---

## CRITICAL RULE 6: i18n — trilingual or nothing

**EVERY user-facing string must exist in ALL 3 locales:**
- `src/i18n/pt-BR.ts` (primary)
- `src/i18n/en-US.ts`
- `src/i18n/es-LATAM.ts`

**Before committing, verify no raw keys leak:**
```bash
# Build and grep for untranslated keys in output
npm run build 2>&1 | grep -i "missing"
# Check that every key added to PT-BR also exists in EN and ES
diff <(grep -oP "'[a-z_]+\.[a-z_]+'" src/i18n/pt-BR.ts | sort) \
     <(grep -oP "'[a-z_]+\.[a-z_]+'" src/i18n/en-US.ts | sort)
```

**Role labels (frequently missed):**
```
researcher → Pesquisador / Researcher / Investigador
tribe_leader → Líder de Tribo / Tribe Leader / Líder de Línea
sponsor → Patrocinador / Sponsor / Patrocinador
chapter_liaison → Ponto Focal / Chapter Liaison / Enlace de Capítulo
manager → Gerente / Manager / Gerente
deputy_manager → Deputy / Deputy Manager / Subgerente
observer → Observador / Observer / Observador
communicator → Comunicação / Communications / Comunicación
```

---

## CRITICAL RULE 7: Astro pages and locale routes

**Every page MUST exist in 3 locale paths:**
```
src/pages/blog.astro          → /blog
src/pages/en/blog.astro       → /en/blog
src/pages/es/blog.astro       → /es/blog
```

If creating a new page, ALWAYS create all 3. Locale pages can be redirect stubs:
```astro
---
// src/pages/en/blog.astro
import BlogPage from '../blog.astro';
---
<BlogPage />
```

**Astro inline `<script>` blocks:**
- Use plain JavaScript (NO TypeScript casts) — they generate IIFEs that bypass the TS compiler
- `define:vars` scripts cannot use TS syntax
- Astro inline scripts ≠ React islands — don't create React components for Astro inline script pages

---

## CRITICAL RULE 8: Event governance schema

Events have a 3-level hierarchy:

```
Level 1: type (geral|tribo|lideranca|comms|parceria|entrevista|1on1|evento_externo)
Level 2: tribe_id (only if type = 'tribo')
Level 3: nature (kickoff|recorrente|avulsa|encerramento|workshop|entrevista_selecao)
```

**Visibility enforcement (automatic):**
- parceria, entrevista, 1on1 → visibility = 'gp_only' (auto-enforced)
- geral, tribo, lideranca → visibility = 'all' (default)

**Role constraints:**
- Leaders can ONLY create tribe events for their own tribe
- GP/Deputy/Superadmin can create any type

**Attendance rules:**
- `excuse_reason` is NEVER visible below GP/Deputy — NEVER in CSV exports
- Detractor detection (3+ consecutive absences) is calculated in SQL, not frontend

---

## CRITICAL RULE 9: Role and permission model

**Operational roles hierarchy:**
```
Tier 1: manager, deputy_manager (+ is_superadmin flag)
Tier 2: tribe_leader, curator, communicator
Tier 3: sponsor, chapter_liaison (read-only executive access)
Tier 4: researcher (standard member)
Tier 5: observer (limited access)
```

**Designations (lateral, additive):**
- curator (22 RPCs worth of permissions)
- ambassador
- founder
- comms_team

**Checking permissions in frontend:**
```javascript
const isGP = member.operational_role === 'manager' || member.operational_role === 'deputy_manager' || member.is_superadmin;
const isLeader = member.operational_role === 'tribe_leader';
const isTier3Plus = ['manager','deputy_manager','tribe_leader','sponsor','chapter_liaison'].includes(member.operational_role) || member.is_superadmin;
```

---

## CRITICAL RULE 10: Terminology

**NEVER use "CoP" (Community of Practice) in user-facing text.**
- PT-BR: "Tribos"
- EN-US: "Research Streams"
- ES-LATAM: "Líneas de Investigación"

"CoP" exists in the underlying data model but is NOT surfaced externally.

---

## PRE-COMMIT CHECKLIST (mandatory — GC-097)

Before EVERY commit, run through this:

### SQL/RPC changes:
- [ ] Verified FK targets (auth.users vs members)
- [ ] Verified ALL column names against `information_schema.columns`
- [ ] Used DROP + CREATE (not CREATE OR REPLACE via DO block)
- [ ] Ran `NOTIFY pgrst, 'reload schema'` after
- [ ] Tested RPC returns data (not just compiles)
- [ ] For RLS deny-all tables: using .rpc() not .from()

### Frontend changes:
- [ ] Chart.js: `maintainAspectRatio: false` + container height set
- [ ] Dark mode: all text uses CSS variables or isDark check
- [ ] No undefined props in render

### i18n:
- [ ] EVERY new key exists in PT-BR, EN-US, AND ES-LATAM
- [ ] No raw key strings visible in UI (grep for patterns like `word.word.word`)

### Routes:
- [ ] New pages exist in all 3 locale paths (/, /en/, /es/)

### Build:
- [ ] `npm run build` → 0 errors

### Visual verification:
- [ ] OPEN THE PAGE IN BROWSER and confirm data loads
- [ ] Check dark mode appearance
- [ ] Test as different role if role-gated (GP vs Leader vs Researcher)
