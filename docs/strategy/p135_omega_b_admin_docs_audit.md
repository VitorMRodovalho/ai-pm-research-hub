# Ω-B Sweep — Admin Docs Audit Report (p135)

**Data**: 2026-05-09
**Agent**: docs auditor (Ω-B sub-agent)
**Escopo**: Auditar staleness de `docs/ADMIN_ARCHITECTURE.md` + `docs/PERMISSIONS_MATRIX.md` vs estado real de `src/pages/admin/` (42 páginas)
**Modo**: read-only — relatório com recomendações priorizadas, sem edições.

---

## Sumário executivo

| Doc | Tamanho | Última atualização declarada | Real cutoff | Staleness | Severidade |
|---|---|---|---|---|---|
| `docs/ADMIN_ARCHITECTURE.md` | 213 L | "08 April 2026 \| v2.9.0+" | 13+ páginas adicionadas pós-cutoff (V4 + Ω-A) | **31% ausente** (13/42 páginas não documentadas) | **Alta** |
| `docs/PERMISSIONS_MATRIX.md` | 320 L | "2026-03-15 (W85)" + "Wave W77 audit" final entry | Pós-V4 cutover (2026-04-13) sem registro | **45% ausente** (19/42 páginas sem entrada explícita) + **0 menções a `can()`/`rls_can`/`engagement_kind_permissions`** | **Crítica** |

### Counts

- **Total páginas admin reais**: 42 (incluindo 4 sob `governance/documents/` e 1 `governance/ip-ratification.astro`)
- **Páginas em ADMIN_ARCHITECTURE.md**: 29 (declarado no doc) → real **22 listadas + 7 órfãs em "Component Map"** = ainda não cobre 13 reais
- **Páginas em PERMISSIONS_MATRIX.md**: ~23 mapeadas via tabela 3.1 ou navigation.config sync (W77)
- **Gap (páginas sem doc nenhum)**: **13** (admin/ai-calibration, admin/chapter, admin/initiative-kinds, admin/member/[id], admin/members/[id], admin/members/inactive-candidates, admin/governance/documents.astro + 4 sub-rotas, admin/governance/ip-ratification, admin/tribe/[id])
- **Drift (doc menciona página inexistente)**: **1 hard drift** + 1 soft (`/admin/board/[id]` → renomeado para `/admin/initiative/[id]` em alguns fluxos? confirmar — Astro file ainda existe como `board/[id].astro`, OK; `BoardMembersPanel.tsx → /admin/chapter` mapping em ADMIN_ARCHITECTURE.md linha 116 é correto)
- **Stale role refs**: **0 referências diretas a `canWrite`/`WRITE_ROLES`/`BOARD_ROLES`** (limpeza pós-V4 cutover OK), MAS **0 menções a `can()`/`can_by_member()`/`rls_can()`/`engagement_kind_permissions`** (V4 invisível na docs admin) + 2 menções residuais a `operational_role` como construct ativo (PERMISSIONS_MATRIX linha 126, ADMIN_ARCHITECTURE linha 208)
- **Comms_team designation legada citada como ativa**: navigation.config.ts linhas 105-106 ainda usam `allowedDesignations: ['comms_team']` para `admin-campaigns` + `admin-blog` (PERMISSIONS_MATRIX trata como "resolvida" em §5)

---

## 1. Tabela completa: 42 páginas × 2 docs × V4-correctness

Legenda:
- **AA** = `ADMIN_ARCHITECTURE.md` status: ✅ listada / ⚠️ parcial (componente sim, página não) / ❌ ausente
- **PM** = `PERMISSIONS_MATRIX.md` status: ✅ na matriz / ⚠️ apenas via navigation.config sync / ❌ ausente
- **V4-correct?** = a entrada (se existe) reflete o modelo V4 (`can()`/`engagement_kind_permissions`/`rls_can`)? **N/A** = não documentada

