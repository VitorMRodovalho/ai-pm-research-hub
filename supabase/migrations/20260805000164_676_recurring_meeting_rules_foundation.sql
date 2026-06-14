-- =====================================================================================
-- #676 Foundation: canonical recurring-meeting model for tribes and initiatives.
--
-- Problem (post-#630): recurrence lived implicitly in `events` rows + a divergent
-- manual `tribe_meeting_slots`, with no stored rule (weekday/time/frequency/parity)
-- and no idempotent generator. #630 reconciled the operational calendar by hand via
-- ad-hoc migrations; this introduces the structural source of truth.
--
-- Scope of THIS slice (Foundation-only, PM-ratified 2026-06-14):
--   1. `recurring_meeting_rules` canonical table (+ audit table & trigger).
--   2. Idempotent reconcile RPCs that GENERATE/extend `events` from a rule
--      (no duplicates, biweekly parity preserved via explicit anchor_date).
--   3. Drift RPC comparing rule vs its events.
--   4. Backfill rules from the existing #630 recurrence groups.
--   5. `tribe_meeting_slots` becomes a DERIVED cache of the rule (PM decision),
--      enforced by a new UNIQUE(tribe_id, day_of_week) and synced from the rule.
--
-- NOT in scope here: admin UI (Frontend slice), cron scheduling of reconcile_all,
-- and per-leader scoped editing. This migration intentionally does NOT mutate
-- `events` — event generation is delivered as the reconcile RPC (operator/cron run).
--
-- Convention notes:
--   - rule.day_of_week is ISO (1=Mon..7=Sun), matching extract(isodow).
--   - tribe_meeting_slots.day_of_week is pg dow (0=Sun..6=Sat); converted as
--     (iso % 7) when syncing slots (ISO 7 Sunday -> pg 0; ISO 1..6 unchanged).
--   - Generated events reuse only domain values already present in `events`
--     (type/audience_level/visibility/nature/source/status) to avoid CHECK churn.
-- =====================================================================================

-- ----------------------------------------------------------------------------
-- 1) Canonical rule table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recurring_meeting_rules (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scope_type        text NOT NULL CHECK (scope_type IN ('tribe','initiative','general','leadership')),
  initiative_id     uuid REFERENCES public.initiatives(id) ON DELETE CASCADE,
  tribe_id          integer REFERENCES public.tribes(id) ON DELETE SET NULL,
  title             text NOT NULL,
  event_type        text NOT NULL,
  audience_level    text NOT NULL DEFAULT 'all',
  visibility        text NOT NULL DEFAULT 'all',
  day_of_week       smallint NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),   -- ISO 1=Mon..7=Sun
  time_start        time NOT NULL,
  duration_minutes  integer NOT NULL DEFAULT 60 CHECK (duration_minutes > 0),
  timezone          text NOT NULL DEFAULT 'America/Sao_Paulo',
  frequency         text NOT NULL DEFAULT 'weekly' CHECK (frequency IN ('weekly','biweekly')),
  anchor_date       date NOT NULL,                                            -- a real occurrence; biweekly parity = anchor + 14k
  meeting_link      text,
  recurrence_group  uuid NOT NULL DEFAULT gen_random_uuid(),
  status            text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','archived')),
  organization_id   uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                       REFERENCES public.organizations(id),
  notes             text,
  created_by        uuid REFERENCES public.members(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rmr_scope_refs CHECK (
       (scope_type = 'tribe'      AND initiative_id IS NOT NULL AND tribe_id IS NOT NULL)
    OR (scope_type = 'initiative' AND initiative_id IS NOT NULL)
    OR (scope_type IN ('general','leadership'))
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_rmr_recurrence_group
  ON public.recurring_meeting_rules(recurrence_group);
CREATE INDEX IF NOT EXISTS ix_rmr_scope
  ON public.recurring_meeting_rules(scope_type, initiative_id);
CREATE INDEX IF NOT EXISTS ix_rmr_status
  ON public.recurring_meeting_rules(status);

COMMENT ON TABLE public.recurring_meeting_rules IS
  '#676 canonical recurrence rules for tribe/initiative meetings; generates/reconciles events idempotently.';

-- ----------------------------------------------------------------------------
-- 2) Audit table + trigger (AC: keep an audit of recurrence changes)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recurring_meeting_rule_audit (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rule_id     uuid,
  action      text NOT NULL,                  -- insert | update | delete | reconcile
  actor_id    uuid,
  old_row     jsonb,
  new_row     jsonb,
  changed_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_rmr_audit_rule ON public.recurring_meeting_rule_audit(rule_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.rmr_audit_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.recurring_meeting_rule_audit(rule_id, action, actor_id, new_row)
    VALUES (NEW.id, 'insert', auth.uid(), to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_at := now();
    INSERT INTO public.recurring_meeting_rule_audit(rule_id, action, actor_id, old_row, new_row)
    VALUES (NEW.id, 'update', auth.uid(), to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSE
    INSERT INTO public.recurring_meeting_rule_audit(rule_id, action, actor_id, old_row)
    VALUES (OLD.id, 'delete', auth.uid(), to_jsonb(OLD));
    RETURN OLD;
  END IF;
END
$function$;

DROP TRIGGER IF EXISTS trg_rmr_audit ON public.recurring_meeting_rules;
CREATE TRIGGER trg_rmr_audit
  BEFORE INSERT OR UPDATE OR DELETE ON public.recurring_meeting_rules
  FOR EACH ROW EXECUTE FUNCTION public.rmr_audit_trigger();

-- ----------------------------------------------------------------------------
-- 3) RLS — read for platform managers only; writes happen via SECDEF RPCs.
-- ----------------------------------------------------------------------------
ALTER TABLE public.recurring_meeting_rules      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_meeting_rule_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rmr_select_admin ON public.recurring_meeting_rules;
CREATE POLICY rmr_select_admin ON public.recurring_meeting_rules
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform')
  ));

DROP POLICY IF EXISTS rmr_audit_select_admin ON public.recurring_meeting_rule_audit;
CREATE POLICY rmr_audit_select_admin ON public.recurring_meeting_rule_audit
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform')
  ));

