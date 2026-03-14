# W124 — Selection Pipeline Digital + Onboarding Journey

**Wave:** 124
**Priority:** Critical (enables Cycle 4 selection at scale)
**Estimated effort:** 4-5 sprints
**Dependencies:** W116 (notifications), W106 (attendance), W90 (curation rubric pattern)
**Source documents:** SELECTION_PROCESS_DEEP_ANALYSIS.md, Manual de Governança R2 (Seção 3), Selecao_candidatos_2026-1.xlsx, WhatsApp Onboarding Chat

---

## 1. EXECUTIVE SUMMARY

Digitize the end-to-end selection and onboarding pipeline currently run via Excel + WhatsApp. The system must support: unified candidacy (researcher + leader in one vacancy), blind evaluation by a configurable Selection Committee, automated scoring with PERT consolidation, candidate status tracking, diversity dashboard, and a 7-step digital onboarding checklist. All historical Cycle 3 data (48 candidates, 10 leader candidates, scores, decisions) must be imported.

---

## 2. GOVERNANCE DECISIONS (confirmed by GP)

| Decision | Detail |
|---|---|
| Selection Committee | Configurable per cycle. GP validates final decisions if not on the committee. Min 2 evaluators. |
| Blind review | Each evaluator scores in isolation. Cannot see other evaluators' scores until all submit. |
| Scale | 0-10 for all criteria with calibration guide per faixa. |
| Vacancy model | Unified: one vacancy, optional leader questions. Fork to leader track at GP discretion. |
| Talent pool | Candidates below 75% of median threshold = rejected. Can reapply. Track application count (GP decides visibility to avoid bias). |
| Diversity | Dashboard tracking: gender, seniority, industry, sector (public/private/academic), region, age band. |
| Onboarding | Included in this wave. 7-step digital checklist. |
| VEP integration | Candidacy stays on PMI VEP. Platform imports CSV export. |
| Interviews | Self-scheduling via Google Calendar Booking Page. Link stored per cycle. |
| SLA | Required per pipeline stage. Auto-alerts on overdue. |
| Conversion flow | Researcher → Leader: system pre-recommends based on score threshold + GP approves + candidate accepts. |

---

## 3. SCHEMA

### 3.1 New Tables

