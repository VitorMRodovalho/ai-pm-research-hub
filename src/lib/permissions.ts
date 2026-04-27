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
    'admin.simulation',
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
    'admin.governance.view',
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
