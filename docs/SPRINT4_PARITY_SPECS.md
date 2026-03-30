# Sprint 4 — Frontend Parity Gap Specs (F1, F2, F4, F5)

**Author:** Claude Chat (Product Leader)
**For:** Claude Code (Executor)
**Date:** 2026-03-29
**Deadline:** Demo Mario Trentim — 3/Abr 10:00 ET
**Execution order:** F1 → F5 → F4 → F2
**Note:** F3 (Board Webinar Badge) deferred to Sprint 5 — low demo impact.

---

## SPEC F1: Homepage Public Stats

**Priority:** P1 | **Effort:** 1–2h | **Commit tag:** `feat(homepage): F1 public platform stats section`

### F1.1 Architectural Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Where on the homepage? | **New section below the hero, above existing KPIs** | First thing visitors see after the hero; establishes credibility before asking for login |
| Astro page or React island? | **Astro inline script** fetching on page load | No interactivity needed; pure display; avoids hydration cost; anon-accessible |
| Data source? | `get_public_platform_stats()` via Supabase REST RPC | Already GRANTED to anon; no auth needed; returns all 6 metrics |
| Caching? | **No cache** — RPC is fast (<100ms) and data changes rarely | Supabase handles connection pooling; homepage isn't high-traffic enough to need CDN cache |

### F1.2 RPC Verification

The RPC already exists and is public. Verify before implementation:

```sql
-- Should return data without auth:
SELECT * FROM get_public_platform_stats();
-- Expected: {active_members: ~50, total_tribes: 7, total_chapters: 5, total_events: ~148, total_resources: ~247, retention_rate: ~76.9}
```

```bash
# Verify anon access via REST:
curl -s "https://ldrfrvwhxsmgaabwmaik.supabase.co/rest/v1/rpc/get_public_platform_stats" \
  -H "apikey: <ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{}' | jq .
```

If the RPC returns an error or empty, check the GRANT:
```sql
GRANT EXECUTE ON FUNCTION get_public_platform_stats() TO anon;
```

### F1.3 Frontend Implementation

**File:** `src/pages/index.astro` (PT-BR homepage) — and the corresponding `/en/index.astro`, `/es/index.astro`

Add a new section component. Since this is data that loads once and never changes during the session, use an Astro inline script that fetches and populates on DOMContentLoaded.

**Create:** `src/components/homepage/PlatformStatsSection.astro`

```astro
---
import { getLangFromURL, t } from '../../i18n/utils';

const lang = getLangFromURL(Astro.url.pathname);
const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;
---

<section id="platform-stats" class="py-12 bg-[var(--bg-surface)]">
  <div class="max-w-6xl mx-auto px-4">
    <h2 class="text-center text-2xl font-bold text-[var(--text-primary)] mb-8">
      {t('homepage.stats.title', lang)}
    </h2>
    <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-6 text-center">
      <div class="stat-card">
        <span id="stat-members" class="text-3xl font-extrabold text-[var(--color-navy)]">—</span>
        <span class="text-sm text-[var(--text-secondary)] mt-1">{t('homepage.stats.members', lang)}</span>
      </div>
      <div class="stat-card">
        <span id="stat-tribes" class="text-3xl font-extrabold text-[var(--color-navy)]">—</span>
        <span class="text-sm text-[var(--text-secondary)] mt-1">{t('homepage.stats.tribes', lang)}</span>
      </div>
      <div class="stat-card">
        <span id="stat-chapters" class="text-3xl font-extrabold text-[var(--color-navy)]">—</span>
        <span class="text-sm text-[var(--text-secondary)] mt-1">{t('homepage.stats.chapters', lang)}</span>
      </div>
      <div class="stat-card">
        <span id="stat-events" class="text-3xl font-extrabold text-[var(--color-navy)]">—</span>
        <span class="text-sm text-[var(--text-secondary)] mt-1">{t('homepage.stats.events', lang)}</span>
      </div>
      <div class="stat-card">
        <span id="stat-resources" class="text-3xl font-extrabold text-[var(--color-navy)]">—</span>
        <span class="text-sm text-[var(--text-secondary)] mt-1">{t('homepage.stats.resources', lang)}</span>
      </div>
      <div class="stat-card">
        <span id="stat-retention" class="text-3xl font-extrabold text-[var(--color-navy)]">—</span>
        <span class="text-sm text-[var(--text-secondary)] mt-1">{t('homepage.stats.retention', lang)}</span>
      </div>
    </div>
  </div>
</section>

<style>
  .stat-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 1rem;
    border-radius: 0.75rem;
    background: var(--bg-card, #fff);
    box-shadow: 0 1px 3px rgba(0,0,0,0.06);
  }
</style>

<script define:vars={{ supabaseUrl, supabaseAnonKey }}>
(function() {
  fetch(supabaseUrl + '/rest/v1/rpc/get_public_platform_stats', {
    method: 'POST',
    headers: {
      'apikey': supabaseAnonKey,
      'Content-Type': 'application/json',
    },
    body: '{}',
  })
  .then(function(r) { return r.json(); })
  .then(function(data) {
    if (!data || data.error) return;
    var el;
    el = document.getElementById('stat-members');
    if (el) el.textContent = String(data.active_members || 0);
    el = document.getElementById('stat-tribes');
    if (el) el.textContent = String(data.total_tribes || 0);
    el = document.getElementById('stat-chapters');
    if (el) el.textContent = String(data.total_chapters || 0);
    el = document.getElementById('stat-events');
    if (el) el.textContent = String(data.total_events || 0);
    el = document.getElementById('stat-resources');
    if (el) el.textContent = String(data.total_resources || 0);
    el = document.getElementById('stat-retention');
    if (el) el.textContent = (data.retention_rate || 0).toFixed(0) + '%';
  })
  .catch(function() { /* silently degrade — dashes remain */ });
})();
</script>
```

