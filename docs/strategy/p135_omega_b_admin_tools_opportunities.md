# Ω-B Sweep — Admin Tools Opportunities (Sustainability Deep-Dive + Governance v2.7 + Selection Refactor + DB FK/Composite Catalog)

**Sweep:** Páginas administrativas (`/admin/*` — 42 pages, 13.6K LOC)
**Date:** 2026-05-09 (p135, follow-up to p134 Ω-A)
**Scope:** Quad-track —
1. Sustainability deep-dive (multi-chapter financial OS, chart of accounts, public transparency)
2. Governance v2.7 enhancements (chain workflow tools, N+1 audits)
3. Selection refactor (3137L monolith — extraction sketch)
4. DB FK + RPC composite catalog across admin scope

**Strategic anchor:** `memory/project_chapter_pmis_saas_vision_p133.md` (whitelabel SaaS for PMI chapters, replaces Sympla/DocuSign/Forms/Sheets, integrates NF-e/Airmeet) + ADR-F (financial org_id) PROPOSED pré-pilot Ω-E.1.

---

## Executive summary (TL;DR)

- **Sustainability schema gap is the single load-bearing blocker** for chapter-pilot revenue: 5 tables exist (`cost_categories`, `cost_entries`, `revenue_categories`, `revenue_entries`, `sustainability_kpi_targets`) but ALL lack `organization_id`. Of these, two are HARD blockers also flagged in p134: (a) `revenue_entries.event_id` FK absent, (b) `sustainability_kpi_targets UNIQUE(cycle, kpi_name)` blocks 2nd chapter. P0/P1 work cannot dodge this.
- **Chart of accounts is greenfield.** No `chart_of_accounts`, `bank_accounts`, `fiscal_documents`, or `chapter_fiscal_config` tables exist today. Schema sketch below covers Brazilian accounting standards (CPC + Receita Federal) + chapter pilot needs.
- **Public transparency module is greenfield.** Today sustainability is admin-only behind `hasPermission('admin.sustainability')`. PMI-GO chapter dirige direção pública per Estatuto Federal § Art. 12 III; need a `/transparencia/[chapter]` view (read-only RPCs no PII).
- **Governance v2.7 has 3 critical N+1s in admin pages.** `governance/documents.astro:443` loops `get_chain_workflow_detail` per chain (1+N pattern over 6 active chains today). `governance/ip-ratification.astro:200-210` is worst — fans 1 list query → N count queries → M reminder queries (1+2N over 6 chains = 13 round-trips). Composite RPC `get_chains_overview()` would collapse to 1.
- **Selection refactor is justified — but bound by complexity, not size.** 3137L = 21 functions, 8 RPCs in modal alone, 6 tabs (4 main + 5 modal sub-tabs). Refactor target = extract Modal (1500L → React island) + extract Bulk Actions panel + extract Committee tab. Pipeline stays as-is (load-bearing real-time UX).
- **Comms.astro has 6 sequential `comms_metrics_latest_by_channel` calls with different `p_days` values** (3/7/14/30) on single page load. This is THE worst RPC fan-out in admin. Composite `get_comms_dashboard_bundle()` would collapse to 1.
- **DB FK gaps newly identified beyond p134 Ω-A:**
  1. `member_document_signatures` lacks composite `(member_id, signed_at DESC)` index → "minhas assinaturas" full table scan.
  2. `approval_signoffs` queried inline `count: 'exact'` per chain → indexed but no composite RPC envelope; replace 2N queries with 1.
  3. `comms_metrics` has no composite `(channel, metric_date DESC, days_window)` index — RPC re-aggregates same data 6× per page load.
- **Composite RPC opportunities (admin scope, AFTER p134 senior-eng "premature composite optimization is bad" caveat applied)**: 4 truly load-bearing cases identified. Comms (6→1), Governance docs (1+N→1), IP-ratification (1+2N→1), Sustainability dashboard merge (3→1). Selection NOT included — its RPCs are user-action-driven (lazy loaded inside modal), not bundle-able.

---

## Track 1: Sustainability Deep-Dive

### 1.1 Current schema audit

**Tables (5):**

| Table | Rows pre-Ω-B | Has `organization_id`? | RLS? | Bloqueio multi-chapter |
|---|---|---|---|---|
| `cost_categories` | 8 (seed) | ❌ | ✅ Authenticated SELECT | Categorias compartilhadas; chapter-specific kept via TEXT label or convention |
| `cost_entries` | low (~20) | ❌ | ✅ Authenticated SELECT | **HARD BLOCKER** — sem org_id chapter pilot vê custos cruzados |
| `revenue_categories` | 7 (seed) | ❌ | ✅ Authenticated SELECT | Idem cost_categories |
| `revenue_entries` | low (~5) | ❌ | ✅ Authenticated SELECT | **HARD BLOCKER + SECONDARY**: também sem `event_id` FK (p134 Ω-A) e `submission_id` FK (asymmetry vs cost_entries) |
| `sustainability_kpi_targets` | 5 (seed cycle 3) | ❌ | ✅ Authenticated SELECT | **HARD BLOCKER**: `UNIQUE(cycle, kpi_name)` impede 2nd chapter no mesmo ciclo |

**RPC surface (10 deployed):**

1. `get_sustainability_dashboard(p_cycle integer)` — bundle dashboard (total_costs, total_revenue, costs_by_category, revenue_by_category, kpis, monthly_trend) — 1500-byte JSONB
2. `get_sustainability_projections(p_months_ahead integer)` — 6-month forecast com `infra_breakdown` last 10 items
3. `get_cost_entries(p_category, p_date_from, p_date_to, p_limit)` — table com FK joins (event_title, submission_title, created_by_name)
4. `get_revenue_entries(p_category, p_date_from, p_date_to, p_limit)` — sem FK joins (revenue_entries não tem event_id/submission_id ainda)
5. `create_cost_entry(...)` — insert + auth gate manager/superadmin
6. `create_revenue_entry(...)` — insert + auth gate manager/superadmin
7. `delete_cost_entry(p_id)` — manager/superadmin
8. `delete_revenue_entry(p_id)` — manager/superadmin
9. `update_sustainability_kpi(p_id, p_target_value, p_current_value, p_notes)` — manager/superadmin
10. `get_annual_kpis(p_cycle, p_year)` — fans out via `v_auto_values` jsonb dispatch (inclui `infra_cost_current` que lê de `cost_entries WHERE category='infrastructure'`)

