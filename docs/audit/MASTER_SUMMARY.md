# W139 — Platform Integrity Audit: Master Summary

**Data:** 2026-03-14
**Autor:** Vitor Rodovalho (via Claude Code)
**Escopo:** Auditoria completa pre-Beta — rotas, RPCs, tabelas, navegação, facades
**Branch:** `main` (read-only audit)

---

## 1. Estatísticas da Plataforma

| Métrica | Valor |
|---------|-------|
| **Rotas únicas** | 42 (excl. redirects e i18n variants) |
| **Rotas públicas** | 11 |
| **Rotas autenticadas (membro)** | 11 |
| **Rotas admin** | 20 |
| **Redirects** | 3 (rank→gamification, admin/help→help) |
| **Variantes i18n** | 18 (en/es meta-refresh redirects) |
| | |
| **RPCs chamados pelo frontend** | 117 |
| **Funções no DB (schema public)** | 263 |
| **RPCs chamados que NÃO existem no DB** | **0** ✅ |
| **Funções no DB sem chamada frontend** | 89 (maioria triggers/helpers/pipeline) |
| | |
| **Tabelas (base)** | 74 |
| **Views** | 9 |
| **Materialized views** | 1 (cycle_tribe_dim) |
| **Tabelas referenciadas pelo frontend** | 38 |
| | |
| **Edge Functions (codebase)** | 14 |
| **Edge Functions usadas pelo frontend** | 9 |
| **Edge Functions backend-only** | 5 (cron/webhook) |
| | |
| **Componentes React com Supabase** | 13 |
| **Dead links na navegação** | **0** ✅ |
| **Referências a colunas dropadas** | **0** ✅ |

---

## 2. Status Consolidado

| Status | Quantidade | Percentual |
|--------|-----------|------------|
| ✅ Totalmente funcional | 37 | 88% |
| ⚠️ Parcialmente funcional | 4 | 10% |
| ❌ Não-funcional/Erro | 0 | 0% |
| 🔀 Redirect | 3 | — |

**Conclusão: A plataforma está em estado sólido para Beta.** Não há páginas completamente quebradas.

---

## 3. Achados Críticos — Ação Necessária

### P0 — Beta Blockers (0 encontrados)

**Nenhum blocker encontrado.** Todos os RPCs chamados pelo frontend existem no DB. Não há referências a colunas dropadas. Todas as rotas na navegação apontam para páginas existentes.

### P1 — Misleading / Falha Silenciosa (2 encontrados)

| # | Achado | Impacto | Ação |
|---|--------|---------|------|
| **F-01** | View `active_members` não existe no DB | `workspace.astro:309` e `AttendanceForm.tsx:95` fazem query que retorna null silenciosamente. **Tribe member count no workspace será 0. Lista de membros no form de attendance estará vazia.** | Criar view: `CREATE VIEW active_members AS SELECT id, name, email, tribe_id, operational_role, designations, chapter, photo_url FROM members WHERE is_active = true AND current_cycle_active = true;` |
| **F-02** | Tabela `publication_submission_events` não existe | `PublicationsBoardIsland.tsx:200` faz query que falha silenciosamente. **Dados de submissão de publicações (external_link, published_at) não aparecem.** | Criar tabela ou remover query do componente |

### P2 — Cosmético / Funcionalidade Incompleta (3 encontrados)

| # | Achado | Impacto | Ação |
|---|--------|---------|------|
| **F-03** | `/admin/sustainability` é mockup puro | 4 cards com status "Planning" hardcoded, zero RPCs, zero tabelas. **Não impacta Beta** (acesso restrito a admin + designations). | Manter como placeholder; criar backend quando priorizado |
| **F-04** | `/projects` — botão "Register Pilot" sem handler | Botão `btn-register-pilot` existe no HTML mas nenhum `addEventListener` o vincula. **Só visível para GP/DM.** | Adicionar handler ou esconder botão |
| **F-05** | `/admin/board/[id]` e `/admin/member/[id]` — páginas órfãs | Existem como rotas válidas mas **nenhum link interno aponta para elas**. Inacessíveis exceto por URL direta. | Adicionar links na UI admin ou remover se não planejadas |