**Note:** Plain JS only in `define:vars` scripts (Skill Rule 7). No TS casts, no arrow function shorthand that might confuse older bundlers.

**Include the component in the homepage:**

```astro
<!-- In src/pages/index.astro, after the hero section: -->
import PlatformStatsSection from '../components/homepage/PlatformStatsSection.astro';
---
<!-- After hero, before existing KPI section: -->
<PlatformStatsSection />
```

Repeat the import in `/en/index.astro` and `/es/index.astro` (Skill Rule 7 — all 3 locale paths).

### F1.4 i18n Keys

Add to all 3 locale files:

**`src/i18n/pt-BR.ts`:**
```typescript
'homepage.stats.title': 'A plataforma em números',
'homepage.stats.members': 'Pesquisadores ativos',
'homepage.stats.tribes': 'Tribos',
'homepage.stats.chapters': 'Capítulos',
'homepage.stats.events': 'Eventos realizados',
'homepage.stats.resources': 'Recursos na biblioteca',
'homepage.stats.retention': 'Taxa de retenção',
```

**`src/i18n/en-US.ts`:**
```typescript
'homepage.stats.title': 'The platform in numbers',
'homepage.stats.members': 'Active researchers',
'homepage.stats.tribes': 'Tribes',
'homepage.stats.chapters': 'Chapters',
'homepage.stats.events': 'Events held',
'homepage.stats.resources': 'Library resources',
'homepage.stats.retention': 'Retention rate',
```

**`src/i18n/es-LATAM.ts`:**
```typescript
'homepage.stats.title': 'La plataforma en números',
'homepage.stats.members': 'Investigadores activos',
'homepage.stats.tribes': 'Líneas de investigación',
'homepage.stats.chapters': 'Capítulos',
'homepage.stats.events': 'Eventos realizados',
'homepage.stats.resources': 'Recursos en la biblioteca',
'homepage.stats.retention': 'Tasa de retención',
```

**Critical:** Use "Líneas de investigación" for tribes in Spanish, NOT "Tribos" (Skill Rule 10).

### F1.5 Verification Checklist

```
1. Visit homepage as anon → stats section visible with real numbers
2. Visit homepage as authenticated → stats section still visible (same data)
3. Numbers match: ~50 members, 7 tribes, 5 chapters, ~148 events, ~247 resources, ~77% retention
4. /en/ → English labels rendered
5. /es/ → Spanish labels rendered
6. Dark mode → text readable, cards have correct background
7. Mobile (320px) → 2-column grid, no overflow
8. npm run build → 0 errors
```

