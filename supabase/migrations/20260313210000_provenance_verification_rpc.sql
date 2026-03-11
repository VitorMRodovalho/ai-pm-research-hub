-- ═══════════════════════════════════════════════════════════════════════════
-- Provenance verification RPC contracts
-- Date: 2026-03-13
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create or replace function public.admin_verify_ingestion_provenance_batch(
  p_batch_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller record;
  v_total integer := 0;
  v_valid integer := 0;
  v_invalid integer := 0;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not (
      auth.role() = 'service_role'
      or v_caller.is_superadmin is true
      or v_caller.operational_role in ('manager', 'deputy_manager')
      or coalesce('co_gp' = any(v_caller.designations), false)
    ) then
    raise exception 'Project management access required';
  end if;

  with checks as (
    select
      s.id,
      s.signature,
      encode(
        digest(
          coalesce(s.batch_id::text, '') || '|' || s.file_path || '|' || s.file_hash || '|' || coalesce(s.source_kind, 'unknown'),
          'sha256'
        ),
        'hex'
      ) as expected_signature
    from public.ingestion_provenance_signatures s
    where s.batch_id = p_batch_id
  )
  select
    count(*)::integer,
    count(*) filter (where signature = expected_signature)::integer,
    count(*) filter (where signature <> expected_signature)::integer
  into
    v_total, v_valid, v_invalid
  from checks;

  return jsonb_build_object(
    'batch_id', p_batch_id,
    'total_signatures', v_total,
    'valid_signatures', v_valid,
    'invalid_signatures', v_invalid,
    'verified', v_invalid = 0
  );
end;
$$;

grant execute on function public.admin_verify_ingestion_provenance_batch(uuid) to authenticated;

commit;
