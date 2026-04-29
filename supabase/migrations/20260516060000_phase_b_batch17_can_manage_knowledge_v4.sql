-- Phase B'' batch 17.1: can_manage_knowledge helper V3 hardcode → V4 can_by_member delegation
-- V3: is_superadmin OR operational_role IN ('manager','deputy_manager')
-- V4: can_by_member(member_id, 'manage_platform') — covers sa + manager/deputy_manager/co_gp
-- Helper used as building block by other RPCs/RLS policies; semantic-preserving rewrite
-- Impact: V3=2, V4=2 (clean match)
CREATE OR REPLACE FUNCTION public.can_manage_knowledge()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce((
    select public.can_by_member(m.id, 'manage_platform'::text)
    from public.members m
    where m.auth_id = auth.uid()
    limit 1
  ), false);
$function$;
