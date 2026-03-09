-- ═══════════════════════════════════════════════════════════════════════════
-- WAVE 1: LGPD Protection — Members RLS + public_members VIEW
-- Date: 2026-03-09
-- Priority: P0 (Critical Security)
--
-- Problem: The `members` table has NO Row Level Security enabled.
-- Any authenticated user can SELECT all rows including email, phone, and
-- other PII via `sb.from('members').select('*')` from the browser console.
--
-- Solution:
--   1. Enable RLS on `members`
--   2. Create strict policies (own-record, tribe-leader scoped, admin full)
--   3. Create `public_members` VIEW without PII for public-facing pages
-- ═══════════════════════════════════════════════════════════════════════════

begin;

-- ─── Step 1: Enable RLS ───
alter table public.members enable row level security;

-- ─── Step 2: RLS Policies ───

-- Policy: Every authenticated user can read their OWN record (full PII)
-- Uses auth.uid() matched against members.auth_id
drop policy if exists "members_select_own" on public.members;
create policy "members_select_own" on public.members
  for select to authenticated
  using (auth_id = auth.uid());

-- Policy: Admin tier (rank >= 4) can read ALL members (full PII)
-- Reuses the existing has_min_tier() database function
drop policy if exists "members_select_admin" on public.members;
create policy "members_select_admin" on public.members
  for select to authenticated
  using (public.has_min_tier(4));

-- Policy: Tribe leader can read members of their OWN tribe (full PII)
-- To avoid circular reference (policy on members referencing members),
-- we use a subquery that fetches the caller's tribe_id and role in one shot.
-- The subquery is evaluated once per statement, not per row.
drop policy if exists "members_select_tribe_leader" on public.members;
create policy "members_select_tribe_leader" on public.members
  for select to authenticated
  using (
    tribe_id = (
      select m.tribe_id from public.members m
      where m.auth_id = auth.uid()
        and m.operational_role = 'tribe_leader'
      limit 1
    )
  );

-- Policy: Members can UPDATE only their own record
-- (profile page edits: secondary_emails, photo_url, linkedin_url, etc.)
drop policy if exists "members_update_own" on public.members;
create policy "members_update_own" on public.members
  for update to authenticated
  using (auth_id = auth.uid())
  with check (auth_id = auth.uid());

-- Policy: Admin tier can UPDATE any member (admin panel edits)
drop policy if exists "members_update_admin" on public.members;
create policy "members_update_admin" on public.members
  for update to authenticated
  using (public.has_min_tier(4))
  with check (public.has_min_tier(4));

-- Policy: Admin tier can INSERT new members (admin registration)
drop policy if exists "members_insert_admin" on public.members;
create policy "members_insert_admin" on public.members
  for insert to authenticated
  with check (public.has_min_tier(4));

-- Policy: Only superadmin can DELETE (safety net)
drop policy if exists "members_delete_superadmin" on public.members;
create policy "members_delete_superadmin" on public.members
  for delete to authenticated
  using (
    exists (
      select 1 from public.members m
      where m.auth_id = auth.uid()
        and m.is_superadmin = true
    )
  );

-- ─── Step 3: public_members VIEW (no PII) ───
-- This view exposes only non-sensitive columns.
-- Public-facing pages (tribe dashboard, gamification, team section, etc.)
-- MUST use this view instead of the members table directly.

drop view if exists public.public_members;
create view public.public_members as
  select
    id,
    name,
    photo_url,
    chapter,
    operational_role,
    designations,
    tribe_id,
    current_cycle_active,
    is_active,
    linkedin_url,
    credly_badges,
    credly_url,
    credly_verified_at,
    cpmai_certified,
    cpmai_certified_at,
    country,
    state,
    cycles,
    created_at
  from public.members;

-- Grant access to the view for authenticated and anon roles
grant select on public.public_members to authenticated;
grant select on public.public_members to anon;

-- The view inherits the RLS of the underlying members table.
-- Since anon users don't match any RLS policy on members, they get 0 rows.
-- Authenticated users will see rows according to their policies.
-- HOWEVER: for public pages we want everyone to see basic info.
-- Solution: Create the view as SECURITY DEFINER via a function-backed approach,
-- or simply grant direct SELECT on specific columns.
--
-- Better approach: Create the view with security_invoker = false (default in PG)
-- so it runs as the view owner (postgres) bypassing RLS on the base table.
-- This is safe because the view itself contains NO PII columns.

-- Force the view to bypass RLS (runs as owner = postgres)
alter view public.public_members set (security_invoker = false);

commit;
