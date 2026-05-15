// src/lib/permissions.ts
// W144: Central permission map — single source of truth for all access control
// Every component should use hasPermission() instead of checking roles directly
//
// V4 NOTE (ADR-0007): This file reads `operational_role` and `tribe_id` from
// the `members` table. In V4, these are **cache fields** maintained by the
// `sync_operational_role_cache` trigger (migration 20260413430000), which
// derives them from the canonical `engagements` table. The logic here is
// therefore V4-cache-correct: it reads denormalized values that are kept in
// sync automatically. The authoritative source of truth is `can()` / `can_by_member()`
// RPCs (used by MCP and RLS), not this file. This file provides frontend-only
// UI gating and is safe to use as long as the sync trigger is active.

// ==========================================
// TYPES
// ==========================================

export type OperationalTier =
  | 'manager'
  | 'sponsor'
  | 'chapter_liaison'
  | 'tribe_leader'
  | 'project_collaborator'
  | 'researcher'
  | 'cop_participant'
  | 'cop_observer'
  | 'observer'
  | 'candidate'
  | 'visitor';

export type Designation =
  | 'deputy_manager'
  | 'curator'
  | 'comms_leader'
  | 'comms_member'
  | 'ambassador'
  | 'founder'
  | 'alumni'
  | 'chapter_board';

export type Permission =
  // ── Admin panel ──
  | 'admin.access'
  | 'admin.members.view'
  | 'admin.members.manage'
  | 'admin.events.manage'
  | 'admin.campaigns'
  | 'admin.analytics'
  | 'admin.analytics.chapter'
  | 'admin.blog'
  | 'admin.publications'
  | 'admin.curation'
  | 'admin.governance.view'
  | 'admin.sustainability'
  | 'admin.portfolio'
  | 'admin.partners'
  | 'admin.simulation'
  | 'admin.gamification'
  // ── Boards ──
  | 'board.view_own_tribe'
  | 'board.view_all'
  | 'board.view_global'
  | 'board.create_item'
  | 'board.edit_own_items'
  | 'board.edit_tribe_items'
  | 'board.delete_item'
  | 'board.manage_checklist'
  | 'board.create_mirror'
  | 'board.view_assigned_only'
  // ── Events ──
  | 'event.create'
  | 'event.edit'
  | 'event.attendance_batch'
  | 'event.view_all'
  | 'event.view_own_tribe'
  // ── Gamification ──
  | 'gamification.sync'
  | 'gamification.calculate'
  | 'gamification.view_ranking'
  | 'gamification.view_own'
  // ── Content ──
  | 'content.submit_publication'
  | 'content.curate'
  | 'content.view_publications'
  | 'content.blog_manage'
  // ── Data / Privacy ──
  | 'data.export_own_lgpd'
  | 'data.export_all_lgpd'
  | 'data.view_members'
  | 'data.view_tribe_members'
  | 'data.view_analytics'
  | 'data.anonymize'
  // ── Workspace ──
  | 'workspace.access'
  | 'workspace.view_tribe_dashboard'
  // ── System ──
  | 'system.manage_cycles'
  | 'system.global_config'
  | 'system.schedule_interviews';

// ==========================================
// TIER → PERMISSIONS MAP
// ==========================================

