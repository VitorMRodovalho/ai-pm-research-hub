-- ═══════════════════════════════════════════════════════════════════════════
-- WAVE 2: WhatsApp Communication Journey
-- Date: 2026-03-09
-- Purpose: Add opt-in privacy column for peer-to-peer WhatsApp sharing
-- ═══════════════════════════════════════════════════════════════════════════

begin;

alter table public.members
  add column if not exists share_whatsapp boolean not null default false;

comment on column public.members.share_whatsapp
  is 'LGPD opt-in: when true, tribe peers can see a "Chat on WhatsApp" button linking to wa.me/{phone}. Phone number is never exposed in text.';

-- Update public_members VIEW to include the opt-in flag
-- (the phone number itself stays EXCLUDED from this view)
drop view if exists public.public_members;
create view public.public_members as
  select
    id, name, photo_url, chapter, operational_role, designations,
    tribe_id, current_cycle_active, is_active, linkedin_url,
    credly_badges, credly_url, credly_verified_at,
    cpmai_certified, cpmai_certified_at,
    country, state, cycles, created_at,
    share_whatsapp
  from public.members;

alter view public.public_members set (security_invoker = false);
grant select on public.public_members to authenticated;
grant select on public.public_members to anon;

-- Update the member_self_update RPC to accept the new field
create or replace function public.member_self_update(
  p_pmi_id text default null,
  p_phone text default null,
  p_linkedin_url text default null,
  p_credly_url text default null,
  p_share_whatsapp boolean default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_uid uuid := auth.uid();
  v_member record;
begin
  select * into v_member from public.members where auth_id = v_uid;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  update public.members set
    pmi_id       = coalesce(p_pmi_id, pmi_id),
    phone        = coalesce(p_phone, phone),
    linkedin_url = coalesce(p_linkedin_url, linkedin_url),
    credly_url   = coalesce(p_credly_url, credly_url),
    share_whatsapp = coalesce(p_share_whatsapp, share_whatsapp),
    updated_at   = now()
  where auth_id = v_uid;

  return jsonb_build_object('success', true);
end;
$$;

commit;

-- ═══════════════════════════════════════════════════════════════════════════
-- RPC: resolve_whatsapp_link
-- Securely returns the wa.me link for a member who opted in.
-- Only returns data if:
--   1. Target member has share_whatsapp = true
--   2. Caller is authenticated
--   3. Caller belongs to the same tribe OR is admin (has_min_tier(4))
-- Phone number is sanitized (digits only) server-side.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.resolve_whatsapp_link(p_member_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller record;
  v_target record;
  v_clean_phone text;
begin
  -- Get caller
  select id, tribe_id, operational_role, is_superadmin
    into v_caller from public.members where auth_id = v_caller_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Caller not found');
  end if;

  -- Get target
  select id, phone, tribe_id, share_whatsapp
    into v_target from public.members where id = p_member_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Member not found');
  end if;

  -- Check opt-in
  if v_target.share_whatsapp is not true then
    return jsonb_build_object('success', false, 'error', 'Member has not opted in');
  end if;

  -- Check same tribe or admin
  if not (
    v_caller.is_superadmin = true
    or v_caller.operational_role in ('manager', 'deputy_manager')
    or (v_caller.tribe_id is not null and v_caller.tribe_id = v_target.tribe_id)
  ) then
    return jsonb_build_object('success', false, 'error', 'Not authorized');
  end if;

  -- No phone registered
  if v_target.phone is null or v_target.phone = '' then
    return jsonb_build_object('success', false, 'error', 'No phone registered');
  end if;

  -- Clean phone: keep only digits
  v_clean_phone := regexp_replace(v_target.phone, '[^0-9]', '', 'g');

  return jsonb_build_object(
    'success', true,
    'url', 'https://wa.me/' || v_clean_phone
  );
end;
$$;
