-- ============================================================
-- Attendance + Meeting Journey — Schema Preparation (Phase 0)
-- ============================================================

-- 0a. Normalize event types (legacy → standard)
UPDATE events SET type = 'tribo' WHERE type = 'tribe_meeting';
UPDATE events SET type = 'geral' WHERE type = 'general_meeting';
UPDATE events SET type = 'lideranca' WHERE type = 'leadership_meeting';
UPDATE events SET type = 'kickoff' WHERE type ILIKE '%kickoff%' AND type != 'kickoff';
UPDATE events SET type = 'entrevista' WHERE type = 'interview';
UPDATE events SET type = 'evento_externo' WHERE type = 'external_event';

-- 0c. Attendance tracking columns
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS excused boolean DEFAULT false;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS excuse_reason text;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS edited_by uuid REFERENCES members(id);
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS edited_at timestamptz;

-- 0d. Event meeting journey columns
ALTER TABLE events ADD COLUMN IF NOT EXISTS agenda_text text;
ALTER TABLE events ADD COLUMN IF NOT EXISTS agenda_url text;
ALTER TABLE events ADD COLUMN IF NOT EXISTS agenda_posted_at timestamptz;
ALTER TABLE events ADD COLUMN IF NOT EXISTS agenda_posted_by uuid REFERENCES members(id);
ALTER TABLE events ADD COLUMN IF NOT EXISTS minutes_text text;
ALTER TABLE events ADD COLUMN IF NOT EXISTS minutes_url text;
ALTER TABLE events ADD COLUMN IF NOT EXISTS minutes_posted_at timestamptz;
ALTER TABLE events ADD COLUMN IF NOT EXISTS minutes_posted_by uuid REFERENCES members(id);
ALTER TABLE events ADD COLUMN IF NOT EXISTS recording_url text;
ALTER TABLE events ADD COLUMN IF NOT EXISTS recording_type text;

-- 0e. Visibility + external participants + manual invites
ALTER TABLE events ADD COLUMN IF NOT EXISTS visibility text DEFAULT 'all';
ALTER TABLE events ADD COLUMN IF NOT EXISTS external_attendees text[];
ALTER TABLE events ADD COLUMN IF NOT EXISTS invited_member_ids uuid[];
ALTER TABLE events ADD COLUMN IF NOT EXISTS selection_application_id uuid;

-- 0f. Event type constraint (drop old, recreate with normalized types)
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_type_check;
ALTER TABLE events ADD CONSTRAINT events_type_check
  CHECK (type IN ('geral', 'tribo', 'lideranca', 'kickoff', 'comms', 'parceria', 'entrevista', '1on1', 'evento_externo', 'webinar'));

-- 0g. Visibility constraint
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'events_visibility_check') THEN
    ALTER TABLE events ADD CONSTRAINT events_visibility_check
      CHECK (visibility IN ('all', 'leadership', 'gp_only'));
  END IF;
END $$;

-- 0h. Meeting action items table
CREATE TABLE IF NOT EXISTS meeting_action_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  description text NOT NULL,
  assignee_id uuid REFERENCES members(id),
  assignee_name text,
  due_date date,
  status text DEFAULT 'open' CHECK (status IN ('open', 'done', 'cancelled', 'carried_over')),
  carried_to_event_id uuid REFERENCES events(id),
  created_by uuid REFERENCES members(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_action_items_event ON meeting_action_items(event_id);
CREATE INDEX IF NOT EXISTS idx_action_items_assignee ON meeting_action_items(assignee_id) WHERE status = 'open';

ALTER TABLE meeting_action_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can read action items" ON meeting_action_items FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admins can manage action items" ON meeting_action_items FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
    AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
) WITH CHECK (
  EXISTS (SELECT 1 FROM members m WHERE m.auth_id = auth.uid()
    AND (m.is_superadmin = true OR m.operational_role IN ('manager', 'deputy_manager', 'tribe_leader')))
);

-- 0i. Performance index for grid query
CREATE INDEX IF NOT EXISTS idx_attendance_member_event ON attendance(member_id, event_id);

-- 0j. Set default visibility for sensitive types
UPDATE events SET visibility = 'gp_only' WHERE type IN ('parceria', 'entrevista', '1on1') AND visibility = 'all';

-- 0k. Reload schema cache
SELECT pg_notify('pgrst', 'reload schema');
