# Contributing to the AI & PM Research Hub

Welcome! The **AI & PM Research Hub** is the operational platform for the *Núcleo de Estudos e Pesquisa em IA e GP* — a joint initiative of PMI Brazilian chapters (PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS). Whether you're a chapter member, a researcher, or an open-source contributor, we appreciate your help making the Hub better.

---

## Getting started

### Prerequisites

- **Node.js** 24+
- **Wrangler CLI** (`npm install -g wrangler`) — required for Workers deploy
- A Supabase project (or access to the shared development instance)

### Local development

```bash
# 1. Clone and install
git clone https://github.com/VitorMRodovalho/ai-pm-research-hub.git
cd ai-pm-research-hub
npm install

# 2. Configure environment
cp .env.example .env
# Edit .env with your Supabase credentials (see .env.example for docs)

# 3. Start the dev server
npm run dev -- --host 0.0.0.0 --port 4321
```

The dev server runs at `http://localhost:4321` by default. Use `npm run dev -- --host 0.0.0.0 --port 4321` to expose it on the network.

### Verifying your setup

```bash
npm test              # Unit tests
npm run build         # Full production build
npm run smoke:routes  # Smoke-test critical routes
```

All three must pass before you open a PR.

### Pre-commit hook (strongly recommended)

This repo ships a pre-commit hook in `.githooks/pre-commit` that scans for:
- `.env` files being staged accidentally
- Opaque tokens (JWT, `sk_live_...`, `ghp_...`, AWS access keys, Supabase service role keys)
- Private key headers
- Real-looking member emails in non-test files
- Large binaries (>10MB, warning)
- New TODO/FIXME (informational — consider logging via the `session-log` skill)

Enable once per clone:

```bash
git config core.hooksPath .githooks
```

Optional: install [gitleaks](https://github.com/gitleaks/gitleaks) for a second-pass scan. If available, the hook will invoke it automatically.

```bash
# macOS
brew install gitleaks
# Linux (example)
go install github.com/gitleaks/gitleaks/v8@latest
```

Bypass (emergency only, explain in commit body):

```bash
git commit --no-verify -m "..."
```

See `SECURITY.md` for what must not be committed and `GOVERNANCE.md` for the content trifold (repo / private wiki / platform SQL).

---

## Code conventions

### Stack

| Layer | Tech |
|-------|------|
| Frontend | Astro 6 + React 19 + Tailwind 4 (utility-only) |
| Database | Supabase (PostgreSQL, RLS, Edge Functions) |
| Hosting | Cloudflare Workers SSR |
| Auth | Google + LinkedIn (OIDC) + Microsoft (Azure) |
| Deploy | Push to main → GitHub Actions → Wrangler → Workers |
| i18n | PT-BR, EN, ES — keys in `src/i18n/` |

### Rules

0. **Never commit `.env`.** Keep local credentials in untracked `.env` files only. Use `.env.example` as the shareable template and never force-add env files to git.

1. **Prefer event delegation for all new work.** Do not add new inline event handlers like `onclick="fn('${var}')"`. Some legacy surfaces still use them and should be refactored when touched; new code should attach listeners via `document.addEventListener` and read `data-*` attributes.

2. **Tailwind utility classes only.** Do not create standalone `.css` files unless they contain complex global animations.

3. **i18n for all user-facing strings.** Add keys to `src/i18n/` (pt-BR, en-US, es-LATAM). Never hardcode display text in templates.

4. **`define:vars` isolation.** In Astro, never combine `define:vars` with `import` in the same `<script>`. Use a separate `is:inline define:vars` script that writes to `window.__*`, and a normal bundled script that reads from it.

5. **SSR safety.** Always guard optional data — never assume arrays or objects exist in server-rendered pages.

6. **Role model v3.** Use `operational_role` and `designations`. Do not rely on the legacy `role` / `roles` columns for new logic.

7. **No hardcoded deletes.** Use soft deletes (`is_active = false`). The governance model requires history preservation.

---

## Submitting a pull request

### Branch naming

Use a descriptive prefix:

```
feat/artifact-gallery-public
fix/credly-paste-ios
docs/update-release-log
chore/ci-node-upgrade
```

### Commit messages

Write clear, imperative-mood messages. One concern per commit — do not mix DB migrations with UI changes.

```
feat: make artifact catalog visible to anonymous visitors
fix: guard missing deliverables in TribesSection SSR
docs: add March 2026 stabilization notes to RELEASE_LOG
```

### PR checklist

- [ ] `npm test` passes
- [ ] `npm run build` succeeds
- [ ] `npm run smoke:routes` passes (if routes were changed)
- [ ] Site hierarchy still matches `navigation.config.ts`, `AdminNav.astro`, and route files
- [ ] i18n keys added for any new user-facing strings
- [ ] Production-impacting changes documented in `docs/RELEASE_LOG.md`
- [ ] DB changes include a migration in `supabase/migrations/`
- [ ] Sprint docs updated when closing a sprint (`docs/GOVERNANCE_CHANGELOG.md`)
- [ ] Pre-commit QA rules from CLAUDE.md (GC-097) followed

CI runs automatically on PRs to `main`. All checks must be green before merge.

### Sprint closure discipline

Every sprint follows the 5-phase routine documented in `AGENTS.md` and `docs/project-governance/SPRINT_IMPLEMENTATION_PRACTICES.md`:

1. Execute
2. Audit
3. Fix
4. Docs
5. Deploy

---

## Reporting bugs

Use the **Bug Report** issue template in this repository. It will guide you through:

- Description of the problem
- Steps to reproduce
- Expected vs. actual behavior
- Browser / OS / device information

If you don't have access to create issues, email the project manager listed in README.md.

---

## Requesting features

Use the **Feature Request** issue template. Include the problem you're solving, your proposed solution, and acceptance criteria so reviewers have clear context.

---

## Project structure references

| Resource | Purpose |
|----------|---------|
| [`AGENTS.md`](./AGENTS.md) | AI agent structure, conventions, doc map, and lane boundaries |
| [`docs/project-governance/`](./docs/project-governance/) | Governance runbook, sprint practices, roadmap, and project snapshots |
| [`docs/BACKLOG.md`](./docs/BACKLOG.md) | Current priorities and backlog |
| [`docs/RELEASE_LOG.md`](./docs/RELEASE_LOG.md) | Release and hotfix history |
| [`DEBUG_HOLISTIC_PLAYBOOK.md`](./DEBUG_HOLISTIC_PLAYBOOK.md) | Debugging and troubleshooting guide |

If you use **Cursor IDE**, see `docs/CURSOR_SETUP.md` for the first-use checklist.

---

## License

This repository does not yet include a standalone `LICENSE` file. As stated in `README.md`:

- **Code** is licensed under the **MIT License**.
- **Documentation** is licensed under **CC BY-SA 4.0**.

The AI & PM Research Hub is a community project of independent PMI® Brazilian chapters and is not directly affiliated with or endorsed by PMI Global. Contributions are subject to these terms.