### F1.6 Execution Order

1. Verify RPC works via curl (anon access)
2. Add i18n keys to all 3 locales
3. Create `PlatformStatsSection.astro`
4. Include in all 3 homepage variants (`/`, `/en/`, `/es/`)
5. Test anon + auth + dark mode + mobile
6. Commit

---

## SPEC F5: Personal Attendance History

**Priority:** P1 | **Effort:** 2h | **Commit tag:** `feat(profile): F5 personal attendance history`

### F5.1 Architectural Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Where in the UI? | **New section on `/profile` page**, below XP/badges | Profile is the natural home for "my history"; avoids cluttering the shared attendance admin page |
| React island or Astro? | **React island** | Needs auth context (supabase client), table interactivity (sort by date), loading state |
| RPC? | `get_my_attendance_history(p_limit)` — already exists | Returns event_id, event_title, event_type, event_date, duration_minutes, present, excused. Filtered by auth.uid(). |
| Default limit? | **20** (last 20 events) | Covers ~2 months of weekly meetings; enough for a useful view; user can see more via scroll/pagination later |

### F5.2 RPC Verification

```sql
-- Verify RPC exists and returns correct structure:
SELECT proname, pronargs FROM pg_proc WHERE proname = 'get_my_attendance_history';
-- Should return 1 row
```

```bash
# Test with auth token:
curl -s "https://ldrfrvwhxsmgaabwmaik.supabase.co/rest/v1/rpc/get_my_attendance_history" \
  -H "apikey: <ANON_KEY>" \
  -H "Authorization: Bearer <USER_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"p_limit": 20}' | jq '.[0:2]'
```

### F5.3 Frontend Implementation

**Create:** `src/components/profile/AttendanceHistoryIsland.tsx`

