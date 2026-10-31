-- #2864 (G19): os gatilhos trg_auto_comms_on_publish e trg_notify_leader_review existiam no banco e em
-- nenhuma migration. Esta migration os captura SEM mudar o comportamento: a definicao e a lida em
-- pg_get_triggerdef no banco vivo, com CREATE OR REPLACE no lugar de CREATE. As funcoes nao mudam.
-- E cria _audit_list_public_triggers(), so para service_role, para o teste de cobertura de
-- migrations passar a olhar gatilho tambem. Com search_path vazio, pg_get_triggerdef sai com os
-- nomes qualificados (public.board_items, public.<funcao>).

CREATE OR REPLACE TRIGGER trg_auto_comms_on_publish AFTER UPDATE OF curation_status ON public.board_items FOR EACH ROW EXECUTE FUNCTION auto_comms_card_on_publish();

CREATE OR REPLACE TRIGGER trg_notify_leader_review AFTER UPDATE OF curation_status ON public.board_items FOR EACH ROW EXECUTE FUNCTION notify_leader_on_review();

CREATE OR REPLACE FUNCTION public._audit_list_public_triggers()
RETURNS TABLE(
  table_name      text,
  trigger_name    text,
  function_schema text,
  function_name   text,
  enabled         text,
  definition      text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT c.relname::text, t.tgname::text, n.nspname::text, p.proname::text, t.tgenabled::text,
         pg_catalog.pg_get_triggerdef(t.oid)
    FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
    JOIN pg_catalog.pg_proc p ON p.oid = t.tgfoid
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE NOT t.tgisinternal
     AND c.relnamespace = 'public'::regnamespace
   ORDER BY c.relname, t.tgname;
$$;

REVOKE ALL ON FUNCTION public._audit_list_public_triggers() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._audit_list_public_triggers() TO service_role;