```sql
-- ============================================================
-- SELECTION CYCLES
-- ============================================================
CREATE TABLE selection_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_code text NOT NULL,                    -- e.g. '2026-1'
  title text NOT NULL,                         -- e.g. 'Seleção Ciclo 3 — 1º Semestre 2026'
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','open','evaluation','interview','decision','closed')),
  open_date date,
  close_date date,
  interview_booking_url text,                  -- Google Calendar Booking Page URL
  min_evaluators int NOT NULL DEFAULT 2,
  -- Scoring config
  objective_criteria jsonb NOT NULL DEFAULT '[]',
  -- Example: [{"key":"certification","label":"Certificação em GP","weight":2,"scale_min":0,"scale_max":10,"guide":"0=Nenhuma, 5=CAPM/Outra, 10=PMP/CPMAI"},...]
  interview_criteria jsonb NOT NULL DEFAULT '[]',
  -- Example: [{"key":"communication","label":"Comunicação","weight":1,"scale_min":0,"scale_max":10,"guide":"0-3=Ruim, 4-6=Regular, 7-8=Bom, 9-10=Ótimo"}]
  leader_extra_criteria jsonb DEFAULT '[]',     -- Additional criteria for leader track
  -- Thresholds
  objective_cutoff_formula text DEFAULT '(2*min + 4*avg + 2*max) / 6 * 0.75',
  final_cutoff_formula text DEFAULT '(2*min + 4*avg + 2*max) / 6 * 0.75',
  -- Onboarding config
  onboarding_steps jsonb NOT NULL DEFAULT '[]',
  -- Example: [{"key":"accept_invite","label":"Aceitar convite na plataforma","sla_days":2},{"key":"vep_accept","label":"Aceitar posição no VEP","sla_days":7},...]
  created_by uuid REFERENCES members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- ============================================================
-- SELECTION COMMITTEE (who evaluates in this cycle)
-- ============================================================
CREATE TABLE selection_committee (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES selection_cycles(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES members(id),
  role text NOT NULL DEFAULT 'evaluator'
    CHECK (role IN ('evaluator','lead','observer')),
  can_interview boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE(cycle_id, member_id)
);

-- ============================================================
-- APPLICATIONS (one per candidate per cycle)
-- ============================================================
CREATE TABLE selection_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES selection_cycles(id),
  -- Candidate data (from VEP import)
  vep_application_id text,
  applicant_name text NOT NULL,
  first_name text,
  last_name text,
  email text NOT NULL,
  phone text,
  pmi_id text,
  chapter text,                                -- PMI-GO, PMI-CE, etc.
  state text,
  country text,
  linkedin_url text,
  resume_url text,
  membership_status text,
  certifications text,
  -- Application content
  role_applied text NOT NULL DEFAULT 'researcher'
    CHECK (role_applied IN ('researcher','leader','both')),
  motivation_letter text,                      -- "Reason for Applying"
  non_pmi_experience text,
  areas_of_interest text,
  availability_declared text,
  -- Leader-specific (optional)
  proposed_theme text,                         -- "Qual temática inédita..."
  leadership_experience text,                  -- "Descreva uma experiência..."
  academic_background text,                    -- "Qual sua base acadêmica..."
  -- Pipeline state
  status text NOT NULL DEFAULT 'submitted'
    CHECK (status IN (
      'submitted',           -- Imported from VEP
      'screening',           -- Minimum requirements check
      'objective_eval',      -- Objective evaluation in progress
      'objective_cutoff',    -- Below cutoff after objective eval
      'interview_pending',   -- Passed objective, awaiting interview
      'interview_scheduled', -- Interview date set
      'interview_done',      -- Interview completed
      'interview_noshow',    -- Candidate didn't show
      'final_eval',          -- Final scoring in progress
      'approved',            -- Selected
      'rejected',            -- Below threshold
      'waitlist',            -- Borderline
      'converted',           -- Moved to different role (e.g. researcher→leader)
      'withdrawn',           -- Candidate withdrew
      'cancelled'            -- Admin cancelled (no response, etc.)
    )),
  -- Conversion tracking
  converted_from text,                         -- 'researcher' if was converted to leader
  converted_to text,                           -- 'leader' if converted from researcher
  conversion_reason text,
  -- Tags (replaces color coding in spreadsheet)
  tags text[] DEFAULT '{}',                    -- e.g. ['convert_to_leader','returning_member','comms_potential']
  -- Scores (denormalized for fast reads)
  objective_score_avg numeric,
  interview_score numeric,
  final_score numeric,
  rank_chapter int,
  rank_overall int,
  -- Feedback
  feedback text,
  -- Metadata
  is_returning_member boolean DEFAULT false,   -- Returning from previous cycle
  previous_cycles text[],                      -- e.g. ['cycle-2']
  application_count int DEFAULT 1,             -- How many times applied across cycles
  -- Diversity fields (self-declared, optional)
  gender text,
  age_band text,                               -- '18-25','26-35','36-45','46-55','56+'
  industry text,
  sector text,                                 -- 'public','private','academic','ngo'
  seniority_years int,
  --
  imported_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- ============================================================
-- EVALUATIONS (one per evaluator per application per phase)
-- ============================================================
CREATE TABLE selection_evaluations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  evaluator_id uuid NOT NULL REFERENCES members(id),
  evaluation_type text NOT NULL
    CHECK (evaluation_type IN ('objective','interview','leader_extra')),
  -- Scores stored as JSONB: {"certification":8, "research_exp":6, ...}
  scores jsonb NOT NULL DEFAULT '{}',
  weighted_subtotal numeric,                   -- Σ(weight × score)
  notes text,                                  -- Evaluator private notes
  -- Blind review enforcement
  submitted_at timestamptz,                    -- NULL = draft, NOT NULL = locked
  created_at timestamptz DEFAULT now(),
  UNIQUE(application_id, evaluator_id, evaluation_type)
);

-- ============================================================
-- INTERVIEWS
-- ============================================================
CREATE TABLE selection_interviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  interviewer_ids uuid[] NOT NULL,             -- Array of member IDs who will interview
  scheduled_at timestamptz,
  duration_minutes int DEFAULT 30,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','scheduled','completed','noshow','cancelled','rescheduled')),
  conducted_at timestamptz,
  theme_of_interest text,                      -- What the candidate wants to research
  calendar_event_id text,                      -- Google Calendar event ID
  notes text,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- ONBOARDING PROGRESS (one row per step per approved member)
-- ============================================================
CREATE TABLE onboarding_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id),
  member_id uuid REFERENCES members(id),       -- Linked once member record is created
  step_key text NOT NULL,                      -- matches onboarding_steps[].key in cycle config
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_progress','completed','skipped','overdue')),
  completed_at timestamptz,
  evidence_url text,                           -- Screenshot/badge upload
  notes text,
  sla_deadline timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE(application_id, step_key)
);

-- ============================================================
-- DIVERSITY SNAPSHOT (aggregate per cycle, no PII)
-- ============================================================
CREATE TABLE selection_diversity_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES selection_cycles(id),
  snapshot_type text NOT NULL
    CHECK (snapshot_type IN ('applicants','approved','final_roster')),
  metrics jsonb NOT NULL,
  -- Example: {"gender":{"M":28,"F":18,"NB":2},"chapter":{"PMI-GO":15,...},"sector":{"private":30,...}}
  created_at timestamptz DEFAULT now()
);
```