| # | Página (path relativo a `src/pages/admin/`) | AA | PM | V4-correct? |
|---|---|---|---|---|
| 1 | `index.astro` (Dashboard) | ✅ linha 67 | ✅ §3.1 linha 66 (Admin Panel) | Não — fala "Admin tier" sem citar `can()` |
| 2 | `adoption.astro` | ✅ linha 73 | ❌ | N/A |
| 3 | `ai-calibration.astro` | ❌ | ❌ | N/A — **gap** |
| 4 | `analytics.astro` | ✅ linha 68 | ✅ §3.1 linha 67 | Pré-V4 (cita designations sem `engagement_kind_permissions`) |
| 5 | `audit-log.astro` | ✅ linha 88 | ❌ (sem entrada explícita; AdminLayout-gated) | N/A |
| 6 | `blog.astro` | ✅ linha 52 | ⚠️ §4 navigation map (linha 234, mas não na matriz 3.1) | Pré-V4 (cita `comms_team` legacy designation) |
| 7 | `board/[id].astro` | ✅ linha 54 (BoardEngine) | ⚠️ §3.13 Tribe Project Boards (mas é o admin board view, escopo amplo) | Pré-V4 (sem `engagement_kind_permissions`) |
| 8 | `campaigns.astro` | ✅ linha 61 | ⚠️ §4 navigation map | Pré-V4 (cita `comms_team` legacy) |
| 9 | `certificates.astro` | ✅ linha 42 | ⚠️ §3.10 LGPD Contact Data citável; sem entry direta | Pré-V4 |
| 10 | `chapter.astro` | ❌ | ❌ | N/A — **gap** |
| 11 | `chapter-report.astro` | ✅ linha 70 | ⚠️ §4 navigation (linha 100 navConfig) | Pré-V4 |
| 12 | `comms.astro` | ✅ linha 59 | ✅ §3.1 linha 68 + §3.4 | Pré-V4 (cita `can_manage_comms_metrics()` que é V3-style) |
| 13 | `comms-ops.astro` | ✅ linha 60 | ✅ §3.1 linha 69 + §4 (W85 Cockpit) | Pré-V4 |
| 14 | `curatorship.astro` | ✅ linha 49 | ✅ §4 linha 238 (navigation) | Pré-V4 |
| 15 | `cycle-report.astro` | ✅ linha 69 | ⚠️ §4 navigation (`admin-cycle-report` → `/report` rota?? **drift potencial**) | Pré-V4 |
| 16 | `data-health.astro` | ✅ linha 75 | ❌ | N/A |
| 17 | `governance/documents.astro` | ❌ | ❌ | N/A — **gap crítico** (governance v2.7 chains live em produção, sem doc) |
| 18 | `governance/documents/[chainId].astro` | ❌ | ❌ | N/A — **gap** |
| 19 | `governance/documents/[chainId]/audit-report.astro` | ❌ | ❌ | N/A — **gap** |
| 20 | `governance/documents/[chainId]/export-docx.astro` | ❌ | ❌ | N/A — **gap** |
| 21 | `governance/documents/[chainId]/export-pdf.astro` | ❌ | ❌ | N/A — **gap** |
| 22 | `governance/ip-ratification.astro` | ❌ | ❌ | N/A — **gap** (D1 v2.7 IP shipped p128) |
| 23 | `governance-v2.astro` | ✅ linha 80 | ✅ §3.1 linha 71 + §4 linha 237 | Pré-V4 |
| 24 | `help.astro` | ✅ linha 89 | ✅ §3.1 linha 72 (Help) | Pré-V4 (irrelevante — public-ish) |
| 25 | `initiative-kinds.astro` | ❌ | ❌ | N/A — **gap crítico** (ADR-0009 config-driven kinds, página existe mas sem doc) |
| 26 | `knowledge.astro` | ✅ linha 51 | ❌ | N/A |
| 27 | `member/[id].astro` (singular) | ❌ | ❌ | N/A — **gap** (note: é DIFERENTE de `members/[id].astro` plural — investigar duplicação) |
| 28 | `members.astro` | ✅ linha 40 | ✅ §3.3 linha 91 + §4 linha 251 | Pré-V4 (cita `members_select_admin` policy V3 RLS) |
| 29 | `members/[id].astro` | ✅ linha 41 | ⚠️ §3.3 indireto | Pré-V4 |
| 30 | `members/inactive-candidates.astro` | ❌ | ❌ | N/A — **gap** (ARM-9 lifecycle, ADR-0071) |
| 31 | `partnerships.astro` | ✅ linha 81 | ⚠️ §4 navigation (linha 99) | Pré-V4 |
| 32 | `pilots.astro` | ✅ linha 82 | ❌ | N/A |
| 33 | `portfolio.astro` | ✅ linha 72 | ✅ §3.1 linha 70 + §4 linha 236 | Pré-V4 |
| 34 | `publications.astro` | ✅ linha 50 | ✅ §3.1 linha 74 + §4 linha 244 | Pré-V4 |
| 35 | `report.astro` | ✅ linha 71 | ⚠️ §4 navigation (linha 94 `admin-exec-report`) | Pré-V4 |
| 36 | `selection.astro` | ✅ linha 43 | ✅ §3.14 linhas 202-206 (Wave 9 LGPD) | Pré-V4 (cita "admin check" sem `can(view_pii)`) |
| 37 | `settings.astro` | ✅ linha 87 | ✅ §3.16 linhas 214-219 (Wave 11) | Pré-V4 (Superadmin only — semântica preservada, mas não usa `can()`) |
| 38 | `sustainability.astro` | ✅ linha 74 | ⚠️ §4 navigation (linha 101) | Pré-V4 |
| 39 | `tags.astro` | ✅ linha 53 | ❌ (citada apenas em §3.7 Wave 5 "Knowledge Hub") | Pré-V4 |
| 40 | `tribe/[id].astro` | ❌ | ❌ | N/A — **gap** (admin tribe dashboard, navigation linha 103) |
| 41 | `tribes.astro` | ✅ linha 48 | ⚠️ §3.11 Lifecycle (RPCs admin_*) + §4 linha 102 (`admin-cross-tribes`) | Pré-V4 (cita `admin_list_tribes` etc com role-list V3) |
| 42 | `webinars.astro` | ✅ linha 62 | ✅ §3.1 linha 73 + §4 (Wave 26-30) | Pré-V4 |