export const TIER_PERMISSIONS: Record<OperationalTier, Permission[]> = {
  manager: [
    'admin.access', 'admin.members.view', 'admin.members.manage',
    'admin.events.manage', 'admin.campaigns', 'admin.analytics',
    'admin.blog', 'admin.publications', 'admin.curation',
    'admin.governance.view',
    'admin.sustainability', 'admin.portfolio', 'admin.partners',
    'admin.simulation', 'admin.gamification',
    'board.view_all', 'board.view_global', 'board.create_item',
    'board.edit_tribe_items', 'board.delete_item',
    'board.manage_checklist', 'board.create_mirror',
    'event.create', 'event.edit', 'event.attendance_batch', 'event.view_all',
    'gamification.sync', 'gamification.calculate',
    'gamification.view_ranking', 'gamification.view_own',
    'content.submit_publication', 'content.curate',
    'content.view_publications', 'content.blog_manage',
    'data.export_own_lgpd', 'data.export_all_lgpd',
    'data.view_members', 'data.view_analytics', 'data.anonymize',
    'workspace.access', 'workspace.view_tribe_dashboard',
    'system.manage_cycles', 'system.global_config', 'system.schedule_interviews',
  ],

  sponsor: [
    'admin.access', 'admin.analytics', 'admin.analytics.chapter',
    'admin.portfolio', 'admin.sustainability', 'admin.partners',
    'admin.governance.view',
    'data.view_analytics',
    'event.view_all', 'gamification.view_ranking',
    'content.view_publications',
    'workspace.access',
  ],

  chapter_liaison: [
    'admin.access', 'admin.analytics', 'admin.analytics.chapter',
    'admin.portfolio', 'admin.partners',
    'admin.governance.view',
    'data.view_analytics',
    'event.view_all', 'gamification.view_ranking',
    'content.view_publications', 'content.curate',
    'workspace.access',
  ],

  tribe_leader: [
    'admin.access', 'admin.analytics', 'admin.analytics.chapter',
    'admin.portfolio', 'admin.sustainability', 'admin.partners',
    'admin.governance.view',
    'board.view_own_tribe', 'board.view_global', 'board.create_item',
    'board.edit_tribe_items', 'board.manage_checklist', 'board.create_mirror',
    'event.create', 'event.edit', 'event.attendance_batch', 'event.view_own_tribe',
    'gamification.view_ranking', 'gamification.view_own',
    'content.submit_publication', 'content.view_publications',
    'data.view_tribe_members', 'data.export_own_lgpd',
    'workspace.access', 'workspace.view_tribe_dashboard',
  ],

  project_collaborator: [
    'board.view_assigned_only',
    'event.view_own_tribe',
    'gamification.view_own',
    'content.view_publications',
    'workspace.access',
  ],

  researcher: [
    'board.view_own_tribe', 'board.edit_own_items', 'board.manage_checklist',
    'event.view_own_tribe',
    'gamification.view_ranking', 'gamification.view_own',
    'content.submit_publication', 'content.view_publications',
    'data.export_own_lgpd',
    'workspace.access', 'workspace.view_tribe_dashboard',
  ],

  cop_participant: [
    'event.view_own_tribe',
    'gamification.view_own',
    'content.view_publications',
    'workspace.access',
  ],

  cop_observer: [
    'event.view_own_tribe',
    'content.view_publications',
  ],

  observer: [
    'content.view_publications',
  ],

  candidate: [],
  visitor: [],
};

// ==========================================
// DESIGNATION → ADDITIONAL PERMISSIONS
// ==========================================

export const DESIGNATION_PERMISSIONS: Record<Designation, Permission[]> = {
  deputy_manager: [
    'admin.access', 'admin.members.view', 'admin.members.manage',
    'admin.events.manage', 'admin.campaigns', 'admin.analytics',
    'admin.sustainability', 'admin.portfolio', 'admin.simulation',
    'admin.governance.view', 'admin.gamification',
    'board.view_all', 'board.view_global',
    'data.view_members', 'data.view_analytics',
    'event.view_all',
  ],
  curator: [
    'admin.curation', 'content.curate',
    'admin.governance.view',
  ],
  comms_leader: [
    'board.view_global',
    'admin.gamification',
  ],
  comms_member: [
    'board.view_global',
  ],
  ambassador: [
    'data.view_analytics', 'admin.analytics.chapter',
  ],
  founder: [],
  alumni: [],
  chapter_board: [
    'admin.access', 'admin.analytics', 'admin.analytics.chapter',
    'admin.governance.view',
    'data.view_analytics',
  ],
};

// ==========================================
// TIER LABELS (for Tier Viewer UI)
// ==========================================