### 3.2 Indexes

```sql
CREATE INDEX idx_sel_apps_cycle ON selection_applications(cycle_id);
CREATE INDEX idx_sel_apps_status ON selection_applications(status);
CREATE INDEX idx_sel_apps_chapter ON selection_applications(chapter);
CREATE INDEX idx_sel_apps_email ON selection_applications(email);
CREATE INDEX idx_sel_evals_app ON selection_evaluations(application_id);
CREATE INDEX idx_sel_evals_evaluator ON selection_evaluations(evaluator_id);
CREATE INDEX idx_sel_interviews_app ON selection_interviews(application_id);
CREATE INDEX idx_onb_progress_app ON onboarding_progress(application_id);
CREATE INDEX idx_onb_progress_member ON onboarding_progress(member_id);
```

### 3.3 RLS Policies

```sql
ALTER TABLE selection_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_interviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_progress ENABLE ROW LEVEL SECURITY;

-- All selection tables: read/write via SECURITY DEFINER RPCs only
-- No direct client access (same pattern as board_items)
```

---

## 4. RPCs (SECURITY DEFINER)

### 4.1 Cycle Management

```
admin_manage_selection_cycle(p_action, p_cycle_id, p_data jsonb)
  -- CRUD for cycles. Superadmin + GP only.
  -- p_data includes: objective_criteria, interview_criteria, onboarding_steps, etc.
  -- When creating: auto-seed default criteria from Manual de Governança Tabela 3

get_selection_cycles()
  -- Returns all cycles. Committee members see evaluation status.
  -- Sponsors see pipeline counts for their chapter.
```

### 4.2 Application Import & Management

```
import_vep_applications(p_cycle_id, p_csv_data jsonb)
  -- Bulk import from VEP CSV export.
  -- Auto-detects returning members (email match in members table).
  -- Auto-sets is_returning_member and previous_cycles.
  -- Auto-sets application_count from previous selection_applications by email.
  -- Returns: {imported: N, duplicates: N, returning: N}

get_selection_applications(p_cycle_id, p_filters jsonb)
  -- Filters: status, chapter, role_applied, tags
  -- Committee sees all. Sponsor sees own chapter only.
  -- BLIND: scores not included until all evaluators submit.

admin_update_application(p_application_id, p_data jsonb)
  -- Update status, tags, feedback, conversion fields
  -- Triggers notification to candidate on status change
  -- Log change in data_anomaly_log for audit trail

admin_tag_application(p_application_id, p_tags text[])
  -- Add tags like 'convert_to_leader', 'comms_potential', 'returning_member'
```

### 4.3 Evaluation (Blind Review)