```tsx
import { useState, useEffect } from 'react';

interface AttendanceRecord {
  event_id: string;
  event_title: string;
  event_type: string;
  event_date: string;
  duration_minutes: number;
  present: boolean;
  excused: boolean;
}

interface Props {
  supabaseUrl: string;
  supabaseAnonKey: string;
  accessToken: string;
  lang: string;
}

const i18n: Record<string, Record<string, string>> = {
  'pt-BR': {
    title: 'Meu histórico de presença',
    date: 'Data',
    event: 'Evento',
    type: 'Tipo',
    status: 'Status',
    present: 'Presente',
    absent: 'Ausente',
    excused: 'Justificado',
    summary: 'Participou de {attended} de {total} eventos ({rate}%)',
    loading: 'Carregando...',
    empty: 'Nenhum evento encontrado.',
    error: 'Erro ao carregar histórico.',
  },
  'en-US': {
    title: 'My attendance history',
    date: 'Date',
    event: 'Event',
    type: 'Type',
    status: 'Status',
    present: 'Present',
    absent: 'Absent',
    excused: 'Excused',
    summary: 'Attended {attended} of {total} events ({rate}%)',
    loading: 'Loading...',
    empty: 'No events found.',
    error: 'Error loading history.',
  },
  'es-LATAM': {
    title: 'Mi historial de asistencia',
    date: 'Fecha',
    event: 'Evento',
    type: 'Tipo',
    status: 'Estado',
    present: 'Presente',
    absent: 'Ausente',
    excused: 'Justificado',
    summary: 'Asistió a {attended} de {total} eventos ({rate}%)',
    loading: 'Cargando...',
    empty: 'No se encontraron eventos.',
    error: 'Error al cargar historial.',
  },
};

// Event type labels (Skill Rule 8)
const TYPE_LABELS: Record<string, Record<string, string>> = {
  'pt-BR': { geral: 'Geral', tribo: 'Tribo', lideranca: 'Liderança', comms: 'Comms', parceria: 'Parceria', entrevista: 'Entrevista', '1on1': '1:1', evento_externo: 'Externo' },
  'en-US': { geral: 'General', tribo: 'Tribe', lideranca: 'Leadership', comms: 'Comms', parceria: 'Partnership', entrevista: 'Interview', '1on1': '1:1', evento_externo: 'External' },
  'es-LATAM': { geral: 'General', tribo: 'Línea', lideranca: 'Liderazgo', comms: 'Comms', parceria: 'Alianza', entrevista: 'Entrevista', '1on1': '1:1', evento_externo: 'Externo' },
};

export default function AttendanceHistoryIsland({ supabaseUrl, supabaseAnonKey, accessToken, lang }: Props) {
  const [records, setRecords] = useState<AttendanceRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const t = i18n[lang] || i18n['pt-BR'];
  const typeLabels = TYPE_LABELS[lang] || TYPE_LABELS['pt-BR'];

  useEffect(() => {
    fetch(`${supabaseUrl}/rest/v1/rpc/get_my_attendance_history`, {
      method: 'POST',
      headers: {
        'apikey': supabaseAnonKey,
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_limit: 20 }),
    })
      .then((r) => r.json())
      .then((data) => {
        if (Array.isArray(data)) {
          setRecords(data);
        } else {
          setError(true);
        }
        setLoading(false);
      })
      .catch(() => {
        setError(true);
        setLoading(false);
      });
  }, []);

  const attended = records.filter((r) => r.present).length;
  const total = records.length;
  const rate = total > 0 ? Math.round((attended / total) * 100) : 0;

  const summaryText = t.summary
    .replace('{attended}', String(attended))
    .replace('{total}', String(total))
    .replace('{rate}', String(rate));

  if (loading) return <p className="text-sm text-[var(--text-secondary)]">{t.loading}</p>;
  if (error) return <p className="text-sm text-red-500">{t.error}</p>;
  if (records.length === 0) return <p className="text-sm text-[var(--text-secondary)]">{t.empty}</p>;

  return (
    <div className="mt-8">
      <h3 className="text-lg font-bold text-[var(--text-primary)] mb-2">{t.title}</h3>

      {/* Summary bar */}
      <div className="mb-4 flex items-center gap-3">
        <div className="flex-1 h-3 rounded-full bg-[var(--bg-muted)] overflow-hidden">
          <div
            className="h-full rounded-full transition-all"
            style={{
              width: `${rate}%`,
              backgroundColor: rate >= 75 ? '#22c55e' : rate >= 50 ? '#f59e0b' : '#ef4444',
            }}
          />
        </div>
        <span className="text-sm font-medium text-[var(--text-secondary)] whitespace-nowrap">
          {summaryText}
        </span>
      </div>

      {/* Table */}
      <div className="overflow-x-auto rounded-lg border border-[var(--border)]">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-[var(--bg-surface)] text-[var(--text-secondary)]">
              <th className="px-3 py-2 text-left font-medium">{t.date}</th>
              <th className="px-3 py-2 text-left font-medium">{t.event}</th>
              <th className="px-3 py-2 text-left font-medium">{t.type}</th>
              <th className="px-3 py-2 text-center font-medium">{t.status}</th>
            </tr>
          </thead>
          <tbody>
            {records.map((r) => (
              <tr key={r.event_id + r.event_date} className="border-t border-[var(--border)] hover:bg-[var(--bg-hover)]">
                <td className="px-3 py-2 whitespace-nowrap">
                  {new Date(r.event_date + 'T00:00:00').toLocaleDateString(lang === 'en-US' ? 'en-US' : lang === 'es-LATAM' ? 'es' : 'pt-BR')}
                </td>
                <td className="px-3 py-2">{r.event_title}</td>
                <td className="px-3 py-2 whitespace-nowrap">
                  <span className="px-2 py-0.5 rounded text-xs bg-[var(--bg-muted)]">
                    {typeLabels[r.event_type] || r.event_type}
                  </span>
                </td>
                <td className="px-3 py-2 text-center">
                  {r.present ? (
                    <span className="inline-block w-2.5 h-2.5 rounded-full bg-green-500" title={t.present} />
                  ) : r.excused ? (
                    <span className="inline-block w-2.5 h-2.5 rounded-full bg-yellow-500" title={t.excused} />
                  ) : (
                    <span className="inline-block w-2.5 h-2.5 rounded-full bg-red-400" title={t.absent} />
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
```

**CRITICAL — Skill Rule 8 compliance:** The `excused` field is returned by the RPC but `excuse_reason` is NOT exposed. The component only shows a yellow dot for excused, never the reason text. This is correct per the attendance rules.

