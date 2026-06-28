-- #785 recurrence guard helper: enumerate public SECURITY DEFINER readers over
-- initiative-linked tables and whether each applies a confidential gate
-- (rls_can_see_initiative / rls_can_see_board / rls_can_see_item).
-- Consumed by tests/contracts/785-secdef-reader-confidential-gate.test.mjs.
CREATE OR REPLACE FUNCTION public._audit_secdef_initiative_reader_gates()
 RETURNS TABLE(proname text, identity_args text, reads_initiative_table boolean, is_writer boolean, exec_authenticated boolean, references_gate boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT
    p.proname::text,
    pg_catalog.pg_get_function_identity_arguments(p.oid)::text,
    (p.prosrc ~ '(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)'),
    (upper(p.prosrc) ~ '(INSERT |UPDATE |DELETE )'),
    pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE'),
    (p.prosrc ~ 'rls_can_see_(initiative|board|item)')
  FROM pg_catalog.pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND p.prokind = 'f'
    AND p.prosecdef
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_depend d
      JOIN pg_catalog.pg_extension e ON e.oid = d.refobjid
      WHERE d.objid = p.oid AND d.deptype = 'e'
    )
  ORDER BY p.proname, p.oid;
$function$;

REVOKE ALL ON FUNCTION public._audit_secdef_initiative_reader_gates() FROM PUBLIC;
