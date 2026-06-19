# ADR-0103 — Vertical (PMI credential community) as an `initiative_kind`

- **Status:** Accepted (2026-06-19 — Ciclo 4 Fatia 0/A)
- **Issue:** #661 ([Discussão] Modelo Verticais × Quadrantes × Tribos) · #680 (Ciclo 4 frontpage)
- **Origin:** Conceptual model `docs/strategy/verticals_x_quadrants_model.md` (a IA como linha de costura entre os silos do PMI). Ratified in principle by PM (Vitor) on 2026-06-12; **ratified + implemented (kind config + piloto Construção)** on 2026-06-19.
- **Refs:** ADR-0005 (`initiative` as domain primitive), ADR-0009 (config-driven `initiative_kinds`), ADR-0004 (`organization_id`), ADR-0007 (`can()` / engagement grants).
- **Migration:** `supabase/migrations/20260805000221_community_vertical_kind_seed.sql` (kind + engagement_kinds `vertical_lead`/`vertical_member`). Vertical-piloto Construção criada via `create_initiative` em runtime (`81fdbdfa-4a92-401f-9e50-9318be9b94fe`).

## Context

The Núcleo organizes knowledge on three orthogonal axes (see strategy doc):

- **Quadrante** — *what* (knowledge taxonomy; 4 domains). Already modeled.
- **Tribo** — *who produces* (Eixo A). Already an `initiative` of `kind = 'research_tribe'` (ADR-0005).
- **Vertical** — *for whom / where it lands* (Eixo B; a PMI credential community: Construction, PMO, Agile, ESG, Business). **Not yet modeled.**

A vertical is a durable, governed grouping with a partner relationship (Global Construction Ambassadors, PMO Global Alliance, GPM) and an anchor credential (PMI-CP, PMI-PMOCP, PMI-ACP, CSPP, …). Several anchor credentials are *lineages in succession* (PMO-CP → PMI-PMOCP; GPM-b → CSPP), so the model must store the **current** anchor and treat predecessors as history.

The question this ADR settles: **is a vertical a first-class `initiative_kind`, or merely a cross-cutting tag/metadata axis on deliverables?**

## Decision (proposed)

1. **A vertical is an `initiative` of a new `kind = 'community_vertical'`** (config-driven per ADR-0009 — no migration, created via admin). Rationale: a vertical is durable, has governance, a partner, a lifecycle, and sub-work — it is *not* just a label. This matches ADR-0009's own examples (study_group, congress) being kinds.

2. **Sub-work plugs in via `parent_initiative_id`** (ADR-0005 hierarchy): the CPMAI study group, per-community webinars, and workshops become children of their vertical.

3. **Deliverable routing stays N:N via metadata, not containment.** A deliverable produced by a tribe carries `quadrant` (already exists) plus a `verticals text[]` (or join table) routing it to one or more verticals. This preserves the anti-silo principle: *production is the tribe's, distribution is the vertical's — the vertical never owns knowledge.* A vertical does **not** contain the tribe's deliverables; it references them.

4. **`community_vertical` kind config (ADR-0009 `initiative_kinds`)** — proposed `custom_fields_schema`:
   ```
   {
     anchor_credential: text,        -- e.g. 'PMI-PMOCP' (current)
     predecessor_credential: text,   -- e.g. 'PMO-CP' (history, nullable)
     credential_body: text,          -- 'PMI' | 'PMI+GPM' | ...
     partner_org: text,              -- 'PMO Global Alliance' (nullable)
     status: enum,                   -- 'forming' | 'open' | 'paused' (drives the landing CTA)
     pmi_registry_url: text
   }
   ```
   `status` is what the public landing reads to render the "chamada de protagonistas" CTA for *declared-but-not-open* verticals (see strategy doc §CTA). No hardcoded vertical list on the page.

5. **The credential ladder (PMIxAI Champion → CPMAI) is NOT a vertical.** It is the cross-cutting spine shared by all verticals, modeled with the existing gamification/cert primitives (`award_champion`, `cpmai_*`). Verticals reference it; they do not duplicate it.

## Consequences

**Positive**
- Zero schema migration to add a vertical (admin config, per ADR-0009).
- Verticals, tribes, study groups, congresses all share one engine — reports `GROUP BY kind` are natural.
- `status = 'forming'` gives an honest, data-driven "founding cohort" CTA without faking activity.
- Anti-silo invariant is structural: deliverables are referenced, never contained, by verticals.

**Costs / risks**
- `verticals text[]` on deliverables is a new routing field + UI for tagging at publish time.
- Need a guard so a vertical does not accidentally become a parent of a *tribe* (would invert the production/distribution relationship). Constraint: `community_vertical` may parent study_group/webinar/workshop kinds, **not** `research_tribe`.
- Lead capture for `forming` verticals (`capture_visitor_lead` → `application`) needs a `target_vertical` reference.

