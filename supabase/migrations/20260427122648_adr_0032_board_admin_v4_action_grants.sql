-- ADR-0032 (Accepted, p66): manage_board_admin V4 action grants
-- Group W (3 writers): nova action manage_board_admin com resource-scoped check
-- Group R (1 reader): reuse view_internal_analytics — sem novo grant aqui
-- See docs/adr/ADR-0032-board-admin-v4-conversion.md
--
-- PM ratified Q1-Q4 (2026-04-26 p66): SIM / SIM / Opção A / p66

INSERT INTO public.engagement_kind_permissions (kind, role, action, scope)
VALUES
  -- Org-admin tier (matches V3 manager/deputy_manager/co_gp)
  ('volunteer',          'co_gp',          'manage_board_admin', 'organization'),
  ('volunteer',          'manager',        'manage_board_admin', 'organization'),
  ('volunteer',          'deputy_manager', 'manage_board_admin', 'organization'),
  -- Initiative-leader tier (matches V3 tribe_leader own-tribe scope via initiative scope)
  ('volunteer',          'leader',         'manage_board_admin', 'initiative'),
  ('study_group_owner',  'owner',          'manage_board_admin', 'initiative'),
  ('study_group_owner',  'leader',         'manage_board_admin', 'initiative'),
  ('committee_member',   'leader',         'manage_board_admin', 'initiative'),
  ('workgroup_member',   'leader',         'manage_board_admin', 'initiative')
ON CONFLICT (kind, role, action) DO NOTHING;

NOTIFY pgrst, 'reload schema';
