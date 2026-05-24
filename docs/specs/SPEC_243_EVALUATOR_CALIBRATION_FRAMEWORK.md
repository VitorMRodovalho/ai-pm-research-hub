# SPEC #243 — Versioned Evaluator Calibration Framework for AI-Assisted Selection

**Issue:** #243 (spec: versioned evaluator calibration framework for AI-assisted selection)
**Status:** Draft (spec-only delivery for #243 close rule + child split)
**Filed:** 2026-05-23 (p236, post-#221/#218 decomposition that unblocked spec work)
**Curator stance (2026-05-23 comment 4524142795):** "Allowed work: spec/ADR and child split only. Operational blockers #260/#251/#116/#179/#230 come first."

This spec proposes the architecture for a governed calibration framework that lifts the PM's external `nucleo-ia-evaluation-calibration` skill (currently used out-of-band during cycle 4 evaluation) into a versioned, in-platform contract that the UI, AI-assist prompts, MCP tools, and QA gates all consume from a single source of truth. It does NOT propose implementation in this issue — only the contract + child split. Implementation will land via ready-leaf children (E2–E6).

---

## 1. Problem

During cycle 4, calibration knowledge for evaluator judgment lived in an external skill the PM invoked manually. The platform has substantial substrate (validation tracking, drift runs, per-criterion notes, suggestion lineage), but the calibration *rules themselves* (PMI-strict certification scoring, courses vs credentials, PMI MORE alignment, CV-vs-form gaps, official GP role vs operational support, mandatory cited evidence, preview-before-confirm, evaluator divergence triggers) are not formalized in a versioned profile the platform can read.

A second cycle 4 observation: calibration quality was materially affected when candidate context was incomplete. Missing resume/CV/LinkedIn/Lattes/Scholar/publication evidence under-scored or misclassified research-track applicants. This needs to become an explicit signal, not a silent assumption.

---

## 2. Substrate audit (what already exists)

### 2.1 Tables already in place

| Table | What it does | Gap for #243 |
|---|---|---|
| `selection_cycles.objective_criteria` / `interview_criteria` / `leader_extra_criteria` / `scoring_formula` (all jsonb) | Per-cycle rubric definitions | Holds *what is scored* but not *how to calibrate the scoring* (no examples, no "counts here / doesn't count" guidance, no evidence expectations) |
| `selection_evaluations.criterion_notes` (jsonb) | Per-criterion evaluator notes | Notes are free-text; no schema enforces "evidence cited" or "calibration confidence" |
| `selection_evaluation_ai_suggestions` | AI suggestion lineage with `prompt_version`, `model_provider/name`, `generation_inputs`, `consumed_at`, `used_in_evaluation_id`, `superseded_by` | `generation_inputs` is jsonb but no field for `calibration_profile_version` or `source_coverage_snapshot` |
| `ai_score_validations` | Per-validation tracking with `validation_action` (`agree`/`disagree`/`override`-like), `override_score`, `comment`, `ai_purpose`, `ai_model`, `ai_score`, `ai_verdict` | Captures human judgment over AI but no per-criterion granularity; no link to calibration profile version active at validation time |
| `ai_calibration_runs` | Per-cycle aggregate drift stats (`n_compared`, `mean_delta_signed`, `mean_delta_abs`, `drift_count_high`, `drift_threshold`, `validator_breakdown`, `sample_payload`) | Aggregates exist; what's missing is a calibration *profile* whose version + content the runs reference, so before/after profile changes can be compared |

### 2.2 RPCs / EFs already in place

- `get_evaluator_calibration_stats` — surfaces evaluator bias/divergence (live MCP tool)
- `compute_ai_calibration_stats` (with p114 normalization fix) — aggregator
- `trigger_ai_calibration_run` — kicks off a calibration run (manual trigger)
- `list_ai_calibration_runs` — paginated read for the calibration page
- Weekly cron for `ai_calibration_runs` (p107/p110 wave)
- `analyze_application` EF — text-based AI analysis (Gemini)
- `analyze_application_video` EF — voice transcription + Claude Haiku 4.5 multimodal video analysis (consent-gated post-p207)

### 2.3 UI already in place

- `/admin/ai-calibration` — dedicated page with `AiCalibrationIsland` component (existing surface for calibration analytics)
- `/admin/selection` — main evaluation UI with inline AI signals + per-criterion notes + human validation controls
- Per-criterion textarea for `criterion_notes` (no calibration hint scaffolding yet)
- AI suggestion preview before consume (p197 #1) — exists but doesn't carry calibration warning text

### 2.4 ADRs that govern adjacent decisions

- **ADR-0059** — Selection phase blind review anti-bias (relevant: what evaluators *can't* see during scoring)
- **ADR-0067** — AI-augmented selection Art. 20 safeguards (relevant: non-binding suggestions, HITL mandate, LGPD basis)
- **ADR-0074** — Onda3 ARM dual-model AI architecture (relevant: how multi-model AI suggestions are framed)
- **ADR-0079** — Subjective scoring via video transcription (relevant: video-derived signals feeding scoring)

The #243 framework MUST consume from these ADRs, not override them.

### 2.5 What's missing (the gap #243 closes)

1. **No `calibration_profiles` table** — there is no place to store versioned calibration *rules* (the "what counts / doesn't count" body, examples, evidence expectations, score ceilings, double-counting rules, calibration meeting triggers).
2. **No context completeness signal model** — no schema or check that asks "is resume/CV/LinkedIn/Lattes/Scholar/Credly coverage sufficient to score reliably?"
3. **No `calibration_profile_version` in suggestion lineage** — AI suggestions reference `prompt_version` but not the active profile version at generation time. Future profile changes can't be cleanly attributed.
4. **No per-criterion calibration hint UI** — `/admin/selection` doesn't render "accepted evidence types / excluded types / common mistake patterns" inline at the moment of scoring.
5. **No outlier/evidence/double-counting preview warning** — `submit_evaluation` runs without flagging "high/low/outlier score without criterion evidence" or "certification scored using non-PMI credentials" before the irreversible lock.
6. **No formal divergence-by-missing-context analytic** — `ai_calibration_runs` aggregates drift but doesn't slice by "context was incomplete at time of scoring," so calibration meetings can't easily target the right root cause.

---

## 3. Proposed contract

### 3.1 Data model: `calibration_profiles` (new table)

```sql
CREATE TABLE public.calibration_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  cycle_code text NOT NULL,           -- e.g. 'cycle4-2026' OR 'default' for cross-cycle fallback
  role_applied text NOT NULL,          -- 'researcher' | 'leader' | 'all'
  evaluation_type text NOT NULL,       -- 'objective' | 'interview' | 'leader_extra' | 'video' | 'all'
  version text NOT NULL,               -- semver-ish: 'v1.0.0' | 'cycle4-2026-rev1'
  is_active boolean NOT NULL DEFAULT false,
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_until timestamptz,         -- NULL = current
  body jsonb NOT NULL,                 -- the calibration content (see 3.2)
  created_by uuid REFERENCES public.members(id),
  created_at timestamptz DEFAULT now(),
  superseded_by uuid REFERENCES public.calibration_profiles(id),
  notes text,                          -- changelog from prior version
  UNIQUE (cycle_code, role_applied, evaluation_type, version)
);

CREATE INDEX idx_calibration_profiles_active
  ON public.calibration_profiles(cycle_code, role_applied, evaluation_type)
  WHERE is_active = TRUE;
```

**Resolution rule**: at evaluation time, resolve the active profile by precedence:
1. Exact match `(cycle_code, role_applied, evaluation_type)` with `is_active=TRUE`
2. Fallback to `(cycle_code, 'all', evaluation_type)`
3. Fallback to `('default', role_applied, evaluation_type)`
4. Fallback to `('default', 'all', 'all')`
5. No profile → return null + UI badge "no active calibration profile; using rubric defaults"

### 3.2 Profile body schema (jsonb)

```json
{
  "version": "cycle4-2026-rev1",
  "summary": "Researcher-track calibration: PMI-strict for certifications, evidence-cited per criterion, no double-count of volunteer-as-leader",
  "principles": [
    { "name": "pmi_strict_certifications", "applies_to": ["certifications"], "rule": "PMP/PMI-ACP/PMI-RMP count at full weight; CSM/PSM/PRINCE2 count at half weight; courses (not certifications) do NOT count toward credential score", "examples": { "counts": ["PMP", "PMI-ACP"], "does_not_count": ["Coursera PM 6h", "EAD 30h"] } },
    { "name": "pmi_more_alignment", "applies_to": ["theme_alignment", "proposed_theme"], "rule": "Themes aligned with PMI MORE strategic priorities (AI, sustainability, DEI, hybrid PM) score higher; pure ops themes score lower" },
    { "name": "official_gp_role", "applies_to": ["leadership_experience"], "rule": "Score requires evidence of OFFICIAL project/program manager authority (budget + team + scope ownership); volunteer-only or operational-support roles do NOT meet the threshold without explicit evidence" },
    { "name": "cv_vs_form_gap_flag", "applies_to": ["all"], "rule": "When CV detail diverges from form summary, the CV is canonical; flag the divergence in criterion_notes" },
    { "name": "evidence_cited", "applies_to": ["all"], "rule": "Each score above the default band MUST cite at least one source: CV section, LinkedIn link, Lattes URL, Credly badge, publication DOI, or interview quote. Notes lacking evidence trigger warning at submit." }
  ],
  "score_bands": {
    "certifications": { "default": 0, "soft_max": 8, "hard_max": 10, "ceiling_warning_threshold": 9 },
    "leadership_experience": { "default": 0, "soft_max": 7, "hard_max": 10 },
    "research_score": { "default": 0, "soft_max": 8, "hard_max": 10, "requires_external_source": true }
  },
  "double_count_rules": [
    { "rule": "Same project listed under both 'leadership' and 'volunteer' may not score in both — split per role" }
  ],
  "calibration_meeting_triggers": {
    "drift_count_high_threshold": 3,
    "evaluator_pair_divergence_count": 2,
    "missing_context_share_threshold": 0.30
  },
  "context_completeness_required": {
    "researcher": ["resume_text_or_cv", "lattes_or_scholar_or_publications"],
    "leader": ["resume_text_or_cv", "linkedin_url"]
  },
  "context_completeness_warning_only": {
    "researcher": ["credly_badges", "linkedin_url"],
    "leader": ["credly_badges", "lattes_url"]
  }
}
```

### 3.3 Context completeness signal model

New RPC `get_application_context_completeness(p_application_id uuid, p_profile_version text DEFAULT NULL)`:

Returns:

```json
{
  "profile_version_used": "cycle4-2026-rev1",
  "role_applied": "researcher",
  "required_sources_present": ["resume_text_or_cv"],
  "required_sources_missing": ["lattes_or_scholar_or_publications"],
  "warning_sources_present": ["credly_badges"],
  "warning_sources_missing": ["linkedin_url"],
  "completeness_pct": 0.50,
  "blocks_submit": false,
  "warning_text": "Sem evidência Lattes/Scholar/publicações; score de pesquisa pode ser sub-estimado",
  "audit_recorded_at": "2026-05-23T..."
}
```

Source predicates (read from `selection_applications` columns + helper joins):

| Source key | Predicate |
|---|---|
| `resume_text_or_cv` | `cv_extracted_text IS NOT NULL OR resume_url IS NOT NULL OR resume_storage_path IS NOT NULL` |
| `linkedin_url` | `linkedin_url IS NOT NULL OR profile_linkedin_url IS NOT NULL` |
| `credly_badges` | `credly_url IS NOT NULL OR EXISTS(credly_badges WHERE member_id matches)` |
| `lattes_or_scholar_or_publications` | (new optional columns `lattes_url`, `scholar_url`, OR `linkedin_relevant_posts IS NOT NULL AND array_length(...) > 0`) — schema extension may be needed; see open questions |
| `pmi_membership_history` | `pmi_memberships IS NOT NULL` OR `service_history_count > 0` |

Not a hard blocker by default. UI surfaces it as a non-blocking warning unless the profile's `context_completeness_required` cohort matches.

### 3.4 UI guardrails in `/admin/selection`

Per-criterion (rendered next to each scoring input):
- One-line hint from `body.principles[N].rule` filtered by `applies_to`
- Click to expand: examples (`counts` / `does_not_count`)
- Calibration version pill ("cycle4-2026-rev1")
- Context completeness chip ("Resume ✅ · LinkedIn ✅ · Lattes ⚠️"): clicking jumps to the application detail panel showing which sources are missing

**Avoid**: turning this into a long instruction document inside the UI. The hint must be 1 line + click-to-expand; the profile body's `summary` field is the only multi-line text rendered inline.

### 3.5 Preview warning contract (extended `submit_evaluation`)

`submit_evaluation()` already returns a preview before lock (per p197 enrichment). Extend the preview to include a `warnings` array:

```json
{
  "preview": { /* existing scores + notes preview */ },
  "warnings": [
    { "code": "outlier_no_evidence", "criterion": "certifications", "severity": "warn", "message": "Score 9 acima do soft_max 8 sem evidência citada em criterion_notes" },
    { "code": "pmi_strict_violation", "criterion": "certifications", "severity": "block_unless_acknowledged", "message": "Score reflete cursos (não certificações) — PMI-strict não permite" },
    { "code": "calibration_band_violation", "criterion": "research_score", "severity": "warn", "message": "Score fora da banda cohort PERT [4.2, 7.8]" },
    { "code": "context_incomplete", "criterion": "all", "severity": "warn", "message": "Lattes/Scholar ausente; researcher score pode estar sub-estimado" },
    { "code": "missing_leader_extra", "criterion": "evaluation_type", "severity": "warn", "message": "Aplicação leader sem leader_extra evaluation" }
  ],
  "block_submit": false,
  "block_reasons": []
}
```

Severity ladder:
- `info` — informational; rendered but doesn't gate
- `warn` — visible warning; doesn't block; logged to audit
- `block_unless_acknowledged` — requires evaluator to type a justification in `criterion_notes[criterion]['acknowledgment']` before submit accepts
- `block` — submit refused until fixed (reserved for hard rule violations like missing required signature)

Warnings NEVER mutate scores silently. Human evaluator remains authoritative.

### 3.6 AI prompt + suggestion lineage extension

Extend `selection_evaluation_ai_suggestions.generation_inputs` jsonb to ALWAYS include:

```json
{
  "calibration_profile_version": "cycle4-2026-rev1",
  "source_coverage_snapshot": {
    "resume_text_or_cv": true,
    "linkedin_url": true,
    "lattes_or_scholar_or_publications": false,
    "credly_badges": true
  },
  "context_completeness_pct": 0.75,
  "prompt_pack_version": "p243_v1"
}
```

Existing fields (`prompt_version`, `model_provider`, `model_name`) stay; the new keys add per-suggestion auditability for *what calibration knowledge was loaded into the prompt* and *what evidence the AI had access to*. The two answer different questions: `prompt_version` answers "which AI prompt template," and `calibration_profile_version` answers "which calibration rules were embedded in that prompt template at generation time."

Update both EFs (`analyze-application` + `analyze-application-video`) to:
1. Resolve active calibration profile at generation time
2. Embed `body.summary` + relevant `body.principles[].rule` items into the system prompt
3. Pass `source_coverage_snapshot` into prompt as context
4. Persist all three under `generation_inputs`

### 3.7 Calibration analytics extension

Extend `get_evaluator_calibration_stats` to slice by:
- `profile_version_at_validation_time` (joined from snapshot at `validated_at`)
- `context_completeness_band` (bucket: full / partial / sparse)
- `missing_source_correlation` (which missing source correlates with which divergence pattern)

These allow calibration meetings to ask: "where did our score drift come from in cycle 4? Was it the profile, the missing context, or evaluator pair X?"

---

## 4. LGPD / HITL stance

- **No autonomous decisioning**: AI suggestions remain advisory. `consumed_at IS NULL` until a human evaluator explicitly validates via `submit_evaluation`. Lineage trail (`ai_suggestion_id` → `used_in_evaluation_id`) preserved.
- **Consent-gated**: `analyze_application` requires `consent_ai_analysis_at`. `analyze_application_video` additionally requires `consent_voice_biometric_at` (post-p207, sibling #331/#332 cover the UI capture + retroactive scope).
- **Calibration profile content NOT PII**: profile body is rules + examples, no candidate data. Safe to share across cycles.
- **`source_coverage_snapshot` is metadata not content**: stores only booleans + counts, not the source text itself.
- **No external profile discovery mandatory**: if a candidate did not provide LinkedIn/Lattes/Scholar OR retrieval is unreliable, the `context_incomplete` warning fires but does NOT block; the human evaluator decides whether to score conservatively or proceed.

---

## 5. Recommended child issue split (PROPOSAL — not filed yet)

Per #243's 5-lane suggestion + the substrate gaps in §2.5. None of these are filed yet — awaits PM approval on the proposal.

| Proposed child | Lane | Status | Blocks | Acceptance evidence |
|---|---|---|---|---|
| **E1** — This spec doc | Governance / Spec | ✅ shipped p236 (this PR) | E2-E6 | This document |
| **E2** — Foundation: `calibration_profiles` table + resolution RPCs (`get_active_calibration_profile`, `get_profile_by_version`) + seed `default` profile + cycle4-2026-rev1 profile from PM's external skill content | Foundation | ready-leaf after PM approval | E3, E4, E5, E6 | Migration applied + 2 profiles seeded + contract test for resolution precedence |
| **E3** — Frontend: per-criterion calibration hint UI in `/admin/selection` + context completeness chip + version pill | Frontend / UX | ready-leaf after E2 | none | Visual smoke + i18n keys present in 3 langs + contract test for hint rendering |
| **E4** — MCP-AI: extend `analyze-application` + `analyze-application-video` EFs to load active profile + embed in prompt + persist `calibration_profile_version` + `source_coverage_snapshot` in `generation_inputs` | MCP-AI | ready-leaf after E2 | E5 (preview shows lineage) | EF deploys + 1 sample suggestion shows new lineage fields + smoke validates prompt embedding |
| **E5** — Foundation + Frontend: preview warning contract in `submit_evaluation` + UI display + acknowledgment flow for `block_unless_acknowledged` severity | Foundation / Frontend | ready-leaf after E2 + E3 | none | Contract test for warning matrix (5+ warning codes) + UI smoke for acknowledgment flow + audit log entry on each warning |
| **E6** — QA: contract tests covering profile resolution precedence, warning matrix, lineage fields, consent gates, HITL non-binding behavior, analytics slicing | QA | ready-leaf parallel to E3-E5 | none | Tests added to `tests/contracts/` covering 6 specific behaviors |

**Sequencing**:
- E2 must ship first (everyone consumes the table/RPCs)
- E3, E4, E5 can run in parallel after E2
- E6 can start immediately after E2 (static tests) and extend as E3-E5 land
- E1 (this doc) ships now and unblocks the others

**Out of scope (carries for future)**:
- Model fine-tuning on candidate data (explicit non-goal per #243)
- Auto-discovery of external profiles (Lattes/Scholar scraping) — only consume if the candidate-provided URL is present
- Live A/B testing of calibration profile versions (a v2 question for after v1 lands)
- AI-driven calibration profile *generation* (humans author profiles; AI consumes them)

---

## 6. Risks + open questions

### 6.1 PM decisions needed before E2 ships

1. **Calibration profile authoring path**: who writes `cycle4-2026-rev1`? Options:
   - (a) PM transcribes from the external skill manually into a SQL seed
   - (b) Spawn a child issue E1.1 to formalize the skill → JSON conversion
   - (c) Accept the external skill as canonical source for v1; E1.1 produces the JSON equivalent before E2 deploys

2. **Lattes / Scholar / publications schema**: do we need new columns on `selection_applications` (`lattes_url`, `scholar_url`)? OR is `linkedin_relevant_posts` jsonb sufficient as a catch-all? Affects E2 scope.

3. **Block severity adoption**: `block_unless_acknowledged` requires evaluator to type a justification — is that acceptable friction for cycle 5 (next opportunity) OR start with `warn`-only and escalate after data shows the warnings are ignored?

4. **Calibration profile vs cycle rubric overlap**: `selection_cycles.objective_criteria` already holds the rubric structure. Does the calibration profile *replace*, *extend*, or *complement* it? Recommend: complement — rubric defines *what to score*, profile defines *how to calibrate the scoring*. Need PM agreement before E2.

5. **Public API surface**: should `get_active_calibration_profile()` be exposed as an MCP tool for external review? Recommend yes (read-only); aligns with #166 semantic layer direction.

### 6.2 Implementation risks

- **Profile-version drift**: if profiles can be edited in place rather than versioned, audit trail breaks. Mitigation: enforce append-only (UPDATE forbidden; new version row required). E2 must include this constraint.
- **Prompt size**: embedding full profile body into every AI prompt could bloat tokens. Mitigation: embed only `summary` + active `principles[]` filtered by `applies_to`; full body available via separate tool call.
- **UI hint info overload**: too many hints make evaluators ignore them. Mitigation: 1-line inline + click-to-expand; surface only when score crosses `soft_max` or evidence is missing.
- **Cross-org leakage**: profiles are `organization_id`-scoped; ensure RLS prevents cross-org reads.

---

## 7. Acceptance criteria status (#243 body)

| Criterion | Status |
|---|---|
| Spec/ADR defines calibration profile model, versioning, data touched, consent basis, audit | **Done** (this doc — promoted to ADR if PM wants formal architectural ratification; current doc serves as spec until then) |
| `/admin/selection` has documented UI plan for context completeness + per-criterion guardrails | **Done** (§3.4 — implementation in E3) |
| AI-assist prompt includes calibration profile version + source coverage | **Done** (§3.6 — implementation in E4) |
| `criterion_notes` expectations documented (when required vs warning) | **Done** (§3.2 evidence_cited principle + §3.5 severity ladder) |
| Missing context represented as explicit warning/confidence signal | **Done** (§3.3 context completeness model + §3.5 `context_incomplete` warning) |
| Follow-up leaf issues created by lane | **Pending** — proposal in §5 awaits PM approval before creation |

---

## 8. Cross-refs

- **Issue**: #243 (parent, this spec satisfies "spec-only" close rule pending child split approval)
- **Related issues**: #254 (Cycle 4 video screening — D5 lineage child depends on this spec) · #251 (Cycle 4 selection trust audit) · #292 (Selection reliability sprint umbrella) · #221+#218 (closed p236 — LGPD voice biometric consent; #243's E4 must remain consent-gated under #331 forward path) · #166 (semantic layer roadmap — E2's RPCs are candidates for public read surface)
- **ADRs that this spec consumes**: ADR-0059 (blind review anti-bias), ADR-0067 (AI Art. 20 safeguards), ADR-0074 (dual-model AI architecture), ADR-0079 (subjective scoring via video)
- **Migrations that this spec extends/references**: `20260316000000_w104_kpi_calibration.sql`, `20260516820000_p107_p1_get_evaluator_calibration_stats_rpc.sql`, `20260517070000_p114_fix_compute_ai_calibration_stats_normalization.sql`, `20260517020000_p110_onda5_calibration_reads_validations.sql`, `20260516960000_onda5_baseline_ai_calibration_runs_and_weekly_cron.sql`
- **External**: PM's `nucleo-ia-evaluation-calibration` skill (v1 source-of-truth; E2 transcribes its content into the seed profile body)

---

## 9. Live state pins (p236)

- HEAD commit at spec time: `5d01dbab` (PR #336 merge — p236 disposition close)
- Invariants 19/19 = 0 violations
- `selection_evaluations` rows with non-null/non-empty `criterion_notes`: TBD (run `SELECT count(*) FROM selection_evaluations WHERE criterion_notes IS NOT NULL AND criterion_notes::text != '{}'` post-spec to baseline)
- `selection_evaluation_ai_suggestions` rows by type: only 1 of type `video` (cycle4 Eduardo Luz background); other types reflect cycle3 history
- `ai_calibration_runs` weekly cron is active
- `/admin/ai-calibration` page is live with `AiCalibrationIsland` component
- `/admin/selection` page is live with inline AI signals + per-criterion notes UI

---

Assisted-By: Claude (Anthropic)