```
get_evaluation_form(p_application_id, p_evaluation_type)
  -- Returns: application data (name, resume, motivation, etc.) + criteria from cycle config
  -- DOES NOT return other evaluators' scores (blind review)
  -- If evaluator already has a draft, returns their draft scores

submit_evaluation(p_application_id, p_evaluation_type, p_scores jsonb, p_notes text)
  -- Validates: caller is in selection_committee for this cycle
  -- Validates: all required criteria have scores
  -- Validates: scores within scale_min/scale_max
  -- Calculates weighted_subtotal
  -- Sets submitted_at (locks evaluation)
  -- If all evaluators for this application have submitted:
  --   → Calculate objective_score_avg using PERT formula
  --   → Check against cutoff threshold
  --   → Auto-advance status: objective_eval → interview_pending (or objective_cutoff)
  --   → Create notification for GP

get_evaluation_results(p_application_id)
  -- Only available AFTER all evaluators submit (blind unlock)
  -- Returns: all evaluators' scores side by side + averages + PERT consolidated
  -- Highlights divergence > 3 points on any criterion (calibration alert)
```

### 4.4 Interview Management

```
schedule_interview(p_application_id, p_interviewer_ids, p_scheduled_at, p_calendar_event_id)
  -- Creates interview record
  -- Updates application status to interview_scheduled
  -- Creates notification for candidate (if email in members)

submit_interview_scores(p_interview_id, p_scores jsonb, p_theme text, p_notes text)
  -- Each interviewer submits independently
  -- When all interviewers submit:
  --   → Calculate interview_score
  --   → Calculate final_score = objective_score_avg + interview_score
  --   → Recalculate rankings (per chapter + overall)
  --   → Auto-advance status to final_eval

mark_interview_status(p_interview_id, p_status)
  -- noshow, cancelled, rescheduled
```

### 4.5 Decision & Ranking

```
calculate_rankings(p_cycle_id)
  -- Recalculates rank_chapter and rank_overall for all applications in cycle
  -- Based on final_score DESC, with chapter grouping
  -- Returns sorted list with recommended decisions:
  --   → score >= median: 'approve'
  --   → score >= cutoff but < median: 'waitlist'
  --   → score < cutoff: 'reject'
  --   → objective_score_avg > 90th percentile: flag 'convert_to_leader'

finalize_decisions(p_cycle_id, p_decisions jsonb)
  -- GP bulk-sets final decisions: [{application_id, decision, feedback}]
  -- Validates: only GP or committee lead can finalize
  -- For approved: auto-creates member record in members table if not exists
  --   → Sets: email, full_name, chapter, pmi_id, phone, linkedin_url, operational_role, current_cycle
  -- For converted: creates selection_conversions record
  -- Triggers notifications per decision type
  -- Triggers onboarding_progress creation for approved candidates
  -- Takes diversity snapshot

get_pipeline_dashboard(p_cycle_id)
  -- Returns aggregate counts by status, chapter, role_applied
  -- Includes conversion funnel: submitted → screening → eval → interview → approved
  -- Includes diversity breakdown
  -- Includes SLA compliance (% on time per stage)
```

### 4.6 Onboarding

```
get_onboarding_status(p_application_id)
  -- Returns checklist with step status, SLA, completion %
  -- Available to: the member themselves, GP, Dir. Voluntariado

update_onboarding_step(p_application_id, p_step_key, p_status, p_evidence_url)
  -- Marks step as completed/skipped
  -- If all required steps completed:
  --   → Update member status to 'active' in members table
  --   → Notify Tribe Leader for allocation
  --   → Notify Comms team for welcome announcement

get_onboarding_dashboard(p_cycle_id)
  -- Aggregate: how many at each step, who's overdue
  -- Per-chapter breakdown
```

### 4.7 Diversity

```
get_diversity_dashboard(p_cycle_id)
  -- Returns current diversity metrics from selection_applications
  -- Dimensions: gender, chapter, sector, seniority, industry, region
  -- Comparison: applicants vs approved vs historical
  -- Recommendations: which dimensions are underrepresented
```

---

## 5. DEFAULT CRITERIA CONFIGURATION

