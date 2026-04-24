# Issue #82 Onda 2/3 — Options memo (PM decision required)

> **Status**: PM decision pending (2026-04-25 p45)
> **Owner**: PM Vitor Rodovalho (decision) + Claude (drafting)
> **Issue**: [#82](https://github.com/VitorMRodovalho/ai-pm-research-hub/issues/82) — Onda 1+1.5+1.6 done (9/11 ERROR closed, p40 commits f5fb688+025450a+7d9cda3). Two ERROR remaining.
> **Goal**: Surface trade-offs for the last 2 SECURITY DEFINER views so PM can pick a path.

---

## Context refresh

After Onda 1/1.5/1.6 (p40), 2 ERROR-level findings remain:

1. **`public.public_members`** — view exposing 22 columns from `members`
2. **`public.gamification_leaderboard`** — view aggregating XP totals + per-category breakdowns

Both are `SECURITY DEFINER` (Postgres advisor flagged), meaning they bypass RLS of the querying role. Anon can `SELECT` both today.

This memo is **decision-only** — no SQL changes happen until PM picks a path. Each option includes blast radius + UX risk.

---

## 1. `public_members` (22 callsites in src/)

### Current behavior

```sql
public.public_members AS
SELECT id, name, photo_url, chapter, operational_role, designations,
       tribe_id, initiative_id, current_cycle_active, is_active,
       linkedin_url, credly_badges, credly_url, credly_verified_at,
       cpmai_certified, cpmai_certified_at, country, state, cycles,
       created_at, share_whatsapp, member_status, signature_url
FROM members;
```

22 columns. Anon + authenticated + service_role can `SELECT *`. SECURITY DEFINER bypasses members RLS — view is intentionally a "public face" of the members table.

### Real callsite inventory (excluding database.gen.ts + i18n)

22 callsites across 14 files. Grouped by use case:

| Use case | Callsites | What columns are read |
|---|---|---|
| **Public landing pages** (Hero, Tribes, Team, CPMAI, PresentationLayer) | 6 | name, photo, chapter, operational_role, designations, member_status (counts mostly) |
| **Authenticated nav badge** (Nav.astro) | 1 | id (count active members) |
| **Tribe page roster** (tribe/[id], initiative/[id]) | 6 | name, photo, operational_role, member_status (incl. observers) |
| **Gamification page** (gamification.astro: leaders + assignment + signature) | 4 | id, name, operational_role, tribe_id, signature_url |
| **Admin dashboards** (webinars, chapter-report, portfolio) | 3 | id (counts), chapter |
| **Certificate PDFs** (certificates/pdf.ts) | 2 | signature_url, name (issuer + counter-signer lookup) |
| **Board members picker** (TribeKanbanIsland.tsx) | 2 | id, name, photo_url |

### Sensitive columns exposed

- `signature_url` — used legitimately by certificate PDFs to render issuer + counter-signer signatures. Public exposure means anyone can fetch any member's signature image. Risk: signature reuse (forgery), even though signed_url is typically a Supabase Storage URL.
- `linkedin_url`, `credly_url`, `credly_badges` — public profile-style fields. Members have control over these via `share_whatsapp`-like opt-in (but no equivalent for LinkedIn/Credly today).
- `country`, `state` — coarse location, low PII risk.
- `member_status` — exposes alumni/observer/inactive. Anyone can scan platform attrition. Possibly intentional (transparency) but could be lever for "raid offboarded members" attacks.
- All others (name, photo, role) are intended as public.

### Options for PM

#### Option A — Flip to security_invoker, keep all 22 columns

```sql
ALTER VIEW public.public_members SET (security_invoker = true);
-- members RLS already allows anon to read non-PII; but need to verify
-- which columns members RLS expose to anon. Likely zero (members table
-- has anon-deny RLS). So anon would lose access entirely → 6 landing
-- page callsites break.
```

**Pros**: closes the advisor finding cleanly.
**Cons**: ~6 landing page callsites would break (anon can't read members directly). Would need to either (a) add anon-allow RLS on safe columns or (b) refactor those 6 to use a SECDEF RPC like `get_public_member_counts()`.

**Effort**: 4-6h (identify safe columns, write column-aware RLS or migrate to RPC, smoke 6 pages).
**UX risk**: medium — landing page hero stat, tribes section, team section all currently show counts/lists. If RLS forbids anon, the counts go to 0. Visible regression.

#### Option B — Keep view as security_definer, REVOKE anon SELECT

```sql
REVOKE SELECT ON public.public_members FROM anon;
-- Authenticated keeps. Anon callsites must move to a separate RPC.
```

**Pros**: minimal SQL change. Authenticated UX preserved.
**Cons**: 6 anon-facing callsites break. Need a parallel `get_public_member_stats()` SECDEF RPC for the landing page (similar to existing `get_public_platform_stats`).

**Effort**: 6-8h (write 1-2 SECDEF RPCs, refactor 6 callsites, smoke).
**UX risk**: low if RPCs ship same migration. Hero/Tribes/Team sections would call RPC instead of view — same data, different mechanism.

#### Option C — Slim the view (drop sensitive cols), keep current grants

```sql
DROP VIEW public.public_members CASCADE;
CREATE VIEW public.public_members
WITH (security_invoker = true) AS
SELECT id, name, photo_url, chapter, operational_role, designations,
       tribe_id, initiative_id, current_cycle_active, is_active,
       cpmai_certified, country, state, member_status
FROM members;
-- Drops: linkedin_url, credly_*, signature_url, share_whatsapp, cycles, created_at
```

**Pros**: closes advisor + addresses real PII concern (signature_url, credly).
**Cons**: 4 callsites would break (certificates/pdf.ts signature_url, gamification.astro signature_url+linkedin, etc.). They'd need to call admin-gated SECDEF RPC for those columns.

**Effort**: 8-12h (slim view, write 1-2 SECDEF RPCs for sensitive cols, refactor 4 callsites, smoke certificate generation flow + gamification signature display).
**UX risk**: medium — certificate PDFs could break if RPC lookup fails. Needs careful smoke.

#### Option D — Keep view as-is, document as accepted risk

```sql
COMMENT ON VIEW public.public_members IS
  'SECURITY DEFINER intentional — exposes public-safe member columns to anon
   for landing page and authenticated for cross-tribe roster. Sensitive cols
   (signature_url, linkedin_url, credly_url) are accepted disclosure under
   member opt-in (T&C §X.Y). Advisor finding [security_definer_view] is
   tracked but not actioned per ADR-XXXX.';
```

**Pros**: zero code change, ADR documents the trade-off.
**Cons**: advisor finding stays open, could be flagged in future audits.

**Effort**: 2h (write ADR, COMMENT ON VIEW, update docs).
**UX risk**: zero.

---

## 2. `gamification_leaderboard` (3 callsites in gamification.astro)

### Current behavior

Massive view (45 columns) aggregating gamification_points per member, with per-category breakdowns (attendance, learning, certs, badges, artifact, showcase, bonus) AND cycle-scoped variants. Joined to `members` filtered by `current_cycle_active = true`.

### Callsite inventory

3 calls in `src/pages/gamification.astro`:
- Line 848: `sb.from('gamification_leaderboard').select('*')` — initial load
- Line 891: same with `withTimeout` — leader stats
- Line 982: same with `withTimeout` — main leaderboard

All authenticated; anon has SELECT grant but no current callsite from anon path.

### Options for PM

#### Option A — Convert to SECDEF RPC

```sql
CREATE OR REPLACE FUNCTION public.get_gamification_leaderboard()
RETURNS TABLE (member_id uuid, name text, ...)  -- 45 columns
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
  WITH current_cycle AS (...) -- same query as view
$$;

DROP VIEW public.gamification_leaderboard;
-- Refactor 3 callsites: sb.from('gamification_leaderboard').select('*')
-- → sb.rpc('get_gamification_leaderboard')
```

**Pros**: closes advisor cleanly. Pattern matches `get_public_leaderboard` (already exists, smaller scope).
**Cons**: 3 callsite refactors. RPC return type with 45 columns is verbose to declare; alternative is `RETURNS jsonb` and pass through. JSON shape changes affect TypeScript types in `database.gen.ts`.
**UX risk**: medium — leaderboard is high-traffic (gamification.astro is one of the most-visited pages per usage stats); any latency regression (sql function vs view materialization) visible.

**Effort**: 8-10h (write RPC matching view exactly, write contract test for column parity, refactor 3 callsites, smoke gamification page, regen database.gen.ts).

#### Option B — Flip to security_invoker

```sql
ALTER VIEW public.gamification_leaderboard SET (security_invoker = true);
```

**Pros**: 1-line fix, no callsite refactor.
**Cons**: anon loses access (RLS on members + gamification_points denies anon). All 3 callsites are authenticated, so authenticated still works IF members and gamification_points RLS allow them. Need to verify RLS for authenticated.
**Risk**: if any RLS blocks authenticated access to gamification_points (e.g., per-tribe scoping), the leaderboard would silently filter to fewer rows. UX regression: "leaderboard shows only my tribe" instead of "all platform". Detection: hard (no error, just less data).

**Effort**: 1h (flip + smoke). 4-6h (smoke + remediate RLS if regression).

#### Option C — Slim view scope to leaderboard essentials only

The current view has 45 columns including many cycle-scoped variants. The 3 callsites use mostly the totals + the cycle_* breakdowns. A slim version would have ~10 cols.

**Pros**: smaller surface = easier to reason about + flip invoker safer.
**Cons**: 3 callsites still need refactor (not all use all columns, but `select('*')` would break). Plus product call: which breakdowns matter?
**Effort**: 8-12h.

#### Option D — Document as accepted risk

Same pattern as public_members Option D.

---

## Combined recommendations

| View | Recommended Option | Why |
|---|---|---|
| `public_members` | **B** (REVOKE anon + SECDEF RPC for landing) OR **D** (document risk) | B is the cleanest if PM wants advisor green; D is fine if PM accepts the trade-off documented in ADR. **Option C (slim view) is a trap** — breaks certificate PDFs, hard to smoke fully without breaking prod cert flow. |
| `gamification_leaderboard` | **A** (SECDEF RPC) OR **B** (flip invoker after RLS verify) | A is canonical pattern (matches `get_public_leaderboard`). B is faster but riskier (silent UX regression possible if RLS scoping). |

### Combined estimates

| Path | Effort | Risk | Advisor closes |
|---|---:|---|---:|
| Both option A | ~14h | medium | 2 |
| public_members B + leaderboard A | ~14h | low | 2 |
| public_members D + leaderboard A | ~10h | low | 1 |
| public_members D + leaderboard D | 4h | none | 0 |
| public_members B + leaderboard B | ~8h | medium-high | 2 |

---

## Decision questions for PM

1. **Closes advisor (2 ERRORs) vs accept trade-off?** Advisor is product-quality signal but not a security blocker per current threat model.
2. **For public_members**: are anon callsites (Hero stats, Tribes section, Team section) load-bearing for first-impression UX? If yes → Option B keeps them. If no → revoke anon entirely (Option A flip).
3. **For gamification_leaderboard**: is the page high-traffic enough that latency regression from view→RPC matters? (Leaderboard is also cached by browser; SECDEF function ~equivalent perf.)
4. **Sensitive columns in public_members**: should `signature_url` be moved to admin-only RPC regardless of advisor decision? Forgery risk argument.
5. **Slim view (Option C) for public_members**: PM appetite to refactor certificate PDFs to use admin RPC for signatures? It's the "right" architecture but biggest scope.

---

## Recommended pick (mine, for PM)

**public_members**: Option D for now (document) + slim signature_url to admin-RPC in a focused future session. Reason: 22 callsites is too much risk for this session, and the threat model says "public roster is intentional".

**gamification_leaderboard**: Option A (SECDEF RPC). 3 callsites = manageable, and the existing `get_public_leaderboard` shows the pattern works.

Combined: ~10h, 1 advisor closed, 1 documented as accepted.

---

**Decision required from PM**:
- [ ] Path for `public_members` (A / B / C / D / other)
- [ ] Path for `gamification_leaderboard` (A / B / C / D / other)
- [ ] Schedule: this sprint, next sprint, post-CBGPL?

---

**Assisted-By**: Claude (Anthropic)
