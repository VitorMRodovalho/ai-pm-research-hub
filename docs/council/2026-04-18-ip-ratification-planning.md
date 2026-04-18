# IP Ratification On-Platform — Planning Document

**Date:** 2026-04-18
**Status:** Planning only — NOT for execution. Requires PM review + Roberto's 2 points validation.
**Council agents:** ux-leader (workflow), data-architect (schema). legal-counsel + accountability-advisor deferred (need .docx conversion + separate session).

---

## Context

4 governance IP documents v2 pendentes de ratificação (em `/home/vitormrodovalho/Downloads/A/`):
- `00_Sumario_Executivo_CR050_v2.docx` — Resumo CR-050 para presidentes
- `01_Politica_Publicacao_IP_v2.docx` — Política central
- `02_Termo_Voluntariado_R3-C3-IP_v2.docx` — Novo termo ciclo 3
- `03_Adendo_Retificativo_Termo_v2.docx` — Correção dos termos já assinados
- `04_Adendo_IP_Acordos_Cooperacao_v2.docx` — Parceiros externos

Roberto's 2 open points (validated Ivan 16/Abr):
- **Software = direito autoral, não propriedade industrial** (adjust clauses 4.1, 4.3)
- **Periódicos pagos vs repositório aberto + INPI/Bib Nacional** (resolve conflito via default = repositório aberto)

Political timeline:
- Ivan PMI-GO aprovou em 16/Abr
- Ivan vai falar com outros 4 presidentes 20-21/Abr
- Marcio (CBGPL organizer) ligará presidentes semana que vem
- CBGPL 28/Abr é momento de validação pública

**Current state:** .docx files in Downloads → aprovação via email → reunião presencial. Não escala para 70+ membros ratificando + 5 presidentes signing.

**Target state:** Workflow on-platform com rastreabilidade legal, diff visualization, comments, e gate-based approval.

---

## UX Leader Output — Workflow Design

### Journey map (perspectiva do membro Tier 1)

| # | Etapa | Output esperado |
|---|---|---|
| 1 | Email trigger com deep link | Chega direto em `/governance/ip-agreement` |
| 2 | Gate de perfil inline | Campos faltantes preenchidos sem redirect |
| 3 | Diff viewer | Identifica o que mudou em < 2min |
| 4 | Comentário opcional | Thread por cláusula |
| 5 | Scroll 100% obrigatório (?) | Botão assinatura ativa |
| 6 | Confirmação identidade | Modal pre-assinatura |
| 7 | Assinatura | Certificate gerado |
| 8 | Confirmação pós-assinatura | PDF + verification_code + badge |

### Friction points (5 critical)

1. **Gate de perfil bloqueia sem contexto** — checklist inline com campos faltantes antes do viewer
2. **Documento jurídico longo sem âncora de relevância** — hero banner "3 cláusulas mudaram" com links diretos
3. **Paradoxo do botão desabilitado** — progress bar de leitura visible + tooltip
4. **Gate multi-presidentes opaco ao membro** — status simplificado em 3 estados (revisão / pronto / vigente) sem revelar votos
5. **Comments em mobile** — bottom sheet contextual, não sidebar

### Reuse de primitivos existentes

ux-leader identificou infra reutilizável:
- `src/components/governance/ManualDocumentViewer.tsx` — TOC com scroll-spy + diff badges R2/R3
- `src/components/governance/GovernanceApprovalTab.tsx` — multi-sponsor quorum pattern
- `src/components/admin/VolunteerAgreementPanel.tsx` — 2-wave signature pattern
- `src/components/onboarding/OnboardingChecklist.tsx` — step-based progressive checklist
- `src/components/NotificationBell.tsx` — in-app reminder

### Diff UI recommendation

**Inline substitution** (não side-by-side). Razão:
- Side-by-side ilegível em 375px mobile
- Versão anterior (adendo já assinado) é conhecida — membro não precisa ler integral
- Pattern: texto riscado em vermelho + texto novo sublinhado verde, com toggle "ver só mudanças"

### Abandonment recovery (principle: lembrar sem irritar)

| Canal | Timing |
|---|---|
| Badge no sino (in-app) | Persistente até assinar |
| Banner workspace | D-7 do prazo |
| Email reminder | D-7 e D-3 |
| Email final | D-1 |
| localStorage last_read_section | Sem backend, anchor automático |

