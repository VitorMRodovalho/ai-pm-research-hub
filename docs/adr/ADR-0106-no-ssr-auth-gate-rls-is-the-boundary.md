# ADR-0106 — Sem auth-gate SSR: RLS + SECURITY DEFINER + capability gate client-side é a fronteira

**Status:** Accepted (2026-06-24, #856)
**Relacionado:** ADR-0011 (V4 auth — `can()` é a fonte de verdade), ADR-0003 (`/admin/analytics` read-only), ADR-0018 (MCP threat model), #855 (security headers SSR), #670 (chapter_liaison narrow).

## Contexto

O repositório tinha um middleware de auth-gate SSR em `src/middleware/index.ts` (criado 2026-03-05): redirect HTTP de anônimos em `/admin`, `/workspace`, `/profile` + checagem de role admin. **O Astro carrega UM único módulo de middleware.** Quando `src/middleware.ts` (redirect canônico + CSRF) foi criado em 2026-03-28, passou a **sombrear** o `index.ts` silenciosamente (sem erro de build). Resultado: o auth-gate **nunca rodou em produção por ~3 meses**. Evidência ao vivo (2026-06-24): `curl /admin`, `/workspace`, `/profile` sem auth → HTTP 200 (um gate vivo daria 302 → `/?auth=required`). Efeito colateral: o fix #670 editou o arquivo morto e nunca aplicou; seu teste de contrato lia o morto (cobertura falsa).

A pergunta era: **ressuscitar** o gate (migrar para o `.ts` vivo) ou **aposentá-lo**?

Auditoria de evidência (workflow multi-agente, 2026-06-24, com verificação adversarial independente) varreu as 52 páginas `src/pages/admin/**` + `workspace.astro` + `profile.astro` + `AdminLayout.astro`:

- **Zero** páginas protegidas fazem fetch autenticado/PII no frontmatter SSR. A única que faz fetch server-side (`analytics.astro`) usa client **anon** explícito chamando `get_active_chapters()` — registro **público** de capítulos PMI (já hardcoded como fallback em `src/lib/chapters.ts`), não PII.
- Todo dado é buscado **client-side** pelos islands React, depois que a sessão Supabase do usuário existe, gateado por **RLS + RPCs SECURITY DEFINER**. Um anônimo recebe um shell HTML vazio, sem dados.
- O frontmatter SSR do Astro **não** tem acesso à sessão Supabase do usuário (a sessão vive no localStorage client-side; o cookie `sb-access-token` só era lido pelo middleware, não injetado nos clients das páginas).

Conclusão dura: o auth-gate SSR **provadamente não protegia dado nenhum**. A fronteira real sempre foi RLS + SECURITY DEFINER + capability gate client-side (`canFor()`, ADR-0011) — e essa fronteira roda com ou sem o gate.

## Decisão

**Aposentar o auth-gate SSR.** Não há gate de auth em middleware SSR por design.

1. `src/middleware/index.ts` (morto) foi removido. O middleware vivo (`src/middleware.ts`) cuida de: redirect de domínio canônico, CSRF manual e security headers SSR (#855) — **nenhuma** lógica de auth-gate.
2. A fronteira de autorização é declarada oficialmente: **RLS + RPCs SECURITY DEFINER + capability gate client-side (`canFor()` / `get_caller_capabilities`)**. Anon/ghost não obtém nada de tabelas PII (GC-162). Role authorization vive em `can()` (ADR-0011) e no allowlist de capabilities (`src/lib/permissions.ts`), nunca em middleware. Este modelo **já era o vigente e testado**: `scripts/smoke-routes.mjs` afirma que rotas `/admin/*` retornam **200** para anônimo E contêm um marcador client-side `id="*-denied"` (ex.: `sel-denied`, `analytics-denied`) que o JS exibe quando falta permissão — i.e., o "deny" sempre foi client-side, não no middleware (que estava morto). Aposentar o arquivo morto não muda comportamento.
3. **Guard anti-shadow permanente** (`tests/contracts/856-auth-gate-retired-shadow-guard.test.mjs`): falha o build/test se `src/middleware/index.ts` reaparecer enquanto `src/middleware.ts` existe — foi a causa-raiz da #855 e da #856.
4. **Backstop de frontmatter** (mesmo teste): nenhuma página `.astro` sob `src/pages/admin/**` pode estabelecer um contexto Supabase **autenticado** no frontmatter SSR (sem service-role key, sem ler o cookie `sb-access-token` num client). Fetch anon de dado público (padrão `analytics.astro`) é permitido. Isso preserva o invariante "shell SSR não carrega dado sensível" sem custo de runtime.
5. O teste do #670 foi repontado do middleware morto para o invariante real em `src/lib/permissions.ts`: os capability sets de `chapter_liaison` (tier e designation) **excluem** `admin.access` (o "admin-shell entry ticket") e contêm apenas o allowlist read-only — visibilidade, nunca o shell admin inteiro.

## Consequências

- **Custo de runtime zero** e **zero risco de lockout** (o gate ressuscitado teria friction de cold-deep-link por causa do cookie client-side de 1h, que renova só com aba aberta — ver análise em #856).
- Remove código morto + teste de cobertura falsa (pagamento de dívida).
- **Trade-off aceito:** os shells HTML de `/admin/*`, `/workspace`, `/profile` continuam retornando 200 para anônimos (info-disclosure cosmético do mapa de rotas / assinaturas de RPC já presentes no bundle client servido a qualquer logado). **Não é vazamento de dado** — RLS bloqueia os RPCs. `noindex,nofollow` em `/admin` já vai pro ar via `src/middleware.ts` (#855/#858), suprimindo crawlers.
- **Postura LGPD (Art. 46):** a medida técnica de proteção de PII é RLS + SECURITY DEFINER (camada de dados), documentada e testada — não a camada de rota. Defensável: o shell sem dado não expõe titular.
- Se um dia uma página precisar fazer fetch autenticado no SSR, o backstop test falha primeiro e força revisita desta decisão (ressuscitar um gate aí passa a ter valor real).
