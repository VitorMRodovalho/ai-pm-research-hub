-- #2447 — _board_item_needs_curation e helper interno: so as RPCs SECURITY DEFINER do fluxo o
-- chamam (complete_peer_review, complete_leader_review, submit_for_curation,
-- get_artifact_classification, set_board_item_artifact_type), e elas rodam como dono. Exposto a
-- `authenticated`, ele respondia "este card e publicacao?" sobre qualquer card, inclusive de
-- iniciativa confidencial, sem o gate rls_can_see_* (guard #785). A tela usa
-- get_artifact_classification, que tem o gate.
REVOKE EXECUTE ON FUNCTION public._board_item_needs_curation(uuid) FROM authenticated;
