# DEBUG_HOLISTIC_PLAYBOOK.md

Guia holístico de debugging e troubleshooting para o **AI & PM Research Hub**. Use este documento como referência ao diagnosticar bugs e alinhar correções com a arquitetura do projeto.

---

## Princípios de debugging

1. **Isolar o layer**: O problema está no frontend (Astro/JS), no backend (Edge Function/RPC), na RLS, no dado ou na integração?
2. **Reproduzir primeiro**: Em qual ambiente (local/produção)? Com qual usuário/perfil? Passos exatos.
3. **Não assumir**: Confirmar estado real do banco, sessão e rede antes de mudar código.

---

## Checklist por camada

### Frontend (Astro + Vanilla JS)

| Sintoma | Possíveis causas | Ações |
|---------|------------------|-------|
| Página em branco ou erro 500 no build | Falha SSR (dados opcionais ausentes) | Adicionar guard: `deliverables ?? []`, `?.map()` ou checagem antes de iteração. Ver `TribesSection.astro` como referência. |
| "Carregando..." infinito | Query sem timeout; erro não tratado | Usar `withTimeout` (ex.: gamification) + `try/catch` com fallback de UI. Mensagem explícita no estado de erro. |
| Toast/erro genérico "Erro desconhecido" | Edge Function retornou erro mal formatado | Usar `describeFnError(err)` para extrair `payload.error` ou `err.message`. Já usado em profile e gamification. |
| Erro 400 recorrente em curadoria de artifacts | `p_id` inválido/ausente em RPC (`curate_item`) | Validar `artifactId` antes da chamada RPC, abortar cedo e exibir mensagem amigável; tratar explicitamente `invalid input syntax for type uuid` no catch. |
| Dados de membro incorretos (papel, tribo, ciclo) | Leitura de `role`/`roles` ou `members` como fonte de histórico | Usar `operational_role`, `designations` e `member_cycle_history`. Ver `docs/MIGRATION.md`. |
| Credly URL não aceita no mobile | Paste com trailing slash, query params ou encoding | Usar `normalizeCredlyUrl` de `src/lib/credly.js`; já faz trim e normalização. Testar em iOS Safari/Chrome. |
| Evento inline não funciona / XSS suspeito | Uso de `onclick="funcao('${var}')"` | Migrar para Event Delegation: `document.addEventListener` + `data-*` nos elementos. Ex.: admin `openAllocate`, `toggleAnnouncement`, `deleteAnnouncement`. Ver `.cursorrules`. |
| Conteúdo injetado de forma insegura | `innerHTML` com dados do banco | Preferir `textContent` ou escape/sanitização. Nunca injetar email, nome ou URLs de usuário em `innerHTML` sem sanitizar. |
| Estilos quebrados ou inconsistentes | CSS isolado fora do Tailwind | Usar exclusivamente classes utilitárias Tailwind. Exceção: animações globais complexas em `src/styles/global.css`. |

### Supabase e dados

| Sintoma | Possíveis causas | Ações |
|---------|------------------|-------|
| RLS bloqueia query esperada | Política restritiva; sessão sem `auth.uid()` | Não contornar RLS no frontend. Ajustar política no Supabase; verificar se usuário está autenticado e se `member_id` está alinhado. |
| Ranking/agregação lenta no frontend | `.reduce()` ou loops pesados em muitos registros | Mover para RPC ou Materialized View no Supabase. Ver `.cursorrules` (processamento pesado). |
| Duplicatas em `gamification_points` | `member_id + reason` sem unique constraint ou upsert incorreto | Verificar `verify-credly` e `sync-credly-all`; garantir upsert com dedup. Rodar audit: `docs/migrations/` (ex.: Credly dedup). |
| Trilha vs Gamificação dessincronizados | `course_progress` vs `gamification_points` desalinhados | `sync-credly-all` já faz reconciliação. Se persistir, checar `legacy_trail_synced` no relatório e validar `course_progress` por membro. |
| Pontos Credly errados (10 em vez de 50) | Badge Tier 1 com pontuação legada | Backend já corrigido. Se houver linhas antigas, rodar SQL de sanitização (ver `docs/RELEASE_LOG.md` Credly Legacy Sanitization). |
| Histórico de ciclo vazio ou incorreto | Dados em `members` em vez de `member_cycle_history` | Timeline e relatórios devem ler de `member_cycle_history`. Garantir que writes de ciclo usem a tabela de histórico. |
| Hard delete acidental | `DELETE` ou `DROP` em dados operacionais | Governança exige soft delete. Usar `is_active = false` ou equivalente. Ver `.cursorrules`. |

### Edge Functions

| Sintoma | Possíveis causas | Ações |
|---------|------------------|-------|
| `invoke` retorna 401/403 | Secret não configurado; token expirado | Verificar `SYNC_COMMS_METRICS_SECRET`, `Authorization: Bearer <session.access_token>`. Refresh session antes de chamar. |
| Invoke retorna erro genérico | CORS; corpo da resposta mal formatado | Edge Function deve retornar `corsHeaders` na resposta. Usar `_shared/cors.ts` se disponível. |
| Credly não encontra badges | URL inválida; API Credly fora do ar | Validar URL com `normalizeCredlyUrl`; checar tier keywords em `verify-credly/index.ts`. |
| sync-credly-all parcial | Alguns membros falham | Relatório retorna `success_count`, `fail_count`, `total_candidates`. Investigar membros sem `credly_url` ou com URL inválida. |

### Rotas e deploy

| Sintoma | Possíveis causas | Ações |
|---------|------------------|-------|
| `/teams`, `/rank`, `/ranks` quebrados | Aliases removidos ou incorretos | Manter redirects conforme `docs/GOVERNANCE_CHANGELOG.md`. Smoke: `npm run smoke:routes`. |
| SPA fallback não funciona | Cloudflare Workers config | Verificar `public/_redirects` para SPA mode. |
| Build local OK, deploy falha | Env vars; diferença Node/Deno | Comparar `.env` local vs secrets no Cloudflare/Supabase. Checar logs do deploy. |

---

## Fluxo sistemático de debug

1. **Reproduzir** — Ambiente, usuário, passos.
2. **Console / Network** — Erros no console? Status HTTP das chamadas? Resposta JSON das Edge Functions?
3. **Dados** — Estado no Supabase (tabelas `members`, `member_cycle_history`, `gamification_points`, `course_progress`) para o membro/contexto afetado.
4. **RLS** — O usuário tem perfil em `members`? `auth.uid()` corresponde ao esperado? Políticas aplicáveis?
5. **Corrigir** — Uma mudança por vez; validar com `npm test` e `npm run build`; atualizar `docs/RELEASE_LOG.md` se afetar produção.

---

## Scripts úteis

```bash
npm test                    # Testes unitários
npm run build               # Build de produção
npm run smoke:routes        # Smoke de rotas (inicia servidor, testa, encerra)
npm run dev -- --host 0.0.0.0 --port 4321   # Dev local
```

---

## Documentos de apoio

- `AGENTS.md` — Contexto do projeto e convenções
- `docs/GOVERNANCE_CHANGELOG.md` — Decisões de governança
- `docs/MIGRATION.md` — Estado de migração (roles, Credly, analytics)
- `docs/RELEASE_LOG.md` — Histórico de releases e hotfixes
- `.cursorrules` — Regras de arquitetura e frontend

---

## Atualização

Este playbook deve ser mantido alinhado com os hotfixes documentados em `docs/RELEASE_LOG.md` e com as regras em `.cursorrules`. Ao corrigir um bug recorrente, considere adicionar ou ajustar uma linha no checklist correspondente.