REVOKE ALL ON public.recurring_meeting_rules      FROM anon, PUBLIC;
REVOKE ALL ON public.recurring_meeting_rule_audit FROM anon, PUBLIC;
GRANT SELECT ON public.recurring_meeting_rules      TO authenticated;
GRANT SELECT ON public.recurring_meeting_rule_audit TO authenticated;

-- ----------------------------------------------------------------------------
-- 4) tribe_meeting_slots becomes a derived cache: enforce one slot per (tribe, dow).
--    Safe: no existing duplicate (tribe_id, day_of_week) pair as of #676.
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_tribe_meeting_slots_tribe_dow
  ON public.tribe_meeting_slots(tribe_id, day_of_week);

-- ----------------------------------------------------------------------------
-- 5) Idempotent reconcile RPC: generate/extend events for one rule.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reconcile_recurring_meeting(
  p_rule_id      uuid,
  p_horizon_end  date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_rule        public.recurring_meeting_rules%ROWTYPE;
  v_cron        boolean;
  v_start       date;
  v_horizon     date;
  v_d           date;
  v_created     int := 0;
  v_rc          int;
  v_slot_dow    int;
  v_slot_synced boolean := false;
BEGIN
  v_cron := (current_setting('role', true) IN ('service_role','postgres')
             OR current_user IN ('postgres','supabase_admin'));
  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    PERFORM 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_platform'; END IF;
  END IF;

  SELECT * INTO v_rule FROM public.recurring_meeting_rules WHERE id = p_rule_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recurring rule not found: %', p_rule_id; END IF;

  v_horizon := COALESCE(p_horizon_end, (current_date + 60));
  v_start   := GREATEST(v_rule.anchor_date, current_date);

  IF v_rule.status = 'active' THEN
    IF v_rule.frequency = 'weekly' THEN
      FOR v_d IN
        SELECT g::date
        FROM generate_series(v_start, v_horizon, interval '1 day') g
        WHERE extract(isodow FROM g)::int = v_rule.day_of_week
      LOOP
        INSERT INTO public.events (
          type, title, date, duration_minutes, duration_actual, meeting_link,
          recurrence_group, is_recorded, audience_level, source, curation_status,
          visibility, nature, time_start, organization_id, initiative_id, timezone, status
        )
        SELECT v_rule.event_type, v_rule.title, v_d, v_rule.duration_minutes, v_rule.duration_minutes,
               v_rule.meeting_link, v_rule.recurrence_group, false, v_rule.audience_level,
               'manual', 'published', v_rule.visibility, 'recorrente', v_rule.time_start,
               v_rule.organization_id, v_rule.initiative_id, v_rule.timezone, 'scheduled'
        WHERE NOT EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.recurrence_group = v_rule.recurrence_group AND e.date = v_d
        );
        GET DIAGNOSTICS v_rc = ROW_COUNT;
        v_created := v_created + v_rc;
      END LOOP;
    ELSE  -- biweekly: stepping 14 days from anchor preserves both weekday and parity
      FOR v_d IN
        SELECT d::date
        FROM generate_series(v_rule.anchor_date, v_horizon, interval '14 days') d
        WHERE d::date >= v_start
      LOOP
        INSERT INTO public.events (
          type, title, date, duration_minutes, duration_actual, meeting_link,
          recurrence_group, is_recorded, audience_level, source, curation_status,
          visibility, nature, time_start, organization_id, initiative_id, timezone, status
        )
        SELECT v_rule.event_type, v_rule.title, v_d, v_rule.duration_minutes, v_rule.duration_minutes,
               v_rule.meeting_link, v_rule.recurrence_group, false, v_rule.audience_level,
               'manual', 'published', v_rule.visibility, 'recorrente', v_rule.time_start,
               v_rule.organization_id, v_rule.initiative_id, v_rule.timezone, 'scheduled'
        WHERE NOT EXISTS (
          SELECT 1 FROM public.events e
          WHERE e.recurrence_group = v_rule.recurrence_group AND e.date = v_d
        );
        GET DIAGNOSTICS v_rc = ROW_COUNT;
        v_created := v_created + v_rc;
      END LOOP;
    END IF;
  END IF;

  -- Derived slot sync (PM decision: tribe_meeting_slots reflects the rule).
  IF v_rule.scope_type = 'tribe' AND v_rule.tribe_id IS NOT NULL THEN
    v_slot_dow := (v_rule.day_of_week % 7);   -- ISO -> pg dow (7 Sun -> 0)
    INSERT INTO public.tribe_meeting_slots (tribe_id, day_of_week, time_start, time_end, is_active, created_at, updated_at)
    VALUES (
      v_rule.tribe_id, v_slot_dow, v_rule.time_start,
      (v_rule.time_start + make_interval(mins => v_rule.duration_minutes)),
      (v_rule.status = 'active'), now(), now()
    )
    ON CONFLICT (tribe_id, day_of_week) DO UPDATE SET
      time_start = EXCLUDED.time_start,
      time_end   = EXCLUDED.time_end,
      is_active  = EXCLUDED.is_active,
      updated_at = now();
    v_slot_synced := true;
  END IF;

  INSERT INTO public.recurring_meeting_rule_audit(rule_id, action, actor_id, new_row)
  VALUES (v_rule.id, 'reconcile', auth.uid(),
          jsonb_build_object('created_events', v_created, 'horizon_end', v_horizon, 'slot_synced', v_slot_synced));

  RETURN jsonb_build_object(
    'rule_id', v_rule.id,
    'status', v_rule.status,
    'created_events', v_created,
    'horizon_end', v_horizon,
    'slot_synced', v_slot_synced
  );