### F5.4 Integration on Profile Page

**File:** The profile page (likely `src/pages/profile.astro` or the React island on it)

```astro
<!-- After the XP/badges section, add: -->
<AttendanceHistoryIsland
  client:load
  supabaseUrl={import.meta.env.PUBLIC_SUPABASE_URL}
  supabaseAnonKey={import.meta.env.PUBLIC_SUPABASE_ANON_KEY}
  accessToken={session.access_token}
  lang={lang}
/>
```

This requires the access token from the Supabase session. Check how other authenticated islands on the profile page receive it and follow the same pattern.

### F5.5 i18n

All strings are inline in the component (trilingual object literal). No i18n file changes needed. If the project convention requires file-level i18n, extract the keys — but the inline pattern reduces coupling.

### F5.6 Verification Checklist

```
1. /profile as authenticated user → attendance history section visible below XP
2. Summary bar shows correct percentage with color coding (green ≥75%, yellow ≥50%, red <50%)
3. Table shows last 20 events with date, title, type badge, status dot
4. Green dot = present, Yellow dot = excused, Red dot = absent
5. NO excuse_reason text visible anywhere (Skill Rule 8)
6. /en/profile → English labels
7. /es/profile → Spanish labels (event types use Spanish translations)
8. Dark mode → table borders and text readable
9. /profile as anon → section not visible (no session = no token = no fetch)
10. npm run build → 0 errors
```

### F5.7 Execution Order

1. Verify RPC returns data with a test token
2. Create `AttendanceHistoryIsland.tsx`
3. Integrate on profile page (all 3 locales)
4. Test with real user session
5. Verify dark mode + mobile
6. Commit

---

## SPEC F4: Library Search via RPC

**Priority:** P1 | **Effort:** 1h | **Commit tag:** `feat(library): F4 server-side search via RPC`

### F4.1 Architectural Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Replace or augment client-side filter? | **Augment** — add keyword search input that calls RPC; keep existing type filters as client-side post-filter | Type filters work fine on the result set; keyword search is what's missing |
| Debounce? | **300ms** | Standard UX; prevents excessive RPC calls while typing |
| Auth required? | **Yes** — RPC is SECURITY DEFINER with auth check | Library page is already behind auth; pass session token |
| Empty search behavior? | Load all resources as before (existing behavior) | Only call RPC when search input has ≥2 characters |

### F4.2 RPC Verification

```sql
-- Verify RPC exists:
SELECT proname FROM pg_proc WHERE proname = 'search_hub_resources';
-- Should return 1 row

-- Test:
SELECT * FROM search_hub_resources('agile', NULL, 5);
-- Should return up to 5 resources matching 'agile' in title/description/tags
```

### F4.3 Frontend Implementation

**File:** The library page's React island (find the component that renders the resource grid on `/library`)

Add a search input above the existing type filter:

```tsx
// Add to the library island component:
import { useState, useEffect, useCallback } from 'react';

// Inside the component:
const [searchQuery, setSearchQuery] = useState('');
const [searchResults, setSearchResults] = useState<Resource[] | null>(null);
const [searching, setSearching] = useState(false);

// Debounced search function
const debounceRef = useRef<ReturnType<typeof setTimeout>>();

const handleSearch = useCallback((query: string) => {
  setSearchQuery(query);
  
  if (debounceRef.current) clearTimeout(debounceRef.current);
  
  if (query.length < 2) {
    setSearchResults(null); // Fall back to full list
    return;
  }
  
  debounceRef.current = setTimeout(async () => {
    setSearching(true);
    try {
      const res = await fetch(`${supabaseUrl}/rest/v1/rpc/search_hub_resources`, {
        method: 'POST',
        headers: {
          'apikey': supabaseAnonKey,
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          p_query: query,
          p_asset_type: null,
          p_limit: 50,
        }),
      });
      const data = await res.json();
      if (Array.isArray(data)) {
        setSearchResults(data);
      }
    } catch {
      // Silently fall back to client-side filter
      setSearchResults(null);
    }
    setSearching(false);
  }, 300);
}, [supabaseUrl, supabaseAnonKey, accessToken]);

// Determine which resources to display:
const displayResources = searchResults !== null ? searchResults : allResources;
// Then apply existing client-side type filter on displayResources
```