**Neutral**
- Conceptually a vertical was always a community; this only gives it a home in the existing primitive.

## Alternatives considered

- **(A) Vertical as a pure tag/metadata axis (no initiative).** Rejected: loses governance, partner, lifecycle, and the `forming/open` status that drives the CTA. A tag cannot have a founding cohort.
- **(B) Vertical as a new top-level entity peer to `initiative`.** Rejected: fragments the model, contradicts ADR-0005 (one primitive) and ADR-0009 (config-driven kinds).
- **(C) Vertical contains the tribe's deliverables (containment, not reference).** Rejected: breaks the anti-silo invariant — would make verticals owners of knowledge and recreate the silos.

## Open questions — resolved at ratification (PM, 2026-06-19)

1. **Curated vs. open → CURATED.** Verticals são um catálogo curado: só GP/liderança cria via `create_initiative`. `max_concurrent_per_org = 8` (config). O teto é um botão de config (ADR-0009, editável no admin **sem migration**) e pode ser elevado quando uma vertical específica precisar de mais — reversível por design. Abrir a proposta à comunidade fica como evolução futura (fluxo request-to-join), não bloqueia o Ciclo 4.
2. **`verticals text[]` vs. join → DEFERIDA.** O roteamento deliverable↔vertical não é necessário para a landing (que só lê a existência da vertical + `metadata.status`). Decidir quando o relatório `GROUP BY vertical` ou metadata de roteamento (framing/owner) for necessário. Sem impacto na Fatia A.
3. **Âncora própria + escada → SIM.** Cada vertical tem sua credencial-âncora (`metadata.anchor_credential`, ex.: Construção = PMI-CP) **além** da escada transversal Champion→CPMAI. Bakeado no `custom_fields_schema`.
4. **Vertical-piloto → CONSTRUÇÃO** (PM sobrepôs a sugestão ESG/Ágil): Henrique Diniz já em pré-onboarding como líder fundador = âncora real, não vaporware.

## Implementação (Fatia A, 2026-06-19) — o que foi feito vs. adiado

**Feito** (migration `20260805000221` + runtime):
- Kind `community_vertical`: `has_board/meeting_notes/deliverables/attendance/certificate = false` (a vertical referencia, não executa — anti-silo §3), `max_concurrent_per_org = 8`, `lifecycle_states` no domínio do engine (`draft/active/concluded/archived`). `metadata.status` (`forming|open|paused`) é ortogonal ao `initiatives.status` e é o que a landing lê para o CTA.
- `custom_fields_schema` com `required: [anchor_credential, status]` (validado por `validate_initiative_metadata` — presença + tipo; enum não é validado no trigger, controlado pela app).
- Par dedicado de engagement kinds `vertical_lead` (legal_basis=consent) + `vertical_member` (legitimate_interest), `initiative_kinds_allowed=['community_vertical']`. **Não** se reusou `committee_*`/`workgroup_*` para não contaminar a CASE WHEN de `operational_role` (`sync_operational_role_cache`) nem a semântica legal.
- Vertical Construção criada (`81fdbdfa…`, `initiatives.status=active`, `metadata.status=forming`, anchor PMI-CP, parceiro Global Construction Ambassadors). Henrique registrado como **líder pretendido em `metadata.intended_lead`** (`engagement_status=pending_volunteer_term`).

**Adiado para a ativação** (kickoff do Ciclo 4 / termo de voluntário do Henrique — decisão PM "não promover ainda"):
- **Engajar o Henrique** como `vertical_lead × leader` (via `manage_initiative_engagement`) — só após o termo de voluntário assinado.
- **Seeds de `engagement_kind_permissions`** para `vertical_lead × leader` (manage_member/initiative, view_pii/initiative, write/initiative): não conceder PII/gestão a um líder ainda em pré-onboarding; gestão da coorte fundadora é GP-only por ora.
- **Elevação de `operational_role`**: `vertical_lead` hoje deriva `guest` (não está na CASE WHEN); elevar (ex.: → researcher) só quando a vertical for `open`. Evita mexer em trigger crítico sem necessidade.
- **Invariante `AJ_vertical_no_tribe_child`** (guard: `community_vertical` não pode parentear `research_tribe` — inverteria o eixo produção/distribuição, §Costs): só relevante quando existir fluxo de criação de filhos de vertical. `create_initiative` não cria filhos automaticamente; o guard entra junto com esse fluxo (Fatia B+).

---
*Authored with PMO (Claude); decision and ratification are the PM/council's. Ratified + implemented against prod 2026-06-19.*
