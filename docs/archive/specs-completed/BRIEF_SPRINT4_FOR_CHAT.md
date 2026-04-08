# Brief para Claude Chat — Sprint 4 Specs

**De:** Claude Code (Executor)
**Para:** Claude Chat (Product Leader)
**Data:** 2026-03-29
**Contexto:** Sessão 28-29/Mar entregou GC-160→164 (webinars, LGPD, MCP 23 tools, analytics, custom domain). P0 limpo. Plataforma estável em nucleoia.vitormr.dev.

---

## Situação Actual

A plataforma está tecnicamente sólida mas **não mede o que importa**. Temos:
- PostHog integrado com 2 dashboards e 5 chart types nativos
- posthog-proxy EF v2 com Query API
- MCP usage logging funcional (mcp_usage_log)
- Adoption dashboard com auth providers + designation filter

**O que falta:** instrumentação granular de features. Sabemos quantos pageviews temos, mas não sabemos se alguém criou um card, moveu um card, viu um webinar, leu um blog post, ou emitiu um certificado. Sem isso, o report para sponsors e a demo para Mario Trentim (3/Abr) carecem de dados concretos de uso.

---

## 3 Specs Necessárias (Sprint 4)

### SPEC 1: S3.3 — Custom PostHog Events (P1, ~3-4h Code)

**Objectivo:** Instrumentar 8 acções-chave na plataforma para que o PostHog capture eventos de negócio, não apenas pageviews.

**Eventos a instrumentar:**

| Evento | Trigger | Propriedades | Persona afectada |
|--------|---------|-------------|-----------------|
| `board_card_created` | Após create via RPC | board_id, tribe_id, tags | Líder, GP |
| `board_card_moved` | Após move via RPC | card_id, from_status, to_status | Líder, GP |
| `webinar_viewed` | Click em card/link de webinar | webinar_id, status, chapter | Todos |
| `blog_post_read` | Scroll >50% ou tempo >30s no post | post_slug, reading_time | Público |
| `profile_updated` | Após salvar perfil | fields_changed[] | Pesquisador |
| `mcp_tool_called` | Já logado no mcp_usage_log, expor para PostHog | tool_name, success | GP, Líder |
| `certificate_issued` | Após emissão | cert_type, member_role | Admin |
| `governance_cr_submitted` | Após submit CR | cr_type, impact_level | Admin |

**Padrão de implementação esperado:**
```typescript
// Client-side (onde PostHog JS SDK está disponível)
posthog.capture('board_card_created', { board_id, tribe_id, tags });

// Server-side (RPCs que não têm PostHog) — opção: EF ou pg_notify
```

**Decisões que o spec deve tomar:**
1. Client-side capture (no componente React/Astro) vs server-side (via EF)?
2. Como conectar mcp_usage_log → PostHog sem duplicar dados?
3. Blog scroll tracking: intersection observer vs tempo na página?
4. O posthog-proxy deve expor estes eventos ou são client-side only?

**Verificação esperada:**
- Após implementação, cada evento aparece no PostHog Events explorer
- Dashboard "Adoption & Engagement" ganha insights baseados nestes eventos
- Annotation automática quando milestones são atingidos (e.g., 100º card criado)

---

### SPEC 2: S3.2 — Designation/Tier Filter Everywhere (P1, ~2-3h Code)

**Objectivo:** O filtro por papel/designação já funciona em `/admin/adoption`. Expandir para `/admin/members`, `/admin/attendance`, e `/teams`.

**Contexto:** O Núcleo tem 10 operational_roles e 7 designations. GPs e liaisons precisam filtrar rapidamente por tipo de membro para acções operacionais (e.g., "mostrar só os tribe_leaders", "mostrar só os sponsors sem login").

**O que já existe:**
- Dropdown funcional em `/admin/adoption` com seções "Papel" e "Designação"
- `members.designations text[]` disponível em todas as queries
- `members.operational_role` disponível

**O que precisa:**
1. `/admin/members` — adicionar dropdown igual ao do adoption (acima da tabela de membros)
2. `/teams` — adicionar filtro por papel/designação (página pública, mas filtro só para autenticados)
3. `/admin/attendance` → AttendanceGridTab — filtro por papel no header (ex: "mostrar só pesquisadores")

**Padrão:** Copiar exactamente o dropdown do adoption (client-side filter, sem nova RPC). Os dados já vêm com `designations` e `operational_role`.

**Decisão:** O filtro no AttendanceGridTab deve ser client-side (filtrar rows já carregadas) ou server-side (novo parâmetro no RPC `get_attendance_grid`)?

