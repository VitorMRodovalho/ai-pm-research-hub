# 🏗️ Hosting Architecture Decision Record

> ADR-001: Infrastructure for the AI & PM Research Hub

## Context

The AI & PM Research Hub needs a web presence for:
1. **Project website** — Public-facing, trilingual, PMI-branded
2. **Kickoff presentations** — Cycle 3 opens March 5, 2026
3. **Knowledge Base** — Public repository of research outputs
4. **Documentation** — Trilingual project docs (EN/PT/ES)

### Constraints
- Zero budget initially (volunteer-driven project)
- Cannot use Snipescheduler corporate infrastructure
- Must support custom domain
- Must support i18n (EN-US, PT-BR, ES-LATAM)
- Should align with PMI Global 2026 brand standards
- Must be maintainable by non-developers (Markdown-based content)

---

## Decision: Cloudflare Pages + Astro + GitHub

### Why This Stack

| Requirement | Solution | Why |
|------------|----------|-----|
| Free hosting | **Cloudflare Pages** | Unlimited sites, bandwidth, builds on free tier |
| Static site generator | **Astro** | Built-in i18n, fast, Markdown-native, partial hydration |
| Styling | **Tailwind CSS** | Utility-first, easy to map PMI brand tokens |
| Content | **Markdown** | Version-controlled, trilingual, non-dev friendly |
| Source control | **GitHub** | Free for public repos, Actions for CI/CD |
| CDN | **Cloudflare** (included) | Global edge network, fast in LATAM and worldwide |
| Domain | **Cloudflare DNS** | Free DNS, integrates with Pages |
| Analytics | **Cloudflare Analytics** | Free, privacy-respecting, no cookies |

### Alternatives Considered

| Option | Verdict | Reason |
|--------|---------|--------|
| Vercel | Good but limited | Free tier: 100GB bandwidth/month, 1 commercial project |
| Netlify | Good but limited | Free tier: 100GB bandwidth, 300 build minutes/month |
| GitHub Pages | Acceptable | No server-side features, basic CDN, good for pure static |
| Railway | Overkill | Designed for dynamic apps, free tier limited to $5/month |
| Self-hosted (personal machine) | Fragile | Downtime risk, no CDN, manual SSL, not professional |

### Why Cloudflare Pages Wins

- **Truly unlimited** on free tier (bandwidth, builds, requests)
- **Global CDN** with edge nodes in São Paulo, Miami, Frankfurt (perfect for EN/PT/ES audiences)
- **Zero cold starts** (static deployment)
- **Free custom domain** with automatic SSL
- **GitHub integration** — push to `main` = auto deploy
- **Preview deployments** — every PR gets a preview URL
- **Web Analytics** included (no Google Analytics needed)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│                   GitHub                         │
│                                                  │
│  ai-pm-research-hub/                            │
│  ├── docs/ (Markdown, trilingual)               │
│  ├── site/ (Astro + Tailwind)                   │
│  └── .github/workflows/deploy.yml               │
│                    │                             │
│                    │ push to main                │
│                    ▼                             │
│         GitHub Actions (build)                   │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│            Cloudflare Pages                      │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ São Paulo│  │  Miami   │  │Frankfurt │      │
│  │  Edge    │  │  Edge    │  │  Edge    │      │
│  └──────────┘  └──────────┘  └──────────┘      │
│                                                  │
│  Custom domain: aipmhub.org (or similar)        │
│  SSL: Automatic (Cloudflare)                    │
│  Analytics: Cloudflare Web Analytics (free)     │
└─────────────────────────────────────────────────┘
```

---

## Setup Steps

### 1. GitHub Repository
```bash
# Create repo (Vitor creates on GitHub)
# Suggested name: ai-pm-research-hub
# Visibility: Public
# License: MIT (code) + CC BY-SA 4.0 (docs)
```

### 2. Astro Project Init
```bash
npm create astro@latest site -- --template minimal
cd site
npx astro add tailwind
npm install @astrojs/sitemap
```

### 3. i18n Configuration (Astro built-in)
```javascript
// astro.config.mjs
export default defineConfig({
  i18n: {
    defaultLocale: "en",
    locales: ["en", "pt-br", "es"],
    routing: {
      prefixDefaultLocale: false
    }
  }
});
```

### 4. PMI Brand Tokens (Tailwind)
```javascript
// tailwind.config.mjs — PMI Global 2026 color standards
export default {
  theme: {
    extend: {
      colors: {
        'pmi-blue': '#0079C1',
        'pmi-dark': '#003B5C',
        'pmi-orange': '#FF6B35',
        'pmi-teal': '#00A3AD',
        'pmi-green': '#78BE20',
        'pmi-gray': '#58595B',
        'pmi-light': '#F5F5F5',
      }
    }
  }
}
```

### 5. Cloudflare Pages Deployment
1. Go to [dash.cloudflare.com](https://dash.cloudflare.com) → Pages
2. Connect GitHub repository
3. Build settings:
   - Framework preset: Astro
   - Build command: `cd site && npm run build`
   - Build output directory: `site/dist`
4. Add custom domain when ready

### 6. Domain Options (to discuss)
| Domain | Availability | Notes |
|--------|-------------|-------|
| `aipmhub.org` | Check | Clean, professional |
| `ai-pm-hub.org` | Check | With hyphen |
| `aipmresearch.org` | Check | More descriptive |

---

## Cost Summary

| Item | Cost | Notes |
|------|------|-------|
| GitHub (public repo) | $0 | Free |
| Cloudflare Pages | $0 | Free tier, unlimited |
| Cloudflare DNS | $0 | Free |
| Cloudflare Analytics | $0 | Free |
| Domain (.org) | ~$10-15/year | Annual renewal |
| **Total Year 1** | **~$12/year** | Domain only |

---

## Future Scaling Path

When the project grows beyond static site needs:

| Need | Solution | Cost |
|------|----------|------|
| Member authentication | Cloudflare Access (free for 50 users) | $0 |
| Forms/surveys | Cloudflare Workers (free 100K req/day) | $0 |
| Database (if needed) | Cloudflare D1 (free 5GB) | $0 |
| Email notifications | Cloudflare Email Routing | $0 |
| Full dynamic app | Cloudflare Workers + D1 | $5/month |

The Cloudflare ecosystem provides a complete growth path from static site to full application without vendor migration.