### 5.1 Researcher Objective Criteria (0-10 scale)

| Key | Label | Weight | Calibration Guide |
|---|---|---|---|
| certification | Certificação em GP | 2 | 0=Nenhuma, 3=CAPM/Outra, 5=PMI-ACP/Especialização, 8=PMP, 10=PMP+CPMAI+Outras |
| research_exp | Experiência em Pesquisa | 2 | 0=Nenhuma, 3=Participou de 1 projeto, 5=Publicações, 8=Múltiplas publicações, 10=Peer reviewer/orientador |
| gp_knowledge | Conhecimento em GP | 3 | 0=Nenhum, 3=Familiaridade PMBOK, 5=Pratica GP, 8=GP sênior, 10=Expert reconhecido |
| ai_knowledge | Conhecimento em IA | 3 | 0=Nenhum, 3=Usa ferramentas IA, 5=Entende conceitos ML/NLP, 8=Implementa soluções IA, 10=Especialista IA |
| tech_skills | Habilidades Técnicas | 2 | 0=Nenhuma, 3=Ferramentas básicas, 5=Softwares especializados, 8=Programação/dados, 10=Full-stack/DevOps |
| availability | Disponibilidade | 1 | 0=Indisponível, 3=2-3h/semana, 5=4h/semana, 8=5-6h/semana, 10=6+h com flexibilidade |
| motivation | Carta de Motivação | 2 | 0=Ausente/genérica, 3=Alinhada parcialmente, 5=Clara e alinhada, 8=Excepcional+tema específico, 10=Visionária com plano |

### 5.2 Interview Criteria (0-10 scale)

| Key | Label | Weight | Calibration Guide |
|---|---|---|---|
| communication | Comunicação | 1 | 0-3=Dificuldade de expressão, 4-6=Clara mas básica, 7-8=Articulada, 9-10=Excepcional |
| proactivity | Proatividade e Iniciativa | 1 | 0-3=Passiva, 4-6=Reativa, 7-8=Proativa com sugestões, 9-10=Visionária |
| teamwork | Trabalho em Equipe | 1 | 0-3=Individual, 4-6=Colaborativa, 7-8=Facilitadora, 9-10=Mentora natural |
| cultural_fit | Alinhamento Cultural | 1 | 0-3=Desalinhado, 4-6=Compatível, 7-8=Forte fit, 9-10=Embaixador natural |

### 5.3 Leader Extra Criteria (0-10 scale, additional to researcher)

| Key | Label | Weight | Calibration Guide |
|---|---|---|---|
| strategic_vision | Visão Estratégica | 3 | 0-3=Operacional, 4-6=Tática, 7-8=Estratégica, 9-10=Visionária transformacional |
| leadership_track | Histórico de Liderança | 2.5 | 0-3=Nenhum, 4-6=Equipe pequena, 7-8=Projetos inovação, 9-10=Múltiplos programas |
| domain_expertise | Conhecimento Técnico (GP+IA) | 2 | 0-3=Básico, 4-6=Intermediário, 7-8=Avançado, 9-10=Expert publicado |
| pmi_involvement | Envolvimento com PMI | 1.5 | 0-3=Membro passivo, 4-6=Voluntário ativo, 7-8=Liderança capítulo, 9-10=Global PMI |
| language | Idiomas | 1 | 0-3=PT básico, 4-6=PT fluente, 7-8=PT+EN proficiente, 9-10=PT+EN+outro |

### 5.4 Scoring Formulas

```
-- Per evaluator subtotal:
subtotal = Σ(criterion_weight × criterion_score)

-- Consolidated score (PERT across evaluators):
consolidated = (2 × MIN(subtotals) + 4 × AVG(subtotals) + 2 × MAX(subtotals)) / 8
-- Note: formula with 8 divisor for N>=2 evaluators

-- Cutoff threshold per phase:
cutoff = consolidated_median × 0.75

-- Final score:
final_score = objective_consolidated + interview_consolidated

-- Ranking: ORDER BY final_score DESC, per chapter and overall
```

---

## 6. DEFAULT ONBOARDING STEPS

