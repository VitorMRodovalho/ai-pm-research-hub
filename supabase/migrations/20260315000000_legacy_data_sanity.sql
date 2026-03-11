-- ============================================================================
-- W86: Data Sanity do Legado
-- Garantir integridade do histórico (Ciclo 1 e 2) e preservar URLs antigas
-- Date: 2026-03-15
-- ============================================================================

begin;

-- 1) Coluna legacy_board_url em tribes (preservar URLs Trello/Miro dos ciclos passados)
alter table public.tribes add column if not exists legacy_board_url text;
comment on column public.tribes.legacy_board_url is 'W86: URL antiga de board Trello/Miro para referência histórica do Kanban nativo.';

-- 2) member_cycle_history orphans: membros que não existem mais em members
--    Marcar com notes='archived_legacy' (soft, sem deletar histórico)
update public.member_cycle_history mch
set notes = coalesce(notes || '; ', '') || 'archived_legacy:member_removed'
where mch.member_id is not null
  and not exists (select 1 from public.members m where m.id = mch.member_id);

-- 3) Padronizar cycle_code em member_cycle_history
--    ciclo_1, cycle_1, 1 -> cycle_1; ciclo_2, cycle_2, 2 -> cycle_2; pilot -> pilot
update public.member_cycle_history
set cycle_code = case
  when lower(trim(cycle_code)) in ('1', 'ciclo_1', 'ciclo1') then 'cycle_1'
  when lower(trim(cycle_code)) in ('2', 'ciclo_2', 'ciclo2') then 'cycle_2'
  when lower(trim(cycle_code)) in ('3', 'ciclo_3', 'ciclo3') then 'cycle_3'
  when lower(trim(cycle_code)) in ('pilot', 'piloto', 'p24') then 'pilot'
  else cycle_code
end
where lower(trim(cycle_code)) in ('1', '2', '3', 'ciclo_1', 'ciclo_2', 'ciclo_3', 'ciclo1', 'ciclo2', 'ciclo3', 'piloto', 'p24');

-- 4) Padronizar cycle_code em legacy_tribes (se existir inconsistência)
update public.legacy_tribes
set cycle_code = case
  when lower(trim(cycle_code)) in ('1', 'ciclo_1', 'ciclo1') then 'cycle_1'
  when lower(trim(cycle_code)) in ('2', 'ciclo_2', 'ciclo2') then 'cycle_2'
  when lower(trim(cycle_code)) in ('3', 'ciclo_3', 'ciclo3') then 'cycle_3'
  when lower(trim(cycle_code)) in ('pilot', 'piloto', 'p24') then 'pilot'
  else cycle_code
end
where lower(trim(cycle_code)) in ('1', '2', '3', 'ciclo_1', 'ciclo_2', 'ciclo_3', 'ciclo1', 'ciclo2', 'ciclo3', 'piloto', 'p24');

-- 5) Migrar miro_url antigo para legacy_board_url quando aplicável (tribes de ciclo 1/2)
--    Apenas se legacy_board_url estiver vazio e miro_url tiver valor
update public.tribes t
set legacy_board_url = coalesce(t.legacy_board_url, t.miro_url)
where t.miro_url is not null
  and (t.legacy_board_url is null or trim(t.legacy_board_url) = '');

commit;