**Authority:** legacy `is_superadmin OR operational_role='manager'` — V4 migration deferred per orphan recovery comment in `20260425142917_qa_orphan_recovery_sustainability_finance.sql`. Drift cleanup pendente.

### 1.2 FK gaps beyond p134 Ω-A

**Net new FK gaps not captured in p134:**

| Source col (missing) | Target | Why matters | Severity |
|---|---|---|---|
| `cost_entries.organization_id` | `organizations(id)` | Já em p134 Ω-A. Reiterado aqui pois é prerequisite. | **CRITICAL** |
| `revenue_entries.organization_id` | `organizations(id)` | Já em p134 Ω-A. | **CRITICAL** |
| `revenue_entries.event_id` | `events(id)` | Já em p134 Ω-A. | **HIGH** |
| `revenue_entries.submission_id` | `publication_submissions(id)` | Já em p134 Ω-A. | **MED** |
| `sustainability_kpi_targets.organization_id` | `organizations(id)` | Já em p134 Ω-A. | **HIGH** |
| `cost_entries.created_by` | `members(id)` | **JÁ EXISTE** (FK confirmed migration 20260319100044) — false alarm em p134 sobre `paid_by`, esse é text livre PROPOSITALMENTE (chapter slug ou role tag). OK. | — |
| `cost_entries.bank_account_id` (NÃO EXISTE) | `bank_accounts(id)` (NEW) | Multi-banco per chapter (PMI-GO Caixa vs PMI-GO Banco do Brasil reconciliation). Sem isso, exporta extrato custom não bate. | **MED** (multi-chapter) |
| `cost_entries.account_id` (NÃO EXISTE) | `chart_of_accounts(id)` (NEW) | Mapping para padrão CPC (NBC TG 03 / Plano de Contas Receita Federal) — relatório fiscal anual (DEFIS / DASN-SIMEI / DIPJ ECF). Sem isso, contador chapter precisa re-classificar manualmente toda entry. | **MED** |
| `revenue_entries.bank_account_id` (NÃO EXISTE) | `bank_accounts(id)` (NEW) | Idem cost_entries. | **MED** |
| `revenue_entries.account_id` (NÃO EXISTE) | `chart_of_accounts(id)` (NEW) | Idem cost_entries. | **MED** |
| `revenue_entries.fiscal_document_id` (NÃO EXISTE) | `fiscal_documents(id)` (NEW per p134) | Vincula receita ao NFS-e/NFC-e emitido. Sem essa coluna, dual-write durante migração Sympla→internal não tem audit trail. | **HIGH** |
| `revenue_entries.payment_method` (col NÃO EXISTE) | enum/text | Cash flow analytics requer PIX vs boleto vs cartão vs transferência separados. | **LOW (futuro)** |
| `revenue_entries.payer_doc` (col NÃO EXISTE) | text (CPF/CNPJ) | Para emissão NFS-e precisa documento do tomador serviço. | **HIGH (Sympla replacement prereq)** |

### 1.3 Composite RPC opportunities (sustainability scope)

**Sustainability dashboard hoje:** carrega via 4 RPCs sequenciais em `loadAll()` (linha 366):
```ts
await Promise.all([loadDashboard(), loadProjections(), loadCostEntries(), loadRevenueEntries()]);
```
Promise.all paraleliza, mas são 4 queries DB. Avaliação senior-eng (p134 caveat): **NÃO MERGE.** São queries independentes, paralelas, e o frontend precisa renderizar 4 widgets diferentes com timing variável. Composite seria hidden coupling sem ganho mensurável. **DEIXAR COMO ESTÁ.**

**Onde composite faz sentido em sustainability:**
1. **`get_sustainability_dashboard` já é composite** (retorna 6 sub-aggregates em 1 round-trip). Bom design.
2. **`get_sustainability_projections` agrega `monthly_avg + projections + infra_breakdown` em 1 RPC** — bom design.

**Real composite opportunity surfacing here:**
- **`get_chapter_financial_summary(p_organization_id, p_period)`** — para futuro `/transparencia/[chapter]` page. 1 RPC que retorna: `{cycle, total_costs, total_revenue, by_account_chart, by_bank_account, by_event, by_submission, fiscal_docs_count, treasury_position}`. Replace 5+ separate widgets queries. **Ship com ADR-F (Ω-E.1).**

### 1.4 Chart of accounts schema sketch

**Multi-chapter prerequisite. Standard CPC (Brasileiro) + chapter-specific overrides.**

```sql
-- Plano de contas hierárquico (pai-filho via parent_id)
-- Padrão: 4 níveis (1.1.01.01 = ATIVO > CIRCULANTE > DISPONÍVEL > CAIXA)
CREATE TABLE public.chart_of_accounts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  account_code    text NOT NULL,           -- '1.1.01.01' formato Receita Federal
  account_name    text NOT NULL,
  account_type    text NOT NULL CHECK (account_type IN ('asset','liability','equity','revenue','expense','contra')),
  parent_id       uuid REFERENCES public.chart_of_accounts(id) ON DELETE RESTRICT,
  level           smallint NOT NULL CHECK (level BETWEEN 1 AND 4),
  is_active       boolean NOT NULL DEFAULT true,
  is_synthetic    boolean NOT NULL DEFAULT false,  -- true = só aceita sub-contas, false = aceita lançamentos
  -- Mapeamento fiscal (preenche-se conforme regime do chapter)
  defis_code      text,    -- Código DEFIS (Simples Nacional declaração)
  ecf_code        text,    -- Código ECF (Lucro Real escrituração contábil fiscal)
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE(organization_id, account_code),
  CHECK ((level = 1 AND parent_id IS NULL) OR (level > 1 AND parent_id IS NOT NULL))
);

CREATE INDEX idx_chart_accounts_org ON public.chart_of_accounts(organization_id) WHERE is_active = true;
CREATE INDEX idx_chart_accounts_type ON public.chart_of_accounts(organization_id, account_type) WHERE is_active = true;
CREATE INDEX idx_chart_accounts_parent ON public.chart_of_accounts(parent_id) WHERE is_active = true;

-- Seed inicial PMI-GO (exemplo, expandir per chapter)
-- Nível 1 (5 grupos)
-- 1 ATIVO  /  2 PASSIVO  /  3 PATRIMÔNIO LÍQUIDO  /  4 RECEITAS  /  5 DESPESAS
-- ...
```

