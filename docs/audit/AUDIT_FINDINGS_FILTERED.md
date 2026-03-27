# Auditoria de Plataforma — Achados Filtrados
## AI & PM Research Hub — 18/Mar/2026

> **Contexto:** Auditoria de 4 camadas (Security, UX, Governance, Institutional Value) executada por leitura estática.
> **Filtro aplicado:** Severidades recalibradas pelo modelo de ameaça real do projeto (52 membros, voluntários, RLS Supabase como camada primária, zero-cost architecture).
> **Originais:** 5 relatórios brutos arquivados em `docs/audit/archive/` (não representam severidade real).

---

## Achados Confirmados (12 itens)

### P0 — Correção Imediata

| # | Achado | Origem | Esforço | GC |
|---|--------|--------|---------|-----|
| B1 | RPC `get_member_detail` referencia `gl.total_xp` e `gl.rank` que não existem na view refatorada (W143). Admin member detail quebra silenciosamente. | L2-2.1 | 30min | GC-088 |
| B2a | `.nvmrc` ausente — builds podem variar entre ambientes (local Node 24 vs Cloudflare 22) | L1-DT06 | 5min | GC-088 |
| B2b | CodeQL workflow com `upload: false` — alertas de segurança não aparecem no GitHub Security tab | L3-G1 | 10min | GC-088 |
| B2c | `release-tag.yml` não verifica se CI passou antes de criar tag | L3-G2 | 15min | GC-088 |

### P1 — Esta Sprint

| # | Achado | Origem | Esforço | GC |
|---|--------|--------|---------|-----|
| B3 | RPCs `SECURITY DEFINER` sem `SET search_path = public, pg_temp`. Risco baixo em single-schema mas boa higiene preventiva. | L1-DT07 | 1h | GC-089 |
| B4 | Middleware SSR desabilitado para `/admin/*`. RLS protege dados reais, mas shell HTML é servido a não-autenticados. Defesa em profundidade faltando. | L1-DT01 | 3h | GC-089 |
| B5 | Sem CSP/HSTS/X-Frame-Options headers. Scripts de terceiros (PostHog, Sentry) carregam sem restrição de origem. | L1-DT04 | 1h | GC-089 |

### P2 — Próxima Sprint

| # | Achado | Origem | Esforço | GC |
|---|--------|--------|---------|-----|
| B6 | ~15 componentes React com cores Tailwind hardcoded sem variantes `dark:` (boards, dashboards, diversity) | L2-3.2 | 3h | — |
| B7 | `board_sla_config` com 0 rows — SLAs do BoardEngine nunca ativados | L4-1.4 | 30min | — |
| B8 | 91% dos board_items sem assignee (legado Trello). Bulk-assign tribe leaders como default. | L4-1.4 | 1h | — |
| B9 | 37+ strings hardcoded em PT-BR em componentes React (TribeDashboard, ReportPage, CuratorshipBoard, Nav) | L2-3.1 | 4h | — |

### P3 — Backlog

| # | Achado | Origem | Esforço | GC |
|---|--------|--------|---------|-----|
| B10 | `navSimulatedTier` acessível em prod via console. Não bypassa RLS, apenas UI. Remover em production builds. | L1-DT03 | 30min | — |
| B11 | Sem `CODEOWNERS` para paths críticos (`src/lib/`, `supabase/`, `.github/`) | L3-G4 | 15min | — |
| B12 | Sem archival automático de cards estagnados no BoardEngine (backlog > 90 dias) | L4-1.4 | 2h | — |

---

## Achados Descartados (com justificativa)

| Achado Original | Severidade Alegada | Por que descartado |
|----------------|-------------------|-------------------|
| "Portas destrancadas" — admin acessível | 🔴 Crítica | RLS Supabase é barreira real. Shell HTML sem dados é inofensivo. Reclassificado como P1 (defense-in-depth). |
| 10 membros "em limbo" sem tribo | 🔴 Crítica | Maioria são papéis cross-tribo por design (GP, Deputy, Curadores, Comms). Feature, não bug. |
| localStorage onboarding como vulnerabilidade | 🔴 Crítica | Atende 5-10 novos membros/ciclo. Tabela server-side existe para uso futuro. Over-engineering migrar agora. |
| `navSimulatedTier` como bypass de segurança | 🟠 Alta | Frontend-only. Não bypassa nenhuma RPC/RLS. Reclassificado como P3. |
| pgvector / RAG "manco" | 🔴 Crítica | Fundação para Ciclo 3+. 1 asset ingerido. Ativar embeddings sem volume de conteúdo é desperdício. |
| ~~Astro 5→6 como "bloqueante para P3"~~ | ✅ Concluído | Migração concluída (GC-133, 2026-03-28). Astro 6 + Workers SSR em produção. |
| `consent_log` como P0 LGPD | 🔴 Alta | Voluntários assinaram termo (step 5 onboarding). Consent tracking formal é Ciclo 4+. |
| ROPA / DPO como obrigatórios | 🟡 Média | Relevante quando houver parceria institucional. Não agora. |
| `assignee_id` obrigatório na criação | P0 | Quebraria workflow de importação sem benefício imediato. Reclassificado como P2 (bulk-assign legado). |

---

## Lições Aprendidas

1. **RPC refactor → validar downstream.** Quando views são refatoradas, todas as RPCs e components que as consomem devem ser atualizados no mesmo commit. Checklist: "quais RPCs/components referenciam esta view/tabela?"

2. **EF deploy flags são estado, não código.** O `--no-verify-jwt` é configuração de deploy que não fica no source. Documentar por EF qual flag usar (ver EF inventory no transition doc).

3. **Auditorias automatizadas inflam severidade.** Calibrar sempre pelo modelo de ameaça real: quem são os usuários, qual é a camada primária de segurança, qual é o volume.

4. **Defense-in-depth ≠ tudo é critical.** Middleware SSR é desejável como camada extra, mas o Supabase RLS é a barreira real. Ausência de camada extra ≠ sistema aberto.

5. **Spec-first permanece.** Não executar prompts monolíticos que alteram 3+ subsistemas. Uma spec, uma execução, uma verificação.

---

*Gerado em 19/Mar/2026. Substitui os 5 relatórios brutos em `docs/audit/archive/`.*