END
$function$;

-- ----------------------------------------------------------------------------
-- 6) Reconcile all active rules (job entrypoint for operator/cron).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reconcile_all_recurring_meetings(
  p_horizon_end date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_cron   boolean;
  v_r      record;
  v_one    jsonb;
  v_total  int := 0;
  v_rules  int := 0;
BEGIN
  v_cron := (current_setting('role', true) IN ('service_role','postgres')
             OR current_user IN ('postgres','supabase_admin'));
  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    PERFORM 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_platform'; END IF;
  END IF;

  FOR v_r IN SELECT id FROM public.recurring_meeting_rules WHERE status = 'active' LOOP
    v_one   := public.reconcile_recurring_meeting(v_r.id, p_horizon_end);
    v_total := v_total + COALESCE((v_one->>'created_events')::int, 0);
    v_rules := v_rules + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'rules_processed', v_rules,
    'events_created', v_total,
    'horizon_end', COALESCE(p_horizon_end, (current_date + 60))
  );
END
$function$;

-- ----------------------------------------------------------------------------
-- 7) Drift report: rule vs its events (missing/time/link mismatches).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_recurring_meeting_drift(
  p_horizon_end date DEFAULT NULL
)
RETURNS TABLE (
  rule_id          uuid,
  scope_type       text,
  title            text,
  status           text,
  frequency        text,
  day_of_week      smallint,
  time_start       time,
  next_occurrence  date,
  future_events    int,
  expected_future  int,
  missing_future   int,
  time_mismatch    int,
  link_mismatch    int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_cron    boolean;
  v_horizon date;
BEGIN
  v_cron := (current_setting('role', true) IN ('service_role','postgres')
             OR current_user IN ('postgres','supabase_admin'));
  IF NOT v_cron THEN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Unauthorized'; END IF;
    PERFORM 1 FROM public.members m
      WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_platform');
    IF NOT FOUND THEN RAISE EXCEPTION 'Unauthorized: requires manage_platform'; END IF;
  END IF;

  v_horizon := COALESCE(p_horizon_end, (current_date + 60));

  RETURN QUERY
  WITH expected AS (
    SELECT r.id AS rule_id,
      CASE WHEN r.frequency = 'weekly' THEN (
        SELECT count(*)::int
        FROM generate_series(GREATEST(r.anchor_date, current_date), v_horizon, interval '1 day') g
        WHERE extract(isodow FROM g)::int = r.day_of_week
      ) ELSE (
        SELECT count(*)::int
        FROM generate_series(r.anchor_date, v_horizon, interval '14 days') d
        WHERE d::date >= current_date
      ) END AS expected_cnt
    FROM public.recurring_meeting_rules r
    WHERE r.status = 'active'
  ),
  ev AS (
    SELECT r.id AS rule_id,
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled')::int AS fut,
      min(e.date) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled') AS nxt,
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled'
                         AND e.time_start IS DISTINCT FROM r.time_start)::int AS tmm,
      count(*) FILTER (WHERE e.date >= current_date AND e.status = 'scheduled'
                         AND e.meeting_link IS DISTINCT FROM r.meeting_link)::int AS lmm
    FROM public.recurring_meeting_rules r
    LEFT JOIN public.events e ON e.recurrence_group = r.recurrence_group
    GROUP BY r.id
  )
  SELECT r.id, r.scope_type, r.title, r.status, r.frequency, r.day_of_week, r.time_start,
         ev.nxt,
         COALESCE(ev.fut, 0),
         COALESCE(ex.expected_cnt, 0),
         GREATEST(COALESCE(ex.expected_cnt, 0) - COALESCE(ev.fut, 0), 0),
         COALESCE(ev.tmm, 0),
         COALESCE(ev.lmm, 0)
  FROM public.recurring_meeting_rules r
  LEFT JOIN expected ex ON ex.rule_id = r.id
  LEFT JOIN ev        ON ev.rule_id = r.id
  ORDER BY r.scope_type, r.title;