export const TIER_LABELS: Record<OperationalTier, { pt: string; en: string; es: string; icon: string }> = {
  manager:              { pt: 'Gerente de Projeto (GP)', en: 'Project Manager',        es: 'Gerente de Proyecto',       icon: '👑' },
  sponsor:              { pt: 'Patrocinador',            en: 'Sponsor',                es: 'Patrocinador',              icon: '🏛️' },
  chapter_liaison:      { pt: 'Ponto Focal do Capítulo', en: 'Chapter Liaison',        es: 'Enlace de Capítulo',        icon: '🔗' },
  tribe_leader:         { pt: 'Líder de Tribo',           en: 'Research Stream Leader', es: 'Líder de Tribu',            icon: '⚡' },
  project_collaborator: { pt: 'Colaborador de Projeto',  en: 'Project Collaborator',   es: 'Colaborador de Proyecto',   icon: '🤝' },
  researcher:           { pt: 'Pesquisador',             en: 'Researcher',             es: 'Investigador',              icon: '🔬' },
  cop_participant:      { pt: 'Participante de Tribo',   en: 'Stream Participant',     es: 'Participante de Tribu',     icon: '👥' },
  cop_observer:         { pt: 'Observador de Tribo',     en: 'Stream Observer',        es: 'Observador de Tribu',       icon: '👁️' },
  observer:             { pt: 'Observador / Alumni',     en: 'Observer / Alumni',      es: 'Observador / Alumni',       icon: '📖' },
  candidate:            { pt: 'Candidato',               en: 'Candidate',              es: 'Candidato',                 icon: '📋' },
  visitor:              { pt: 'Visitante',               en: 'Visitor',                es: 'Visitante',                 icon: '🌐' },
};

export const DESIGNATION_LABELS: Record<Designation, { pt: string; en: string; es: string }> = {
  deputy_manager: { pt: 'Vice-Gerente',         en: 'Deputy Manager',    es: 'Vice-Gerente' },
  curator:        { pt: 'Curador',              en: 'Curator',           es: 'Curador' },
  comms_leader:   { pt: 'Líder de Comunicação', en: 'Comms Leader',     es: 'Líder de Comunicación' },
  comms_member:   { pt: 'Time de Comunicação',  en: 'Comms Member',     es: 'Equipo de Comunicación' },
  ambassador:     { pt: 'Embaixador',           en: 'Ambassador',       es: 'Embajador' },
  founder:        { pt: 'Fundador',             en: 'Founder',          es: 'Fundador' },
  alumni:         { pt: 'Alumni',               en: 'Alumni',           es: 'Alumni' },
  chapter_board:  { pt: 'Diretoria do Capítulo', en: 'Chapter Board',   es: 'Directiva del Capítulo' },
};

// Tier color categories for simulation banner
export const TIER_COLORS: Record<OperationalTier, string> = {
  manager: '#7C3AED',              // purple
  sponsor: '#F97316',              // orange
  chapter_liaison: '#F97316',      // orange
  tribe_leader: '#10B981',         // green
  project_collaborator: '#3B82F6', // blue
  researcher: '#3B82F6',           // blue
  cop_participant: '#06B6D4',      // cyan
  cop_observer: '#94A3B8',         // gray
  observer: '#94A3B8',             // gray
  candidate: '#CBD5E1',            // light gray
  visitor: '#CBD5E1',              // light gray
};

// ==========================================
// CORE FUNCTION
// ==========================================

export interface MemberForPermission {
  is_superadmin?: boolean;
  operational_role: string;
  designations?: string[];
  tribe_id?: number | null;
  initiative_id?: string | null;
}

interface SimulationState {
  active: boolean;
  tier: OperationalTier | null;
  designations: Designation[];
  tribe_id: number | null;
  initiative_id: string | null;
}

let _simulation: SimulationState = {
  active: false, tier: null, designations: [], tribe_id: null, initiative_id: null,
};

export function setSimulation(state: SimulationState) {
  _simulation = state;
}

export function getSimulation(): SimulationState {
  return _simulation;
}

export function clearSimulation() {
  _simulation = { active: false, tier: null, designations: [], tribe_id: null, initiative_id: null };
}

// ==========================================
// V4 CAPABILITY CACHE (ADR-0007)
// ==========================================
//
// Capabilities is the per-call cache populated at bootstrap from
// `get_caller_capabilities()` RPC. It mirrors `can()` semantics in pure
// data: org-scoped action set + per-initiative + per-tribe (legacy_tribe_id).
//
// `canFor(action, scope?)` is the V4 replacement for V3 patterns like
// `member.operational_role === 'tribe_leader'`. The V3 cache (operational_role)
// is single-value and global — promoting on the priority ladder leaks scope
// (a workgroup leader becomes "tribe_leader" globally and gets
// admin/board/event privileges they do not hold institutionally).
// `canFor` consults the engagement-derived permission set with scope intact.
//
// Migration is gradual: gates that need scope distinction (tribe_leader exact
// match, "leader of THIS tribe", etc.) move to canFor. Tier-based gates that
// already match member tier semantics (manager/deputy_manager admin pages)
// can remain on hasPermission until a follow-up pass.
//
// Background: docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md.

