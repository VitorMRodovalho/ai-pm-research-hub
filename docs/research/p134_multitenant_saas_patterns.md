# Research — Multi-tenant SaaS architecture patterns

**Wave 2 council research | p134 Ω-A | 2026-05-09**
**Scope:** Inform ADRs A (URL routing), B (brand schema), D (per-chapter MCP), E (chapter-aware i18n) for Núcleo IA Hub multi-tenant pivot.
**Stack constraint:** Astro v6 (Cloudflare Workers) · Supabase Postgres (RLS via `can()`) · `nucleo-mcp` Edge Function · Zod 4 / SDK 1.29.0.
**Existing scaffolding:** `organization_id` already present in 60+ migrations; `chapter_registry` seeded (5 chapters); V4 authority (`can()`/`can_by_member()`) is per-org.

---

## TL;DR (5 lines)

1. **Stay row-per-tenant on shared schema** — schema-per-tenant breaks at hundreds of tenants (catalog bloat) and adds 200-300% memory cost; RLS overhead is 1-5% on indexed `organization_id` columns. Núcleo's existing `organization_id` + V4 `can()` is correct foundation.
2. **URL routing: hybrid path-first, subdomain-later** — start `/org/[slug]/` (zero DNS work, single Worker, Astro v6 SSR friendly); add subdomain (`pmi-go.nucleoia.app`) when first paying chapter requests white-label; reserve custom-domain (`pmi-go.org.br`) for Wave 3+ via Cloudflare for SaaS.
3. **Per-tenant theming via CSS variables on `[data-org]` root** — Tailwind v4 `@theme` + CSS vars referenced by utility classes; logo/brand assets in shared Storage bucket scoped by `organization_id` prefix (`brand/{org_id}/logo.png`).
4. **MCP per-tenant scoping via JWT claim, NOT per-tenant server** — keep single `nucleo-mcp` Edge Function; inject `organization_id` into JWT custom claim via Supabase Auth Hook; tools resolve org from `auth.jwt() ->> 'org_id'` and scope all RPCs accordingly. Anthropic's MCP spec leaves multi-tenant unstandardized — JWT claim is the production-tested path.
5. **i18n: chapter-aware overrides via namespace inheritance** — keep base `pt-BR/en-US/es-LATAM` dictionaries; add optional `tenant_overrides[org_slug]` namespace loaded conditionally (chapter brand strings only — "PMI-GO" vs "PMI-CE" vs generic "Núcleo"). Bundle splitting per tenant is overkill for our scale (<50 chapters projected).

---

## 1. PostgreSQL RLS multi-tenant

### Pattern decision matrix

| Pattern | Tenants supported | Compliance | Op overhead | Cross-tenant queries | Recommend Núcleo |
|---|---|---|---|---|---|
| **Database-per-tenant** | <100 | Highest (physical isolation) | Highest (300% CPU, 200% mem per Microsoft 2026 benchmark) | Impossible | NO — incompatible with Supabase project model |
| **Schema-per-tenant** | <500 (catalog bloat past that) | High (logical isolation) | High (migrations × N schemas; planner slowdown) | Cross-schema joins required | NO — Núcleo needs cross-tenant analytics for Detroit/LIM/Latam |
| **Shared schema + RLS (row-per-tenant)** | 10K+ proven (Slack, Vitess sharding) | Adequate w/ proper RLS audit | Lowest | Native | **YES — current foundation extended** |

