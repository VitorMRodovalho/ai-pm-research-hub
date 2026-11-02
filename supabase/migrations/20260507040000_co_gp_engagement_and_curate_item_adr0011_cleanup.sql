-- ADR-0011 drift cleanup — remove `is_superadmin OR` de curate_item +
-- grant engagement `volunteer × co_gp` a Fabrício Costa (formaliza autoridade
-- org-wide via can_by_member em vez do bypass legacy is_superadmin).
--
-- Root cause do drift (data-architect p38 agent `a02262299817c2f16`):
-- Fabrício é `is_superadmin=true` mas `can_by_member(id, 'manage_member')=false`
-- apesar de ter `committee_member × leader` authoritative+active. Permission
-- `committee_member × leader → manage_member` tem `scope='initiative'` (migration
-- 20260422010000 linha 61), e o filtro em `can()` body com `p_resource_id=NULL`
-- exige `ae.legacy_tribe_id IS NOT NULL` — committees são iniciativas nativas
-- V4 sem tribe legada, então o filtro falha silenciosamente.
--
-- Opção B escolhida: grant `volunteer × co_gp` (scope='organization' via
-- permission `volunteer × co_gp → manage_member` seeded em 20260413400000).
-- Alinha com realidade operacional de Fabrício (committee_coordinator + 2
-- committee_member roles + curator signoffs em 5 chains IP + is_superadmin
-- legacy). Zero side effects: permissão é idêntica à que já tinha via
-- is_superadmin, agora derivada de engagement conforme ADR-0011.
--
-- Agreement certificate reutilizado do volunteer × leader existente
-- (626b05b1-01ac-451c-8d00-eed662b25a22) — mesmo contrato de voluntariado
-- Lei 9.608/98 cobre todos os engagements volunteer dele.
--
-- Rollback: DELETE FROM engagements WHERE id = NEW_ENGAGEMENT_ID
-- + CREATE OR REPLACE curate_item com branch `is_superadmin OR` restaurada.

BEGIN;

-- =============================================================================
-- 1. INSERT engagement volunteer × co_gp para Fabrício (org-scoped)
-- =============================================================================
INSERT INTO public.engagements (
  person_id,
  organization_id,
  initiative_id,
  kind,
  role,
  status,
  start_date,
  end_date,
  legal_basis,
  agreement_certificate_id,
  metadata
) VALUES (
  '199b0514-6868-41fc-a1bb-a189399e94b3',  -- Fabrício Costa person_id
  '2b4f58ab-7c45-4170-8718-b77ee69ff906',  -- Núcleo IA organization_id
  NULL,                                      -- NULL = org-scoped (não initiative-scoped)
  'volunteer',
  'co_gp',
  'active',
  CURRENT_DATE,
  NULL,
  'contract_volunteer',
  '626b05b1-01ac-451c-8d00-eed662b25a22',  -- mesmo cert do volunteer × leader existente
  jsonb_build_object(
    'granted_reason', 'ADR-0011 drift cleanup — Fabrício atua como co-GP operacional (committee_coordinator de Publications Board + 2 committee_member leaderships + curator signoffs em 5 chains IP p35 + is_superadmin legacy). Engagement formaliza autoridade org-wide via can_by_member em vez do bypass is_superadmin.',
    'migration', '20260507040000',
    'session', 'p38',
    'data_architect_agent', 'a02262299817c2f16'
  )
);

-- =============================================================================
-- 2. CREATE OR REPLACE curate_item sem `is_superadmin OR` (ADR-0011 compliance)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.curate_item(
  p_table text,
  p_id uuid,
  p_action text,
  p_tags text[] DEFAULT NULL::text[],
  p_tribe_id integer DEFAULT NULL::integer,
  p_audience_level text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_caller record;
  v_rows integer := 0;
  v_initiative_id uuid := NULL;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null
    or not public.can_by_member(v_caller.id, 'manage_member')
  then
    raise exception 'Admin access required';
  end if;

  if p_action not in ('approve', 'reject', 'update_tags') then
    raise exception 'Invalid action: %', p_action;
  end if;

  if p_tribe_id is not null then
    SELECT id INTO v_initiative_id FROM public.initiatives WHERE legacy_tribe_id = p_tribe_id LIMIT 1;
  end if;

  if p_table = 'knowledge_assets' then
    if p_action = 'approve' then
      update public.knowledge_assets
      set
        is_active = true,
        published_at = coalesce(published_at, now()),
        tags = coalesce(p_tags, tags),
        metadata = case
          when p_tribe_id is null then metadata
          else jsonb_set(coalesce(metadata, '{}'::jsonb), '{target_tribe_id}', to_jsonb(p_tribe_id), true)
        end
      where id = p_id;
    elsif p_action = 'reject' then
      update public.knowledge_assets
      set
        is_active = false,
        published_at = null
      where id = p_id;
    else
      update public.knowledge_assets
      set tags = coalesce(p_tags, tags)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'hub_resources' then
    if p_action = 'approve' then
      update public.hub_resources
      set
        curation_status = 'approved',
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.hub_resources
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.hub_resources
      set
        tags = coalesce(p_tags, tags),
        initiative_id = coalesce(v_initiative_id, initiative_id)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  elsif p_table = 'events' then
    if p_action = 'approve' then
      update public.events
      set
        curation_status = 'approved',
        initiative_id = coalesce(v_initiative_id, initiative_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    elsif p_action = 'reject' then
      update public.events
      set curation_status = 'rejected'
      where id = p_id;
    else
      update public.events
      set
        initiative_id = coalesce(v_initiative_id, initiative_id),
        audience_level = coalesce(nullif(trim(coalesce(p_audience_level, '')), ''), audience_level)
      where id = p_id;
    end if;
    get diagnostics v_rows = row_count;
  else
    raise exception 'Invalid table: %', p_table;
  end if;

  if v_rows = 0 then
    raise exception 'Item not found: % in %', p_id, p_table;
  end if;

  return jsonb_build_object(
    'success', true,
    'table', p_table,
    'id', p_id,
    'action', p_action,
    'tribe_id', p_tribe_id,
    'audience_level', p_audience_level,
    'by', v_caller.name
  );
end;
$function$;

GRANT EXECUTE ON FUNCTION public.curate_item(text, uuid, text, text[], integer, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