```json
[
  {"key": "accept_invite", "label": "Aceitar convite na plataforma", "sla_days": 2, "required": true,
   "description": "Clique no link de convite recebido por email e complete seu cadastro."},

  {"key": "complete_profile", "label": "Completar perfil", "sla_days": 3, "required": true,
   "description": "Preencha: bio, LinkedIn, foto, disponibilidade semanal, áreas de interesse."},

  {"key": "vep_accept", "label": "Aceitar posição no PMI VEP", "sla_days": 7, "required": true,
   "description": "Acesse volunteer.pmi.org e aceite a oferta de voluntário do Núcleo. Envie print da confirmação."},

  {"key": "kickoff_course", "label": "Completar curso Kickoff PMI", "sla_days": 7, "required": true,
   "description": "Complete pelo menos um: Kickoff Preditivo ou Kickoff Ágil (45min cada). Link: pmi.org/kickoff. Envie print da badge."},

  {"key": "volunteer_term", "label": "Assinar Termo de Voluntariado", "sla_days": 14, "required": true,
   "description": "O Termo será gerado automaticamente com seus dados. Assine eletronicamente na plataforma."},

  {"key": "join_channels", "label": "Entrar nos canais de comunicação", "sla_days": 7, "required": true,
   "description": "Entre no grupo geral do WhatsApp e no grupo da sua tribo. Links fornecidos após alocação."},

  {"key": "attend_kickoff", "label": "Participar do Kick-off do projeto", "sla_days": 21, "required": true,
   "description": "Participe da reunião geral de abertura do ciclo. Data será comunicada via email e WhatsApp."}
]
```

---

## 7. UI PAGES

### 7.1 `/admin/selection` — Pipeline Dashboard (GP + Committee)

**Layout:** Kanban-style columns for each status stage.
**Cards:** Candidate name, chapter badge, score (when available), tags.
**Filters:** Chapter, role_applied, status, tags.
**Actions:** Bulk import (CSV), create cycle, finalize decisions.
**Metrics bar:** Total candidates, per chapter, conversion funnel, SLA compliance.

### 7.2 `/admin/selection/[cycleId]` — Cycle Detail

**Tabs:**
- **Pipeline** — Kanban view of all applications
- **Evaluations** — List of pending/completed evaluations per evaluator
- **Interviews** — Calendar view of scheduled interviews
- **Rankings** — Sorted table with scores, ranks, recommended decisions
- **Onboarding** — Progress dashboard for approved candidates
- **Diversity** — Charts: chapter distribution, gender, sector, seniority, region
- **Settings** — Criteria config, committee members, SLA, thresholds

### 7.3 `/admin/selection/evaluate/[applicationId]` — Evaluation Form

**Split view:**
- **Left panel:** Candidate info (name, chapter, certifications, resume link, LinkedIn link, motivation letter, VEP responses). LinkedIn URL opens in new tab for GP research.
- **Right panel:** Rubric with sliders (0-10) per criterion. Each criterion shows calibration guide on hover. Notes field at bottom. Submit button locks evaluation.

**Blind enforcement:** No scores from other evaluators visible until own submission is locked.

### 7.4 `/admin/selection/results/[applicationId]` — Evaluation Results (post-blind)

**All evaluators' scores side-by-side.** Divergence > 3 points highlighted in amber. PERT consolidated score. Interview scores below. Final score + rank.

### 7.5 `/workspace` addition — Onboarding Checklist (for new members)

**Widget in workspace:** Progress bar (X/7 steps complete). Expandable checklist with description, upload button, status badge. SLA countdown per step.

### 7.6 `/admin/chapter-report` addition — Selection Pipeline Metrics

**New section in chapter dashboard:** Candidates per chapter in current cycle, approval rate, average score, diversity metrics.

---

## 8. NOTIFICATIONS (extend W116)