**NÃO usar**: modal de bloqueio ("não pode usar plataforma até assinar"). Coerção → resistência em voluntários.

### UX Open Questions (ux-leader):

1. **Scroll 100% obrigatório é juridicamente necessário ou é UX choice?**
2. **Membros Tier 1 podem comentar ou só revisores (curadores/líderes)?**
3. **Diff baseline: adendo retificativo (doc 03) ou termo original (doc 02)?** Varia por ciclo de entrada do membro.
4. **Parceiros externos (AIPM, Christine) usam o mesmo viewer ou têm fluxo separado com token temporário?**
5. **Comportamento se membro não assinar no prazo 30d?** Bloqueio? Apenas flag? Impacta gamification?

---

## Data Architect Output — Schema Design

### Proposed tables (DDL draft)

**`document_versions`** — histórico imutável
```sql
CREATE TABLE document_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL REFERENCES governance_documents(id) ON DELETE RESTRICT,
  version_number int NOT NULL CHECK (version_number >= 1),
  content_html text NOT NULL,
  content_diff_json jsonb,
  published_at timestamptz,
  published_by uuid REFERENCES members(id) ON DELETE SET NULL,
  locked_at timestamptz,
  UNIQUE (document_id, version_number)
);
```

**`approval_chains`** — estado da cadeia
```sql
CREATE TABLE approval_chains (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL,
  version_id uuid NOT NULL REFERENCES document_versions(id),
  status text CHECK (status IN ('draft','review','approved','active','withdrawn')),
  gates jsonb,  -- [{kind, threshold, order}] — CONFIG only, status é computed (ADR-0012)
  opened_at timestamptz,
  closed_at timestamptz,
  UNIQUE (document_id, version_id)
);
```

**`document_comments`** — revisão com threading
```sql
CREATE TABLE document_comments (
  id uuid PRIMARY KEY,
  document_version_id uuid REFERENCES document_versions(id) ON DELETE CASCADE,
  author_id uuid REFERENCES members(id),
  clause_anchor text,  -- 'section-2.3', 'p-12'
  body text NOT NULL,
  parent_id uuid REFERENCES document_comments(id),
  visibility text CHECK (visibility IN ('public','curator_only','admin_only')),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES members(id)
);
```

**`approval_signoffs`** — registro imutável
```sql
CREATE TABLE approval_signoffs (
  id uuid PRIMARY KEY,
  approval_chain_id uuid REFERENCES approval_chains(id),
  gate_kind text CHECK (gate_kind IN ('curator','leader','president_go',
                                     'president_others','member_ratification')),
  signer_id uuid REFERENCES members(id),
  signoff_type text CHECK (signoff_type IN ('approval','acknowledge')),
  signed_at timestamptz,
  signature_hash text,
  content_snapshot jsonb,  -- snapshot of document_version at signing
  UNIQUE (approval_chain_id, gate_kind, signer_id)  -- idempotence
);
```

### Reuse decisions (data-architect)

- **Certificates vs approval_signoffs**: SEPARADAS. Semantic difference: certificate is "issued TO member" (beneficiary), signoff is "issued BY member" (agent). Enum expansion of certificate.type = polution.
- **Final member ratification**: emite `certificate(type='ip_ratification')` ao completar a chain. Reutiliza `verify_certificate(code)` + `get_my_certificates()` MCP tool.
- **`governance_documents.current_version_id`**: OPEN QUESTION (cache com trigger sync vs computed query).

### RLS sketch

- `document_versions`: authenticated lê published only; curator/admin lê drafts
- `document_comments`: visibility field drives who sees what; author always sees own
- `approval_chains`: public read (accountability); write via RPC only
- `approval_signoffs`: public read (audit trail); insert via `sign_ip_ratification()` SECURITY DEFINER RPC

### Triggers

- `trg_approval_chain_advance` (AFTER INSERT ON approval_signoffs) — FSM advance
- `trg_notify_on_gate_advance` — creates notifications for next gate stakeholders
- `trg_lock_document_on_active` — marks document_version.locked_at when chain becomes 'active'

### Integration points

- **New RPC**: `sign_ip_ratification(p_chain_id, p_language)` — mirrors `sign_volunteer_agreement` pattern
- **Email**: reuses `campaign_templates` + `campaign_sends` with template `ip-ratification-gate-notify`
- **MCP tools new**: `get_pending_ratifications`, `sign_ip_ratification`
- **Invariants new**: G/H/I/J/K (see data-architect report for details)