```sql
-- Bancos por chapter (multi-conta)
CREATE TABLE public.bank_accounts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  bank_code       text NOT NULL,           -- código FEBRABAN (001=BB, 104=Caixa, 237=Bradesco, 341=Itau, 260=Nubank, 077=Inter)
  bank_name       text NOT NULL,
  agency          text,
  account_number  text,
  account_type    text NOT NULL CHECK (account_type IN ('checking','savings','digital','treasury')),
  pix_key         text,                    -- chave PIX (CNPJ chapter ou aleatória)
  pix_key_type    text CHECK (pix_key_type IN ('cnpj','cpf','email','phone','random')),
  initial_balance numeric(14,2) DEFAULT 0,
  current_balance numeric(14,2) DEFAULT 0, -- atualizado por trigger ao inserir cost/revenue entry
  is_active       boolean NOT NULL DEFAULT true,
  -- Mapeamento contábil
  chart_account_id uuid REFERENCES public.chart_of_accounts(id),  -- typically 1.1.01.x
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_bank_accounts_org ON public.bank_accounts(organization_id) WHERE is_active = true;
CREATE UNIQUE INDEX uq_bank_accounts_pix ON public.bank_accounts(organization_id, pix_key) WHERE pix_key IS NOT NULL AND is_active = true;
```

```sql
-- Adições em cost_entries / revenue_entries (organization_id já em p134 Ω-A V5 financial migration)
ALTER TABLE public.cost_entries
  ADD COLUMN IF NOT EXISTS account_id uuid REFERENCES public.chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS bank_account_id uuid REFERENCES public.bank_accounts(id),
  ADD COLUMN IF NOT EXISTS payment_method text CHECK (payment_method IN ('pix','boleto','credit_card','debit_card','transfer','cash','dollar_card','other')),
  ADD COLUMN IF NOT EXISTS supplier_doc text,        -- CNPJ/CPF do fornecedor
  ADD COLUMN IF NOT EXISTS supplier_name text;       -- razão social/nome

ALTER TABLE public.revenue_entries
  ADD COLUMN IF NOT EXISTS account_id uuid REFERENCES public.chart_of_accounts(id),
  ADD COLUMN IF NOT EXISTS bank_account_id uuid REFERENCES public.bank_accounts(id),
  ADD COLUMN IF NOT EXISTS payment_method text CHECK (payment_method IN ('pix','boleto','credit_card','debit_card','transfer','cash','other')),
  ADD COLUMN IF NOT EXISTS payer_doc text,           -- CPF/CNPJ tomador
  ADD COLUMN IF NOT EXISTS payer_name text,
  ADD COLUMN IF NOT EXISTS event_id uuid REFERENCES public.events(id),
  ADD COLUMN IF NOT EXISTS submission_id uuid REFERENCES public.publication_submissions(id),
  ADD COLUMN IF NOT EXISTS fiscal_document_id uuid REFERENCES public.fiscal_documents(id);

CREATE INDEX idx_cost_entries_account ON public.cost_entries(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX idx_cost_entries_bank ON public.cost_entries(bank_account_id) WHERE bank_account_id IS NOT NULL;
CREATE INDEX idx_revenue_entries_account ON public.revenue_entries(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX idx_revenue_entries_bank ON public.revenue_entries(bank_account_id) WHERE bank_account_id IS NOT NULL;
CREATE INDEX idx_revenue_entries_event ON public.revenue_entries(event_id) WHERE event_id IS NOT NULL;
CREATE INDEX idx_revenue_entries_fiscal ON public.revenue_entries(fiscal_document_id) WHERE fiscal_document_id IS NOT NULL;
```

### 1.5 Multi-chapter scoping plan

**Paths (3 alternatives, escolha PM no Ω-E.1):**

**Path A (single-org-mode-default):** `auth_org()` retorna org do member via lookup `members.organization_id`. RLS auto-filtra todas as tabelas. RPCs ganham parâmetro opcional `p_organization_id` que default = `auth_org()`.
- **Pros:** menor mudança RPC; RLS handles tudo; backward compatible.
- **Cons:** GP cross-chapter (presidente regional, GP Latam) precisa elevation explícita; RLS complexa quando role tem multi-chapter scope.

**Path B (explicit-org-param):** RPCs todas ganham `p_organization_id NOT NULL`. Frontend lê `member.organization_id` ou seletor de chapter (GP cross-chapter). Sem RLS automática — RPC valida.
- **Pros:** explícito; debug fácil; cross-chapter trivial via param.
- **Cons:** verbose; cada RPC vira boilerplate de validação; risco de esquecer = dado vazado.

**Path C (hybrid org-aware-helper):** `org_scope_check(p_organization_id)` SECURITY DEFINER returns true if caller pode acessar essa org (via designations cross-chapter ou própria). Cada RPC chama helper no início. Default `p_organization_id = auth_org()` for self-scope.
- **Pros:** boilerplate centralizado; cross-chapter via designation `regional_president` ou `pmi_latam_lead`; testável.
- **Cons:** mais 1 helper por RPC = +20% DDL; lookup overhead per call.

**Recomendação:** **Path C.** Justifica investment dado strategic anchor (multi-chapter SaaS). RLS-only (Path A) frágil quando designations cross-chapter chegarem (ADR-0006 já permite engagements cross-org). Path B verbose demais.

**Implementação prioritária:**
1. **V5 Financial Migration** (cost/revenue/kpi_targets ganham `organization_id`). Backfill = `auth_org()` from `created_by` member.
2. **`org_scope_check()` helper** SECURITY DEFINER.
3. **Refactor 10 sustainability RPCs** to use helper + accept `p_organization_id`.
4. **`/admin/sustainability` UI** ganha chapter selector (visível só se member.designations contém `regional_president` ou `pmi_latam_lead` ou is_superadmin).
5. **Drop `UNIQUE(cycle, kpi_name)`, replace with `UNIQUE(organization_id, cycle, kpi_name)`** — desbloqueia 2nd chapter.