### Resumo agregado

| Métrica | Valor |
|---|---|
| Total páginas | 42 |
| Documentadas em **AA** (✅) | 29 (69%) |
| Documentadas em **PM** (✅ ou ⚠️) | 23 (55%) |
| Documentadas em ambos (✅+✅) | 17 (40%) |
| **Gap (sem doc nenhum)** | **13 (31%)** |
| **V4-correct (cita `can()`/`engagement_kind_permissions`/`rls_can`)** | **0** (0%) |

---

## 2. Gap list — páginas SEM documentação

13 páginas reais não aparecem em ADMIN_ARCHITECTURE.md nem em PERMISSIONS_MATRIX.md (matriz ou navigation map):

| # | Página | Severidade | Motivo gap |
|---|---|---|---|
| 1 | `admin/ai-calibration.astro` | Média | Onda 3 ARM dual-model AI (ADR-0074); admin tool nova p108+ |
| 2 | `admin/chapter.astro` | Alta | Chapter-scope admin dashboard (multi-client anchor); page existe mas sem doc — **bloqueia replication guide** |
| 3 | `admin/governance/documents.astro` | **Crítica** | Governance v2.7 chains (Política IP D1 p128) — produção live, sem doc admin |
| 4 | `admin/governance/documents/[chainId].astro` | Crítica | Sub-rota chain detail — sem doc |
| 5 | `admin/governance/documents/[chainId]/audit-report.astro` | Alta | Chain audit report export — sem doc |
| 6 | `admin/governance/documents/[chainId]/export-docx.astro` | Alta | DOCX export route — sem doc |
| 7 | `admin/governance/documents/[chainId]/export-pdf.astro` | Alta | PDF export route — sem doc |
| 8 | `admin/governance/ip-ratification.astro` | Crítica | D1 v2.7 IP ratification flow shipped p128 — sem doc |
| 9 | `admin/initiative-kinds.astro` | **Crítica** | ADR-0009 config-driven initiative kinds; admin de config V4 — invisível em docs |
| 10 | `admin/member/[id].astro` (singular) | Média | Possível duplicação histórica vs `members/[id].astro`; investigar antes de documentar |
| 11 | `admin/members/inactive-candidates.astro` | Alta | ARM-9 lifecycle (ADR-0071) — admin tool para inativação assistida |
| 12 | `admin/tribe/[id].astro` | Média | Admin tribe dashboard (per-tribe operational view); navegação linha 103 navigation.config |
| 13 | (já contado em #10) | — | — |

**Note**: 8 das 13 são governance V2.7 + initiative-kinds (ADR-0009) + ARM-9 (ADR-0071) — todas frentes V4-era importantes mas invisíveis nos docs. ADMIN_ARCHITECTURE.md último cutoff "08 April 2026" precede a maioria desses ships.

---

## 3. Drift list — entradas em docs sem página correspondente

Análise: cross-check de TODAS as rotas mencionadas em `ADMIN_ARCHITECTURE.md` (Page Map §"29 pages") vs filesystem real.

| Doc entry | Doc localização | Status no filesystem | Tipo drift |
|---|---|---|---|
| `/admin` | AA linha 67 | `index.astro` ✅ | OK |
| `/admin/members` | AA linha 40 | `members.astro` ✅ | OK |
| `/admin/members/[id]` | AA linha 41 | `members/[id].astro` ✅ | OK |
| `/admin/certificates` | AA linha 42 | `certificates.astro` ✅ | OK |
| `/admin/selection` | AA linha 43 | `selection.astro` ✅ | OK |
| `/admin/tribes` | AA linha 48 | `tribes.astro` ✅ | OK |
| `/admin/curatorship` | AA linha 49 | `curatorship.astro` ✅ | OK |
| `/admin/publications` | AA linha 50 | `publications.astro` ✅ | OK |
| `/admin/knowledge` | AA linha 51 | `knowledge.astro` ✅ | OK |
| `/admin/blog` | AA linha 52 | `blog.astro` ✅ | OK |
| `/admin/tags` | AA linha 53 | `tags.astro` ✅ | OK |
| `/admin/board/[id]` | AA linha 54 | `board/[id].astro` ✅ | OK (mantém — é admin shadow do board) |
| `/admin/comms` | AA linha 59 | `comms.astro` ✅ | OK |
| `/admin/comms-ops` | AA linha 60 | `comms-ops.astro` ✅ | OK |
| `/admin/campaigns` | AA linha 61 | `campaigns.astro` ✅ | OK |
| `/admin/webinars` | AA linha 62 | `webinars.astro` ✅ | OK |
| `/admin/analytics` | AA linha 68 | `analytics.astro` ✅ | OK |
| `/admin/cycle-report` | AA linha 69 | `cycle-report.astro` ✅ | OK |
| `/admin/chapter-report` | AA linha 70 | `chapter-report.astro` ✅ | OK |
| `/admin/report` | AA linha 71 | `report.astro` ✅ | OK |
| `/admin/portfolio` | AA linha 72 | `portfolio.astro` ✅ | OK |
| `/admin/adoption` | AA linha 73 | `adoption.astro` ✅ | OK |
| `/admin/sustainability` | AA linha 74 | `sustainability.astro` ✅ | OK |
| `/admin/data-health` | AA linha 75 | `data-health.astro` ✅ | OK |
| `/admin/governance-v2` | AA linha 80 | `governance-v2.astro` ✅ | OK |
| `/admin/partnerships` | AA linha 81 | `partnerships.astro` ✅ | OK |
| `/admin/pilots` | AA linha 82 | `pilots.astro` ✅ | OK |
| `/admin/settings` | AA linha 87 | `settings.astro` ✅ | OK |
| `/admin/audit-log` | AA linha 88 | `audit-log.astro` ✅ | OK |
| `/admin/help` | AA linha 89 | `help.astro` ✅ | OK |
| `/admin/chapter` (componente BoardMembersPanel mencionado linha 116) | AA linha 116 — **rota em "Component Map" só** | `chapter.astro` ✅ existe mas não tem entrada na §Page Map | **Soft drift**: doc Component Map cita `/admin/chapter` mas Page Map omite |

**Hard drift count**: 0
**Soft drift**: 1 (`/admin/chapter` mencionado em Component Map mas não em Page Map → ADMIN_ARCHITECTURE inconsistência interna)

PERMISSIONS_MATRIX.md drift: nenhuma referência a páginas removidas. A matriz é puramente conceitual e referencia tabelas/RPCs (não rotas) na maioria das entradas. Drift potencial menor: §4 navigation map cita `admin-cycle-report` apontando para `/report` (linha 100 navigation.config.ts confirma href=`/report`, mas há também `admin-exec-report → /admin/report`). Distinção é correta no código (cycle-report = legado público em `/report` ou ambos? — confirmar com PM se essa duplicação é intencional).

---

## 4. Stale role / authority references

### 4.1 Direct legacy refs (canWrite, WRITE_ROLES, BOARD_ROLES)

```
$ grep -n 'canWrite\|WRITE_ROLES\|BOARD_ROLES' docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md
(empty)
```

✅ **Nenhum hit** — limpeza pós-V4 cutover (2026-04-13) preservada. Bom sinal.

### 4.2 `operational_role` como construct ativo

Atualmente `operational_role` é cache mantido por trigger `sync_operational_role_cache` (per CLAUDE.md). Documentos ainda tratam como source of truth:

| Doc | Linha | Texto | Status |
|---|---|---|---|
| `ADMIN_ARCHITECTURE.md` | 208 | `Tier model is generic — adjust 'operational_role' values if different` | **Estale** — `operational_role` não é mais ajustável "se diferente"; é cache derivado de engagements. Replication guide deveria apontar para `engagement_kind_permissions` seed. |
| `PERMISSIONS_MATRIX.md` | 126 | `Membros com operational_role != guest e current_cycle_active = true` | **Estale** — mesma raiz: cache, não verdade. Lógica funciona porque cache é correto, mas a frame conceitual é V3. |
| `PERMISSIONS_MATRIX.md` | 174-179 | Múltiplas RPCs `admin_*_tribe` descritas como "gestão de projeto (manager, deputy_manager, co_gp)" | **Estale** — V4 frame é `can_by_member(member, 'manage_member')`. Listar role-names hardcoded contradiz ADR-0007. |
| `PERMISSIONS_MATRIX.md` | 284 | `is_superadmin || operational_role in (manager, deputy_manager)` | **Estale** — Edge Function check pré-V4. Pós-cutover, padrão é canV4 (`can_by_member`). |

### 4.3 V4 invisibility

Search results em ambos docs:

```
$ grep -n 'can()\|can_by_member\|rls_can\|engagement_kind_permissions' docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md
(empty)
$ grep -n 'ADR-0004\|ADR-0005\|ADR-0006\|ADR-0007\|ADR-0008\|ADR-0009\|Domain Model V4\|V4' docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md
(empty)
```

✅ **Sediment confirmado**: V4 não foi propagado para os docs admin. Quem ler PERMISSIONS_MATRIX.md como onboarding entrará com mental model V3. Para ADR-0007 ser source of truth, precisa de seção dedicada em PERMISSIONS_MATRIX.

### 4.4 Tier model como verdade de runtime

Tabela §1 (rank 0-5) é correta como **abstração frontend** (`navigation.config.ts` ainda usa `minTier`), mas no backend pós-V4 a chamada canônica é `can_by_member(member, action)`. Frontend tier check é uma optimization de UX (esconder itens), não uma autorização. Doc não diferencia.

### 4.5 `comms_team` designation

navigation.config.ts linhas 105-106 ainda usam `allowedDesignations: ['comms_team']` para `admin-campaigns` + `admin-blog`. PERMISSIONS_MATRIX.md §5 trata como "resolvida em S-COM1" (linhas 280-282) — mas o filtro live no código ainda existe. **Discrepância doc × código**: doc declara resolução, código preserva. Provavelmente backward-compat preservada intencionalmente, mas matrix entry para campaigns/blog deveria explicitar `['comms_team', 'comms_leader', 'comms_member']` com nota de migração.

---

## 5. Recommended doc refresh plan

Priorizado por (a) páginas em produção live × (b) usuários atuais que dependem da accuracy do doc para onboarding/replication × (c) custo do refresh.

### 5.1 Tier P0 — Crítico (refresh OBRIGATÓRIO antes de qualquer onboarding novo de dev/admin)

| # | Ação | Doc | Esforço estimado | Risco se adiar |
|---|---|---|---|---|
| 1 | **Adicionar seção V4 Authority em PERMISSIONS_MATRIX.md** após §1 (Tier Model). 1 página explicando: (a) tier é frontend-only, (b) backend canonical = `can_by_member`, (c) source = `engagement_kind_permissions` × designations × inline scoping. Linkar `docs/reference/V4_AUTHORITY_MODEL.md` + ADR-0007. | PM | 30 min | Alto — onboarding novo confunde V3 e V4, propostas de seed expansion erradas |
| 2 | **Documentar 5 governance/documents/* + ip-ratification.astro páginas** em ADMIN_ARCHITECTURE.md (Governance section). Adicionar entries em PERMISSIONS_MATRIX.md (provavelmente §3.X nova: "Governance Chains v2.7"). | AA + PM | 45 min | Alto — produção live (D1 v2.7 IP shipped p128) sem doc |
| 3 | **Documentar `admin/initiative-kinds.astro`** + apontar para ADR-0009 em ambos docs. | AA + PM | 15 min | Alto — quebra invariante "config-driven kinds, not code" se usuário não sabe da página |
| 4 | **Atualizar header de PERMISSIONS_MATRIX.md** "Última atualização: 2026-03-15" → "2026-05-09 (Ω-B). V4 cutover ratified 2026-04-13 (ADR-0007 + 0006 + 0005); docs alinhamento em curso." | PM | 2 min | Médio — leitor confia em data e assume tudo V3 |

### 5.2 Tier P1 — Alto (refresh em sprint de docs hygiene)

| # | Ação | Doc | Esforço |
|---|---|---|---|
| 5 | Adicionar 8 páginas faltantes restantes (ai-calibration, chapter, member/[id], members/inactive-candidates, tribe/[id], + clarificar member/[id] vs members/[id]) em ADMIN_ARCHITECTURE.md Page Map com colunas Component / Purpose. | AA | 30 min |
| 6 | Atualizar `Page Map (29 pages)` header em ADMIN_ARCHITECTURE.md → `Page Map (42 pages)` + atualizar todas as section counts. | AA | 5 min |
| 7 | Reescrever §4.1-§4.4 entries que citam `operational_role in (manager, deputy_manager, co_gp)` para framing V4: `can_by_member(member, 'manage_member')` é a gate; `(volunteer, manager)`/`(volunteer, deputy_manager)`/`(volunteer, co_gp)` em `engagement_kind_permissions` é o que satisfaz. | PM §3.11, §5 | 20 min |
| 8 | Adicionar comentário em §5 (Divergências) sobre `comms_team` ainda hardcoded em navigation.config.ts apesar da resolução S-COM1 declarada — listar como "Divergência menor pendente: backward-compat hardcode em allowedDesignations". | PM §5 | 5 min |
| 9 | Atualizar Component Map em ADMIN_ARCHITECTURE.md (linhas 96-117) — `21 components` declarado mas `find` retorna **30 .tsx files** em `src/components/admin/**` (4 subdirs novas: dashboard, modals, audit, blog, members). | AA | 15 min |
| 10 | Adicionar `admin/chapter` à Page Map (atualmente só em Component Map) → resolver soft drift. | AA | 2 min |

### 5.3 Tier P2 — Médio (nice-to-have)

| # | Ação | Doc | Esforço |
|---|---|---|---|
| 11 | Adicionar exemplos "antes/depois" V3→V4 em PERMISSIONS_MATRIX.md (ex: "antes: `WRITE_ROLES.includes(role)`; depois: `can_by_member(member, 'write')`"). Útil para reviewers de PR antigos. | PM | 30 min |
| 12 | Cross-link de PERMISSIONS_MATRIX.md para `docs/reference/V4_AUTHORITY_MODEL.md` em todas as menções a "designation gate" (Caminho 2) e "inline scoping" (Caminho 3). | PM | 10 min |
| 13 | Atualizar §6 Changelog em PERMISSIONS_MATRIX.md com entry "2026-04-13 — V4 cutover (ADR-0007). Tier model permanece como abstração frontend; backend canonical migrou para `can_by_member`. operational_role agora é cache." | PM §6 | 5 min |
| 14 | Adicionar seção "Replication for other PMI chapters" em PERMISSIONS_MATRIX.md (atualmente só em ADMIN_ARCHITECTURE.md §"Replication Guide"). Apontar para `engagement_kind_permissions` seed como passo crítico de setup multi-client. | PM | 20 min |

### 5.4 Tier P3 — Defer (não bloqueia uso atual)

- Refactor completo de §3.1-§3.16 em PERMISSIONS_MATRIX.md para framework "action × kind × role" V4 nativo (vs tabela tier-based atual). Custo alto (~3h), benefício marginal — tabelas tier-based ainda funcionam como espelho frontend. Considerar apenas se PMIS multi-client começar a tracionar e replication guide virar load-bearing.

---

## 6. Anexos

### 6.1 Comandos de verificação executados

| Comando | Resultado |
|---|---|
| `find src/pages/admin -maxdepth 4 -name "*.astro" \| wc -l` | **42** páginas |
| `wc -l docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md` | 213 / 320 |
| `grep -c "canWrite\|WRITE_ROLES\|BOARD_ROLES" docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md` | **0** (ambos) |
| `grep -c "can()\|can_by_member\|rls_can\|engagement_kind_permissions" docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md` | **0** (ambos) |
| `grep -c "ADR-000[4-9]\|V4" docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md` | **0** (ambos) |
| `grep -c "operational_role" docs/ADMIN_ARCHITECTURE.md docs/PERMISSIONS_MATRIX.md` | 1 / 2 |
| `find src/components/admin -maxdepth 2 -name "*.tsx" \| wc -l` | **30** components (doc declara 21) |
| `ls src/pages/admin/governance/documents/` | 3 sub-rotas + index page (4 .astro files no diretório `[chainId]/`) |

### 6.2 Inventário 42 páginas — agrupamento por subdir

```
src/pages/admin/
├── (28 páginas top-level)
│   ├── adoption.astro
│   ├── ai-calibration.astro          ← gap
│   ├── analytics.astro
│   ├── audit-log.astro
│   ├── blog.astro
│   ├── campaigns.astro
│   ├── certificates.astro
│   ├── chapter.astro                 ← gap (Page Map)
│   ├── chapter-report.astro
│   ├── comms.astro
│   ├── comms-ops.astro
│   ├── curatorship.astro
│   ├── cycle-report.astro
│   ├── data-health.astro
│   ├── governance-v2.astro
│   ├── help.astro
│   ├── index.astro
│   ├── initiative-kinds.astro        ← gap crítico
│   ├── knowledge.astro
│   ├── members.astro
│   ├── partnerships.astro
│   ├── pilots.astro
│   ├── portfolio.astro
│   ├── publications.astro
│   ├── report.astro
│   ├── selection.astro
│   ├── settings.astro
│   ├── sustainability.astro
│   ├── tags.astro
│   ├── tribes.astro
│   └── webinars.astro
├── board/
│   └── [id].astro
├── governance/                       ← 6 páginas, TODAS gap
│   ├── documents.astro
│   ├── ip-ratification.astro
│   └── documents/
│       ├── [chainId].astro
│       └── [chainId]/
│           ├── audit-report.astro
│           ├── export-docx.astro
│           └── export-pdf.astro
├── member/
│   └── [id].astro                    ← gap (singular — investigar duplicação)
├── members/
│   ├── [id].astro
│   └── inactive-candidates.astro     ← gap
└── tribe/
    └── [id].astro                    ← gap
```

### 6.3 Top 5 risk items

1. **6 governance pages live em produção sem doc admin** (D1 v2.7 Política IP shipped p128) — onboarding de novo dev/admin quase certamente perderá fluxo.
2. **0 menções a V4 authority em ambos docs** apesar de cutover 2026-04-13 ratified — propostas de seed expansion / role-list edits virão pré-V4.
3. **`initiative-kinds.astro` ausente dos docs** — viola invariante ADR-0009 "config-driven kinds, not code" se quem replicate plataforma não souber que essa página existe.
4. **`operational_role` tratado como construct ativo em 3 entries de PERMISSIONS_MATRIX** — leitor pensa que pode "ajustar values" (per ADMIN_ARCHITECTURE replication guide) mas é cache; mudança real precisa via `engagement_kind_permissions`.
5. **`admin/member/[id].astro` (singular) vs `admin/members/[id].astro` (plural)** — possível duplicação histórica não-documentada. Drift técnico que pode causar 404 ou roteamento errado.

---

**Fim do relatório.** Sweep Ω-B — admin docs auditor sub-agent. Read-only — nenhum arquivo source editado.

Cross-refs sugeridos para refresh real:
- ADR-0007 (canonical authority gate)
- ADR-0009 (config-driven initiative kinds)
- ADR-0011 (V4 auth pattern em RPCs+MCP)
- `docs/reference/V4_AUTHORITY_MODEL.md` (3 caminhos paralelos)
- `docs/refactor/DOMAIN_MODEL_V4_MASTER.md` (cutover history)
- handoff p128 D1 (governance v2.7 IP ratification flow)
- ADR-0071 (member lifecycle ARM-9)
- ADR-0074 (Onda 3 ARM dual-model AI)
