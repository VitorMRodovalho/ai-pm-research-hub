# SPEC: Diversity Data Enrichment + Certificates/Volunteer Agreement UX

**Status:** Draft
**Priority:** High
**Created:** 2026-04-08
**Author:** Claude (PM/Architect) + Vitor (GP)

---

## 1. Context & Problem Statement

### 1.1 Diversity Dashboard — Empty Data

The `/admin/selection` diversity tab shows "Nao informado" for all demographic dimensions (gender, sector, seniority) because:

- The VEP application form **did not collect** gender, sector, or seniority data
- The `selection_applications` table has 70 rows but `gender` is NULL for all 70
- `sector` and `seniority_years` are also all NULL
- We DO have `applicant_name` (70/70), `state` (68/70), `chapter` (61/70)

**Data available to infer:**
- **Gender** can be inferred from first names with high accuracy for Brazilian Portuguese names (e.g., "Ana Carla" = F, "Fabricio" = M)
- **Sector/seniority** cannot be inferred — would need to be collected in future forms or enriched manually

### 1.2 Certificates & Volunteer Agreement Panel — Missing Visibility

The `/admin/certificates` page currently shows:
- Pending counter-signatures (from `get_pending_countersign` RPC) ✅
- The `VolunteerAgreementPanel` React island was added ✅

**But in production the panel doesn't render because:**
- The `VolunteerAgreementPanel` calls `get_volunteer_agreement_status` which requires manager/chapter_board auth
- The panel self-hides when no data — if the user has permission but the RPC returns empty, nothing shows
- There's no visual feedback about what the panel does or who can see it

**Missing UX elements:**
1. No status explanation for each certificate (what "pending counter-signature" means)
2. No visual workflow showing: Member signs → Chapter board counter-signs → Certificate ready
3. No way to see the signed document/content from the admin view
4. No way to filter by cycle/year
5. No compliance dashboard for managers to see cross-chapter overview

---

## 2. Stakeholder Analysis (by Persona/Tier)

### 2.1 Who accesses `/admin/selection` (Diversity tab)

| Persona | Tier/Designation | What they need |
|---------|-----------------|----------------|
| **GP (Vitor)** | manager + superadmin | Full diversity metrics across all cycles to report to PMI Board and congress. Needs gender/region/chapter breakdown for DEI reporting. |
| **Deputy Manager** | deputy_manager designation | Same as GP for operational purposes |
| **Sponsors (Ivan, Marcio, etc.)** | sponsor + chapter_board | Their chapter's applicant diversity vs approved diversity — to justify selection decisions to their board |
| **Chapter Liaison** | chapter_liaison designation | Similar to sponsor — chapter-level view |

**Key insight:** DEI reporting to PMI requires gender data. Without it, the diversity dashboard is a non-functional shell.

### 2.2 Who accesses `/admin/certificates` (Volunteer Agreement)

| Persona | Tier/Designation | What they need |
|---------|-----------------|----------------|
| **GP (Vitor)** | manager | Global compliance view: which chapters have 100% signed, which are lagging. Export for governance reporting. |
| **Chapter Board (Lorena, Emanoela)** | observer + chapter_board | Their chapter's members: who signed, who didn't, counter-sign pending certs, send reminders. Need clear workflow. |
| **Sponsors (Ivan, Marcio)** | sponsor + chapter_board | Same as chapter board — they are the original signatories for their chapters. |
| **Members (researchers, etc.)** | researcher/cop_participant | See their own cert status in `/certificates` and `/profile` banner. Sign the agreement in `/volunteer-agreement`. |

---

## 3. Requirements

### 3.1 Diversity Data Enrichment

**Data already available in the database (just not structured):**

| Source field | Available | Can extract |
|---|---|---|
| `applicant_name` | 70/70 (100%) | **Gender** (PT-BR first name inference ~95%) |
| `linkedin_url` | 63/70 (90%) | **Sector**, seniority, current role, company |
| `resume_url` | 69/70 (99%) | **All demographics** — sector, experience, background |
| `academic_background` | 64/70 (91%) | Education level, certifications, indirect seniority |
| `certifications` | 33/70 (47%) | Professional level (PMP = senior, CAPM = junior) |
| `leadership_experience` | 12/70 (17%) | Sector context, seniority indicators |
| `role_applied` | 70/70 (100%) | researcher vs leader profile |