### 1.6 Public transparency module sketch

**Use case:** PMI-GO Estatuto Federal Art. 12 III obriga prestação de contas pública anual. Hoje: PDF anexo em sympla.com/site institucional. Proposta: `/transparencia/[chapter-slug]` view real-time.

**Arquitetura:**
```
nucleoia.vitormr.dev/transparencia/pmi-go
  → SSR via Astro
  → Reads from get_chapter_public_transparency(p_organization_slug)
  → Returns:
    {
      chapter: { name, cnpj, address_public, contact_public },
      cycle: { number, start, end, status },
      financial: {
        total_revenue_brl,
        total_costs_brl,
        net_position_brl,
        revenue_breakdown: [{ category, amount, count }],
        cost_breakdown: [{ category, amount, count }],
        treasury_balance_brl  -- soma bank_accounts.current_balance
      },
      events_count_year,
      members_count_active,
      published_documents: [{ title, version, ratified_at, public_url }],
      governance_chains_active: count_only,  -- sem PII
      generated_at: timestamp
    }
```

**Tabela nova: `public_transparency_config`** (controle do que cada chapter expõe):
```sql
CREATE TABLE public.public_transparency_config (
  organization_id        uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  expose_financial       boolean NOT NULL DEFAULT false,  -- requires opt-in
  expose_event_counts    boolean NOT NULL DEFAULT true,
  expose_member_counts   boolean NOT NULL DEFAULT true,
  expose_governance_docs boolean NOT NULL DEFAULT true,
  hide_amounts_below_brl numeric DEFAULT 0,        -- e.g. R$100 — esconde despesas reembolsáveis pequenas
  hide_categories        text[] DEFAULT '{}',      -- categorias específicas a omitir publicly
  contact_public_email   text,                      -- contato@pmigo.org.br
  contact_public_phone   text,
  address_public         jsonb,                     -- {street, city, state, cep, country}
  cnpj                   text,                       -- registrado para exibir publicly
  estatuto_pdf_url       text,
  custom_disclaimer      text,                       -- "Dados auditados por... 2026..."
  last_updated_by        uuid REFERENCES public.members(id),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.public_transparency_config ENABLE ROW LEVEL SECURITY;
-- Anon read: only flagged rows + opt-in to expose
CREATE POLICY "Anon read transparency config" ON public.public_transparency_config
  FOR SELECT TO anon, authenticated
  USING (true);  -- exposed via SECURITY DEFINER RPC anyway, RLS-loose ok here
GRANT SELECT ON public.public_transparency_config TO anon, authenticated;
```

**Anti-pattern guard:** RPCs `get_chapter_public_transparency()` devem **filtrar por `expose_*` flags**. Se chapter não opted-in, RPC retorna `{error: 'transparency disabled'}` em vez de bypass.

**Trigger com sustainability:** `total_revenue_brl` exposto só se `expose_financial=true`. Caso contrário o objeto financial é `null`. Cada chapter decide.

**Design legal-counsel referral:** confirmar que financial transparency exposure não viola LGPD Art. 6º (princípio finalidade) — payer_doc/supplier_doc PII não pode ir para anon view, só agregados.

---

## Track 2: Governance v2.7 Tools Audit

### 2.1 Tool inventory (existing in admin scope)

**Pages:**
- `src/pages/admin/governance-v2.astro` (295L) — Change Requests + Boards + OrgChart
- `src/pages/admin/governance/documents.astro` (520L) — Document chains list, mine pendings, drafts
- `src/pages/admin/governance/documents/[chainId].astro` — single chain review
- `src/pages/admin/governance/documents/[chainId]/audit-report.astro` — audit timeline export
- `src/pages/admin/governance/documents/[chainId]/export-{docx,pdf}.astro` — exports
- `src/pages/admin/governance/ip-ratification.astro` — overview + advance state lifecycle

**MCP tools (15 governance-related, deployed in nucleo-mcp v2.69.0):**
| Tool | Type | Notes |
|---|---|---|
| `add_document_comment` | write | inline review comments |
| `approve_change_request` | write | CR ratification |
| `submit_change_request` | write | CR creation |
| `review_change_request` | write | curator/leader review |
| `list_change_requests` | read | CR list with filters |
| `get_pending_ratifications` | read | per-member pending gates |
| `get_chain_audit_report` | read | timeline export |
| `get_governance_change_log` | read | superadmin governance audit |
| `get_governance_docs` | read | doc list with active versions |
| `lock_document_version` | write | curator finalize draft |
| `propose_new_version` | write | curator new version |
| `propose_manual_version` | write | non-curator emergency version |
| `cancel_manual_version_proposal` | write | rollback |
| `confirm_manual_version` | write | curator accepts manual proposal |
| `recirculate_governance_doc` | write | re-circulate after edit |
| `sign_ratification_gate` | write | gate signature |
| `resolve_document_comment` | write | mark comment resolved |

**Coverage gap:** existente bem servido. **Sem novas RPCs necessárias.**

### 2.2 N+1 problems (LOAD-BEARING — ship Ω-B)

**Problema 1: `governance/documents.astro:443`**
```ts
// 1 query approval_chains (with id + status filter)
var chainsRes = await sb.from('approval_chains').select('id').in('status', ['draft','review','approved','active']);
// N queries (one per chain — 6 chains today, will scale)
for (var i = 0; i < ids.length; i++) {
  var res = await sb.rpc('get_chain_workflow_detail', { p_chain_id: ids[i] });
  ...
}
```
**Cost today:** 1 + 6 = 7 round-trips. Scaling: 1 + N (linear).

**Solution:** **`get_chains_overview(p_status_filter text[] DEFAULT NULL)`** — 1 RPC retorna todos os details em batch.
- Internamente faz 1 query approval_chains + 1 query approval_signoffs JOIN — usa a mesma lógica do `get_chain_workflow_detail` mas em batch.
- Returns: `[{ chain_id, document_id, document_title, status, gates: [...], gate_summary, ball_in_court }, ...]`
- Effort: M (RPC orchestrator não-trivial; replicate workflow_detail logic inside loop ou refactor it).