| Trigger | Recipient | Type |
|---|---|---|
| New cycle opens | All members (announcement) | `selection_cycle_open` |
| Application imported | Committee members | `selection_new_applications` |
| All evaluators submitted for an application | Committee lead + GP | `selection_evaluation_complete` |
| Interview scheduled | Candidate (if member) + interviewers | `selection_interview_scheduled` |
| Interview no-show (24h after scheduled) | GP | `selection_interview_noshow` |
| Decision finalized (approved) | New member | `selection_approved` |
| Decision finalized (rejected) | Candidate email (external) | `selection_rejected` |
| Decision finalized (waitlist) | Candidate email (external) | `selection_waitlisted` |
| Conversion offer (researcher→leader) | Candidate | `selection_conversion_offer` |
| Onboarding step overdue | Member + GP | `onboarding_overdue` |
| Onboarding 100% complete | Tribe Leader + Comms | `onboarding_complete` |

---

## 9. HISTORICAL DATA IMPORT (Cycle 3)

### 9.1 Cycle Config Seed

```sql
INSERT INTO selection_cycles (cycle_code, title, status, open_date, close_date, ...)
VALUES ('2026-1', 'Seleção Ciclo 3 — 1º Semestre 2026', 'closed', '2026-01-16', '2026-02-11', ...);
```

### 9.2 Application Import

From `Selecao_candidatos_2026-1.xlsx`:
- **48 researcher candidates** (tab "Avaliação Pesquisador") with full scores
- **10 leader candidates** (tab "Avaliação Líderes") with full scores
- All evaluation scores per evaluator (Fabricio + Vitor)
- Interview data (date, theme, scores)
- Final decisions (Approved, Rejected, Waitlist, Converted, Withdrawn, Cancelled)
- Tags (from color coding): convert_to_leader, returning_member, comms_potential
- Feedback text

### 9.3 Member Data Enrichment

From `Ciclo 2 + Ciclo 3` tab — update existing members with:
- phone, linkedin_url, pmi_id (WHERE NULL)
- 44 members to update

---

## 10. IMPLEMENTATION PHASES

### Phase 1: Schema + Import + Dashboard (Sprint 1-2)

1. Create all 6 tables + indexes + RLS
2. Create RPCs: admin_manage_selection_cycle, import_vep_applications, get_selection_applications, get_pipeline_dashboard
3. Seed Cycle 3 data from spreadsheet (48 + 10 candidates with all scores)
4. Member data enrichment (44 members: phone, linkedin, pmi_id)
5. UI: `/admin/selection` pipeline dashboard with Kanban view
6. Tests: schema validation, import integrity, dashboard queries

### Phase 2: Blind Evaluation + Scoring (Sprint 2-3)

1. Create RPCs: get_evaluation_form, submit_evaluation, get_evaluation_results, calculate_rankings
2. Scoring engine: weighted subtotals, PERT consolidation, cutoff calculation, auto-ranking
3. Calibration alert (divergence > 3 points)
4. UI: `/admin/selection/evaluate/[id]` — split-view evaluation form
5. UI: `/admin/selection/results/[id]` — post-blind comparison
6. Tests: blind enforcement, score calculation accuracy, ranking order

### Phase 3: Interview + Decision + Conversion (Sprint 3-4)

1. Create RPCs: schedule_interview, submit_interview_scores, mark_interview_status, finalize_decisions
2. Conversion flow: pre-recommendation + GP approval + candidate acceptance
3. Auto-create member on approval
4. Notifications (extend W116 triggers)
5. UI: Rankings tab with bulk decision actions
6. UI: Conversion dialog
7. Tests: decision flow, member creation, notification triggers

### Phase 4: Onboarding + Diversity (Sprint 4-5)

1. Create RPCs: get_onboarding_status, update_onboarding_step, get_onboarding_dashboard, get_diversity_dashboard
2. Onboarding checklist widget in `/workspace`
3. Evidence upload (reuse Supabase Storage)
4. SLA enforcement with overdue notifications
5. Diversity dashboard with charts (recharts)
6. Chapter report integration (W115 extension)
7. Tests: onboarding progression, SLA alerts, diversity calculations

---

## 11. MANUAL DE GOVERNANÇA — CHANGE PROPOSALS

Based on the analysis, the following changes should be proposed to the Manual R2 for approval:

