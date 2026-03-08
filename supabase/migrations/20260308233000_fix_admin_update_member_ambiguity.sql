-- Fix PostgREST PGRST203 ambiguity: drop the 5-param overload.
-- The 11-param overload (with defaults) handles both admin/index and member/[id] cases.
DROP FUNCTION IF EXISTS public.admin_update_member(uuid, text, text[], text, boolean);