**Search input JSX** (add above the existing type filter buttons):

```tsx
<div className="mb-4">
  <input
    type="text"
    value={searchQuery}
    onChange={(e) => handleSearch(e.target.value)}
    placeholder={t('library.search.placeholder', lang)}
    className="w-full md:w-80 rounded-lg border border-[var(--border)] bg-[var(--bg-surface)] px-4 py-2 text-sm text-[var(--text-primary)] placeholder:text-[var(--text-tertiary)] focus:outline-none focus:ring-2 focus:ring-[var(--color-navy)]"
  />
  {searching && (
    <span className="ml-2 text-xs text-[var(--text-secondary)]">
      {t('library.search.searching', lang)}
    </span>
  )}
  {searchResults !== null && (
    <span className="ml-2 text-xs text-[var(--text-secondary)]">
      {searchResults.length} {t('library.search.results', lang)}
    </span>
  )}
</div>
```

### F4.4 i18n Keys

Add to all 3 locale files:

```
'library.search.placeholder': 'Pesquisar recursos...' / 'Search resources...' / 'Buscar recursos...'
'library.search.searching': 'Buscando...' / 'Searching...' / 'Buscando...'
'library.search.results': 'resultados' / 'results' / 'resultados'
```

### F4.5 Verification Checklist

```
1. /library → search input visible above type filters
2. Type "agile" → after 300ms, results filtered to matching resources
3. Clear search → all resources shown again
4. Type "a" (1 char) → no RPC call, full list stays
5. Type "certification" → results match title/description/tags
6. Select type filter AFTER search → further narrows results
7. Dark mode → input readable
8. npm run build → 0 errors
```

### F4.6 Execution Order

1. Verify RPC returns correct data
2. Add i18n keys (3 locales)
3. Add search input + debounced RPC call to library island
4. Wire `displayResources` into existing render logic
5. Test search + type filter combination
6. Commit

---

## SPEC F2: Co-managers Selector in Webinar Modal

**Priority:** P1 | **Effort:** 2h | **Commit tag:** `feat(webinars): F2 co-manager selector in CRUD modal`

### F2.1 Architectural Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| UI pattern? | **Multi-select with checkboxes** inside the existing webinar CRUD modal | Consistent with other multi-select patterns in the platform; no new dependency needed |
| Member list source? | Fetch active members via `public_members` view (filtered by `current_cycle_active = true`) | Already used elsewhere; lightweight; shows name + role |
| Which members to show? | **All active members** (not just tribe members) | Co-managers can be cross-tribe; GPs assign co-managers from any tribe |
| Save mechanism? | Pass `p_co_manager_ids` to existing `upsert_webinar()` RPC | RPC already accepts this parameter; no backend changes needed |

### F2.2 RPC Verification

```sql
-- Verify upsert_webinar accepts co_manager_ids:
SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'upsert_webinar';
-- Should show p_co_manager_ids uuid[] parameter
```

```sql
-- Verify list_webinars_v2 returns co_managers:
SELECT * FROM list_webinars_v2() LIMIT 1;
-- Should include co_managers array: [{id, name}, ...]
```

### F2.3 Frontend Implementation

**File:** The webinar CRUD modal component (find it in the admin/webinars page island)

Add a co-managers section to the modal form, between existing fields:

```tsx
// State for co-managers:
const [coManagerIds, setCoManagerIds] = useState<string[]>(
  editingWebinar?.co_managers?.map((cm: any) => cm.id) || []
);
const [allMembers, setAllMembers] = useState<{ id: string; name: string; operational_role: string }[]>([]);

// Fetch active members on modal open:
useEffect(() => {
  if (!isModalOpen) return;
  supabase
    .from('public_members')
    .select('id, name, operational_role')
    .eq('current_cycle_active', true)
    .order('name')
    .then(({ data }) => {
      if (data) setAllMembers(data);
    });
}, [isModalOpen]);

// Toggle co-manager:
const toggleCoManager = (memberId: string) => {
  setCoManagerIds((prev) =>
    prev.includes(memberId)
      ? prev.filter((id) => id !== memberId)
      : [...prev, memberId]
  );
};
```