### Data Architect Open Questions:

1. **`current_version_id` cache or computed?** — PM decision
2. **`gates` jsonb as config or state?** — recommend CONFIG ONLY (ADR-0012 alignment)
3. **Comment edit window?** — fixed (15min?) or open until chain.status='active'?
4. **`ip_ratification` as new certificate.type or new entity?** — recommend type extension (pragmatic for 280 signoffs)
5. **Presidents não são members — how to handle external signers?** — nullable `signer_id` + `external_signer_name/email` OR onboard presidents as members with restricted role

---

## Consolidated Open Questions for PM Decision

| # | Question | Agent | Recommendation |
|---|---|---|---|
| 1 | Scroll 100% obrigatório? | ux | Checkbox "declaro li" parece suficiente juridicamente |
| 2 | Tier 1 pode comentar? | ux | Provavelmente não — confunde + adiciona moderation overhead |
| 3 | Diff baseline varia por ciclo de entrada? | ux | Sim — armazenar "last signed version" por membro |
| 4 | Parceiros externos: mesmo viewer ou fluxo separado? | ux/data | Recomend: magic-link com token temporário, sem auth |
| 5 | Comportamento de não-assinatura em 30d? | ux | Flag only — não bloqueio |
| 6 | `current_version_id` cache ou computed? | data | Computed para volume atual (revisar em 6 meses) |
| 7 | `gates` config ou state? | data | **CONFIG ONLY** — ADR-0012 mandato |
| 8 | Comment edit window? | data | 15min suggested |
| 9 | `ip_ratification` certificate type ou new entity? | data | **Type extension** — reuse infra |
| 10 | Presidentes: members ou external signers? | data | **Depende de consenso**: on-platform vs hybrid |

---

## Proposed Phased Implementation

### Phase IP-1: Document ingestion (1 session)
- Convert 5 .docx → HTML (via pandoc or similar)
- Seed `governance_documents` + `document_versions` (v1 = current, v2 = draft under review)
- Create `approval_chains` table + seed first chain for doc 01

### Phase IP-2: Admin-side workflow (1-2 sessions)
- Admin UI para upload/edit documents
- Curator/leader/president approval panels
- Gate advance notifications

### Phase IP-3: Member-side ratification (1-2 sessions)
- `/governance/ip-agreement` page with viewer + diff
- Profile gate check + signing flow
- Certificate generation + badge

### Phase IP-4: External signers (opcional, 1 session)
- Magic-link token flow para parceiros externos
- Separate audit trail in `approval_signoffs` com `signer_id IS NULL` + `external_signer_*` fields

**Total estimated**: 4-6 sessions. Not feasible pre-CBGPL. Target: May 2026 post-LIM.

---

## Dependencies and Blockers

### Blocked until:
- Roberto's 2 pontos validation (software as direito autoral + periódicos conflict) — **Legal-counsel review of v2 docs**. Currently deferred (need .docx conversion).
- Ivan + 4 other presidents sign off on v2 content (political track running in parallel)
- PM decisions on 10 open questions above

### Depends on:
- `chapter_registry` table (already exists) for president lookup by chapter_code
- Current `governance_documents` + `certificates` tables (already in place)
- Email infra `campaign_sends` + `campaign_templates` (already in place)
- MCP tool framework (already in place)

### Not blocked by:
- Phase 5 completion (independent domain)
- CBGPL (can run post)

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Roberto's 2 pontos not resolved in v2 | HIGH | Flagged for next legal-counsel session. Block IP-2 until resolved. |
| Presidents reluctant to sign on-platform | MED | Phase IP-4 fallback to hybrid (docusign external) if needed |
| Certificate/Signoff entity confusion | LOW | Data-architect recommends clear separation (above) |
| Member abandonment during gate wait | MED | UX abandonment recovery strategy (above) |
| LGPD exposure of draft content | LOW | `document_versions` RLS: authenticated reads published only |

---

## Next Steps

1. **PM decides** on 10 open questions
2. **Legal-counsel session** — convert 5 .docx to readable format, review for Roberto's 2 points + LGPD compliance
3. **Accountability-advisor session** — define minimum audit trail + PMI governance compliance
4. **Schedule Phase IP-1 start** (document ingestion) for post-CBGPL window

Document owner: Vitor (PM). Council advisors: ux-leader, data-architect, legal-counsel (pending), accountability-advisor (pending).