**Problema 2: `governance/ip-ratification.astro:200-210`** — pior caso encontrado
```ts
// 1 query approval_chains (com selects + inner joins)
const chainsRes = await sb.from('approval_chains').select('...').in('status', [...]);
// N queries approval_signoffs count (1 per chain)
for (const c of chains) {
  const sCountRes = await sb.from('approval_signoffs').select('id', { count: 'exact', head: true }).eq('approval_chain_id', c.id);
  // M queries reminder targets (1 per chain in review/approved status)
  if (c.status === 'review' || c.status === 'approved') {
    const rem = await sb.rpc('get_ratification_reminder_targets', { p_document_id: c.document_id });
  }
}
```
**Cost today:** 1 + N + M = 1 + 6 + 4 = 11+ round-trips para 6 chains. Pior em scale.

**Solution:** **`get_ratification_overview()`** — 1 RPC bundle.
- Returns: `[{ chain_id, document_id, document_title, status, gate_count, signoff_count, pending_members, version_label, eligible_gates }, ...]`
- Replace 11 round-trips com 1.
- Effort: M (lógica já existe distribuída, consolidar em 1 PL/pgSQL function).

**Problema 3 (não-N+1, mas relacionado):** `documents.astro:476` chama `list_my_document_drafts` separadamente; `documents.astro:501` chama `governance_documents.select()`. Esses 2 + `loadChains` rodam em paralelo via `Promise.all`. **Não é ganho composite** — paralelizado já é OK. Senior-eng caveat aplicado.

### 2.3 Workflow optimizations (manual → auto)

**Today, manual:**
1. **Ratify chain → notify members:** depois de `sign_ratification_gate`, GP/curador precisa enviar email manual via `admin_send_campaign` ou WhatsApp. Cron `governance_recirculate_daily` parcialmente cobre, mas só `recirculate_governance_doc` action.
2. **Lock version → propose chain:** depois de `lock_document_version`, curador precisa create chain + add gates manualmente. Workflow é 2-3 cliques.
3. **External signer collect:** quando gate é `external_signer`, sistema permite só upload manual de PDF assinado externamente. Sem integração DocuSign-equivalente.

**Suggested automations:**
1. **Trigger `notify_chain_ratified`** — quando `approval_chains.status` muda para `active`, dispara EF `governance-notify-ratified` que envia digest aos membros opt-in. Cron-less, on-demand.
2. **`lock_and_circulate_in_one(p_version_id, p_chain_template_id)`** — combina `lock_document_version` + `create_approval_chain` + `add_gates_from_template` em 1 RPC. Curador escolhe template (e.g. "Política IP standard 6 gates") e plataforma faz o resto.
3. **External signer dispatch via Resend** — quando gate `external_signer` é criado, EF dispara email com link assinatura `/governance/external/[token]` que aceita PDF upload + auth via OTP email. Sem DocuSign needed.

### 2.4 Governance bug surface (low-priority but logged)

Per memory `handoff_p131_governance_sprint_shipped.md`, 4 bugs governance v2.7 já shipped. Audit reveals:
- ✅ "Suas pendências" race condition (p130 hotfix `waitForMember`)
- ✅ Threshold='all' gate semantics fix (4 chains affected, fixed p128 D1)
- 🟡 **P3 NEW**: `documents.astro:227` informational gate handling (`tStr === '0'`) duplica logic em 3 places (`pipelineHtml`, `ballInCourt`, separate branches). Risk of drift. **Refactor opportunity:** extract `gateState(g)` helper retornando `{state, satisfied, eligibleCount}`. Effort: S.
- 🟡 **P3 NEW**: i18n bundle injected via `define:vars` em `documents.astro:171` é OK mas inconsistent com pattern outras pages que usam `<script id="page-i18n" type="application/json">`. Sediment risk: 2 patterns coexistent. Decide: standardize.

---

## Track 3: Selection Pipeline Refactor

### 3.1 Complexity inventory

**3137 LOC = LARGEST file in admin scope, 21 functions, 41 RPCs:**

**Tabs (4 main + 5 modal):**
- `data-sel-tab="pipeline"` — Kanban + Table + Bulk Actions (loadDashboard, applyFilters, renderKanban, renderTable, executeBulkDecision)
- `data-sel-tab="import"` — VEP opportunities + CSV upload (loadOpportunities, saveOpportunity, executeImport)
- `data-sel-tab="committee"` — Committee management (loadCommittee, addCommitteeMemberById, removeCommitteeMember)
- `data-sel-tab="diversity"` — DiversityDashboard React island

**Modal sub-tabs (5):**
- `data-modal-tab="info"` — Application detail + AI panels (renderInlineAiPanel, triggerTriage, triggerBriefing)
- `data-modal-tab="evaluate"` — Evaluation form (loadEvaluationForm, loadLeaderExtraCriteria, submit_evaluation)
- `data-modal-tab="interview"` — Interview scheduling + scores (loadInterviewForm)
- `data-modal-tab="comms"` — Communications history (loadCommunications)
- `data-modal-tab="ai-runs"` — AI analysis runs (loadAiAnalysisRuns)
- `data-modal-tab="audit-log"` — Gate audit log (loadGateAuditLog)

**RPCs called (41 total):**
- Dashboard: `get_selection_cycles`, `get_selection_dashboard`, `get_application_onboarding_pct`
- Application detail: `schedule_interview`, `request_interview_reschedule`, `admin_update_application`, `update_application_contact`
- AI: `get_application_ai_analysis_runs`, `record_ai_validation`, `list_my_ai_validations`
- Evaluation: `get_evaluation_form`, `submit_evaluation`, `get_evaluation_results`
- Interview: `mark_interview_status`, `submit_interview_scores`, `get_application_interviews`
- Gate audit: `get_application_gate_attempts`
- Comms: `get_application_communications`, `get_application_returning_context`
- Bulk: bulk update via `admin_update_application` × N
- Import: `import_vep_applications`, table `vep_opportunities`
- Committee: `get_selection_committee`, `manage_selection_committee`, `members SELECT`

### 3.2 Refactor opportunity scoring

**Apply senior-eng caveat (p134):** "premature decomposition is bad". Selection é monolith justificado por:
- Many shared state (filters affect kanban + table simultaneously)
- Modal is shared across 6 tabs with cross-cutting concerns
- Real-time drag-drop UX that's hard to extract

