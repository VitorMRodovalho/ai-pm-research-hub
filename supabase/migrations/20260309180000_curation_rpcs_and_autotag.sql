-- ═══════════════════════════════════════════════════════════════════════════
-- Wave 5 Phase 1: Curation RPCs + KPI-Aligned Auto-Tag
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Taxonomy Tags reference table
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.taxonomy_tags (
  id         serial primary key,
  category   text not null,
  tag_key    text not null unique,
  label_pt   text not null,
  label_en   text not null default '',
  label_es   text not null default '',
  kpi_ref    text,
  is_active  boolean not null default true
);

alter table public.taxonomy_tags enable row level security;

create policy taxonomy_tags_read on public.taxonomy_tags
  for select to authenticated using (true);

create policy taxonomy_tags_manage on public.taxonomy_tags
  for all to authenticated
  using ((select r.is_superadmin from public.get_my_member_record() r));

insert into public.taxonomy_tags (category, tag_key, label_pt, label_en, label_es, kpi_ref) values
  ('research',   'article',              'Artigo',              'Article',           'Articulo',           '+10 artigos'),
  ('research',   'paper',                'Paper',               'Paper',             'Paper',              '+10 artigos'),
  ('research',   'framework',            'Framework',           'Framework',         'Framework',          '+10 artigos'),
  ('research',   'survey',               'Pesquisa/Survey',     'Survey',            'Encuesta',           '+10 artigos'),
  ('education',  'webinar',              'Webinar',             'Webinar',           'Webinar',            '+6 webinars'),
  ('education',  'workshop',             'Workshop',            'Workshop',          'Taller',             '+6 webinars'),
  ('education',  'course',               'Curso',               'Course',            'Curso',              '+6 webinars'),
  ('education',  'certification',        'Certificacao',        'Certification',     'Certificacion',      '+6 webinars'),
  ('community',  'chapter_partnership',  'Parceria Capitulo',   'Chapter Partnership','Alianza Capitulo',  '8 capitulos'),
  ('community',  'onboarding',           'Onboarding',          'Onboarding',        'Onboarding',         '8 capitulos'),
  ('community',  'mentoring',            'Mentoria',            'Mentoring',         'Mentoria',           '8 capitulos'),
  ('innovation', 'ai_tool',              'Ferramenta IA',       'AI Tool',           'Herramienta IA',     '3 pilotos'),
  ('innovation', 'prototype',            'Prototipo',           'Prototype',         'Prototipo',          '3 pilotos'),
  ('innovation', 'pilot_project',        'Projeto Piloto',      'Pilot Project',     'Proyecto Piloto',    '3 pilotos'),
  ('impact',     'volunteer_hours',      'Horas Voluntariado',  'Volunteer Hours',   'Horas Voluntariado', '1.800h impacto'),
  ('impact',     'social_project',       'Projeto Social',      'Social Project',    'Proyecto Social',    '1.800h impacto'),
  ('impact',     'external_talk',        'Palestra Externa',    'External Talk',     'Charla Externa',     '1.800h impacto'),
  ('governance', 'meeting_minutes',      'Ata de Reuniao',      'Meeting Minutes',   'Acta de Reunion',    'Operacional'),
  ('governance', 'report',               'Relatorio',           'Report',            'Informe',            'Operacional'),
  ('governance', 'process_doc',          'Doc de Processo',     'Process Doc',       'Doc de Proceso',     'Operacional')
on conflict (tag_key) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Auto-tag function (KPI-aligned keyword matching)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.suggest_tags(
  p_title text,
  p_type text default null,
  p_cycle_code text default null
)
returns text[]
language plpgsql stable as $$
declare
  v_tags text[] := '{}';
  v_lower text := lower(coalesce(p_title, ''));
  v_type text := lower(coalesce(p_type, ''));
begin
  -- Keyword-based detection
  if v_lower like '%webinar%' or v_lower like '%pmi-%' or v_lower like '%capitulo%' or v_lower like '%chapter%' then
    v_tags := v_tags || 'webinar'::text;
    if v_lower like '%pmi-go%' or v_lower like '%goias%' or v_lower like '%pmi-ce%' or v_lower like '%pmi-df%' or v_lower like '%pmi-mg%' or v_lower like '%pmi-rs%' then
      v_tags := v_tags || 'chapter_partnership'::text;
    end if;
  end if;

  if v_lower like '%artigo%' or v_lower like '%article%' or v_lower like '%paper%' or v_lower like '%publicacao%' then
    v_tags := v_tags || 'article'::text;
  end if;

  if v_lower like '%framework%' or v_lower like '%modelo%' or v_lower like '%template%' then
    v_tags := v_tags || 'framework'::text;
  end if;

  if v_lower like '%curso%' or v_lower like '%course%' or v_lower like '%trilha%' or v_lower like '%trail%' then
    v_tags := v_tags || 'course'::text;
  end if;

  if v_lower like '%mentor%' or v_lower like '%onboarding%' then
    v_tags := v_tags || 'onboarding'::text;
  end if;

  if v_lower like '%prototip%' or v_lower like '%prototype%' or v_lower like '%piloto%' or v_lower like '%pilot%' then
    v_tags := v_tags || 'pilot_project'::text;
  end if;

  if v_lower like '%ata%' or v_lower like '%minuta%' or v_lower like '%minutes%' or v_lower like '%reuniao%' then
    v_tags := v_tags || 'meeting_minutes'::text;
  end if;

  if v_lower like '%relatorio%' or v_lower like '%report%' then
    v_tags := v_tags || 'report'::text;
  end if;

  -- Type-based fallback
  if v_type in ('article', 'paper') and not ('article' = any(v_tags)) then
    v_tags := v_tags || 'article'::text;
  end if;
  if v_type = 'video' and not ('webinar' = any(v_tags)) then
    v_tags := v_tags || 'webinar'::text;
  end if;

  -- Cycle-based default (from Wave5 plan)
  if array_length(v_tags, 1) is null then
    case
      when p_cycle_code in ('pilot') then v_tags := ARRAY['governance'];
      when p_cycle_code in ('cycle_1', 'cycle_2') then v_tags := ARRAY['article'];
      when p_cycle_code in ('cycle_3') then v_tags := ARRAY['chapter_partnership'];
      else v_tags := ARRAY['untagged'];
    end case;
  end if;

  return v_tags;