### P3 — Technical Debt (3 categorias)

| # | Achado | Escala | Ação |
|---|--------|--------|------|
| **F-06** | 89 funções DB sem chamada frontend | 42 são ingestion pipeline (legítimo), ~16 são candidatas a UI futura, 5 são deprecated, ~26 são triggers/helpers | Manter. Baixa prioridade. Fazer cleanup de deprecated em sprint dedicada |
| **F-07** | 5 Edge Functions sem referência frontend | `send-notification-digest`, `send-tribe-broadcast`, `sync-comms-metrics`, `sync-knowledge-insights`, `sync-knowledge-social-content` | Legítimo — são cron/webhook-triggered. Documentar |
| **F-08** | `/admin/comms` — tokens de API null | Canais configurados (YouTube, LinkedIn, Instagram) mas `oauth_token` = null em todos. Dados seed existem (5 métricas manuais). | Não é facade — é feature com sync automático desabilitado. Funciona com dados manuais. Configurar tokens quando contas sociais estiverem prontas |

---

## 4. RPCs Quebrados

**NENHUM.** Todos os 117 RPCs chamados pelo frontend existem no schema público do Supabase.

---

## 5. Funções DB Órfãs (selecção relevante)

| Função | Categoria | Recomendação |
|--------|-----------|-------------|
| `comms_metrics_latest` | Deprecated (replaced by `_by_channel`) | Drop em cleanup sprint |
| `exec_funnel_v2` | Deprecated (replaced by `exec_funnel_summary`) | Drop em cleanup sprint |
| `kpi_summary` | Deprecated (replaced by `exec_portfolio_health`) | Drop em cleanup sprint |
| `move_board_item_to_board` | Duplicata de `move_item_to_board` | Drop em cleanup sprint |
| `finalize_decisions` | Legacy seletivo v1 | Drop em cleanup sprint |
| `admin_get_member_details` | Candidata a UI `/admin/member/[id]` | Manter para uso futuro |
| `mark_interview_status` | Candidata a UI `/admin/selection` | Manter — usado internamente |
| `submit_interview_scores` | Candidata a UI `/admin/selection` | Manter — usado internamente |
| `knowledge_*` (5 funções) | Backend pipeline | Manter — sem UI planejada |

Ver `docs/audit/RPC_INVENTORY.md` para lista completa.

---

## 6. Dead Navigation Links

**NENHUM.** Todas as 30 rotas registradas em `navigation.config.ts` e `AdminNav.astro` apontam para arquivos `.astro` existentes.

---

## 7. Páginas Órfãs (sem link de navegação)

| Página | Acessível Via | Órfão Real? |
|--------|--------------|------------|
| `/about` | Link em `/help` | Não |
| `/admin/board/[id]` | **Nenhum link encontrado** | ⚠️ Sim |
| `/admin/member/[id]` | **Nenhum link encontrado** | ⚠️ Sim |
| `/admin/webinars` | Link em `/admin/comms` | Não |
| `/privacy` | Footer do BaseLayout | Não |
| `/teams` | Links em `/workspace` e `/publications` | Não |

---

## 8. Colunas Legadas

**ZERO** referências a `members.role` (dropada) em funções DB ou código frontend.

Colunas `role` existentes (todas legítimas):
- `board_item_assignments.role` (author, reviewer, contributor)
- `member_attendance_summary.role` (computed via `compute_legacy_role()`)
- `project_memberships.role` (membro de projeto)
- `selection_committee.role` (lead, member, observer)

---

## 9. Facades Classificadas

| Rota | Tipo de Facade | Impacto | Esforço |
|------|---------------|---------|---------|
| `/admin/sustainability` | Página completa — zero backend | BAIXO | Médio |
| `/projects` | Botão único sem handler | BAIXO | Pequeno |
| `/workspace` | View `active_members` inexistente → count=0 | MÉDIO | Pequeno (criar view) |
| `/publications` | Tabela `publication_submission_events` inexistente | BAIXO | Pequeno |