**Refactor decisions:**

**EXTRACT (high-confidence, isolated boundary):**

1. **`SelectionApplicationModal.tsx` (target: 1500L extracted)** — Modal is 6 tabs × 6 RPC patterns × 6 state slices. Extract as React island with own boot logic + own `loadAll`.
   - **Pros:** isolates AI panel logic, evaluation form drift, audit log reuse from member detail page
   - **Cons:** breaks `applyFilters` ↔ modal state coupling — need pubsub. **Use Zustand or simple custom event bus.**
   - **Effort:** L (3-5 dias). **High value** dado modal é where most evolution happens.

2. **`SelectionCommitteeTab.tsx` (target: 200L)** — Committee tab é independent, has own RPCs (`get_selection_committee`, `manage_selection_committee`, member search), zero overlap com pipeline state.
   - **Pros:** trivial extraction; React island enables future enhancements (drag-drop reorder, role assignment matrix).
   - **Cons:** none.
   - **Effort:** S (1 dia).

3. **`SelectionImportTab.tsx` (target: 300L)** — Import tab tem 2 sub-features (vep_opportunities CRUD + CSV upload). Both isolated.
   - **Effort:** M (2 dias).

**KEEP MONOLITH (load-bearing coupling):**
- `tab-pipeline` — kanban + table + filters share allRows, filteredRows, applyFilters() — coupling necessária para sync UI.
- Bulk actions panel — depende de selectedRows que é state shared com table. Could extract to React mas overhead > benefit.

### 3.3 Composite RPC candidates (selection scope)

**`loadDashboard` + `get_application_onboarding_pct` parallel fan-out (lines 532-572):**
```ts
const { data: dashboard } = await sb.rpc('get_selection_dashboard');
// then for approved/converted apps:
const pctPromises = approvedIds.map((appId: string) => sb.rpc('get_application_onboarding_pct', ...));
```
- 1 + (N candidates approved/converted) round-trips. Today ~5-10 approved → ~6-11 RPCs.
- **Composite candidate:** **`get_selection_dashboard_with_onboarding()`** — 1 RPC inclui onboarding_pct inline para approved/converted rows. Eliminates fan-out.
- **Effort:** S (modify existing RPC com LEFT JOIN onboarding aggregate).
- **Senior-eng caveat:** this is justified — same page, sequential calls, total cost meaningful.

**Modal RPCs (`loadEvaluationForm` + `loadAiAnalysisRuns` + `loadInterviewForm` + `loadGateAuditLog` + `loadCommunications` + `loadReturningContext`):**
- These are **lazy-loaded per-tab on click**. **DO NOT MERGE.**
- Senior-eng caveat: user opens info tab, may never click ai-runs. Bundling pre-loads data they'll never see.

### 3.4 Mobile readiness audit

**Current state (selection.astro mobile):**
- Pipeline kanban: `grid-cols-2 sm:grid-cols-5` — 2 cols mobile (5 status × 2 cols = 5 rows of cards). **Usable.**
- Filters bar: `flex flex-wrap gap-3` — quebra linha mobile. **Usable.**
- Modal: `max-w-[1200px]` em desktop, full-screen mobile. Sub-tabs: `<button>` rendered inline-flex — **horizontal scroll mobile (6 tabs).**
- Table view: full table com 12 cols. **NOT MOBILE-FRIENDLY** — scroll horizontal forçado, hard to tap.

**P0 mobile fixes (não está nesta sweep, but log here):**
1. Modal sub-tabs: collapse to bottom-nav style mobile (`<nav>` fixed bottom).
2. Table: extract `SelectionApplicationCard.tsx` mobile list view (1 card per row, 4 most-important fields, expand-on-tap).
3. Bulk actions panel: sticky-bottom mobile with slide-up animation.

**Effort total mobile:** M (3 days) but secondary to refactor extractions.

### 3.5 N+1 in selection (none load-bearing)

After audit, **no N+1 patterns** in main selection page (all list-RPCs already batch via single SECURITY DEFINER aggregations like `get_selection_dashboard`). Modal RPCs are lazy. **Skip composite refactor.**

---

## Track 4: Cross-cutting DB FK + RPC Composite Catalog

### 4.1 Admin-page RPC fan-out scoreboard

| Page | Lines | RPC count | Worst pattern | Composite candidate |
|---|---|---|---|---|
| `selection.astro` | 3137 | 41 | None (lazy-loaded) | Skip (`get_selection_dashboard_with_onboarding` minor) |
| `comms.astro` | 768 | 12 | **6× `comms_metrics_latest_by_channel(p_days=3,7,14,30)`** | **`get_comms_dashboard_bundle()`** — TOP PRIORITY |
| `sustainability.astro` | 820 | 10 | 4× `Promise.all` parallel — OK | Skip (already composite via `get_sustainability_dashboard`) |
| `governance/documents.astro` | 520 | 4 | **1+N over chain ids** | **`get_chains_overview()`** |
| `governance/ip-ratification.astro` | 290 | 5 | **1+2N (worst N+1 in admin)** | **`get_ratification_overview()`** |
| `campaigns.astro` | 783 | 5 | None pattern | Skip |
| `webinars.astro` | 751 | 4 | OK | Skip |
| `portfolio.astro` | 360 | 5 | OK | Skip |
| `chapter-report.astro` | 338 | 4 | OK | Skip |
| `cycle-report.astro` | 572 | 2 | OK | Skip |
| `adoption.astro` | 1016 | 2 | OK | Skip |
| `analytics.astro` | 967 | 1 | OK | Skip |

### 4.2 Composite RPCs proposed (TOP 4 admin)

**1. `get_comms_dashboard_bundle(p_period_short int=3, p_period_med int=7, p_period_long int=30)`** — replace 6 RPCs with 1.
   - Returns: `{ recent: {...}, week: {...}, month: {...}, top_media: [...], channel_status: [...], alerts: [...] }`
   - **Effort:** M (consolidate 6 different aggregates).
   - **ROI:** HIGH — comms.astro carrega lentamente hoje, 6 round-trips × 200-500ms = 1.2-3s page load.