---

### SPEC 3: GC-097 Phase 2 — Scripted Smoke Test (P1, ~2h Code)

**Objectivo:** Automatizar a verificação pós-deploy com um script executável que testa todos os endpoints críticos.

**Contexto:** O smoke-test actual (`scripts/smoke-routes.mjs`) testa apenas se rotas retornam HTML. Falta verificar:
- OAuth flow endpoints (register, authorize, .well-known)
- MCP proxy (401 + WWW-Authenticate)
- PostHog proxy
- Edge Function health
- Supabase RPC availability (pelo menos get_public_leaderboard)
- Redirect de domínios legados

**O que o script deve testar:**

```
✅ Site: nucleoia.vitormr.dev → 200
✅ Legacy redirect: workers.dev → 301 → nucleoia.vitormr.dev
✅ OAuth register: POST → 201 + client_id
✅ OAuth authorize: GET → 302 → consent
✅ OAuth discovery: .well-known → JSON com issuer correcto
✅ MCP: POST → 401 + WWW-Authenticate header
✅ EF health: nucleo-mcp/health → {"status":"ok","version":"2.2.1","tools":23}
✅ Public RPC: get_public_leaderboard → rows
✅ PostHog proxy: ?endpoint=dashboards → 403 (sem auth) ou 200 (com auth)
✅ i18n: ?lang=en-US → lang="en" no HTML
```

**Decisões:**
1. Shell script (bash + curl) vs Node.js (com asserts)?
2. Deve correr no CI (GitHub Actions) ou só local?
3. Precisa de auth token para testar endpoints protegidos?

---

## Contexto para Todas as 3 Specs

### Personas e cobertura actual

| Persona | Count | Precisa de | Sprint 4 impacta? |
|---|---|---|---|
| Pesquisador | 32 | Ver uso próprio, perfil completo | ✅ profile_updated event, filter |
| Líder de Tribo | 7 | Board analytics, attendance filter | ✅ board events, designation filter |
| Comms | 3 | Blog engagement metrics | ✅ blog_post_read event |
| GP | 2 | Visão consolidada, demo para Mario | ✅ Todos os eventos + smoke test |
| Sponsor | 5 | Report com dados reais | ✅ PostHog events alimentam dashboards |
| Chapter Liaison | 3 | Filtrar membros do capítulo | ✅ Designation filter |

### Princípios Amazon relevantes

- **Customer Obsession:** Os 32 pesquisadores e 7 líderes são os clientes primários. As instrumentações medem se eles estão realmente a beneficiar da plataforma.
- **Insist on the Highest Standards:** O smoke test garante que cada deploy mantém a qualidade. Zero regressões.
- **Bias for Action:** Todos os 3 specs são executáveis sem blockers externos. Não dependem do Ivan, dos sponsors, ou do MCP connector.
- **Deliver Results:** A demo para Mario (3/Abr) precisa de dados concretos. PostHog events são o caminho.

### Decisões já tomadas (não mudar)

1. PostHog SDK já está no frontend (client-side capture funciona)
2. posthog-proxy EF está deployed com Query API
3. MCP usage logging é separado (mcp_usage_log table) — não duplicar no PostHog
4. Designation filter pattern já existe no adoption page — copiar, não reinventar
5. Custom domain nucleoia.vitormr.dev é final — todos os URLs usam este

### O que NÃO incluir nestas specs

- MCP P3 tools (Sprint 5)
- Frontend parity gaps F1-F5 (Sprint 4-5, specs separadas)
- Sponsor auth onboarding (blocker externo)
- Pre-onboarding gamification (Sprint 5+)

---

## Formato de Spec Esperado

Cada spec deve ter:
1. **SQL Migration** (se aplicável) — código pronto, não pseudocódigo
2. **Frontend changes** — path de arquivo exacto, código TypeScript/JSX
3. **Verification checklist** — queries SQL e curl commands
4. **Execution order** — sequência explícita
5. **i18n keys** (se aplicável) — nos 3 locales
6. **Estimated effort** — para o Code executar

O Code executa specs na ordem que o Product Leader define. Cada spec gera 1 commit + 1 deploy.

---

## Timeline

| Data | Milestone |
|---|---|
| 29/Mar | Brief enviado ao Chat Claude |
| 30-31/Mar | Specs produzidas e validadas |
| 1-2/Abr | Code implementa Sprint 4 |
| 3/Abr 10:00 ET | Demo Mario Trentim (com dados reais de PostHog) |
