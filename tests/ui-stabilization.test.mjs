import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

function read(relativePath) {
  return readFileSync(resolve(ROOT, relativePath), 'utf8');
}

test('profile uses delegated credly normalization instead of per-render rebind helper', () => {
  const content = read('src/pages/profile.astro');
  assert.equal(content.includes('bindCredlyField('), false);
  assert.equal(content.includes("target.id === 'self-credly'"), true);
});

test('profile credly verification retries once on 401 with refreshed session', () => {
  const content = read('src/pages/profile.astro');
  assert.equal(content.includes('const callVerifyCredly = async (accessToken: string)'), true);
  assert.equal(content.includes('if (response.status === 401)'), true);
  assert.equal(content.includes('await sb.auth.refreshSession();'), true);
});

test('profile credly verify action keeps delegated handler and button state safety', () => {
  const content = read('src/pages/profile.astro');
  assert.equal(content.includes("case 'verify-credly':"), true);
  assert.equal(content.includes("id=\"btn-credly-verify\" data-action=\"verify-credly\""), true);
  assert.equal(content.includes('btn.disabled = true; btn.textContent = PROFILE_I18N.credlyVerifying;'), true);
  assert.equal(content.includes('btn.disabled = false; btn.textContent = PROFILE_I18N.verifyCredly;'), true);
});

test('admin allocation pending list is null-safe for name and phone rendering', () => {
  const content = read('src/pages/admin/index.astro');
  const memberFormat = read('src/lib/admin/member-format.ts');
  assert.equal(content.includes("from '../../lib/admin/member-format'"), true);
  assert.equal(memberFormat.includes('export function safeName(member: any): string'), true);
  assert.equal(memberFormat.includes('export function normalizeDigits(value: unknown): string'), true);
  assert.equal(content.includes('const nm = safeName(m);'), true);
  assert.equal(content.includes('const phone = normalizeDigits(m?.phone);'), true);
});

test('gamification lifetime ranking uses aggregated points map before fallback', () => {
  const content = read('src/pages/gamification.astro');
  assert.equal(content.includes('lifetime_points: Number(lifetimePointsByMember[m.member_id] ?? m.total_points ?? 0)'), true);
  assert.equal(content.includes('? Number(lifetimePointsByMember[m.member_id] ?? m.total_points ?? 0)'), true);
});

test('selection page no longer hardcodes cycle tabs or snapshot cycle title', () => {
  const content = read('src/pages/admin/selection.astro');
  assert.equal(content.includes('data-cycle="3"'), false);
  assert.equal(content.includes('Comparação de Snapshots — Ciclo 3'), false);
  assert.equal(content.includes('loadSelectionCycles()'), true);
});

test('confirm dialog no longer mutates confirm button onclick directly', () => {
  const content = read('src/components/ui/ConfirmDialog.astro');
  assert.equal(content.includes('btn.onclick ='), false);
  assert.equal(content.includes("document.getElementById('confirm-btn')?.addEventListener('click'"), true);
});

test('dark mode foundation persists ui theme and exposes profile toggle', () => {
  const layout = read('src/layouts/BaseLayout.astro');
  const nav = read('src/components/nav/Nav.astro');
  const css = read('src/styles/global.css');
  assert.equal(layout.includes("const key = 'ui_theme'"), true);
  assert.equal(layout.includes("document.documentElement.setAttribute('data-theme', theme);"), true);
  assert.equal(nav.includes("const THEME_KEY = 'ui_theme';"), true);
  assert.equal(nav.includes("id=\"pd-theme-toggle\""), true);
  assert.equal(nav.includes("if (action === 'toggle-theme')"), true);
  assert.equal(css.includes('@custom-variant dark'), true);
});

test('dark mode styling is applied to teams, webinars, and tribe board modal surfaces', () => {
  const teams = read('src/pages/teams.astro');
  const webinars = read('src/pages/admin/webinars.astro');
  const tribe = read('src/pages/tribe/[id].astro');
  const darkAuditScript = read('scripts/audit_dark_mode_a11y.sh');
  const darkChecklist = read('docs/project-governance/DARK_MODE_A11Y_CHECKLIST.md');
  assert.equal(teams.includes('dark:bg-slate-900'), true);
  assert.equal(webinars.includes('dark:bg-slate-900'), true);
  assert.equal(tribe.includes('id="board-item-modal"'), true);
  assert.equal(tribe.includes('dark:bg-slate-900'), true);
  assert.equal(tribe.includes('dark:border-slate-700'), true);
  assert.equal(tribe.includes('id="deliverable-modal"'), true);
  assert.equal(tribe.includes('close-deliverable-modal'), true);
  assert.equal(darkAuditScript.includes('src/pages/tribe/[id].astro'), true);
  assert.equal(darkAuditScript.includes('PASS: dark mode audit passed.'), true);
  assert.equal(darkChecklist.includes('./scripts/audit_dark_mode_a11y.sh'), true);
});

test('admin webinars now reuses the events stack instead of staying a placeholder', () => {
  const content = read('src/pages/admin/webinars.astro');
  const publicRoute = read('src/pages/webinars.astro');
  assert.equal(content.includes('Em Breve'), false);
  assert.equal(content.includes("sb.rpc('get_events_with_attendance'"), true);
  assert.equal(content.includes("sb.rpc('list_meeting_artifacts'"), true);
  assert.equal(content.includes("sb.from('hub_resources').select('*').eq('is_active', true).eq('asset_type', 'webinar')"), true);
  assert.equal(content.includes("ev.type === 'webinar'"), true);
  assert.equal(content.includes('canAccessWebinarsWorkspace(member)'), true);
  assert.equal(content.includes("navSb?.auth?.getSession"), true);
  assert.equal(content.includes('list_webinars'), false);
  assert.equal(content.includes('Agenda & Presenca'), true);
  assert.equal(content.includes('/admin/comms'), true);
  assert.equal(content.includes('Publicacao de replay'), true);
  assert.equal(content.includes("publicationBadge('Presentations'"), true);
  assert.equal(content.includes("publicationBadge('Workspace'"), true);
  assert.equal(content.includes('Acoes rapidas prioritarias'), true);
  assert.equal(content.includes('function operatorAction(ev: any)'), true);
  assert.equal(content.includes('buildAttendanceHref(ev: any'), true);
  assert.equal(content.includes('buildCommsHref(ev: any'), true);
  assert.equal(content.includes('buildPresentationsHref(ev: any)'), true);
  assert.equal(content.includes('buildWorkspaceHref(ev: any)'), true);
  assert.equal(content.includes("params.set('eventId', String(ev.id))"), true);
  assert.equal(content.includes("params.set('focus', 'broadcasts')"), true);
  assert.equal(content.includes("params.set('tab', 'events')"), true);
  assert.equal(content.includes("params.set('type', 'webinar')"), true);
  assert.equal(content.includes('Proxima acao:'), true);
  assert.equal(content.includes('renderActions(webinars);'), true);
  assert.equal(publicRoute.includes("import WebinarsPanel from './admin/webinars.astro';"), true);
});

