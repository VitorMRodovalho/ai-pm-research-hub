-- ═══════════════════════════════════════════════════════════════════════════
-- Sprint: Scalability Refinement
-- 1. communication_templates table with dynamic signature support
-- 2. Tighten webinars SELECT policy to admin+ (was all authenticated)
-- 3. Add curation_status to artifacts/hub_resources for Human-in-the-Loop
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Communication Templates (Dynamic Signatures)
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.communication_templates (
  id            serial primary key,
  slug          text not null unique,
  label         text not null,
  subject_tpl   text not null default '',
  body_html_tpl text not null default '',
  signature_tpl text not null default '',
  variables     text[] not null default '{}',
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.communication_templates is
  'Email templates with {{variable}} placeholders for dynamic content rendering.';

alter table public.communication_templates enable row level security;

create policy templates_select on public.communication_templates
  for select to authenticated
  using (
    (select r.operational_role in ('manager','deputy_manager','tribe_leader') or r.is_superadmin
     from public.get_my_member_record() r)
  );

create policy templates_manage on public.communication_templates
  for all to authenticated
  using (
    (select r.is_superadmin from public.get_my_member_record() r)
  );

-- Seed default templates
insert into public.communication_templates (slug, label, subject_tpl, body_html_tpl, signature_tpl, variables) values
  (
    'tribe_broadcast',
    'Comunicado de Tribo',
    '[{{tribe_name}}] {{subject}}',
    '',
    '<p style="color:#64748B;font-size:12px;line-height:1.6">Atenciosamente,<br><strong>{{sender_name}}</strong>'
      || '<br>{{sender_phone}} | <a href="{{sender_linkedin}}" style="color:#0D9488">LinkedIn</a>'
      || '<br>{{sender_role}} - {{cycle_label}}</p>',
    ARRAY['sender_name','sender_phone','sender_linkedin','sender_role','tribe_name','subject','cycle_label']
  ),
  (
    'global_onboarding',
    'Boas-vindas Global (Onboarding)',
    'Bem-vindo ao {{cycle_label}} do Nucleo de Pesquisa em IA & GP!',
    '',
    '<p style="color:#64748B;font-size:12px;line-height:1.6">Atenciosamente,<br><strong>{{sender_name}}</strong>'
      || '<br>{{sender_phone}} | <a href="{{sender_linkedin}}" style="color:#0D9488">LinkedIn</a>'
      || '<br>{{sender_role}} - Nucleo IA & GP</p>',
    ARRAY['sender_name','sender_phone','sender_linkedin','sender_role','cycle_label']
  ),
  (
    'member_deactivation',
    'Comunicado de Desligamento',
    'Comunicado: Afastamento de {{member_name}}',
    '<p>Prezados,</p><p>Informamos que o(a) pesquisador(a) <strong>{{member_name}}</strong> '
      || 'foi desligado(a) do Nucleo IA & GP.</p><p>Motivo: {{reason}}</p>',
    '<p style="color:#64748B;font-size:12px;line-height:1.6">Atenciosamente,<br><strong>{{sender_name}}</strong>'
      || '<br>Gerencia do Projeto</p>',
    ARRAY['sender_name','member_name','reason','tribe_name']
  )
on conflict (slug) do nothing;

-- RPC to fetch a template and resolve variables
create or replace function public.get_communication_template(
  p_slug text,
  p_vars jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer as $$
declare
  v_tpl record;
  v_sig text;
  v_subj text;
  v_body text;
  v_key text;
  v_val text;
begin
  select * into v_tpl from public.communication_templates where slug = p_slug and is_active = true;
  if v_tpl is null then
    return jsonb_build_object('error', 'Template not found: ' || p_slug);
  end if;

  v_sig := v_tpl.signature_tpl;
  v_subj := v_tpl.subject_tpl;
  v_body := v_tpl.body_html_tpl;

  for v_key in select unnest(v_tpl.variables)
  loop
    v_val := coalesce(p_vars ->> v_key, '');
    v_sig := replace(v_sig, '{{' || v_key || '}}', v_val);
    v_subj := replace(v_subj, '{{' || v_key || '}}', v_val);
    v_body := replace(v_body, '{{' || v_key || '}}', v_val);
  end loop;

  return jsonb_build_object(
    'slug', v_tpl.slug,
    'label', v_tpl.label,
    'subject', v_subj,
    'body_html', v_body,
    'signature_html', v_sig,
    'variables', to_jsonb(v_tpl.variables)
  );
end;
$$;

grant execute on function public.get_communication_template(text, jsonb) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Tighten webinars SELECT to leader+ (was any authenticated)
-- ═══════════════════════════════════════════════════════════════════════════

drop policy if exists webinars_select on public.webinars;

create policy webinars_select on public.webinars
  for select to authenticated
  using (
    (select r.operational_role in ('manager','deputy_manager','tribe_leader') or r.is_superadmin
     from public.get_my_member_record() r)
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Curation status for legacy imports (Human-in-the-Loop)
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'artifacts' and column_name = 'curation_status'
  ) then
    alter table public.artifacts add column curation_status text not null default 'published'
      check (curation_status in ('draft','pending_review','approved','published','rejected'));
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'hub_resources' and column_name = 'curation_status'
  ) then
    alter table public.hub_resources add column curation_status text not null default 'published'
      check (curation_status in ('draft','pending_review','approved','published','rejected'));
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'events' and column_name = 'curation_status'
  ) then
    alter table public.events add column curation_status text not null default 'published'
      check (curation_status in ('draft','pending_review','approved','published','rejected'));
  end if;
end $$;

commit;