**Nota importante:** `/admin/comms` **NÃO é facade** — tem 8 RPCs funcionais e dados reais no DB.

---

## 10. Plano de Fix Priorizado

### Antes do Beta Send (P0+P1)

| # | Fix | Esforço | Detalhes |
|---|-----|---------|----------|
| F-01 | Criar view `active_members` | 5 min | SQL migration simples |
| F-02 | Criar tabela `publication_submission_events` | 10 min | SQL migration |

### Primeira Semana Pós-Beta (P2)

| # | Fix | Esforço |
|---|-----|---------|
| F-04 | Handler para botão "Register Pilot" em `/projects` | 30 min |
| F-05 | Decidir destino de páginas órfãs (`/admin/board/[id]`, `/admin/member/[id]`) | Decisão GP |

### Backlog (P3)

| # | Fix | Esforço |
|---|-----|---------|
| F-03 | Backend para `/admin/sustainability` (quando priorizado) | 1-2 sprints |
| F-06 | Cleanup de funções deprecated no DB | 1 sprint |
| F-07 | Documentar Edge Functions backend-only | 30 min |
| F-08 | Configurar tokens de API social em `/admin/comms` | Dependência externa |

---

## 11. Decisões para o GP

1. **`/admin/board/[id]` e `/admin/member/[id]`** — Manter como páginas de acesso direto (URL), linkar da UI admin, ou remover?
2. **`/admin/sustainability`** — Manter como placeholder visível ou esconder da navegação até ter backend?
3. **View `active_members`** — Confirma criação da view simples `WHERE is_active = true AND current_cycle_active = true`?
4. **5 funções deprecated** — Autoriza drop em sprint de cleanup? (`comms_metrics_latest`, `exec_funnel_v2`, `kpi_summary`, `move_board_item_to_board`, `finalize_decisions`)

---

## 12. Edge Functions — Inventário

### Referenciadas pelo Frontend (9)

| Edge Function | Chamada De | Propósito |
|--------------|-----------|-----------|
| `import-calendar-legacy` | `admin/index.astro:2611` | Importação de calendário legacy |
| `import-trello-legacy` | `admin/index.astro:2560` | Importação de Trello legacy |
| `send-allocation-notify` | `admin/index.astro:1729,1780` | Notificação de alocação de tribos |
| `send-campaign` | `admin/campaigns.astro:463` | Entrega de emails de campanha via Resend |
| `send-global-onboarding` | `admin/index.astro:3945` | Email de onboarding global |
| `sync-attendance-points` | `gamification.astro:1047` | Sync de pontos de presença |
| `sync-credly-all` | `gamification.astro:1069` | Sync de certificações Credly |
| `verify-credly` | `profile.astro:1197` | Verificação de badge Credly |

### Backend-Only / Cron (5)

| Edge Function | Propósito |
|--------------|-----------|
| `send-notification-digest` | Digest de notificações (cron) |
| `send-tribe-broadcast` | Broadcast para tribo (usado em `tribe/[id].astro:1221`) |
| `sync-comms-metrics` | Sync de métricas sociais (cron) |
| `sync-knowledge-insights` | Sync de insights de conhecimento (cron) |
| `sync-knowledge-social-content` | Sync de conteúdo social (cron) |

**Nota:** `send-tribe-broadcast` É referenciado por `tribe/[id].astro` — não é puramente backend-only.

---

## Arquivos de Referência

- `docs/audit/ROUTE_INVENTORY.md` — Inventário detalhado de todas as rotas com status
- `docs/audit/RPC_INVENTORY.md` — Inventário de RPCs e funções DB
- `docs/audit/TABLE_INVENTORY.md` — Inventário de tabelas e views com row counts
- `docs/audit/DEPENDENCY_MAP.md` — Mapa de dependências por rota (gerado separadamente)

---

*GC-039: W139 Platform Integrity Audit — 42 rotas auditadas, 0 RPCs quebrados, 0 dead links, 0 referências a colunas dropadas. 2 falhas silenciosas identificadas (P1: views/tabelas inexistentes), 3 facades documentadas (P2). Plataforma pronta para Beta.*
