-- S-KNW1: Allow can_manage_knowledge() to select all rows (including inactive)
-- Needed for admin CRUD to list and toggle is_active

begin;

create policy knowledge_assets_select_manage
  on public.knowledge_assets for select
  to authenticated
  using (public.can_manage_knowledge());

commit;
