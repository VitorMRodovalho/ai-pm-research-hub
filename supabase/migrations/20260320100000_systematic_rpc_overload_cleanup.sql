-- ============================================================
-- GC-093: Systematic RPC overload cleanup
-- ============================================================
-- Drop ALL legacy function overloads that cause PostgREST 400 errors.
-- Frontend is source of truth — DB must match frontend signatures.
-- Zero overloads should remain after this migration.

-- create_event: keep 6-param (with audience_level), drop 5-param and UUID versions
DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, uuid, text);
DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, uuid);
DROP FUNCTION IF EXISTS public.create_event(text, text, date, integer, integer);

-- update_event: keep 8-param (with audience_level), drop 7-param
DROP FUNCTION IF EXISTS public.update_event(uuid, text, date, integer, text, boolean, text);

-- member_self_update: keep 5-param (with share_whatsapp), drop 3-param and 4-param
DROP FUNCTION IF EXISTS public.member_self_update(text, text, text);
DROP FUNCTION IF EXISTS public.member_self_update(text, text, text, text);

-- upsert_publication_submission_event: keep 7-param (with external_link, published_at), drop 5-param
DROP FUNCTION IF EXISTS public.upsert_publication_submission_event(uuid, text, timestamptz, text, text);

-- admin_list_members: keep 4-param (search, tier, tribe_id, status), drop 6-param legacy
DROP FUNCTION IF EXISTS public.admin_list_members(text, text, text, boolean, integer, integer);

-- get_admin_dashboard: fix gamification_points.cycle column reference (doesn't exist)
-- Uses created_at >= cycle_start instead. Applied via separate CREATE OR REPLACE.

-- exec_cycle_report: designations ?| (jsonb operator) → && (text[] overlap)
-- designations column is text[], not jsonb. ?| only works on jsonb.
-- Fixed via dynamic DO block in production; recorded here for local parity.
-- Also fixed: c.code→c.cycle_code, c.name→c.cycle_label, c.start_date→c.cycle_start, c.end_date→c.cycle_end
-- Also fixed: jsonb_array_length(cycles)→COALESCE(array_length(cycles,1),0) — cycles is text[], not jsonb