**2. `get_chains_overview(p_status_filter text[] DEFAULT ARRAY['draft','review','approved','active'])`** — replace 1+N pattern.
   - Returns: `[{ chain_id, document_id, document_title, version_label, status, gates: [...], gate_summary, ball_in_court }, ...]`
   - **Effort:** M.
   - **ROI:** MEDIUM-HIGH — escala linearmente.

**3. `get_ratification_overview()`** — replace 1+2N pattern (worst).
   - Returns: `[{ chain_id, document_id, document_title, status, gate_count, signoff_count, pending_members, version_label, eligible_gates }, ...]`
   - **Effort:** M.
   - **ROI:** HIGH.

**4. `get_selection_dashboard_with_onboarding()`** — minor but justified.
   - **Effort:** S.
   - **ROI:** LOW (only ~10 RPCs avoided).

### 4.3 Newly-identified FK gaps in admin scope

Beyond p134 Ω-A:

| Source col | Target | Severity | Justification |
|---|---|---|---|
| `member_document_signatures` composite index `(member_id, signed_at DESC)` | — | MED | "Minhas assinaturas" full table scan today |
| `comms_metrics` composite index `(channel, metric_date DESC)` | — | MED | 6× re-aggregations on different date windows |
| `cost_entries.account_id` (NEW) | `chart_of_accounts(id)` | MED | Multi-chapter pre-req (Track 1) |
| `cost_entries.bank_account_id` (NEW) | `bank_accounts(id)` | MED | Multi-chapter pre-req |
| `cost_entries.supplier_doc` text (NEW) | — | LOW | Reporting fiscal anual |
| `revenue_entries.account_id` (NEW) | `chart_of_accounts(id)` | MED | Multi-chapter pre-req |
| `revenue_entries.bank_account_id` (NEW) | `bank_accounts(id)` | MED | Multi-chapter pre-req |
| `revenue_entries.payer_doc` text (NEW) | — | HIGH | NFS-e emit pre-req |
| `revenue_entries.fiscal_document_id` (NEW) | `fiscal_documents(id)` | HIGH | Sympla replacement audit trail |
| `bank_accounts.chart_account_id` (NEW table FK) | `chart_of_accounts(id)` | MED | Bridge contábil |
| `public_transparency_config.organization_id` PK FK | `organizations(id)` | MED | Public exposure opt-in |
| `vep_opportunities.organization_id` (NÃO EXISTE) | `organizations(id)` | LOW | VEP integration multi-chapter (futuro Sympla replacement) |

### 4.4 Indexes recommended (admin scope, beyond p134 Ω-A)

| Table | Column(s) | Page | Estimated benefit |
|---|---|---|---|
| `member_document_signatures` | `(member_id, signed_at DESC NULLS LAST)` | governance/my-pending, profile.astro | MED — full scan eliminado |
| `approval_signoffs` | `(approval_chain_id) INCLUDE (signed_at, member_id, gate_kind)` | governance/ip-ratification | HIGH if `get_ratification_overview` shipped |
| `comms_metrics` | `(channel, metric_date DESC)` | comms.astro 6 aggregations | HIGH |
| `comms_metrics` | `(metric_date DESC) WHERE channel IN ('instagram','youtube','linkedin','newsletter')` partial | comms.astro filtros | LOW (already covered by composite acima) |
| `application_communications` | `(application_id, created_at DESC)` | selection modal comms tab | MED |
| `vep_opportunities` | `(organization_id, created_at DESC)` partial WHERE active | selection import tab (futuro multi-chapter) | LOW (futuro) |

---

## Priority Tiered Backlog

### P0 ship Ω-B (this sweep, immediate)

**P0-1 — Composite `get_comms_dashboard_bundle()`** (TOP ROI, biggest user-facing latency win)
- Effort: M (1-2 days)
- Bundle 6 `comms_metrics_latest_by_channel` calls + `comms_top_media` + `comms_channel_status` + `comms_check_token_expiry` em 1 RPC.
- Frontend: refactor comms.astro to single load + cached re-render por filtro.

**P0-2 — Composite `get_ratification_overview()`** (worst N+1 in admin, governance-impacting)
- Effort: M
- Replaces 1+2N round-trips em ip-ratification.astro.
- Audit: verify backwards compat with `get_chain_workflow_detail` for [chainId].astro single view.

**P0-3 — Composite `get_chains_overview()`** (1+N elimination, governance docs page)
- Effort: M
- Replaces N RPCs em documents.astro:443 loop.
- Co-deploys com P0-2 (lógica overlap).

**P0-4 — Composite `get_selection_dashboard_with_onboarding()`** (minor, but trivial)
- Effort: S (4-8 hours)
- Modify existing `get_selection_dashboard` to LEFT JOIN onboarding aggregate.

**P0-5 — Index `(channel, metric_date DESC)` em comms_metrics**
- Effort: trivial (1 migration line)
- Co-required for P0-1 to be effective.

**P0-6 — Index `(member_id, signed_at DESC)` em member_document_signatures**
- Effort: trivial
- Used by 4 pages (profile.astro Ω-A.6, governance/my-pending, ip-ratification view, document signatures audit).

### P1 ship Ω-C (next sprint, strategic prep)

**P1-1 — V5 Financial Foundation: `organization_id` em cost/revenue/kpi tables**
- Effort: L (3-5 days)
- Migration: ADD COLUMN NOT NULL DEFAULT auth_org() backfill.
- Drop `UNIQUE(cycle, kpi_name)` → recreate as `UNIQUE(organization_id, cycle, kpi_name)`.
- All 10 sustainability RPCs ganham `org_scope_check()` helper.
- ADR-F formalize.

**P1-2 — Chart of accounts schema + bank_accounts + new cost/revenue cols**
- Effort: L (3 days)
- Migration: CREATE chart_of_accounts + bank_accounts.
- ALTER cost_entries / revenue_entries com novos FKs.
- Seed PMI-GO chart of accounts (50-80 rows).
- Frontend: dropdowns em sustainability modals.

**P1-3 — Public transparency module + RPCs**
- Effort: M (2 days)
- CREATE public_transparency_config.
- New RPC: `get_chapter_public_transparency(p_organization_slug)`.
- New page: `/transparencia/[chapter-slug]/index.astro` + redirects EN/ES.
- LGPD legal-counsel review of exposure surface.