#### R1: Gender inference from Brazilian first names (immediate)
- **What:** One-time data enrichment script that infers gender from `applicant_name` first token
- **How:** Curated lookup table of ~200 common Brazilian first names → M/F
- **Accuracy:** ~95% for PT-BR names. Unknown/international names → "Não informado"
- **Scope:** Both cycles (62 + 8 = 70 applications)
- **Storage:** `UPDATE selection_applications SET gender = X` directly
- **Auditability:** Log in `admin_audit_log` with method = 'name_inference'

#### R2: Sector inference from LinkedIn + resume (batch enrichment)
- **What:** Extract sector/industry from existing LinkedIn URLs and resume data
- **How:**
  - **Option A (manual):** Admin reviews 63 LinkedIn profiles and categorizes into sectors (Tecnologia, Engenharia, Consultoria, Governo, Academia, Saude, Financeiro, Outros)
  - **Option B (AI-assisted):** Use the `academic_background`, `leadership_experience`, and `certifications` fields to infer sector via pattern matching (e.g., "Engenheiro Civil" → Engenharia, "ambiente de TI" → Tecnologia)
  - **Option C (LinkedIn scrape):** NOT recommended — violates ToS
- **Recommended:** Option B first (covers ~64/70 from academic_background), then manual review for gaps
- **Storage:** `UPDATE selection_applications SET sector = X, industry = X`

#### R3: Seniority inference from certifications + background
- **What:** Estimate years of experience from available data
- **How:** Heuristic bands based on certifications and academic background:
  - PMP/PMI-RMP/PMI-SP → Senior (10+ years mapped to `seniority_years = 12`)
  - CAPM → Junior (2-5 years mapped to `seniority_years = 3`)
  - MBA/Masters → Mid-Senior (6-10 years mapped to `seniority_years = 8`)
  - No certs, no advanced degree → Entry (0-2 years mapped to `seniority_years = 1`)
- **Accuracy:** Rough approximation — good enough for aggregate DEI charts, not for individual assessment
- **Storage:** `UPDATE selection_applications SET seniority_years = X`

#### R4: Future application forms must collect demographics
- **What:** Next VEP import or application form should include: gender, sector, seniority (years)
- **How:** Add fields to CSV import mapping in `/admin/selection`
- **Options for gender:** Masculino, Feminino, Não-binário, Prefiro não informar

### 3.2 Certificates & Volunteer Agreement UX

#### R4: Visual workflow indicator
- **What:** A clear step-by-step visual showing the certificate lifecycle
- **Steps:** `Membro assina` → `Pendente contra-assinatura` → `Contra-assinado` → `Disponivel`
- **Where:** Top of `/admin/certificates` page, above the panels
- **Design:** Horizontal stepper with active/completed/pending states

#### R5: VolunteerAgreementPanel improvements
- **What:** The existing panel needs better UX
- **Add:**
  - Year/cycle selector (currently hardcoded to current year)
  - Counter-sign action button directly in the member table (for chapter_board users)
  - "View signed document" link that opens the content_snapshot in a modal
  - Progress indicator per chapter (the bar chart already exists but needs labels)
  - Empty state message when no data: "Nenhum membro elegivel assinou ainda neste ciclo"

#### R6: Counter-signature inline in panel
- **What:** Chapter board members should be able to counter-sign directly from the VolunteerAgreementPanel table, not just from the "pending counter-signatures" section
- **How:** Add a "Contra-assinar" button in the status column for signed-but-not-countersigned rows, visible only to authorized users (chapter_board of same chapter, or manager)

#### R7: Certificate document preview
- **What:** Allow admin to view the signed agreement content
- **How:** Button in the table that opens a modal showing `content_snapshot` from the `certificates` table
- **Fields to show:** Member name, email, role, tribe, clauses accepted, signature hash, timestamp

#### R8: Compliance summary on stakeholder dashboard
- **What:** Chapter sponsors and chapter_board should see volunteer agreement compliance on `/stakeholder`
- **How:** Small card similar to the admin dashboard widget, but scoped to their chapter
- **Deferred:** Can be done later — admin dashboard widget is sufficient for now

---

## 4. Technical Plan

