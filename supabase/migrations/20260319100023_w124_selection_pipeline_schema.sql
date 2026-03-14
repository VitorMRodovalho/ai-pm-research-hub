-- W124 Phase 1: Selection Pipeline Schema + Historical Data Import
-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS selection_cycles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_code text NOT NULL,
  title text NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','open','evaluation','interview','decision','closed')),
  open_date date,
  close_date date,
  interview_booking_url text,
  min_evaluators int NOT NULL DEFAULT 2,
  objective_criteria jsonb NOT NULL DEFAULT '[]',
  interview_criteria jsonb NOT NULL DEFAULT '[]',
  leader_extra_criteria jsonb DEFAULT '[]',
  objective_cutoff_formula text DEFAULT '(2*min + 4*avg + 2*max) / 6 * 0.75',
  final_cutoff_formula text DEFAULT '(2*min + 4*avg + 2*max) / 6 * 0.75',
  onboarding_steps jsonb NOT NULL DEFAULT '[]',
  created_by uuid REFERENCES members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS selection_committee (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES selection_cycles(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES members(id),
  role text NOT NULL DEFAULT 'evaluator'
    CHECK (role IN ('evaluator','lead','observer')),
  can_interview boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE(cycle_id, member_id)
);

CREATE TABLE IF NOT EXISTS selection_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES selection_cycles(id),
  vep_application_id text,
  applicant_name text NOT NULL,
  first_name text,
  last_name text,
  email text NOT NULL,
  phone text,
  pmi_id text,
  chapter text,
  state text,
  country text,
  linkedin_url text,
  resume_url text,
  membership_status text,
  certifications text,
  role_applied text NOT NULL DEFAULT 'researcher'
    CHECK (role_applied IN ('researcher','leader','both')),
  motivation_letter text,
  non_pmi_experience text,
  areas_of_interest text,
  availability_declared text,
  proposed_theme text,
  leadership_experience text,
  academic_background text,
  status text NOT NULL DEFAULT 'submitted'
    CHECK (status IN (
      'submitted','screening','objective_eval','objective_cutoff',
      'interview_pending','interview_scheduled','interview_done',
      'interview_noshow','final_eval','approved','rejected',
      'waitlist','converted','withdrawn','cancelled'
    )),
  converted_from text,
  converted_to text,
  conversion_reason text,
  tags text[] DEFAULT '{}',
  objective_score_avg numeric,
  interview_score numeric,
  final_score numeric,
  rank_chapter int,
  rank_overall int,
  feedback text,
  is_returning_member boolean DEFAULT false,
  previous_cycles text[],
  application_count int DEFAULT 1,
  gender text,
  age_band text,
  industry text,
  sector text,
  seniority_years int,
  imported_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS selection_evaluations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  evaluator_id uuid NOT NULL REFERENCES members(id),
  evaluation_type text NOT NULL
    CHECK (evaluation_type IN ('objective','interview','leader_extra')),
  scores jsonb NOT NULL DEFAULT '{}',
  weighted_subtotal numeric,
  notes text,
  submitted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE(application_id, evaluator_id, evaluation_type)
);

CREATE TABLE IF NOT EXISTS selection_interviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id) ON DELETE CASCADE,
  interviewer_ids uuid[] NOT NULL,
  scheduled_at timestamptz,
  duration_minutes int DEFAULT 30,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','scheduled','completed','noshow','cancelled','rescheduled')),
  conducted_at timestamptz,
  theme_of_interest text,
  calendar_event_id text,
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS onboarding_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES selection_applications(id),
  member_id uuid REFERENCES members(id),
  step_key text NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','in_progress','completed','skipped','overdue')),
  completed_at timestamptz,
  evidence_url text,
  notes text,
  sla_deadline timestamptz,
  created_at timestamptz DEFAULT now(),
  UNIQUE(application_id, step_key)
);

CREATE TABLE IF NOT EXISTS selection_diversity_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES selection_cycles(id),
  snapshot_type text NOT NULL
    CHECK (snapshot_type IN ('applicants','approved','final_roster')),
  metrics jsonb NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_sel_apps_cycle ON selection_applications(cycle_id);
CREATE INDEX IF NOT EXISTS idx_sel_apps_status ON selection_applications(status);
CREATE INDEX IF NOT EXISTS idx_sel_apps_chapter ON selection_applications(chapter);
CREATE INDEX IF NOT EXISTS idx_sel_apps_email ON selection_applications(email);
CREATE INDEX IF NOT EXISTS idx_sel_evals_app ON selection_evaluations(application_id);
CREATE INDEX IF NOT EXISTS idx_sel_evals_evaluator ON selection_evaluations(evaluator_id);
CREATE INDEX IF NOT EXISTS idx_sel_interviews_app ON selection_interviews(application_id);
CREATE INDEX IF NOT EXISTS idx_onb_progress_app ON onboarding_progress(application_id);
CREATE INDEX IF NOT EXISTS idx_onb_progress_member ON onboarding_progress(member_id);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE selection_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_committee ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_interviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE selection_diversity_snapshots ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE selection_cycles IS 'Selection cycles with configurable criteria and thresholds';
COMMENT ON TABLE selection_applications IS 'Candidate applications per selection cycle';
COMMENT ON TABLE selection_evaluations IS 'Individual evaluator scores per application (blind review)';
COMMENT ON TABLE selection_interviews IS 'Interview scheduling and tracking';
COMMENT ON TABLE onboarding_progress IS 'Post-approval onboarding step tracking';