end;
$$;

grant execute on function public.suggest_tags(text, text, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Curation RPCs (Human-in-the-Loop)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.list_pending_curation(
  p_table text default 'all'
)
returns jsonb
language plpgsql security definer as $$
declare
  v_caller record;
  v_result jsonb := '[]'::jsonb;
  v_artifacts jsonb;
  v_resources jsonb;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;
  if not (v_caller.is_superadmin
       or v_caller.operational_role in ('manager','deputy_manager','tribe_leader'))
  then
    raise exception 'Insufficient permissions';
  end if;

  if p_table in ('all', 'artifacts') then
    select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb) into v_artifacts
    from (
      select a.id, a.title, a.url, a.type, a.status, a.source, a.tags,
             a.curation_status, a.trello_card_id, a.cycle,
             a.created_at, m.name as author_name,
             t.name as tribe_name,
             'artifacts' as _table,
             public.suggest_tags(a.title, a.type, a.cycle) as suggested_tags
      from public.artifacts a
      left join public.members m on m.id = a.member_id
      left join public.tribes t on t.id = a.tribe_id
      where a.source is distinct from 'manual'
        and a.curation_status in ('draft','pending_review')
      order by a.created_at desc
      limit 200
    ) r;
    v_result := v_result || coalesce(v_artifacts, '[]'::jsonb);
  end if;

  if p_table in ('all', 'hub_resources') then
    select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb) into v_resources
    from (
      select h.id, h.title, h.url, h.asset_type as type, h.source, h.tags,
             h.curation_status, h.trello_card_id, h.cycle_code as cycle,
             h.created_at, null::text as author_name,
             t.name as tribe_name,
             'hub_resources' as _table,
             public.suggest_tags(h.title, h.asset_type, h.cycle_code) as suggested_tags
      from public.hub_resources h
      left join public.tribes t on t.id = h.tribe_id
      where h.source is distinct from 'manual'
        and h.curation_status in ('draft','pending_review')
      order by h.created_at desc
      limit 200
    ) r;
    v_result := v_result || coalesce(v_resources, '[]'::jsonb);
  end if;

  return v_result;
end;
$$;

grant execute on function public.list_pending_curation(text) to authenticated;

-- Approve / reject / update tags
create or replace function public.curate_item(
  p_table text,
  p_id uuid,
  p_action text,
  p_tags text[] default null
)
returns jsonb
language plpgsql security definer as $$
declare
  v_caller record;
begin
  select * into v_caller from public.get_my_member_record();
  if v_caller is null or not (
    v_caller.is_superadmin
    or v_caller.operational_role in ('manager','deputy_manager')
  ) then
    raise exception 'Admin access required';
  end if;

  if p_action not in ('approve', 'reject', 'update_tags') then
    raise exception 'Invalid action: %', p_action;
  end if;

  if p_table = 'artifacts' then
    if p_action = 'approve' then
      update public.artifacts set curation_status = 'approved',
        tags = coalesce(p_tags, tags) where id = p_id;
    elsif p_action = 'reject' then
      update public.artifacts set curation_status = 'rejected' where id = p_id;
    elsif p_action = 'update_tags' then
      update public.artifacts set tags = coalesce(p_tags, tags) where id = p_id;
    end if;
  elsif p_table = 'hub_resources' then
    if p_action = 'approve' then
      update public.hub_resources set curation_status = 'approved',
        tags = coalesce(p_tags, tags) where id = p_id;
    elsif p_action = 'reject' then
      update public.hub_resources set curation_status = 'rejected' where id = p_id;
    elsif p_action = 'update_tags' then
      update public.hub_resources set tags = coalesce(p_tags, tags) where id = p_id;
    end if;
  else
    raise exception 'Invalid table: %', p_table;
  end if;

  return jsonb_build_object(
    'success', true,
    'table', p_table,
    'id', p_id,
    'action', p_action,
    'by', v_caller.name
  );
end;
$$;

grant execute on function public.curate_item(text, uuid, text, text[]) to authenticated;

-- List all taxonomy tags
create or replace function public.list_taxonomy_tags()
returns setof public.taxonomy_tags
language sql security definer as $$
  select * from public.taxonomy_tags where is_active = true order by category, tag_key;
$$;

grant execute on function public.list_taxonomy_tags() to authenticated;

commit;