export interface Capabilities {
  caller_id: string | null;
  person_id: string | null;
  is_superadmin: boolean;
  org_actions: string[];
  initiative_actions: Record<string, string[]>;  // initiative_id (uuid) → action set
  tribe_actions: Record<string, string[]>;       // legacy_tribe_id (int as string) → action set
}

let _capabilities: Capabilities | null = null;

// Symbol-based window key — chosen so the Astro inline `<script>` in Nav.astro
// (which can't import this module directly) can populate the cache through
// `window.__nucleoCapabilities` and React islands consume it transparently.
// Keeping both module-scope and window storage avoids islands fighting each
// other when multiple bundles co-exist.
const WINDOW_KEY = '__nucleoCapabilities';

export function setCapabilities(caps: Capabilities | null): void {
  _capabilities = caps;
  if (typeof window !== 'undefined') {
    (window as any)[WINDOW_KEY] = caps;
  }
}

export function getCapabilities(): Capabilities | null {
  if (_capabilities) return _capabilities;
  if (typeof window !== 'undefined') {
    const w = (window as any)[WINDOW_KEY];
    if (w) {
      _capabilities = w;
      return w;
    }
  }
  return null;
}

export function clearCapabilities(): void {
  _capabilities = null;
  if (typeof window !== 'undefined') {
    (window as any)[WINDOW_KEY] = null;
  }
}

// Normalize the raw RPC payload (which may have null/missing fields if the
// caller is unauthenticated or has no member). Centralises defensive coercion
// so call sites don't repeat null-guards.
export function normalizeCapabilities(raw: unknown): Capabilities {
  const r = (raw ?? {}) as Partial<Capabilities>;
  return {
    caller_id: typeof r.caller_id === 'string' ? r.caller_id : null,
    person_id: typeof r.person_id === 'string' ? r.person_id : null,
    is_superadmin: !!r.is_superadmin,
    org_actions: Array.isArray(r.org_actions) ? r.org_actions.filter(s => typeof s === 'string') : [],
    initiative_actions: (r.initiative_actions && typeof r.initiative_actions === 'object')
      ? r.initiative_actions as Record<string, string[]>
      : {},
    tribe_actions: (r.tribe_actions && typeof r.tribe_actions === 'object')
      ? r.tribe_actions as Record<string, string[]>
      : {},
  };
}

export type CanForScope =
  | { type: 'initiative'; id: string }
  | { type: 'tribe'; id: number | string };

// canFor — V4 capability check with scope.
//   canFor('manage_member')                       → org-scoped only
//   canFor('write_board', { type: 'initiative', id }) → org or that initiative
//   canFor('write_board', { type: 'tribe', id })      → org or that tribe (legacy_tribe_id)
//
// If capabilities have not been loaded (e.g. anon, ghost, or pre-bootstrap),
// returns false (fail-closed). Superadmin bypasses everything by design.
export function canFor(action: string, scope?: CanForScope): boolean {
  const caps = getCapabilities();
  if (!caps) return false;
  if (caps.is_superadmin) return true;
  if (caps.org_actions?.includes(action)) return true;
  if (!scope) return false;
  if (scope.type === 'initiative') {
    return caps.initiative_actions?.[scope.id]?.includes(action) ?? false;
  }
  // tribe scope: id can be number or string; key is text
  const key = String(scope.id);
  return caps.tribe_actions?.[key]?.includes(action) ?? false;
}

// canForAnyTribe — true if the action holds in ANY tribe scope (not just one).
// Used by gates that don't have a specific tribe context but want "is this
// person a tribe-scoped leader anywhere?" semantics. Org-scoped actions still
// short-circuit to true.
export function canForAnyTribe(action: string): boolean {
  const caps = getCapabilities();
  if (!caps) return false;
  if (caps.is_superadmin) return true;
  if (caps.org_actions?.includes(action)) return true;
  for (const acts of Object.values(caps.tribe_actions || {})) {
    if (acts.includes(action)) return true;
  }
  for (const acts of Object.values(caps.initiative_actions || {})) {
    if (acts.includes(action)) return true;
  }
  return false;
}