Sources: [PlanetScale tenancy](https://planetscale.com/blog/approaches-to-tenancy-in-postgres), [Supabase storage multi-tenant docs](https://deepwiki.com/supabase/storage/4-multi-tenant-system), [Multi-Tenancy DB Patterns 2026](https://dasroot.net/posts/2026/01/multi-tenancy-database-patterns-schema-database-row-level/).

### Performance — what actually matters

- **RLS overhead is 1-5% on indexed tenant columns** (consistent across AntStack benchmarks, AWS Database Blog, MVP Factory). Núcleo's `organization_id` columns already have indexes via FK — confirm with `EXPLAIN ANALYZE` on top RPCs once multi-tenant traffic arrives.
- **Index discipline is non-negotiable:** every table with `organization_id` MUST have an index on `(organization_id)` or `(organization_id, <hot_filter_col>)`. Missing indexes = sequential scans even with RLS predicate. AntStack flags this as the #1 perf killer.
- **Use `auth.jwt() ->> 'org_id'` over subqueries** in policies. Avoid `EXISTS (SELECT FROM members WHERE auth_id = auth.uid() AND org_id = X)` in hot paths — it forces a join per row. Cache the org_id in JWT claim instead (Custom Access Token Hook).
- **Wrap JWT extraction in `STABLE` functions** — Supabase's `auth.jwt()` is already STABLE, but custom helpers like `current_org_id()` should also be marked STABLE so PG planner can hoist them out of loops.

### Pooled connection gotchas (Supabase Pooler / PgBouncer)

- `set_config('app.tenant', X, false)` (session-scoped) **leaks** between transactions in transaction-pooler mode. Use `set_config('...', X, true)` (transaction-scoped) — but better: rely on JWT claim, no `set_config` needed.
- **Service-role bypass:** `service_role` key bypasses RLS entirely. Worker code that uses service role MUST resolve `organization_id` itself before any query — never trust client-supplied org. Audit all `nucleo-mcp` tools using service role.
- **Policy caching:** PG caches policy plans per session — schema migrations to policies require connection drop or `DISCARD ALL`. With Supabase pooler this means waiting for connection cycle.

Sources: [AWS multi-tenant RLS](https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/), [Supabase RLS deep dive](https://supabase.com/docs/guides/database/postgres/row-level-security), [Optimizing RLS Performance with Supabase (AntStack)](https://www.antstack.com/blog/optimizing-rls-performance-with-supabase/).

---

## 2. URL routing patterns

### Comparison table

| Pattern | Pros | Cons | SEO | Cookie isolation | Cloudflare Workers fit | Astro v6 fit | Recommend Núcleo |
|---|---|---|---|---|---|---|---|
| **Path `/org/[slug]/`** | Zero DNS; single cert; trivial cross-org links; works on `*.workers.dev` for dev | "Messy" middleware; harder to white-label perception | Subfolders inherit domain authority (Yoast/Google) — best for SEO consolidation | Shared cookies w/ path scope | Native — single Worker, single route | Native via `[org]` dynamic route + middleware org resolution | **HIGH (Phase 1)** |
| **Subdomain `pmi-go.nucleoia.app`** | Brand perception; clean URLs; isolated cookies | Wildcard cert; per-tenant DNS records (or wildcard); each subdomain seen as separate site for SEO | Subdomain treated as separate site by Google — splits authority | Isolated by default | Wildcard route on Worker (`*.nucleoia.app/*`); Cloudflare Custom Domains do **NOT** support wildcards directly — use Workers for Platforms or wildcard route + DNS wildcard CNAME | Requires SSR (no static gen) + middleware to extract subdomain from `Host` header | **MEDIUM (Phase 2 — when first chapter requests)** |
| **Custom domain `pmi-go.org.br`** | Full white-label; tenant owns domain | TLS provisioning per tenant; ACME validation; tenant manages DNS CNAME/AAAA | Best — independent SEO | Full isolation | **Cloudflare for SaaS** custom hostnames API + Workers for Platforms dynamic dispatch | Requires SSR + Host header → org_slug lookup table | **LOW (Phase 3 — paying enterprise tier only)** |

### Concrete recommendations for Núcleo

**Phase 1 (now → Q3 2026):** Path routing.
- Astro route: `src/pages/org/[orgSlug]/...` mirroring current `src/pages/...`
- Middleware extracts `orgSlug` from URL path → resolves `organization_id` via cached lookup → injects into request locals.
- Default redirect: `nucleoia.vitormr.dev/` → `nucleoia.vitormr.dev/org/nucleo-ia-gp/` (current single-tenant content lives under canonical org slug).

**Phase 2 (when PMI-GO/PMI-CE pilot signs):** Add subdomain alias.
- DNS wildcard `*.nucleoia.app CNAME nucleoia.vitormr.dev`.
- Worker route `*.nucleoia.app/*` resolves subdomain → org_slug → 308 to `/org/[slug]/...` (or rewrites internally without redirect for cleaner URL).
- Avoids Cloudflare Custom Domain wildcard limitation by using a wildcard **route** instead.

**Phase 3 (enterprise tier):** Cloudflare for SaaS custom hostnames.
- Tenant adds `CNAME pmi-go.org.br → nucleoia.app`.
- Cloudflare provisions TLS via `/hostnames` API.
- Workers for Platforms dynamic dispatch routes by `Host` header.

**SEO/i18n integration:**
- `hreflang` reciprocal tags on every variant (PT/EN/ES); each canonical is **self-referencing** (Yoast guidance — never cross-region canonical).
- Consolidate domain authority via subfolders for now; only split to subdomains when a chapter explicitly wants distinct SEO presence.

Sources: [AWS tenant routing strategies](https://aws.amazon.com/blogs/networking-and-content-delivery/tenant-routing-strategies-for-saas-applications-on-aws/), [Cloudflare Custom Domains docs (no wildcards)](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), [Cloudflare Workers for Platforms hostname routing](https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/configuration/hostname-routing/), [Handling wildcard domains for multi-tenant Cloudflare Workers](https://hossamelshahawi.com/2025/01/26/handling-wildcard-domains-for-multi-tenant-apps-with-cloudflare-workers/), [Yoast international domain structures](https://yoast.com/domain-structures-for-international-and-multilingual-seo/), [Google managing multi-regional sites](https://developers.google.com/search/docs/specialty/international/managing-multi-regional-sites).

---

## 3. Per-tenant theming

### Pattern — CSS variables + `[data-org]` root attribute

```css
/* global.css — base layer */
@layer base {
  :root {
    --color-primary: oklch(0.55 0.18 240); /* Núcleo blue default */
    --color-accent: oklch(0.70 0.15 60);
    --logo-url: url('/brand/nucleo/logo.svg');
  }
  [data-org="pmi-go"] {
    --color-primary: oklch(0.55 0.18 30);  /* PMI-GO red */
    --logo-url: url('/brand/pmi-go/logo.svg');
  }
  [data-org="pmi-ce"] {
    --color-primary: oklch(0.55 0.18 140); /* PMI-CE green */
    --logo-url: url('/brand/pmi-ce/logo.svg');
  }
}
```

```js
// tailwind.config.js (or @theme in Tailwind v4)
@theme {
  --color-primary: var(--color-primary);
  --color-accent: var(--color-accent);
}
```

```astro
<!-- Layout.astro -->
<html data-org={org.slug} lang={lang}>
  <body>...</body>
</html>
```

### Why this pattern wins for Núcleo

1. **Zero JS overhead** — theme switches happen at HTML attribute level, no runtime React re-render.
2. **SSR-friendly** — middleware sets `data-org` server-side; no flash of unstyled content.
3. **Cache-friendly** — CSS bundle is shared across all tenants; only one version in CDN.
4. **Dark mode compatible** — combine `[data-org="pmi-go"][data-theme="dark"]` selectors.

### Brand asset CDN architecture

- **Shared Supabase Storage bucket** `brand-assets` (public read).
- **Path convention:** `brand/{org_slug}/{logo|favicon|hero}.{ext}`.
- **RLS on bucket:** authenticated users can read all; only `manage_organization` role can write to their own org prefix.
- **Cache:** Supabase Storage already CDN-edged; set `Cache-Control: public, max-age=31536000, immutable` with hash-versioned filenames for invalidation.

### Email templates per-tenant

- **Resend templates** support per-send variables — pass `{{logo_url, primary_color, org_name}}` from PG `organizations` table.
- **Single template per language**, variables injected from `organizations.brand_config` JSONB column — avoid template proliferation.

Sources: [Multi-Tenant Themes with Tailwind v4 (Wawandco)](https://wawand.co/blog/posts/managing-multiple-portals-with-tailwind/), [Tailwind v4 data-theme discussion](https://github.com/tailwindlabs/tailwindcss/discussions/15199), [Multi-tenant theming Tailwind (DEV)](https://dev.to/jonathz/designing-multi-tenant-ui-with-tailwind-css-5gi7).

---

## 4. Per-tenant MCP architecture

### Anthropic's MCP multi-tenant story (state 2026)

- **OAuth 2.1 with PKCE** is the spec'd auth mechanism for remote MCP servers (formalized Nov 2025).
- **Multi-tenant remains unstandardized** in MCP spec — implementations vary. Common pattern: single MCP server, per-user/per-org token via headers, server-side scoping. Sources flag this as a "rough edge of 2026 ecosystem."
- **Audience claim per-tenant:** OAuth `aud` claim CAN encode tenant, but Anthropic's docs don't prescribe this. Production implementations (Webflow MCP, Scalekit guides) use **JWT custom claim** (`org_id`) injected by the auth server.

### Recommended pattern for Núcleo: single MCP, JWT-scoped

```typescript
// nucleo-mcp/index.ts — current pattern, extended for multi-tenant
mcp.tool("get_chapter_dashboard", "...", {}, async () => {
  const member = await getMember(sb);
  if (!member) return err("Not authenticated");

  // NEW: extract org_id from JWT claim, NOT from request param
  const orgId = member.organization_id; // injected by auth hook
  if (!orgId) return err("No organization context");

  // RPC scoped by RLS using auth.jwt() ->> 'org_id'
  const { data, error } = await sb.rpc("get_chapter_dashboard", { p_org_id: orgId });
  // ...
});
```

### Auth flow for multi-tenant MCP

1. **User logs in via OAuth** (`/oauth/authorize` → `/oauth/consent`). If user belongs to multiple orgs, consent screen shows org selector.
2. **Token endpoint** (`/oauth/token`) returns JWT with `org_id` custom claim (set via Supabase Custom Access Token Hook on login).
3. **MCP request** flows through Worker proxy → Edge Function. Auth middleware extracts `org_id` from JWT → all RPCs auto-scoped by RLS.
4. **Tool catalog can be org-conditional** — `tools/list` filters tools the org has subscribed to (e.g., free tier vs paid tier). Read `organizations.feature_flags` JSONB.

### Anti-patterns to avoid

- **DO NOT spawn one MCP Edge Function per tenant** — Supabase Edge Function cold-start + deploy overhead per chapter is operationally untenable (already at 283 tools in single function, can scale by adding tools, not instances).
- **DO NOT pass `org_id` as tool parameter** — clients could spoof. Always derive from JWT.
- **DO NOT issue same JWT across orgs** — if user switches org context, mint new token (org switcher endpoint, refresh with new claim).

### Per-tenant rate limiting

- **Cloudflare Workers Rate Limiting binding** (native, not KV) — scoped by `${jwt.org_id}:${endpoint}` key.
- **Avoid KV for counters** — 1 write/sec/key limit + $5/M writes makes it expensive at scale. Use Durable Objects if cross-Worker coordination needed.
- **Per-org tier in `organizations.rate_tier`** ENUM (free=60rpm, paid=600rpm, enterprise=unlimited).

Sources: [MCP Authorization spec](https://modelcontextprotocol.io/specification/draft/basic/authorization), [MCP Security Multi-Tenant (Prefactor)](https://prefactor.tech/blog/mcp-security-multi-tenant-ai-agents-explained), [Multi-Tenant MCP Servers — Isolating Context at Scale](https://ranjankumar.in/multi-tenant-mcp-servers-isolating-context-at-scale), [Single MCP server across multiple Webflow clients](https://www.pravinkumar.co/blog/single-mcp-server-multi-client-webflow-2026), [Cloudflare Workers Rate Limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/).

---

## 5. Chapter-aware i18n bundling

### Pattern — namespace inheritance with optional override

```typescript
// src/i18n/loader.ts
async function loadDictionary(lang: 'pt-BR'|'en-US'|'es-LATAM', orgSlug?: string) {
  const base = await import(`./dicts/${lang}.ts`);
  if (!orgSlug || orgSlug === 'nucleo-ia-gp') return base.default;

  // Optional per-tenant overrides — only loads if file exists
  try {
    const overrides = await import(`./dicts/overrides/${orgSlug}/${lang}.ts`);
    return { ...base.default, ...overrides.default }; // shallow merge OK for flat keys
  } catch {
    return base.default; // chapter has no overrides → fall back
  }
}
```

### What to override (small surface)

- **Chapter name strings:** `header.title`, `footer.org`, `email.from_name` — render "PMI-GO Hub" vs "PMI-CE Hub" vs "Núcleo IA".
- **Brand-specific verbiage:** "membros" vs "voluntários" vs "associados" (some chapters prefer different terms).
- **Local legal references:** PMI-GO references `Lei Estadual GO XYZ`, PMI-CE references `Lei Estadual CE ABC`.

### What NOT to override

- **Domain terminology:** `tribe`, `engagement`, `webinar` — system primitives, must stay consistent for cross-org analytics.
- **Form labels, validation errors, button text** — UI vocabulary stays uniform.

### Bundle size implications at Núcleo scale

- Base `pt-BR/en-US/es-LATAM` dictionaries = ~2300 keys × 3 langs ≈ 280KB raw, ~50KB gzipped (current state).
- Per-org override file estimated 20-50 keys × 3 langs ≈ 5KB raw, ~1KB gzipped.
- **Conclusion:** bundle splitting per tenant is overkill for <50 chapters. Lazy-load overrides on org context resolution; cache in browser per session. Total payload increase ~1-3KB per tenant. Don't over-engineer.

### Server-side vs client-side

- **SSR resolves base dictionary** based on `lang` route segment (already current pattern).
- **Override loaded server-side** in same request once `orgSlug` resolved by middleware → injected as page prop.
- **No client-side i18next runtime needed** — Astro's static + island model handles this natively. Avoid bringing in i18next/react-i18next dependency for this case.

Sources: [Locize multi-tenant translations](https://www.locize.com/blog/i18next-in-production/), [i18next multi-tenant overrides (Mussini)](https://maximomussini.com/posts/i18n-multitenant), [react-i18next multiple files](https://react.i18next.com/guides/multiple-translation-files).

---

## 6. Supabase multi-tenant case studies

### Production patterns observed

- **`auth.users.app_metadata.org_id` + Custom Access Token Hook** (most common 2026 pattern): server-only metadata, can't be modified by user, automatically embedded in JWT. Supabase Custom Access Token Hook reads `app_metadata` and injects into JWT claims at token issuance. Reference: KristianRykkje/Supabase-multi-tenancy-auth.
- **Avoid `user_metadata` for org_id** — user-modifiable, security risk per Supabase docs.
- **Multi-org users:** `members` table (Núcleo's existing pattern) with `(person_id, organization_id)` composite + active engagement flag. JWT carries currently-selected org; switcher endpoint mints new token.

### Database scaling considerations

- **Supabase default Postgres tier** handles ~1K tenants comfortably with shared schema + RLS per AntStack benchmarks.
- **Pgbouncer transaction mode** is default for Supabase pooler — works fine with `auth.jwt()`-based RLS (no `set_config` needed).
- **Read replicas** (Supabase paid tier) help if cross-tenant analytics queries dominate — route OLAP to replica, OLTP to primary.

### Storage multi-tenant

- **Single bucket, prefix-scoped paths**: `org/{org_id}/...` is canonical. Storage RLS policies use prefix matching against `auth.jwt() ->> 'org_id'`.
- **Avoid bucket-per-tenant**: each new bucket requires API calls + bucket policies; Supabase has a 100-bucket soft cap per project.
- **Public assets (logos)**: separate `brand-assets` public bucket; private assets (member CVs, contracts) in tenant-scoped private buckets.

### Realtime multi-tenant

- **Channel naming convention:** `org:{org_id}:tribe:{tribe_id}` — Supabase Realtime respects RLS on the underlying table; channel subscription itself is just a routing key.
- **Auth on channels:** Realtime checks `auth.uid()` + RLS on subscribed table — automatically enforces tenant boundary.

Sources: [Multi-Tenant Authentication with Supabase (Kriryk, Mar 2026)](https://medium.com/@kriryk/multi-tenant-authentication-with-supabase-a-production-implementation-0f6064f50d55), [Supabase Custom Access Token Hook docs](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook), [Supabase RLS Best Practices (Makerkit)](https://makerkit.dev/blog/tutorials/supabase-rls-best-practices), [Supabase storage multi-tenant system](https://deepwiki.com/supabase/storage/4-multi-tenant-system).

---

## 7. Comparable platforms architecture

| Platform | Tenant unit | DB strategy | URL pattern | Lesson for Núcleo |
|---|---|---|---|---|
| **Slack** | Workspace | Vitess sharded by `workspace_id`; RLS for isolation | `{workspace}.slack.com` (subdomain) | Sharding by org_id is the path past 10K+ tenants. Cross-workspace features (Shared Channels, Unified Grid) required architectural retrofit — design for cross-org from day 1 (e.g., Detroit/Latam visibility). |
| **Discord** | Server (guild) | Sharded by `guild_id` (Cassandra for messages) | `discord.com/channels/{guildId}` (path) | Path routing with stable IDs, not slugs in path. Slug aliases as redirect layer. |
| **Notion** | Workspace | Per-workspace databases logically; shared infra | `notion.so/{workspace-slug}/{page}` (path) | Path routing scales fine; subdomain only for enterprise SSO. Workspace switcher is a key UX primitive. |
| **Figma** | Team / Org | Shared infra, RLS-style policies | `figma.com/files/{teamId}/...` (path) + `app.figma.com` | API-first means MCP-style integrations work cleanly per-team via OAuth audience scope. |
| **Linear** | Workspace | Shared schema with workspace_id | `{workspace}.linear.app` (subdomain) | Subdomain perception matters for B2B SaaS — but they had funding to do it. Path-first is acceptable starting position. |

### Cross-cutting lessons

1. **Cross-org features are hard to retrofit** — Slack's Shared Channels took years post-launch. Núcleo's "Detroit AI Summit" / "PMI Latam Hub" inherently cross-chapter — design data model now to support cross-org listing/joining (already partially done via `engagement_kind_permissions`).
2. **Org switcher is core UX** — Notion / Linear / Figma all invest heavily here. Multi-org users (Vitor, who'll be in Núcleo + PMI-GO + PMI-CE) need fast switching.
3. **Path routing is fine for billions of users** — Notion + Discord prove it at massive scale. Subdomain is brand polish, not a tech requirement.
4. **Tenant ID stability matters** — Slack / Discord use opaque IDs in URL; Notion uses slugs but allows rename via redirect. Núcleo should treat `org_slug` as stable (rename rare, redirect old slugs).

Sources: [Slack Multi-Tenancy deep dive](https://dev.to/devcorner/deep-dive-slacks-multi-tenancy-architecture-m38), [Slack Shared Channels engineering](https://slack.engineering/how-slack-built-shared-channels/), [Slack Unified Grid re-architecture](https://slack.engineering/unified-grid-how-we-re-architected-slack-for-our-largest-customers/).

---

## 8. ADR-A/B/D/E recommended approach

### ADR-A — Multi-tenant URL routing

**Decision:** Path routing `/org/[slug]/` Phase 1; subdomain alias Phase 2; custom domain Phase 3 enterprise.

**Astro v6 implementation:**
- Add `src/pages/org/[orgSlug]/[...rest].astro` catchall that delegates to existing routes.
- Middleware (`src/middleware.ts`) extracts `orgSlug` from path → loads org config → sets `Astro.locals.org`.
- Default: `nucleoia.vitormr.dev/` rewrites to `/org/nucleo-ia-gp/` (canonical org for current single-tenant content).
- I18n redirects (`/en/`, `/es/`) become `/org/[slug]/en/`, `/org/[slug]/es/` — update redirect pages.

**Cloudflare Workers fit:** Single Worker, single route `nucleoia.vitormr.dev/*`. No Workers for Platforms needed Phase 1.

**Backward compat:** Keep `nucleoia.vitormr.dev/admin` etc. working as alias to `nucleo-ia-gp` org for grace period (308 redirect 6 months).

### ADR-B — Chapter brand config schema

**Decision:** `organizations.brand_config JSONB` column with strict shape.

```sql
ALTER TABLE organizations ADD COLUMN brand_config JSONB DEFAULT '{}'::jsonb;

-- Shape (validated by trigger or app-layer Zod schema):
-- {
--   "primary_color": "oklch(0.55 0.18 240)",
--   "accent_color": "oklch(0.70 0.15 60)",
--   "logo_url": "/storage/v1/object/public/brand-assets/pmi-go/logo.svg",
--   "favicon_url": "...",
--   "email_from_name": "PMI-GO Hub",
--   "display_name": { "pt-BR": "PMI-GO", "en-US": "PMI-GO", "es-LATAM": "PMI-GO" }
-- }
```

**Why JSONB not separate columns:** brand attributes evolve; new attrs (hero image, footer text) shouldn't require migrations.

**Validation:** PG check constraint on required keys + Zod schema in admin UI form.

**Fallback chain:** org override → Núcleo defaults (hardcoded in CSS).

### ADR-D — Per-chapter MCP server scoping

**Decision:** Single `nucleo-mcp` Edge Function, per-tenant scoping via JWT `org_id` custom claim.

**Implementation:**
1. **Add Custom Access Token Hook** (Supabase Auth) reading `app_metadata.org_id` (or `members.organization_id` for currently-active org) → injects `org_id` claim into JWT.
2. **MCP tools read `member.organization_id`** (already loaded via `getMember(sb)` from `members` table) — no protocol change needed.
3. **Tool catalog filtering** (optional Phase 2): `tools/list` returns subset based on `organizations.feature_flags`.
4. **Org switcher endpoint** (`/api/switch-org`): validates user has engagement in target org, mints new JWT with new `org_id` claim, returns refresh token.

**No protocol changes needed for Anthropic clients** — they see same MCP server URL, same tools; server-side scoping is invisible.

**Migration risk:** existing JWT tokens won't have `org_id` claim. Solution: on missing claim, fall back to `nucleo-ia-gp` (canonical org) for grace period; force re-auth after 30 days.

### ADR-E — Chapter-aware i18n bundle

**Decision:** Base dictionaries unchanged; optional per-org override file loaded conditionally.

**Implementation:**
- `src/i18n/dicts/{pt-BR,en-US,es-LATAM}.ts` — base, unchanged.
- `src/i18n/dicts/overrides/{org_slug}/{lang}.ts` — optional, sparse override map (only changed keys).
- `usePageI18n()` hook receives `orgSlug` from context, merges base + override at runtime.
- Override file has same shape as base but only contains overridden keys (TypeScript `Partial<typeof base>`).

**Bundle implications:** ~1-3KB per tenant override file, loaded only when org context active. No bundle splitting infrastructure needed.

**Translation workflow:** Admin UI lets chapter Tier-1 leader edit override keys; saves to `organizations.i18n_overrides JSONB`; on deploy a build step generates static override files (or load from DB at runtime via separate fetch — simpler, slightly slower TTI).

---

## 9. Migration path single-tenant → multi-tenant

**Non-trivial — 3-month phased plan recommended (per industry consensus, "always a multi-month project"):**

### Phase 0 — Foundation audit (1 week)
- Audit all 60+ tables with `organization_id` for index coverage on `(organization_id, ...)`.
- Audit all RPCs for `organization_id` scoping (some may rely on `auth.uid()` alone — refactor to derive org from member).
- Add `organizations.brand_config` + `organizations.i18n_overrides` JSONB columns.

### Phase 1 — Path routing + brand schema (2 weeks)
- Implement `/org/[slug]/...` route + middleware org resolution.
- Add `data-org` to layout root + CSS variable system.
- Backward-compat redirect for legacy URLs.
- **Smoke test:** create dummy "PMI-GO" org, verify isolation via test member.

### Phase 2 — JWT custom claim (1 week)
- Implement Custom Access Token Hook injecting `org_id`.
- Update MCP tools to derive org from JWT (no protocol break).
- Add org switcher UI for users with multiple orgs.

### Phase 3 — i18n overrides + admin (2 weeks)
- Override file loader + `usePageI18n` integration.
- Admin UI for chapter leaders to edit brand + override strings.

### Phase 4 — Pilot with PMI-GO/PMI-CE (4 weeks)
- Real chapter onboarding: brand assets, override strings, chapter-specific members.
- Monitor RLS perf via `pg_stat_statements`; add indexes as needed.
- Iterate on UX based on chapter leader feedback.

### Phase 5 — Subdomain support (2 weeks, on demand)
- DNS wildcard + Worker wildcard route.
- 308 redirects path → subdomain or vice-versa based on config.

### Phase 6 — Custom domain (Workers for Platforms) (deferred)
- Only when paying enterprise customer requests.
- Cloudflare for SaaS custom hostnames API integration.

### Risk mitigation per phase

- **Feature flag every phase** — `organizations.features.multi_tenant_routing_enabled` etc.
- **Dual-write/dual-read during JWT migration** — accept both old (no claim) and new (with claim) tokens for 30 days.
- **Rollback plan per phase** — each phase MUST be revertible without data loss (e.g., brand_config JSONB is additive; never drop).
- **Smoke tests per phase** — extend existing test suite with multi-org fixture.

---

## Sources

### Postgres / Supabase / RLS
- [Supabase Row Level Security docs](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase RLS Best Practices (Makerkit)](https://makerkit.dev/blog/tutorials/supabase-rls-best-practices)
- [Multi-Tenant Authentication with Supabase Production (Kriryk, Mar 2026)](https://medium.com/@kriryk/multi-tenant-authentication-with-supabase-a-production-implementation-0f6064f50d55)
- [Supabase Custom Access Token Hook](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook)
- [Supabase Custom Claims & RBAC](https://supabase.com/docs/guides/database/postgres/custom-claims-and-role-based-access-control-rbac)
- [Supabase Multi-Tenancy Discussion #1148](https://github.com/orgs/supabase/discussions/1148)
- [Supabase Storage Multi-Tenant System (DeepWiki)](https://deepwiki.com/supabase/storage/4-multi-tenant-system)
- [AWS Multi-tenant data isolation with PostgreSQL RLS](https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/)
- [Optimizing RLS Performance with Supabase (AntStack)](https://www.antstack.com/blog/optimizing-rls-performance-with-supabase/)
- [Multi-Tenant Apps with RLS on Supabase (AntStack)](https://www.antstack.com/blog/multi-tenant-applications-with-rls-on-supabase-postgress/)
- [Approaches to tenancy in Postgres (PlanetScale)](https://planetscale.com/blog/approaches-to-tenancy-in-postgres)
- [Multi-Tenancy Database Patterns 2026 (dasroot.net)](https://dasroot.net/posts/2026/01/multi-tenancy-database-patterns-schema-database-row-level/)
- [RLS in Postgres tenant isolation (MVP Factory)](https://mvpfactory.io/blog/row-level-security-in-postgresql-multi-tenant-data-isolation-for-your-saas)
- [Designing the most performant RLS schema (Caleb Brewer)](https://cazzer.medium.com/designing-the-most-performant-row-level-security-strategy-in-postgres-a06084f31945)

### URL routing / Cloudflare / Astro
- [AWS Tenant routing strategies for SaaS](https://aws.amazon.com/blogs/networking-and-content-delivery/tenant-routing-strategies-for-saas-applications-on-aws/)
- [Azure Domain Name Considerations Multitenant](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/considerations/domain-names)
- [Cloudflare Workers Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
- [Cloudflare Workers Routes](https://developers.cloudflare.com/workers/configuration/routing/routes/)
- [Cloudflare for Platforms hostname routing](https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/configuration/hostname-routing/)
- [Cloudflare for SaaS getting started](https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/getting-started/)
- [Handling wildcard domains for multi-tenant Cloudflare Workers](https://hossamelshahawi.com/2025/01/26/handling-wildcard-domains-for-multi-tenant-apps-with-cloudflare-workers/)
- [Astro Routing docs](https://docs.astro.build/en/guides/routing/)
- [Astro Cloudflare adapter](https://docs.astro.build/en/guides/integrations-guide/cloudflare/)
- [Astro v6 upgrade guide](https://docs.astro.build/en/guides/upgrade-to/v6/)
- [Cloudflare Workers Rate Limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)

### Theming / i18n
- [Multi-tenant theming Tailwind v4 (Wawandco)](https://wawand.co/blog/posts/managing-multiple-portals-with-tailwind/)
- [Tailwind v4 data-theme discussion #15199](https://github.com/tailwindlabs/tailwindcss/discussions/15199)
- [Designing Multi-Tenant UI with Tailwind (DEV)](https://dev.to/jonathz/designing-multi-tenant-ui-with-tailwind-css-5gi7)
- [i18n Multitenancy Customer-Specific (Mussini)](https://maximomussini.com/posts/i18n-multitenant)
- [Locize i18next in Production](https://www.locize.com/blog/i18next-in-production/)
- [react-i18next Multiple Translation Files](https://react.i18next.com/guides/multiple-translation-files)

### MCP / multi-tenant agent infra
- [MCP Authorization spec](https://modelcontextprotocol.io/specification/draft/basic/authorization)
- [MCP Security for Multi-Tenant AI Agents (Prefactor)](https://prefactor.tech/blog/mcp-security-multi-tenant-ai-agents-explained)
- [Multi-Tenant MCP Servers Isolating Context at Scale (Ranjan Kumar)](https://ranjankumar.in/multi-tenant-mcp-servers-isolating-context-at-scale)
- [Single MCP Server Across Multiple Webflow Clients 2026](https://www.pravinkumar.co/blog/single-mcp-server-multi-client-webflow-2026)
- [Securing MCP Servers (Scalekit)](https://geekpython.medium.com/securing-mcp-servers-from-vulnerable-to-bulletproof-with-scalekit-6522b07187da)
- [AWS Enforcing tenant isolation prescriptive guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/agentic-ai-multitenant/enforcing-tenant-isolation.html)

### Comparable platforms
- [Slack Multi-Tenancy deep dive (DEV)](https://dev.to/devcorner/deep-dive-slacks-multi-tenancy-architecture-m38)
- [Slack Shared Channels engineering](https://slack.engineering/how-slack-built-shared-channels/)
- [Slack Unified Grid re-architecture](https://slack.engineering/unified-grid-how-we-re-architected-slack-for-our-largest-customers/)

### SEO / hreflang
- [Yoast international domain structures](https://yoast.com/domain-structures-for-international-and-multilingual-seo/)
- [Google Managing multi-regional sites](https://developers.google.com/search/docs/specialty/international/managing-multi-regional-sites)
- [International SEO hreflang ccTLD vs subfolder](https://venue.cloud/news/announcements/international-seo-hreflang-cctld-vs-subfolder-localize-convert/)