**Co-manager selector JSX** (add in the modal form, after the main fields):

```tsx
<div className="mt-4">
  <label className="block text-sm font-medium text-[var(--text-primary)] mb-2">
    {t('webinars.co_managers', lang)}
  </label>
  <div className="max-h-48 overflow-y-auto rounded-lg border border-[var(--border)] p-2 space-y-1">
    {allMembers.map((m) => (
      <label
        key={m.id}
        className="flex items-center gap-2 px-2 py-1.5 rounded hover:bg-[var(--bg-hover)] cursor-pointer text-sm"
      >
        <input
          type="checkbox"
          checked={coManagerIds.includes(m.id)}
          onChange={() => toggleCoManager(m.id)}
          className="rounded border-[var(--border)]"
        />
        <span className="text-[var(--text-primary)]">{m.name}</span>
        <span className="text-xs text-[var(--text-tertiary)]">
          ({t(`roles.${m.operational_role}`, lang)})
        </span>
      </label>
    ))}
  </div>
  {coManagerIds.length > 0 && (
    <p className="mt-1 text-xs text-[var(--text-secondary)]">
      {coManagerIds.length} {t('webinars.co_managers_selected', lang)}
    </p>
  )}
</div>
```

**On save**, include `coManagerIds` in the RPC call:

```tsx
// When calling upsert_webinar:
const { error } = await supabase.rpc('upsert_webinar', {
  // ...existing params...
  p_co_manager_ids: coManagerIds.length > 0 ? coManagerIds : null,
});
```

### F2.4 i18n Keys

Add to all 3 locale files:

```
'webinars.co_managers': 'Co-gestores' / 'Co-managers' / 'Co-gestores'
'webinars.co_managers_selected': 'selecionados' / 'selected' / 'seleccionados'
```

### F2.5 Verification Checklist

```
1. /admin/webinars → open "Create webinar" modal → co-manager section visible
2. Check 2 members → count shows "2 selecionados"
3. Save webinar → co_manager_ids persisted in DB
4. Re-open webinar for edit → previously selected co-managers are checked
5. Uncheck a co-manager → save → removed from DB
6. list_webinars_v2 → co_managers array reflects changes
7. Webinar card (display) → still shows co-manager names (existing behavior)
8. Role label renders correctly per locale
9. Dark mode → checkboxes and labels readable
10. npm run build → 0 errors
```

### F2.6 Execution Order

1. Verify `upsert_webinar` accepts `p_co_manager_ids` and `list_webinars_v2` returns `co_managers`
2. Add i18n keys (3 locales)
3. Add state + member fetch to webinar modal
4. Add co-manager selector JSX
5. Wire `coManagerIds` into the save RPC call
6. Test create, edit, remove co-managers
7. Commit

---

## Summary — Execution Plan for Code

| Order | Spec | Commit | Est. | Demo Impact |
|-------|------|--------|------|-------------|
| 1 | F1: Homepage Stats | `feat(homepage): F1 public platform stats` | 1–2h | 🔴 High — anon sees real data |
| 2 | F5: Attendance History | `feat(profile): F5 attendance history` | 2h | 🔴 High — researcher self-service |
| 3 | F4: Library Search | `feat(library): F4 server-side search` | 1h | 🟡 Medium — 247 resources searchable |
| 4 | F2: Co-managers | `feat(webinars): F2 co-manager selector` | 2h | 🟡 Medium — governance UX |

**Total estimated:** 6–7h of Code execution time.

**Deferred:** F3 (Board Webinar Badge) → Sprint 5 (low demo impact, pipeline-internal).

---

## Appendix: Why F3 Is Deferred

F3 (Board Card Webinar Badge) shows a badge on Kanban cards when linked to a webinar. While useful for tribe leaders, it:
- Only affects the internal board view (not visible in the demo flow)
- Requires modifying the BoardEngine CardDetail component which is complex (DnD interactions)
- Has only 6 linked webinars currently — small data set
- Can be implemented in Sprint 5 when the board gets more attention

The 4 specs above cover all high and medium demo-impact items.