**P1-4 — Composite `get_chapter_financial_summary(p_organization_id, p_period)`**
- Effort: M
- Used by `/transparencia/[chapter]` and admin sustainability multi-chapter view.

**P1-5 — Selection refactor Wave 1: extract `SelectionCommitteeTab.tsx`**
- Effort: S (1 day)
- Lowest-risk extraction; isolated state.
- Use as proving ground for tab→island pattern.

**P1-6 — Governance v2.7 P3 lints**
- Effort: S
- Extract `gateState(g)` helper from `pipelineHtml + ballInCourt`.
- Standardize i18n bundle injection pattern (define:vars vs page-i18n script tag).

### P2 ship Ω-D (Sympla replacement prep)

**P2-1 — `fiscal_documents` table + `chapter_fiscal_config` table** (per p134 Ω-A schema)
- Effort: L (3 days)
- CREATE both + FKs.
- ADR-0078 formalize (Sympla replacement).

**P2-2 — Edge Function `nfse_emit` MVP**
- Effort: XL (5-7 days)
- Use NFS-e nacional API (per p134 research).
- Vault integration cert A1.
- Web Crypto signing.

**P2-3 — Selection refactor Wave 2: extract `SelectionImportTab.tsx`**
- Effort: M (2 days)

**P2-4 — Lock_and_circulate workflow auto** (governance v2.7 enhancement)
- Effort: M (2 days)
- Combine `lock_document_version` + chain creation + gate seeding em 1 RPC.

### P3 ship Ω-E (multi-chapter pilot)

**P3-1 — Selection refactor Wave 3: extract `SelectionApplicationModal.tsx`** (largest)
- Effort: L (3-5 days)
- Modal is 6 tabs × 6 RPC patterns. Extract w/ pubsub state.

**P3-2 — Chapter selector UI em sustainability/comms/governance**
- Effort: M
- Visible só para `regional_president`, `pmi_latam_lead`, superadmin.

**P3-3 — Mobile-friendly selection table card view**
- Effort: M

**P3-4 — Trigger `notify_chain_ratified` (governance auto-notification)**
- Effort: S

**P3-5 — Selection: composite `get_selection_dashboard_with_pipeline_metrics()` future merge**
- Defer; senior-eng caveat applies.

### P4 future / opportunistic

- Internal video carousel from events.youtube_url (p134 Ω-A quick-win #2)
- `external_signer` dispatch via Resend (governance enhancement)
- Bank account reconciliation auto via Pluggy/Belvo open finance APIs
- NFC-e (modelo 65) integration via node-sped-nfe (p134 Ω-A Track 3)

---

## Sugestões pra Ω-E consolidation

1. **`docs/strategy/SUSTAINABILITY_V5_REFACTOR_ROADMAP.md`** — consolidar Track 1 (Multi-chapter scoping path C + chart of accounts seed + bank_accounts + transparency module + ADR-F).
2. **`docs/adr/ADR-0080-public-transparency-module-lgpd-bounded.md`** (proposto) — formalize transparency exposure surface + LGPD trade-offs (CNPJ + endereço público OK; payer_doc PII NOT exposed).
3. **`docs/adr/ADR-0081-chart-of-accounts-multi-chapter.md`** (proposto) — formalize plano de contas hierárquico org-scoped + DEFIS/ECF mapping.
4. **`docs/strategy/COMPOSITE_RPC_BACKLOG_P135.md`** — consolidar Track 4 com migrations sugeridas (4 composite RPCs P0).
5. **`docs/strategy/SELECTION_REFACTOR_PLAN.md`** — Wave 1 (Committee tab) → Wave 2 (Import tab) → Wave 3 (Modal). Critério reversibility per wave.
6. **`docs/strategy/GOVERNANCE_V27_AUDIT_P135.md`** — N+1 fixes (P0-2, P0-3) + workflow autos (P2-4, P3-4) + P3 lints.

---

## Observações finais para PM

- **Maior surpresa Track 1:** chart of accounts é **greenfield total**. Sem isso, contador chapter (PMI-GO ou outros) precisa re-classificar manualmente toda entry no fim do ano para DEFIS. Isso desencoraja chapter de migrar para o Hub. **Schema sketch acima é realmente o caminho mais curto** — e barato (1 migration M).
- **Maior surpresa Track 2:** `governance/ip-ratification.astro` é o **PIOR N+1 no admin** (1+2N). Hoje tolerável (6 chains) mas escala ruim. Composite `get_ratification_overview()` deve ir em Ω-B mesmo (P0-2).
- **Maior surpresa Track 3:** selection refactor pode ser feito **sem tocar a tab pipeline** (mais arriscada). Wave 1 = Committee tab, ROI baixo mas zero-risk proving ground. Defer modal extraction até Ω-E confidence builds up.
- **Maior surpresa Track 4:** `comms.astro` faz **6 calls do mesmo RPC** com p_days diferentes. Rodando em rede mobile = 1.5-3s page load. Composite `get_comms_dashboard_bundle()` = TOP ROI single shipping unit do Ω-B.
- **Decisão pendente para PM Ω-E.1:** Path A vs B vs C de multi-chapter scoping. Recomendação: Path C (hybrid org-aware-helper). Mas vale council referral data-architect.
- **Decisão pendente para PM Ω-E.1:** transparency module exposure surface — quem decide opt-in flags? Recomendação: chapter GP (manage_member action), com legal-counsel sign-off LGPD.
- **Council referrals sugeridos para Ω-E:**
  - **legal-counsel** sub-agent: validar `public_transparency_config` exposure surface vs LGPD Art. 6º + 7º; CNPJ chapter público OK; payer_doc NEVER.
  - **data-architect** sub-agent: review chart_of_accounts hierarchy + bank_accounts + path A/B/C de multi-chapter scoping.
  - **security-engineer** sub-agent: `org_scope_check()` helper invariants — fail-closed; nunca permitir bypass via designations sem assertion.
  - **senior-software-engineer** sub-agent: review selection modal extraction — Zustand vs custom event bus para state sync.
  - **product-leader**: confirmar que public transparency module cabe no scope Ω-E (multi-chapter pilot pré-requisite) ou desloca para Ω-F.