| # | Current (Manual R2) | Proposed Change | Rationale |
|---|---|---|---|
| MG-1 | Seção 3.4 — Researcher selection uses Tabela 3 with mixed scales (0-1, 0-5, 0-3) | Normalize all scales to 0-10 with calibration guide | Better discrimination, easier to understand |
| MG-2 | Seção 3.4 — Leader selection is same as researcher + no extra evaluation | Formalize leader as researcher evaluation + leader extra criteria (5 additional criteria from Tabela 2) | Current practice already does this informally |
| MG-3 | Seção 3.4 — "Dois avaliadores independentes" | Formalize Selection Committee (min 2, configurable) with blind review | Scalable governance |
| MG-4 | Not covered | Formalize conversion flow: researcher→leader recommendation + GP approval + candidate acceptance | Already practiced informally (3 candidates converted in Cycle 3) |
| MG-5 | Seção 3.4 — Disponibilidade scale 0-5 | Standardize to 0-10 like all other criteria | Consistency |
| MG-6 | Not covered | Diversity metrics tracking and reporting per cycle | PMI Global alignment, R&D best practice |
| MG-7 | Seção 3.8.1 — Onboarding described in prose | Formalize 7-step onboarding checklist with SLAs | Measurable, trackable |

These changes should be logged in `GOVERNANCE_CHANGELOG.md` as GC-007 through GC-013 once approved by the Liderança dos Capítulos.

---

## 12. CONTRACT TESTS

```
test_selection_schema:
  - selection_cycles table exists with correct columns
  - selection_applications table exists with all status enum values
  - selection_evaluations table exists with blind enforcement constraint
  - onboarding_progress table exists with step tracking

test_selection_blind_review:
  - evaluator A cannot see evaluator B's scores before submitting own
  - after both submit, get_evaluation_results returns both
  - divergence > 3 points flagged in results

test_selection_scoring:
  - weighted subtotal calculation matches manual computation
  - PERT consolidation formula: (2*min + 4*avg + 2*max) / 8
  - cutoff at 75% of median correctly filters candidates
  - rankings update correctly on score change

test_selection_pipeline:
  - application status transitions are valid
  - finalize_decisions creates member records for approved
  - conversion flow creates correct records
  - notifications trigger on status changes

test_onboarding:
  - onboarding_progress created for all approved candidates
  - step completion updates member status to active when all done
  - SLA overdue detection works correctly
  - evidence upload stores URL correctly

test_selection_permissions:
  - only committee members can evaluate
  - only GP can finalize decisions
  - sponsors see only own chapter applications
  - candidates cannot see other candidates' data

test_diversity:
  - snapshot captures correct aggregate metrics
  - no PII in diversity table
  - chapter distribution calculated correctly

test_historical_import:
  - 48 researcher applications imported with correct scores
  - 10 leader applications imported
  - 3 conversions (Ana Carla, Hayala, Klemz) recorded correctly
  - 44 member records enriched with phone/linkedin/pmi_id
```

---

## 13. ACCEPTANCE CRITERIA

- [ ] GP can create a selection cycle with configurable criteria and committee
- [ ] VEP CSV import creates applications with correct data mapping
- [ ] Committee members evaluate independently (blind) with 0-10 scale + calibration guides
- [ ] PERT scoring consolidation matches manual calculation within 0.1 tolerance
- [ ] Cutoff threshold auto-filters candidates below 75% of median
- [ ] Rankings calculated per chapter and overall, visible to GP
- [ ] Interview scheduling links to Google Calendar Booking Page
- [ ] GP can finalize decisions in bulk with feedback
- [ ] Approved candidates auto-get member records + onboarding checklist
- [ ] Conversion flow (researcher→leader) works with 3-gate process
- [ ] Onboarding checklist tracks 7 steps with SLA countdown
- [ ] Diversity dashboard shows 6 dimensions with historical comparison
- [ ] All Cycle 3 historical data imported and queryable
- [ ] 44 existing members enriched with phone, LinkedIn, PMI ID
- [ ] Pipeline dashboard shows funnel metrics per chapter
- [ ] SLA alerts fire for overdue stages
- [ ] All 18 contract tests pass
- [ ] CI green (existing 160 tests + new selection tests)