### 4.1 Gender inference (Backend)

```sql
-- One-time enrichment: update gender from first name
WITH name_gender AS (
  SELECT unnest AS name, gender FROM (VALUES
    -- Feminine names (common PT-BR)
    ('Ana', 'F'), ('Alessandra', 'F'), ('Andressa', 'F'), ('Deborah', 'F'),
    ('Estela', 'F'), ('Fabricia', 'F'), ('Francisca', 'F'), ('Lorena', 'F'),
    ('Maria', 'F'), ('Paula', 'F'), ('Emanoela', 'F'), ('Jessica', 'F'),
    -- Masculine names (common PT-BR)
    ('Adalberto', 'M'), ('Alexandre', 'M'), ('Antonio', 'M'), ('Daniel', 'M'),
    ('Edson', 'M'), ('Erick', 'M'), ('Fabiano', 'M'), ('Fabricio', 'M'),
    ('Felipe', 'M'), ('Herlon', 'M'), ('Ivan', 'M'), ('Jefferson', 'M'),
    ('Marcos', 'M'), ('Mario', 'M'), ('Matheus', 'M'), ('Pedro', 'M'),
    ('Vitor', 'M'), ('Carlos', 'M'), ('Marcio', 'M'), ('Italo', 'M'),
    ('Joao', 'M'), ('Rafael', 'M'), ('Rodrigo', 'M'), ('Leonardo', 'M'),
    ('Bruno', 'M'), ('Diego', 'M'), ('Fernando', 'M'), ('Gustavo', 'M'),
    ('Lucas', 'M'), ('Thiago', 'M'), ('Wagner', 'M')
    -- ... expand as needed
  ) AS t(unnest, gender)
)
UPDATE selection_applications sa
SET gender = ng.gender
FROM name_gender ng
WHERE SPLIT_PART(sa.applicant_name, ' ', 1) = ng.name
  AND sa.gender IS NULL;
```

### 4.2 Frontend components to create/modify

| Component | Action | File |
|-----------|--------|------|
| `VolunteerAgreementPanel.tsx` | Add counter-sign button, document preview modal, empty state | `src/components/admin/` |
| `CertificateWorkflow.tsx` | NEW — visual stepper showing cert lifecycle | `src/components/admin/` |
| `admin/certificates.astro` | Add workflow stepper above panels | `src/pages/admin/` |
| `DiversityDashboard.tsx` | Add "data incomplete" warning when gender is mostly NULL | `src/components/selection/` |

### 4.3 RPCs to modify

| RPC | Change |
|-----|--------|
| `get_volunteer_agreement_status` | Add `counter_sign_eligible` field per member (true if signed but not countersigned and caller can counter-sign) |
| `get_pending_countersign` | Already fixed — add `content_snapshot` to response for document preview |

---

## 5. Acceptance Criteria

- [ ] Gender data populated for >= 90% of applications (both cycles)
- [ ] Diversity charts show real M/F breakdown instead of "Nao informado"
- [ ] `/admin/certificates` shows visual workflow stepper
- [ ] VolunteerAgreementPanel shows member table with compliance data
- [ ] Chapter board can counter-sign directly from the panel
- [ ] "View document" button shows signed agreement content
- [ ] Empty state when no data instead of blank space
- [ ] All changes pass build + 779 tests

---

## 6. Priority / Sequencing

### Wave 1 — Immediate (this session)
1. **P0 — R1: Gender enrichment** (SQL script, 15 min) — unblocks diversity dashboard
2. **P0 — R2: Sector inference** from academic_background/certifications (SQL script, 20 min)
3. **P0 — R3: Seniority inference** from certifications (SQL script, 10 min)
4. **P0 — VolunteerAgreementPanel visibility fix** (debug why it doesn't render in prod)

### Wave 2 — Next session
5. **P1 — R6: Counter-sign inline** in VolunteerAgreementPanel table (30 min)
6. **P1 — R7: Document preview modal** (30 min)
7. **P1 — R5: Panel UX improvements** — empty state, cycle selector (20 min)

### Wave 3 — Backlog
8. **P2 — R5: Visual workflow stepper** (20 min)
9. **P2 — R4: Future form demographics** (next selection cycle)
10. **P3 — R8: Stakeholder dashboard compliance card** (deferred)