END
$function$;

-- ----------------------------------------------------------------------------
-- 8) Grants for the RPCs (SECDEF; callable by authenticated + service_role).
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.reconcile_recurring_meeting(uuid, date)      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reconcile_all_recurring_meetings(date)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_recurring_meeting_drift(date)            FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconcile_recurring_meeting(uuid, date)   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_all_recurring_meetings(date)    TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_recurring_meeting_drift(date)         TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 9) Backfill canonical rules from existing #630 recurrence groups (idempotent).
--    Frequency inferred from the smallest positive gap between distinct dates;
--    anchor = earliest actual occurrence in the group (preserves biweekly parity).
-- ----------------------------------------------------------------------------
DO $backfill$
DECLARE
  r        record;
  v_freq   text;
  v_anchor date;
BEGIN
  FOR r IN
    SELECT e.recurrence_group AS grp,
           e.type             AS etype,
           e.initiative_id    AS iid,
           i.legacy_tribe_id  AS tid,
           mode() WITHIN GROUP (ORDER BY e.title)                        AS title,
           mode() WITHIN GROUP (ORDER BY e.time_start)                   AS ctime,
           mode() WITHIN GROUP (ORDER BY e.duration_minutes)             AS cdur,
           mode() WITHIN GROUP (ORDER BY e.meeting_link)                 AS clink,
           mode() WITHIN GROUP (ORDER BY extract(isodow FROM e.date)::int) AS cdow,
           mode() WITHIN GROUP (ORDER BY e.audience_level)               AS caud,
           mode() WITHIN GROUP (ORDER BY e.visibility)                   AS cvis,
           min(e.date)        AS first_future
    FROM public.events e
    LEFT JOIN public.initiatives i ON i.id = e.initiative_id
    WHERE e.type IN ('tribo','comms')
      AND e.recurrence_group IS NOT NULL
      AND e.date >= current_date
    GROUP BY e.recurrence_group, e.type, e.initiative_id, i.legacy_tribe_id
  LOOP
    IF EXISTS (SELECT 1 FROM public.recurring_meeting_rules WHERE recurrence_group = r.grp) THEN
      CONTINUE;
    END IF;
    IF r.iid IS NULL THEN
      CONTINUE;  -- cannot anchor a rule without an initiative scope in this slice
    END IF;

    SELECT CASE WHEN min(gap) >= 13 THEN 'biweekly' ELSE 'weekly' END
    INTO v_freq
    FROM (
      SELECT (d - lag(d) OVER (ORDER BY d)) AS gap
      FROM (SELECT DISTINCT date AS d FROM public.events WHERE recurrence_group = r.grp) s
    ) gaps
    WHERE gap IS NOT NULL;
    v_freq := COALESCE(v_freq, 'weekly');

    SELECT min(date) INTO v_anchor FROM public.events WHERE recurrence_group = r.grp;

    INSERT INTO public.recurring_meeting_rules (
      scope_type, initiative_id, tribe_id, title, event_type, audience_level, visibility,
      day_of_week, time_start, duration_minutes, frequency, anchor_date, meeting_link,
      recurrence_group, status
    ) VALUES (
      CASE WHEN r.tid IS NOT NULL THEN 'tribe' ELSE 'initiative' END,
      r.iid, r.tid, r.title, r.etype, r.caud, COALESCE(r.cvis, 'all'),
      r.cdow::smallint, r.ctime, COALESCE(r.cdur, 60), v_freq,
      COALESCE(v_anchor, r.first_future), r.clink, r.grp, 'active'
    );
  END LOOP;
END
$backfill$;

-- ----------------------------------------------------------------------------
-- 10) Sync tribe_meeting_slots from the backfilled tribe rules (derived cache).
--     Does not touch events; pure slot reconciliation.
-- ----------------------------------------------------------------------------
DO $slots$
DECLARE
  r     record;
  v_dow int;
BEGIN
  FOR r IN
    SELECT * FROM public.recurring_meeting_rules
    WHERE scope_type = 'tribe' AND tribe_id IS NOT NULL
  LOOP
    v_dow := (r.day_of_week % 7);
    INSERT INTO public.tribe_meeting_slots (tribe_id, day_of_week, time_start, time_end, is_active, created_at, updated_at)
    VALUES (
      r.tribe_id, v_dow, r.time_start,
      (r.time_start + make_interval(mins => r.duration_minutes)),
      (r.status = 'active'), now(), now()
    )
    ON CONFLICT (tribe_id, day_of_week) DO UPDATE SET
      time_start = EXCLUDED.time_start,
      time_end   = EXCLUDED.time_end,
      is_active  = EXCLUDED.is_active,
      updated_at = now();
  END LOOP;
END
$slots$;

NOTIFY pgrst, 'reload schema';