test('presentations and workspace accept deep-link query filters for webinar follow-through', () => {
  const presentations = read('src/pages/presentations.astro');
  const workspace = read('src/pages/workspace.astro');
  assert.equal(presentations.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(presentations.includes("const q = params.get('q')"), true);
  assert.equal(presentations.includes("const tribe = params.get('tribe')"), true);
  assert.equal(presentations.includes("document.getElementById('pres-search')"), true);
  assert.equal(workspace.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(workspace.includes("activeType = params.get('type') || ''"), true);
  assert.equal(workspace.includes("searchQuery = (params.get('q') || '').trim()"), true);
  assert.equal(workspace.includes('syncTypeButtons();'), true);
});

test('attendance and admin comms accept contextual webinar handoff state from URL', () => {
  const attendance = read('src/pages/attendance.astro');
  const comms = read('src/pages/admin/comms.astro');
  const webinarHelpers = read('src/lib/webinars/context-aids.ts');
  assert.equal(attendance.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(attendance.includes("ATTENDANCE_ROUTE.eventId = params.get('eventId') || ''"), true);
  assert.equal(attendance.includes("ATTENDANCE_ROUTE.edit = params.get('edit') === '1'"), true);
  assert.equal(attendance.includes("document.getElementById('attendance-search')"), true);
  assert.equal(attendance.includes("openEditEvent(focused);"), true);
  assert.equal(attendance.includes("document.getElementById('edit-ev-context')"), true);
  assert.equal(attendance.includes('buildWebinarCommsHref(ATTENDANCE_ROUTE, focused)'), true);
  assert.equal(attendance.includes('getAttendanceHandoffCopy(ATTENDANCE_ROUTE.action)'), true);
  assert.equal(attendance.includes('getAttendanceEditAssistantCopy(ATTENDANCE_ROUTE.action)'), true);
  assert.equal(attendance.includes("data-action=\"open-focused-edit\""), true);
  assert.equal(comms.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(comms.includes("COMMS_ROUTE.focus = params.get('focus') || ''"), true);
  assert.equal(comms.includes("COMMS_ROUTE.context = params.get('context') || ''"), true);
  assert.equal(comms.includes('buildAttendanceFromCommsRoute(COMMS_ROUTE)'), true);
  assert.equal(comms.includes('buildCommsPlaybookTemplates(COMMS_ROUTE, formatRouteDate)'), true);
  assert.equal(comms.includes("document.getElementById('comms-broadcast-search')"), true);
  assert.equal(comms.includes("document.getElementById('broadcast-section')?.scrollIntoView"), true);
  assert.equal(comms.includes('buildCommsPlaybook()'), true);
  assert.equal(comms.includes('navigator.clipboard?.writeText'), true);
  assert.equal(comms.includes('data-action="copy-template"'), true);
  assert.equal(webinarHelpers.includes('export function buildWebinarCommsHref'), true);
  assert.equal(webinarHelpers.includes('export function buildAttendanceFromCommsRoute'), true);
  assert.equal(webinarHelpers.includes('export function buildCommsPlaybookTemplates'), true);
});

test('curatorship keeps operator filters and approval targeting wired to rpc payload', () => {
  const curatorship = read('src/pages/admin/curatorship.astro');
  assert.equal(curatorship.includes('id="cur-search"'), true);
  assert.equal(curatorship.includes('let searchQuery ='), true);
  assert.equal(curatorship.includes("if (target && target.id === 'cur-search')"), true);
  assert.equal(curatorship.includes('p_tribe_id: extra?.tribeId ?? null'), true);
  assert.equal(curatorship.includes('p_audience_level: extra?.audienceLevel ?? null'), true);
  assert.equal(curatorship.includes("class=\"cur-confirm-approve"), true);
  assert.equal(curatorship.includes("sb.from('tribes').select('id,name,is_active').eq('is_active', true).order('id')"), true);
});

test('curatorship rpc contract keeps approve/reject payload keys stable', () => {
  const curatorship = read('src/pages/admin/curatorship.astro');
  assert.equal(curatorship.includes("const { error } = await sb.rpc('curate_item', {"), true);
  assert.equal(curatorship.includes('p_table: table'), true);
  assert.equal(curatorship.includes('p_id: id'), true);
  assert.equal(curatorship.includes('p_action: action'), true);
  assert.equal(curatorship.includes('p_tags: tags || null'), true);
  assert.equal(curatorship.includes('p_tribe_id: extra?.tribeId ?? null'), true);
  assert.equal(curatorship.includes('p_audience_level: extra?.audienceLevel ?? null'), true);
  assert.equal(curatorship.includes("table === 'artifacts' && sendToPublication ? 'pmi_submission' : null"), true);
  assert.equal(curatorship.includes("callCurate(table, id, 'reject');"), true);
});

test('publications global board route and curatorship enqueue toggle are wired', () => {
  const navConfig = read('src/lib/navigation.config.ts');
  const publications = read('src/pages/publications.astro');
  const publicationsIsland = read('src/components/boards/PublicationsBoardIsland.tsx');
  const curatorship = read('src/pages/admin/curatorship.astro');
  const constants = read('src/lib/admin/constants.ts');
  const migration = read('supabase/migrations/20260314170000_global_publications_and_operational_board_scope.sql');

  assert.equal(navConfig.includes("key: 'publications'"), true);
  assert.equal(navConfig.includes("href: '/publications'"), true);
  assert.equal(constants.includes('export function canAccessPublicationsWorkspace(member: any): boolean'), true);
  assert.equal(publications.includes("import PublicationsBoardIsland"), true);
  assert.equal(publications.includes("<PublicationsBoardIsland client:load />"), true);
  assert.equal(publicationsIsland.includes("sb.rpc('list_project_boards', { p_tribe_id: null })"), true);
  assert.equal(publicationsIsland.includes("domain_key || '') === 'publications_submissions'"), true);
  assert.equal(publicationsIsland.includes("sb.rpc('move_board_item'"), true);
  assert.equal(curatorship.includes('cur-approve-publication'), true);
  assert.equal(curatorship.includes("'pmi_submission'"), true);
  assert.equal(migration.includes("domain_key = 'publications_submissions'"), true);
  assert.equal(migration.includes('create or replace function public.enqueue_artifact_publication_card('), true);
});

test('astro island foundation includes React and dnd-kit for kanban evolution', () => {
  const astroConfig = read('astro.config.mjs');
  const packageJson = read('package.json');
  const publicationsIsland = read('src/components/boards/PublicationsBoardIsland.tsx');
  assert.equal(astroConfig.includes("import react from '@astrojs/react'"), true);
  assert.equal(astroConfig.includes('integrations: [react()]'), true);
  assert.equal(packageJson.includes('"@astrojs/react"'), true);
  assert.equal(packageJson.includes('"react"'), true);
  assert.equal(packageJson.includes('"@dnd-kit/core"'), true);
  assert.equal(publicationsIsland.includes('DndContext'), true);
  assert.equal(publicationsIsland.includes('SortableContext'), true);
});

test('tribe exploration and lifecycle management honor active-member access plus project management controls', () => {
  const nav = read('src/components/nav/Nav.astro');
  const tribe = read('src/pages/tribe/[id].astro');
  const admin = read('src/pages/admin/index.astro');
  const tribeAccess = read('src/lib/tribes/access.ts');
  const migration = read('supabase/migrations/20260311123000_expand_tribe_lifecycle_management_access.sql');

  assert.equal(tribeAccess.includes('export function canExploreTribes'), true);
  assert.equal(tribeAccess.includes('export function canManageTribeLifecycle'), true);
  assert.equal(nav.includes("sb.from('public_members')"), true);
  assert.equal(nav.includes('derived_active'), true);
  assert.equal(nav.includes('canExploreTribes(_member)'), true);
  assert.equal(tribe.includes('id="tribe-denied"'), true);
  assert.equal(tribe.includes('id="tribe-shell" class="hidden"'), true);
  assert.equal(tribe.includes('canExploreTribes(currentMember)'), true);
  assert.equal(tribe.includes('Modo exploração:'), true);
  assert.equal(tribe.includes(".eq('current_cycle_active', true)"), true);
  assert.equal(admin.includes("canManageTribeLifecycle(m)"), true);
  assert.equal(admin.includes("bindLifecycleButton('btn-move-member'"), true);
  assert.equal(admin.includes(".from('public_members')"), true);
  assert.equal(migration.includes("Project management access required"), true);
  assert.equal(migration.includes("operational_role in ('manager', 'deputy_manager')"), true);
});

test('tribe catalog supports dynamic runtime entries and explicit active status', () => {
  const tribe = read('src/pages/tribe/[id].astro');
  const tribeEn = read('src/pages/en/tribe/[id].astro');
  const tribeEs = read('src/pages/es/tribe/[id].astro');
  const admin = read('src/pages/admin/index.astro');
  const nav = read('src/components/nav/Nav.astro');
  const workspace = read('src/pages/workspace.astro');
  const artifacts = read('src/pages/artifacts.astro');
  const gamification = read('src/pages/gamification.astro');
  const hero = read('src/components/sections/HeroSection.astro');
  const tribesSection = read('src/components/sections/TribesSection.astro');
  const catalog = read('src/lib/tribes/catalog.ts');
  const migration = read('supabase/migrations/20260312050000_dynamic_tribe_catalog_and_status.sql');
  const lineageMigration = read('supabase/migrations/20260312150000_tribe_lineage_and_legacy_links.sql');
  const communicationMigration = read('supabase/migrations/20260312160000_communication_tribe_and_board_linking.sql');

  assert.equal(tribe.includes('tribeId < 1 || tribeId > 8'), false);
  assert.equal(tribeEn.includes('tribeId < 1 || tribeId > 8'), false);
  assert.equal(tribeEs.includes('tribeId < 1 || tribeId > 8'), false);
  assert.equal(tribe.includes('buildTribeLabel(_tribe'), true);
  assert.equal(tribe.includes('tribeData.is_active === false'), true);
  assert.equal(admin.includes("sb.rpc('admin_list_tribes'"), true);
  assert.equal(admin.includes("data-action=\"create-tribe\""), true);
  assert.equal(admin.includes("data-action=\"toggle-tribe-active\""), true);
  assert.equal(nav.includes("select('id, name, whatsapp_url, quadrant, quadrant_name, is_active')"), true);
  assert.equal(tribe.includes('id="tribe-context-switch"'), true);
  assert.equal(workspace.includes("sb.from('tribes').select('id, name, is_active').order('id')"), true);
  assert.equal(artifacts.includes("sb.from('tribes').select('id, name, is_active').order('id')"), true);
  assert.equal(gamification.includes("sb.from('tribes').select('id, name, quadrant').eq('is_active', true).order('id')"), true);
  assert.equal(hero.includes(".eq('is_active', true)"), true);
  assert.equal(tribesSection.includes(".select('id, name, notes, whatsapp_url, is_active')"), true);
  assert.equal(tribesSection.includes("if (card && activeMap[tid] === false)"), true);
  assert.equal(tribesSection.includes("if (title && nameMap[tid]) title.textContent = String(nameMap[tid]);"), true);
  assert.equal(catalog.includes('export function getTribeColor'), true);
  assert.equal(catalog.includes('export function isRuntimeTribeActive'), true);
  assert.equal(migration.includes('add column if not exists is_active boolean not null default true'), true);
  assert.equal(migration.includes('create or replace function public.admin_upsert_tribe'), true);
  assert.equal(migration.includes('create or replace function public.admin_list_tribes'), true);
  assert.equal(migration.includes('create or replace function public.admin_set_tribe_active'), true);
  assert.equal(lineageMigration.includes('create table if not exists public.tribe_lineage'), true);
  assert.equal(lineageMigration.includes('create or replace function public.admin_upsert_tribe_lineage('), true);
  assert.equal(lineageMigration.includes('create or replace function public.admin_list_tribe_lineage('), true);
  assert.equal(communicationMigration.includes('alter table public.project_boards'), true);
  assert.equal(communicationMigration.includes('add column if not exists domain_key text'), true);
  assert.equal(communicationMigration.includes('create or replace function public.admin_ensure_communication_tribe('), true);
  assert.equal(communicationMigration.includes('create or replace function public.admin_link_communication_boards('), true);
});

test('analytics v2 grants readonly access without widening admin actions and ships staged metric contracts', () => {
  const constants = read('src/lib/admin/constants.ts');
  const navConfig = read('src/lib/navigation.config.ts');
  const adminNav = read('src/components/nav/AdminNav.astro');
  const adminIndex = read('src/pages/admin/index.astro');
  const analytics = read('src/pages/admin/analytics.astro');
  const migration = read('supabase/migrations/20260312110000_analytics_v2_internal_readonly_and_metrics.sql');

  assert.equal(constants.includes('ANALYTICS_READONLY_DESIGNATIONS'), true);
  assert.equal(constants.includes('canReadInternalAnalytics(member)'), true);
  assert.equal(constants.includes('canManageAdminActions(member)'), true);
  assert.equal(navConfig.includes("allowedDesignations: ['sponsor', 'chapter_liaison', 'curator']"), true);
  assert.equal(adminNav.includes("allowedDesignations: ['sponsor', 'chapter_liaison', 'curator']"), true);
  assert.equal(adminIndex.includes("tab === 'analytics' && !canAccessAdminRoute(MEMBER, 'admin_analytics')"), true);
  assert.equal(adminIndex.includes('id="exec-analytics-link-card"'), true);
  assert.equal(analytics.includes('id="analytics-filter-cycle"'), true);
  assert.equal(analytics.includes('id="analytics-filter-tribe"'), true);
  assert.equal(analytics.includes('id="analytics-filter-chapter"'), true);
  assert.equal(analytics.includes("safeRpc('exec_funnel_v2')"), true);
  assert.equal(analytics.includes("safeRpc('exec_impact_hours_v2')"), true);
  assert.equal(analytics.includes("safeRpc('exec_certification_delta')"), true);
  assert.equal(analytics.includes("safeRpc('exec_chapter_roi')"), true);
  assert.equal(analytics.includes("safeRpc('exec_role_transitions')"), true);
  assert.equal(analytics.includes("safeRpc('exec_analytics_v2_quality')"), true);
  assert.equal(analytics.includes('id="analytics-quality-banner"'), true);
  assert.equal(analytics.includes('id="analytics-interpretation-card"'), true);
  assert.equal(analytics.includes('id="analytics-copy-summary"'), true);
  assert.equal(analytics.includes('function buildExecutiveSummary()'), true);
  assert.equal(analytics.includes("sb.from('cycles').select('cycle_code, cycle_label, is_current, sort_order')"), true);
  assert.equal(analytics.includes("sb.from('tribes').select('id, name, is_active').eq('is_active', true).order('id')"), true);
  assert.equal(migration.includes('create or replace function public.can_read_internal_analytics()'), true);
  assert.equal(migration.includes('create or replace function public.analytics_member_scope('), true);
  assert.equal(migration.includes('create or replace function public.exec_funnel_v2('), true);
  assert.equal(migration.includes('create or replace function public.exec_impact_hours_v2('), true);
  assert.equal(migration.includes('create or replace function public.exec_certification_delta('), true);
  assert.equal(migration.includes('create or replace function public.exec_chapter_roi('), true);
  assert.equal(migration.includes('create or replace function public.exec_role_transitions('), true);
  const qualityMigration = read('supabase/migrations/20260312130000_analytics_v2_quality_checks.sql');
  assert.equal(qualityMigration.includes('create or replace function public.exec_analytics_v2_quality('), true);
  assert.equal(qualityMigration.includes('grant execute on function public.exec_analytics_v2_quality(text, integer, text) to authenticated;'), true);
  assert.equal(migration.includes('raise exception \'Internal analytics access required\''), true);
});

test('unified ingestion pipeline keeps sensitive governance in backend contracts', () => {
  const migration = read('supabase/migrations/20260312170000_unified_ingestion_batches.sql');
  const pipeline = read('scripts/unified_ingestion_pipeline.ts');
  const controlsMigration = read('supabase/migrations/20260312200000_ingestion_source_controls.sql');
  const lockingMigration = read('supabase/migrations/20260313000000_ingestion_apply_locking.sql');
  assert.equal(migration.includes('create table if not exists public.ingestion_batches'), true);
  assert.equal(migration.includes('create table if not exists public.ingestion_batch_files'), true);
  assert.equal(migration.includes('create or replace function public.admin_start_ingestion_batch('), true);
  assert.equal(migration.includes('create or replace function public.admin_finalize_ingestion_batch('), true);
  assert.equal(pipeline.includes('blocked_by_policy_whatsapp_manual_only'), true);
  assert.equal(pipeline.includes("sb.rpc('admin_start_ingestion_batch'"), true);
  assert.equal(pipeline.includes("sb.rpc('admin_finalize_ingestion_batch'"), true);
  assert.equal(pipeline.includes("sb.rpc('admin_get_ingestion_source_policy'"), true);
  assert.equal(controlsMigration.includes('create table if not exists public.ingestion_source_controls'), true);
  assert.equal(controlsMigration.includes('create or replace function public.admin_set_ingestion_source_policy('), true);
  assert.equal(controlsMigration.includes('create or replace function public.admin_get_ingestion_source_policy('), true);
  assert.equal(lockingMigration.includes('create table if not exists public.ingestion_apply_locks'), true);
  assert.equal(lockingMigration.includes('create or replace function public.admin_acquire_ingestion_apply_lock('), true);
  assert.equal(lockingMigration.includes('create or replace function public.admin_release_ingestion_apply_lock('), true);
  assert.equal(pipeline.includes("sb.rpc('admin_acquire_ingestion_apply_lock'"), true);
  assert.equal(pipeline.includes("sb.rpc('admin_release_ingestion_apply_lock'"), true);
});

test('legacy tribe materialization uses explicit backend lineage/links', () => {
  const migration = read('supabase/migrations/20260312180000_legacy_tribe_materialization.sql');
  const script = read('scripts/materialize_legacy_tribes.ts');
  assert.equal(migration.includes('create table if not exists public.legacy_tribes'), true);
  assert.equal(migration.includes('create table if not exists public.legacy_tribe_board_links'), true);
  assert.equal(migration.includes('create or replace function public.admin_upsert_legacy_tribe('), true);
  assert.equal(migration.includes('create or replace function public.admin_link_board_to_legacy_tribe('), true);
  assert.equal(script.includes("sb.rpc('admin_upsert_legacy_tribe'"), true);
  assert.equal(script.includes("sb.rpc('admin_link_board_to_legacy_tribe'"), true);
});

test('data quality audit contract tracks tribe and legacy integrity', () => {
  const migration = read('supabase/migrations/20260312190000_data_quality_audit_rpc.sql');
  const script = read('scripts/run_data_quality_audit.ts');
  assert.equal(migration.includes('create or replace function public.admin_data_quality_audit()'), true);
  assert.equal(migration.includes("'tribe_6_without_boards'"), true);
  assert.equal(migration.includes("'communication_tribe_missing'"), true);
  assert.equal(migration.includes("'legacy_cycle_1_2_empty'"), true);
  assert.equal(script.includes("sb.rpc('admin_data_quality_audit'"), true);
});

test('notion normalization contracts are backend-mapped before board insertion', () => {
  const migration = read('supabase/migrations/20260312210000_notion_normalization_and_board_mapping.sql');
  const script = read('scripts/notion_normalize_import.ts');
  assert.equal(migration.includes('create table if not exists public.notion_import_staging'), true);
  assert.equal(migration.includes('create or replace function public.admin_map_notion_item_to_board('), true);
  assert.equal(script.includes("sb.from('notion_import_staging').insert(payload)"), true);
  assert.equal(script.includes("sb.rpc('admin_start_ingestion_batch'"), true);
  assert.equal(script.includes("sb.rpc('admin_finalize_ingestion_batch'"), true);
});

test('continuity overrides support explicit renumbering paths', () => {
  const migration = read('supabase/migrations/20260312220000_tribe_continuity_overrides.sql');
  const script = read('scripts/seed_continuity_overrides.ts');
  assert.equal(migration.includes('create table if not exists public.tribe_continuity_overrides'), true);
  assert.equal(migration.includes('create or replace function public.admin_upsert_tribe_continuity_override('), true);
  assert.equal(script.includes('fabricio-stream-renumbering'), true);
  assert.equal(script.includes('debora-stream-renumbering'), true);
  assert.equal(script.includes("sb.rpc('admin_upsert_tribe_continuity_override'"), true);
});

test('post-ingestion healthcheck persists governance alerts', () => {
  const migration = read('supabase/migrations/20260312230000_post_ingestion_healthcheck_alerts.sql');
  const script = read('scripts/run_post_ingestion_healthcheck.ts');
  assert.equal(migration.includes('create table if not exists public.ingestion_alerts'), true);
  assert.equal(migration.includes('create or replace function public.admin_run_post_ingestion_healthcheck('), true);
  assert.equal(migration.includes("'communication_tribe_missing'"), true);
  assert.equal(migration.includes("'legacy_cycle_1_2_empty'"), true);
  assert.equal(script.includes("sb.rpc('admin_run_post_ingestion_healthcheck'"), true);
});

test('legacy member continuity links stay backend-governed', () => {
  const migration = read('supabase/migrations/20260313010000_legacy_member_links.sql');
  const script = read('scripts/seed_legacy_member_links.ts');

  assert.equal(migration.includes('create table if not exists public.legacy_member_links'), true);
  assert.equal(migration.includes('create or replace function public.admin_link_member_to_legacy_tribe('), true);
  assert.equal(migration.includes("check (link_type in ('historical_member', 'historical_leader', 'continued_member'))"), true);
  assert.equal(script.includes("sb.rpc('admin_link_member_to_legacy_tribe'"), true);
});

test('notion board suggestions are generated by backend contracts', () => {
  const migration = read('supabase/migrations/20260313020000_notion_board_suggestions.sql');
  const script = read('scripts/notion_suggest_board_links.ts');

  assert.equal(migration.includes('create or replace function public.admin_suggest_notion_board_mappings('), true);
  assert.equal(migration.includes('returns table('), true);
  assert.equal(migration.includes('security definer'), true);
  assert.equal(script.includes("sb.rpc('admin_suggest_notion_board_mappings'"), true);
});

test('data quality snapshots persist audit history in backend', () => {
  const migration = read('supabase/migrations/20260313030000_data_quality_audit_snapshots.sql');
  const script = read('scripts/capture_data_quality_snapshot.ts');

  assert.equal(migration.includes('create table if not exists public.data_quality_audit_snapshots'), true);
  assert.equal(migration.includes('create or replace function public.admin_capture_data_quality_snapshot('), true);
  assert.equal(migration.includes("select public.admin_data_quality_audit() into v_audit;"), true);
  assert.equal(script.includes("sb.rpc('admin_capture_data_quality_snapshot'"), true);
});

test('release readiness gate centralizes alerts and snapshot checks', () => {
  const migration = read('supabase/migrations/20260313040000_release_readiness_gate.sql');
  const script = read('scripts/run_release_readiness_gate.ts');

  assert.equal(migration.includes('create or replace function public.admin_release_readiness_gate('), true);
  assert.equal(migration.includes('from public.data_quality_audit_snapshots'), true);
  assert.equal(migration.includes('from public.ingestion_alerts'), true);
  assert.equal(script.includes("sb.rpc('admin_release_readiness_gate'"), true);
});

test('ingestion pipeline run ledger enforces idempotent apply runs', () => {
  const migration = read('supabase/migrations/20260313050000_ingestion_run_ledger.sql');
  const pipeline = read('scripts/unified_ingestion_pipeline.ts');

  assert.equal(migration.includes('create table if not exists public.ingestion_run_ledger'), true);
  assert.equal(migration.includes('create or replace function public.admin_register_ingestion_run('), true);
  assert.equal(migration.includes('create or replace function public.admin_complete_ingestion_run('), true);
  assert.equal(pipeline.includes("sb.rpc('admin_register_ingestion_run'"), true);
  assert.equal(pipeline.includes("sb.rpc('admin_complete_ingestion_run'"), true);
});

test('ingestion alerts have auditable lifecycle transitions', () => {
  const migration = read('supabase/migrations/20260313060000_ingestion_alert_lifecycle.sql');
  const script = read('scripts/manage_ingestion_alert.ts');

  assert.equal(migration.includes('create table if not exists public.ingestion_alert_events'), true);
  assert.equal(migration.includes('create or replace function public.admin_update_ingestion_alert_status('), true);
  assert.equal(migration.includes("raise exception 'Invalid transition closed -> acknowledged';"), true);
  assert.equal(script.includes("sb.rpc('admin_update_ingestion_alert_status'"), true);
});

test('readiness gate supports strict and advisory policy modes', () => {
  const migration = read('supabase/migrations/20260313070000_release_readiness_policy_modes.sql');
  const runScript = read('scripts/run_release_readiness_gate.ts');
  const policyScript = read('scripts/set_release_readiness_policy.ts');

  assert.equal(migration.includes('create table if not exists public.release_readiness_policies'), true);
  assert.equal(migration.includes('create or replace function public.admin_set_release_readiness_policy('), true);
  assert.equal(migration.includes("if v_mode = 'strict' then"), true);
  assert.equal(runScript.includes('p_policy_mode: MODE || null'), true);
  assert.equal(policyScript.includes("sb.rpc('admin_set_release_readiness_policy'"), true);
});

test('post-ingestion chain orchestrates healthcheck snapshot and gate', () => {
  const migration = read('supabase/migrations/20260313080000_post_ingestion_chain_orchestrator.sql');
  const script = read('scripts/run_post_ingestion_chain.ts');

  assert.equal(migration.includes('create or replace function public.admin_run_post_ingestion_chain('), true);
  assert.equal(migration.includes('public.admin_run_post_ingestion_healthcheck('), true);
  assert.equal(migration.includes('public.admin_capture_data_quality_snapshot('), true);
  assert.equal(migration.includes('public.admin_release_readiness_gate('), true);
  assert.equal(script.includes("sb.rpc('admin_run_post_ingestion_chain'"), true);
});

test('partner-safe governance summary stays backend read-only', () => {
  const migration = read('supabase/migrations/20260313090000_partner_governance_summary.sql');
  const script = read('scripts/run_partner_governance_summary.ts');

  assert.equal(migration.includes('create or replace function public.exec_partner_governance_summary('), true);
  assert.equal(migration.includes("coalesce('sponsor' = any(v_caller.designations), false)"), true);
  assert.equal(migration.includes("coalesce('chapter_liaison' = any(v_caller.designations), false)"), true);
  assert.equal(migration.includes("public.admin_release_readiness_gate(null, null, 'advisory')"), true);
  assert.equal(script.includes("sb.rpc('exec_partner_governance_summary'"), true);
});

test('ingestion source sla contracts enforce timeout governance', () => {
  const migration = read('supabase/migrations/20260313100000_ingestion_source_sla_timeouts.sql');
  const script = read('scripts/check_ingestion_source_timeout.ts');

  assert.equal(migration.includes('create table if not exists public.ingestion_source_sla'), true);
  assert.equal(migration.includes('create or replace function public.admin_set_ingestion_source_sla('), true);
  assert.equal(migration.includes('create or replace function public.admin_check_ingestion_source_timeout('), true);
  assert.equal(script.includes("sb.rpc('admin_check_ingestion_source_timeout'"), true);
});

test('ingestion alert remediation hooks are backend-governed and auditable', () => {
  const migration = read('supabase/migrations/20260313110000_ingestion_alert_remediation_hooks.sql');
  const script = read('scripts/run_ingestion_alert_remediation.ts');

  assert.equal(migration.includes('create table if not exists public.ingestion_alert_remediation_rules'), true);
  assert.equal(migration.includes('create table if not exists public.ingestion_alert_remediation_runs'), true);
  assert.equal(migration.includes('create or replace function public.admin_set_ingestion_alert_remediation_rule('), true);
  assert.equal(migration.includes('create or replace function public.admin_run_ingestion_alert_remediation('), true);
  assert.equal(script.includes("sb.rpc('admin_run_ingestion_alert_remediation'"), true);
});

test('release readiness timeline persists go-no-go decisions', () => {
  const migration = read('supabase/migrations/20260313120000_release_readiness_history.sql');
  const script = read('scripts/record_release_readiness_decision.ts');

  assert.equal(migration.includes('create table if not exists public.release_readiness_history'), true);
  assert.equal(migration.includes('create or replace function public.admin_record_release_readiness_decision('), true);
  assert.equal(migration.includes('v_gate := public.admin_release_readiness_gate(null, null, p_mode);'), true);
  assert.equal(script.includes("sb.rpc('admin_record_release_readiness_decision'"), true);
});

test('partner governance rpc pack includes trend contracts', () => {
  const migration = read('supabase/migrations/20260313130000_partner_governance_trends.sql');
  const script = read('scripts/run_partner_governance_trends.ts');

  assert.equal(migration.includes('create or replace function public.exec_partner_governance_trends('), true);
  assert.equal(migration.includes('from public.release_readiness_history h'), true);
  assert.equal(migration.includes('from public.ingestion_alerts a'), true);
  assert.equal(script.includes("sb.rpc('exec_partner_governance_trends'"), true);
});

test('dry-run rehearsal chain validates governance without mutating ingestion', () => {
  const migration = read('supabase/migrations/20260313140000_dry_run_rehearsal_chain.sql');
  const script = read('scripts/run_dry_rehearsal_chain.ts');

  assert.equal(migration.includes('create or replace function public.admin_run_dry_rehearsal_chain('), true);
  assert.equal(migration.includes('v_audit := public.admin_data_quality_audit();'), true);
  assert.equal(migration.includes('v_gate := public.admin_release_readiness_gate(null, null, p_gate_mode);'), true);
  assert.equal(migration.includes("v_timeout_probe := public.admin_check_ingestion_source_timeout('mixed'"), true);
  assert.equal(script.includes("sb.rpc('admin_run_dry_rehearsal_chain'"), true);
});

test('remediation escalation matrix resolves action by severity and recurrence', () => {
  const migration = read('supabase/migrations/20260313150000_remediation_escalation_matrix.sql');
  const script = read('scripts/resolve_remediation_action.ts');

  assert.equal(migration.includes('create table if not exists public.ingestion_remediation_escalation_matrix'), true);
  assert.equal(migration.includes('create or replace function public.admin_resolve_remediation_action('), true);
  assert.equal(migration.includes('and m.recurrence_threshold <= greatest(v_recurrence, 1)'), true);
  assert.equal(script.includes("sb.rpc('admin_resolve_remediation_action'"), true);
});

test('readiness slo breach checks emit governed alerts', () => {
  const migration = read('supabase/migrations/20260313160000_readiness_slo_breach_alerts.sql');
  const script = read('scripts/check_readiness_slo_breach.ts');

  assert.equal(migration.includes('create table if not exists public.readiness_slo_alerts'), true);
  assert.equal(migration.includes('create or replace function public.admin_check_readiness_slo_breach('), true);
  assert.equal(migration.includes("where a.alert_key = 'readiness_slo_breach'"), true);
  assert.equal(script.includes("sb.rpc('admin_check_readiness_slo_breach'"), true);
});

test('ingestion provenance signatures are generated and stored in backend', () => {
  const migration = read('supabase/migrations/20260313170000_ingestion_provenance_signatures.sql');
  const script = read('scripts/sign_ingestion_provenance.ts');

  assert.equal(migration.includes('create table if not exists public.ingestion_provenance_signatures'), true);
  assert.equal(migration.includes('create or replace function public.admin_sign_ingestion_file_provenance('), true);
  assert.equal(migration.includes("digest("), true);
  assert.equal(script.includes("sb.rpc('admin_sign_ingestion_file_provenance'"), true);
});

test('partner governance scorecards aggregate summary and trends', () => {
  const migration = read('supabase/migrations/20260313180000_partner_governance_scorecards.sql');
  const script = read('scripts/run_partner_governance_scorecards.ts');

  assert.equal(migration.includes('create or replace function public.exec_partner_governance_scorecards('), true);
  assert.equal(migration.includes('v_summary := public.exec_partner_governance_summary(p_window_days);'), true);
  assert.equal(migration.includes('v_trends := public.exec_partner_governance_trends(p_window_days);'), true);
  assert.equal(script.includes("sb.rpc('exec_partner_governance_scorecards'"), true);
});

test('controlled rollback contracts support planned and approved execution', () => {
  const migration = read('supabase/migrations/20260313190000_controlled_rollback_contracts.sql');
  const script = read('scripts/run_controlled_rollback.ts');

  assert.equal(migration.includes('create table if not exists public.ingestion_rollback_plans'), true);
  assert.equal(migration.includes('create or replace function public.admin_plan_ingestion_rollback('), true);
  assert.equal(migration.includes('create or replace function public.admin_execute_ingestion_rollback('), true);
  assert.equal(script.includes("sb.rpc('admin_execute_ingestion_rollback'"), true);
});

test('rollback execution safeguards require dual approval and valid window', () => {
  const migration = read('supabase/migrations/20260313200000_rollback_execution_safeguards.sql');
  const script = read('scripts/approve_controlled_rollback.ts');

  assert.equal(migration.includes('create or replace function public.admin_approve_ingestion_rollback('), true);
  assert.equal(migration.includes("raise exception 'Rollback execution requires dual approval';"), true);
  assert.equal(migration.includes("raise exception 'Rollback execution is before allowed window';"), true);
  assert.equal(script.includes("sb.rpc('admin_approve_ingestion_rollback'"), true);
});

test('provenance verification rpc validates stored signatures', () => {
  const migration = read('supabase/migrations/20260313210000_provenance_verification_rpc.sql');
  const script = read('scripts/verify_ingestion_provenance.ts');

  assert.equal(migration.includes('create or replace function public.admin_verify_ingestion_provenance_batch('), true);
  assert.equal(migration.includes('where s.batch_id = p_batch_id'), true);
  assert.equal(migration.includes("'invalid_signatures'"), true);
  assert.equal(script.includes("sb.rpc('admin_verify_ingestion_provenance_batch'"), true);
});

test('readiness slo dashboard contracts aggregate SLO KPIs', () => {
  const migration = read('supabase/migrations/20260313220000_slo_dashboard_contracts.sql');
  const script = read('scripts/run_readiness_slo_dashboard.ts');

  assert.equal(migration.includes('create or replace function public.exec_readiness_slo_dashboard('), true);
  assert.equal(migration.includes('from public.readiness_slo_alerts'), true);
  assert.equal(migration.includes("'mtbd_hours'"), true);
  assert.equal(script.includes("sb.rpc('exec_readiness_slo_dashboard'"), true);
});

test('remediation effectiveness analytics summarize rule outcomes', () => {
  const migration = read('supabase/migrations/20260313230000_remediation_effectiveness_analytics.sql');
  const script = read('scripts/run_remediation_effectiveness.ts');

  assert.equal(migration.includes('create or replace function public.exec_remediation_effectiveness('), true);
  assert.equal(migration.includes('from public.ingestion_alert_remediation_runs'), true);
  assert.equal(migration.includes("'success_rate'"), true);
  assert.equal(script.includes("sb.rpc('exec_remediation_effectiveness'"), true);
});

test('governance export bundle composes all governance contracts', () => {
  const migration = read('supabase/migrations/20260314000000_governance_export_bundle.sql');
  const script = read('scripts/run_governance_export_bundle.ts');

  assert.equal(migration.includes('create or replace function public.exec_governance_export_bundle('), true);
  assert.equal(migration.includes('public.exec_partner_governance_summary(p_window_days);'), true);
  assert.equal(migration.includes('public.exec_remediation_effectiveness(p_window_days);'), true);
  assert.equal(script.includes("sb.rpc('exec_governance_export_bundle'"), true);
});

test('dual-control rollback audit trails are persisted in backend', () => {
  const migration = read('supabase/migrations/20260314010000_dual_control_audit_trails.sql');
  const script = read('scripts/append_rollback_audit_event.ts');

  assert.equal(migration.includes('create table if not exists public.rollback_audit_events'), true);
  assert.equal(migration.includes('create or replace function public.admin_append_rollback_audit_event('), true);
  assert.equal(migration.includes("check (event_type in ('planned', 'approved_stage_1', 'approved_stage_2', 'executed', 'cancelled'))"), true);
  assert.equal(script.includes("sb.rpc('admin_append_rollback_audit_event'"), true);
});

test('provenance anomalies can emit critical governance alerts', () => {
  const migration = read('supabase/migrations/20260314020000_provenance_anomaly_alerts.sql');
  const script = read('scripts/raise_provenance_anomaly_alert.ts');

  assert.equal(migration.includes('create or replace function public.admin_raise_provenance_anomaly_alert('), true);
  assert.equal(migration.includes("public.admin_verify_ingestion_provenance_batch(p_batch_id)"), true);
  assert.equal(migration.includes("'provenance_signature_anomaly'"), true);
  assert.equal(script.includes("sb.rpc('admin_raise_provenance_anomaly_alert'"), true);
});

test('slo drill-down by source aggregates ingestion file outcomes', () => {
  const migration = read('supabase/migrations/20260314030000_slo_drilldown_by_source.sql');
  const script = read('scripts/run_readiness_slo_by_source.ts');

  assert.equal(migration.includes('create or replace function public.exec_readiness_slo_by_source('), true);
  assert.equal(migration.includes('from public.ingestion_batch_files f'), true);
  assert.equal(migration.includes("'processed_rate'"), true);
  assert.equal(script.includes("sb.rpc('exec_readiness_slo_by_source'"), true);
});

test('rollback simulation harness scores risk without mutating state', () => {
  const migration = read('supabase/migrations/20260314040000_rollback_simulation_harness.sql');
  const script = read('scripts/run_rollback_simulation.ts');

  assert.equal(migration.includes('create or replace function public.admin_simulate_ingestion_rollback('), true);
  assert.equal(migration.includes("'risk_score'"), true);
  assert.equal(migration.includes("'recommended'"), true);
  assert.equal(script.includes("sb.rpc('admin_simulate_ingestion_rollback'"), true);
});

test('governance bundle snapshots persist export history', () => {
  const migration = read('supabase/migrations/20260314050000_governance_bundle_snapshots.sql');
  const script = read('scripts/capture_governance_bundle_snapshot.ts');

  assert.equal(migration.includes('create table if not exists public.governance_bundle_snapshots'), true);
  assert.equal(migration.includes('create or replace function public.admin_capture_governance_bundle_snapshot('), true);
  assert.equal(migration.includes('v_payload := public.exec_governance_export_bundle'), true);
  assert.equal(script.includes("sb.rpc('admin_capture_governance_bundle_snapshot'"), true);
});

test('board lifecycle and source-to-tribe integrity contracts are backend-enforced', () => {
  const migration = read('supabase/migrations/20260314130000_board_lifecycle_and_tribe_fact_integrity.sql');
  assert.equal(migration.includes('create table if not exists public.board_source_tribe_map'), true);
  assert.equal(migration.includes('create trigger trg_enforce_board_item_source_tribe_integrity'), true);
  assert.equal(migration.includes('project_boards_linked_sources_require_tribe_chk'), true);
  assert.equal(migration.includes('create table if not exists public.board_lifecycle_events'), true);
  assert.equal(migration.includes('create or replace function public.admin_archive_project_board('), true);
  assert.equal(migration.includes('create or replace function public.admin_restore_project_board('), true);
  assert.equal(migration.includes('create or replace function public.admin_archive_board_item('), true);
  assert.equal(migration.includes('create or replace function public.admin_restore_board_item('), true);
});

test('tribe taxonomy includes workstream classification for navigation grouping', () => {
  const migration = read('supabase/migrations/20260314152000_tribes_workstream_type_taxonomy.sql');
  const teams = read('src/pages/teams.astro');
  assert.equal(migration.includes('add column if not exists workstream_type text not null default'), true);
  assert.equal(migration.includes("check (workstream_type in ('research', 'operational', 'legacy'))"), true);
  assert.equal(teams.includes('Ativas (Pesquisa)'), true);
  assert.equal(teams.includes('Subprojetos (Operação)'), true);
  assert.equal(teams.includes('Legado (Read-only)'), true);
  assert.equal(teams.includes("select('id, name, quadrant_name, is_active, workstream_type')"), true);
});

test('tribe kanban supports modal edit/create and archive actions', () => {
  const tribe = read('src/pages/tribe/[id].astro');
  const migration = read('supabase/migrations/20260314153000_board_item_editor_rpc.sql');
  assert.equal(tribe.includes('id="board-item-modal"'), true);
  assert.equal(tribe.includes('data-action="open-board-item"'), true);
  assert.equal(tribe.includes('data-action="add-board-card"'), true);
  assert.equal(tribe.includes("sb.rpc('upsert_board_item'"), true);
  assert.equal(tribe.includes("sb.rpc('admin_archive_board_item'"), true);
  assert.equal(tribe.includes('id="board-item-form"'), true);
  assert.equal(tribe.includes('id="bi-labels"'), true);
  assert.equal(tribe.includes('id="bi-checklist"'), true);
  assert.equal(tribe.includes('const checklistBadge = checklistTotal > 0'), true);
  assert.equal(migration.includes('create or replace function public.upsert_board_item('), true);
  assert.equal(migration.includes("raise exception 'Project management access required';"), true);
});

test('schedule flow no longer depends on far-future deadline sentinel', () => {
  const scheduleContent = read('src/lib/schedule.ts');
  const tribesContent = read('src/components/sections/TribesSection.astro');
  const heroContent = read('src/components/sections/HeroSection.astro');
  assert.equal(scheduleContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(tribesContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(heroContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(tribesContent.includes('selectionUnavailable'), true);
});

test('tribes section touched links no longer use inline onclick handlers', () => {
  const content = read('src/components/sections/TribesSection.astro');
  assert.equal(content.includes('onclick='), false);
  assert.equal(content.includes('data-stop-propagation'), true);
});

test('ci browser guards use retry wrapper and playwright cache', () => {
  const ci = read('.github/workflows/ci.yml');
  const retryScript = read('scripts/run_browser_guards_with_retry.sh');
  assert.equal(ci.includes('Cache Playwright browsers'), true);
  assert.equal(ci.includes('./scripts/run_browser_guards_with_retry.sh'), true);
  assert.equal(retryScript.includes('max_attempts=2'), true);
  assert.equal(retryScript.includes('npm run test:browser:guards'), true);
});

test('ci heartbeat monitor tracks CI Validate status on main', () => {
  const heartbeat = read('.github/workflows/ci-heartbeat-monitor.yml');
  assert.equal(heartbeat.includes('name: CI Heartbeat Monitor'), true);
  assert.equal(heartbeat.includes("cron: '*/30 * * * *'"), true);
  assert.equal(heartbeat.includes("workflow_id = 'ci.yml'"), true);
  assert.equal(heartbeat.includes("alertTitle = '[CI Monitor] CI Validate failing on main'"), true);
  assert.equal(heartbeat.includes('issues: write'), true);
});

test('workflows force JavaScript actions onto Node 24 runtime', () => {
  const ci = read('.github/workflows/ci.yml');
  const heartbeat = read('.github/workflows/ci-heartbeat-monitor.yml');
  assert.equal(ci.includes("FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: 'true'"), true);
  assert.equal(heartbeat.includes("FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: 'true'"), true);
});

test('cloudflare public env parity runbook includes preview checks and local audit script', () => {
  const runbook = read('docs/project-governance/CLOUDFLARE_ENV_INJECTION_VALIDATION.md');
  const script = read('scripts/audit_cloudflare_public_env_parity.sh');
  assert.equal(runbook.includes('./scripts/audit_cloudflare_public_env_parity.sh'), true);
  assert.equal(runbook.includes('Checklist de validação (preview)'), true);
  assert.equal(script.includes('PUBLIC_SUPABASE_URL'), true);
  assert.equal(script.includes('PUBLIC_SUPABASE_ANON_KEY'), true);
  assert.equal(script.includes('src/lib/supabase.ts'), true);
});

test('route smoke script validates anonymous deny markers on protected routes', () => {
  const smoke = read('scripts/smoke-routes.mjs');
  assert.equal(smoke.includes("assertContains('/admin/selection', 'id=\"sel-denied\"')"), true);
  assert.equal(smoke.includes("assertContains('/admin/analytics', 'id=\"analytics-denied\"')"), true);
  assert.equal(smoke.includes("assertContains('/admin/curatorship', 'id=\"cur-denied\"')"), true);
  assert.equal(smoke.includes("assertContains('/admin/comms', 'id=\"comms-denied\"')"), true);
  assert.equal(smoke.includes("assertContains('/webinars', 'id=\"webinars-denied\"')"), true);
  assert.equal(smoke.includes("assertContains('/tribe/1', 'id=\"tribe-denied\"')"), true);
});

test('docs index exposes persona map and has audit script for reference integrity', () => {
  const index = read('docs/INDEX.md');
  const auditScript = read('scripts/audit_docs_index_links.sh');
  assert.equal(index.includes('# Docs Index por Persona'), true);
  assert.equal(index.includes('./scripts/audit_docs_index_links.sh'), true);
  assert.equal(auditScript.includes('docs/INDEX.md'), true);
  assert.equal(auditScript.includes('broken references'), true);
});

test('adr baseline exists and index audit script validates referenced ADR files', () => {
  const adrIndex = read('docs/adr/README.md');
  const adr1 = read('docs/adr/ADR-0001-source-of-truth-and-cycle-history.md');
  const adr2 = read('docs/adr/ADR-0002-role-model-v3-operational-role-and-designations.md');
  const adr3 = read('docs/adr/ADR-0003-admin-analytics-internal-readonly-surface.md');
  const adrAudit = read('scripts/audit_adr_index.sh');
  assert.equal(adrIndex.includes('ADR-0001-source-of-truth-and-cycle-history.md'), true);
  assert.equal(adrIndex.includes('ADR-0002-role-model-v3-operational-role-and-designations.md'), true);
  assert.equal(adrIndex.includes('ADR-0003-admin-analytics-internal-readonly-surface.md'), true);
  assert.equal(adr1.includes('`members` representa snapshot atual'), true);
  assert.equal(adr2.includes('operational_role'), true);
  assert.equal(adr3.includes('/admin/analytics'), true);
  assert.equal(adrAudit.includes('docs/adr/README.md'), true);
  assert.equal(adrAudit.includes('ADR index has broken references'), true);
});

test('admin tribe catalog UI helpers are extracted to dedicated module', () => {
  const admin = read('src/pages/admin/index.astro');
  const helpers = read('src/lib/admin/tribe-catalog-ui.ts');
  assert.equal(admin.includes("from '../../lib/admin/tribe-catalog-ui'"), true);
  assert.equal(admin.includes('getTribeCatalogSummary(tribes, MEMBER?.is_superadmin === true, isRuntimeTribeActive)'), true);
  assert.equal(admin.includes('buildAdminTribeFilterHtml({'), true);
  assert.equal(helpers.includes('export function getTribeCatalogSummary('), true);
  assert.equal(helpers.includes('export function buildAdminTribeFilterHtml('), true);
});

test('home pages resolve shared home schedule instead of fetching only the deadline', () => {
  const pt = read('src/pages/index.astro');
  const en = read('src/pages/en/index.astro');
  const es = read('src/pages/es/index.astro');
  for (const content of [pt, en, es]) {
    assert.equal(content.includes('getHomeSchedule'), true);
    assert.equal(content.includes('schedule={homeSchedule}'), true);
    assert.equal(content.includes('AgendaSection deadline={deadlineIso}'), true);
    assert.equal(content.includes('ResourcesSection deadline={deadlineIso}'), true);
  }
});

test('home fallback copy no longer hardcodes kickoff dates or recurring meeting times', () => {
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');
  const hero = read('src/components/sections/HeroSection.astro');

  assert.equal(pt.includes('5 de Março de 2026 · 19:30 BRT · Google Meet'), false);
  assert.equal(en.includes('March 5, 2026 · 7:30 PM BRT · Google Meet'), false);
  assert.equal(es.includes('5 de Marzo de 2026 · 19:30 BRT · Google Meet'), false);
  assert.equal(pt.includes('Quintas · 19:30 → 20:30 BRT'), false);
  assert.equal(en.includes('Thursdays · 7:30 → 8:30 PM BRT'), false);
  assert.equal(es.includes('Jueves · 19:30 → 20:30 BRT'), false);
  assert.equal(hero.includes("hi18n.meetingSchedule || 'Quintas · 19:30 → 20:30 BRT'"), false);
  assert.equal(hero.includes("hi18n.recurringMeeting || 'Reunião Recorrente · Quintas 19:30 BRT'"), false);
});

test('resources fallback playlist no longer hardcodes saturday deadline copy', () => {
  const resources = read('src/components/sections/ResourcesSection.astro');
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');

  assert.equal(resources.includes('8 vídeos. Escolha até Sáb 12h.'), false);
  assert.equal(resources.includes("title: 'Playlist YouTube'"), false);
  assert.equal(resources.includes("t('resources.playlist.descPrefix', lang)"), true);
  assert.equal(pt.includes("'resources.playlist.descPrefix'"), true);
  assert.equal(en.includes("'resources.playlist.descPrefix'"), true);
  assert.equal(es.includes("'resources.playlist.descPrefix'"), true);
});

test('public home locale copy no longer hardcodes cycle 3 labels', () => {
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');

  assert.equal(pt.includes('KICK-OFF OFICIAL — CICLO 03 (2026/1)'), false);
  assert.equal(en.includes('OFFICIAL KICK-OFF — CYCLE 03 (2026/1)'), false);
  assert.equal(es.includes('KICK-OFF OFICIAL — CICLO 03 (2026/1)'), false);
  assert.equal(pt.includes('os primeiros certificados do Ciclo 3 serão exibidos aqui.'), false);
  assert.equal(en.includes('the first Cycle 3 certifications will be displayed here.'), false);
  assert.equal(es.includes('las primeras certificaciones del Ciclo 3 se mostrarán aquí.'), false);
  assert.equal(pt.includes('coordenação e governança · Ciclo 3'), false);
  assert.equal(en.includes('coordination and governance · Cycle 3'), false);
  assert.equal(es.includes('coordinación y gobernanza · Ciclo 3'), false);
  assert.equal(pt.includes('participantes ativos · Ciclo 3'), false);
  assert.equal(en.includes('active participants · Cycle 3'), false);
  assert.equal(es.includes('participantes activos · Ciclo 3'), false);
  assert.equal(pt.includes('gestão, operações & comunicação · Ciclo 3'), false);
  assert.equal(en.includes('management, operations & communications · Cycle 3'), false);
  assert.equal(es.includes('gestión, operaciones & comunicación · Ciclo 3'), false);
});

test('hero post-kickoff state now uses runtime kickoff metadata before optional event enrichment', () => {
  const hero = read('src/components/sections/HeroSection.astro');

  assert.equal(hero.includes("kickoffAt: schedule?.kickoffAt ?? null"), true);
  assert.equal(hero.includes("platformLabel: schedule?.platformLabel ?? null"), true);
  assert.equal(hero.includes("const heroKickoffPassed ="), true);
  assert.equal(hero.includes("const evDate = new Date(ev.date + 'T22:30:00Z');"), false);
  assert.equal(hero.includes("eventArea.innerHTML = kickoffFallbackHtml(dateStr);"), true);
});

test('tribes deadline formatting no longer relies on manual UTC math or stale fixed fallback copy', () => {
  const tribes = read('src/components/sections/TribesSection.astro');
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');

  assert.equal(tribes.includes("const months = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];"), false);
  assert.equal(tribes.includes("d.getUTCHours() - 3"), false);
  assert.equal(tribes.includes("new Intl.DateTimeFormat(currentLang"), true);
  assert.equal(pt.includes("'tribes.deadline': 'Encerra Sáb 08/Mar 12h BRT'"), false);
  assert.equal(en.includes("'tribes.deadline': 'Closes Sat 03/08 12PM BRT'"), false);
  assert.equal(es.includes("'tribes.deadline': 'Cierra Sáb 08/Mar 12h BRT'"), false);
});