// Set of org-scoped V4 actions that legitimately indicate admin-tier authority
// (engagement-derived). Source: engagement_kind_permissions WHERE scope IN
// ('organization','global'). Verdade institucional:
//   - volunteer.{manager,deputy_manager,co_gp,leader,comms_leader} têm `write` org
//   - sponsor.sponsor → manage_finance / manage_partner / view_internal_analytics
//   - chapter_board.{liaison,board_member} → view_chapter_dashboards / view_pii / view_internal_analytics
//   - observer.{curator,reviewer} → participate_in_governance_review (não dá admin entry isolado)
// Nota: 'participate_in_governance_review' propositalmente NÃO inclusa — observer.curator/reviewer
// puros não devem ganhar admin entry, apenas governance review pages (gate separado).
export const ADMIN_TIER_ACTIONS = [
  'write',
  'manage_event',
  'manage_member',
  'manage_partner',
  'manage_finance',
  'manage_comms',
  'manage_board_admin',
  'manage_platform',
  'view_internal_analytics',
  'view_chapter_dashboards',
] as const;

// canForAdminEntry — true if the caller has any ENGAGEMENT-DERIVED org-scoped
// action that historically conveys admin-tier authority. Used as the V4
// substitute for V3 patterns like:
//   ['manager','deputy_manager','tribe_leader','comms_leader','sponsor','chapter_liaison']
//     .includes(member.operational_role)
//
// Designation-based admin grants (curator, deputy_manager designation,
// chapter_board) remain checked separately in the call site — designations are
// institutionally assigned and not engagement-derived.
//
// Background: docs/audit/P163_A3_BACKFILL_DECISION_AUDIT.md.
export function canForAdminEntry(): boolean {
  const caps = getCapabilities();
  if (!caps) return false;
  if (caps.is_superadmin) return true;
  return ADMIN_TIER_ACTIONS.some(a => caps.org_actions.includes(a));
}

export function hasPermission(
  member: MemberForPermission,
  permission: Permission
): boolean {
  // ── Simulation mode: use simulated tier permissions ──
  if (_simulation.active && _simulation.tier) {
    const tierPerms = TIER_PERMISSIONS[_simulation.tier] || [];
    const desigPerms = _simulation.designations
      .flatMap(d => DESIGNATION_PERMISSIONS[d as Designation] || []);
    return [...tierPerms, ...desigPerms].includes(permission);
  }

  // ── Real mode ──
  if (!member) return false;
  if (member.is_superadmin) return true;

  const tier = member.operational_role as OperationalTier;
  const tierPerms = TIER_PERMISSIONS[tier] || [];
  const desigPerms = (member.designations || [])
    .flatMap(d => DESIGNATION_PERMISSIONS[d as Designation] || []);

  return [...tierPerms, ...desigPerms].includes(permission);
}

// Convenience: get effective tribe_id (real or simulated)
export function getEffectiveTribeId(member: MemberForPermission): number | null {
  if (_simulation.active && _simulation.tribe_id !== null) {
    return _simulation.tribe_id;
  }
  return member.tribe_id ?? null;
}

// Convenience: get effective initiative_id (real or simulated)
export function getEffectiveInitiativeId(member: MemberForPermission): string | null {
  if (_simulation.active && _simulation.initiative_id) {
    return _simulation.initiative_id;
  }
  return member.initiative_id ?? null;
}

// TRIBE DASHBOARD PERMISSIONS: moved to src/lib/tribePermissions.ts
// Import from there directly to avoid bundler conflicts between
// Astro inline scripts and React islands.

// Get all permissions for display/audit
export function getEffectivePermissions(member: MemberForPermission): Permission[] {
  if (_simulation.active && _simulation.tier) {
    const tierPerms = TIER_PERMISSIONS[_simulation.tier] || [];
    const desigPerms = _simulation.designations
      .flatMap(d => DESIGNATION_PERMISSIONS[d as Designation] || []);
    return [...new Set([...tierPerms, ...desigPerms])];
  }

  if (!member) return [];
  if (member.is_superadmin) {
    return [...new Set(Object.values(TIER_PERMISSIONS).flat())];
  }

  const tier = member.operational_role as OperationalTier;
  const tierPerms = TIER_PERMISSIONS[tier] || [];
  const desigPerms = (member.designations || [])
    .flatMap(d => DESIGNATION_PERMISSIONS[d as Designation] || []);
  return [...new Set([...tierPerms, ...desigPerms])];
}
