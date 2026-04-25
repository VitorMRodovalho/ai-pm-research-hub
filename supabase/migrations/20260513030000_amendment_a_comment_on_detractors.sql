-- ADR-0011 Amendment A — fast-path stakeholder fan-out comment.
--
-- `public.detect_and_notify_detractors()` was migrated to V4 `can_by_member('manage_platform')`
-- as caller gate in 20260513010000 (Amendment B). The function body still enumerates
-- leaders (manager + deputy_manager) inside its fan-out loop using
-- `operational_role IN ('manager', 'deputy_manager')`. That enumeration is a data
-- filter (selects which members to notify), not an authority gate, and falls under
-- ADR-0011 Amendment A (fast-path stakeholder fan-out). Adding the documentation
-- comment per Amendment A criterion 4.

COMMENT ON FUNCTION public.detect_and_notify_detractors() IS
  'fast-path stakeholder fan-out per ADR-0011 Amendment A — enumerates leaders (manager + deputy_manager) to notify when detractor pattern detected. Caller authority is gated separately via can_by_member(v_caller_id, ''manage_platform''). No write side effects on caller-facing data, no PII cross-member surfaced.';

NOTIFY pgrst, 'reload schema';
