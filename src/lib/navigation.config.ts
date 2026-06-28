/**
 * ═══════════════════════════════════════════════════════════════════════════
 * GOVERNANÇA: A atualização da árvore de navegação neste arquivo é
 * Critério de Aceite obrigatório para qualquer nova feature ou página.
 *
 * Este arquivo é a FONTE ÚNICA DE VERDADE para a estrutura de menus.
 * Os componentes de UI (Nav.astro, Profile Drawer) leem daqui e renderizam
 * dinamicamente. Nenhuma regra de acesso deve ser hardcoded nos componentes.
 *
 * Preparado para futura feature: Superadmin poderá editar permissões via
 * frontend (merge DB override + defaults deste arquivo).
 * ═══════════════════════════════════════════════════════════════════════════
 */
import type { AccessTier } from './admin/constants';

export interface NavItem {
  key: string;
  labelKey: string;
  href: string;
  disabled?: boolean;
  minTier: AccessTier;
  allowedDesignations?: string[];
  allowedOperationalRoles?: string[];
  requiresAuth: boolean;
  section: 'main' | 'drawer' | 'both';
  group?: string;
  badge?: 'crimson' | 'purple' | 'teal';
  drawerSection?: 'meu-espaco' | 'minha-tribo' | 'producao' | 'explorar' | 'admin';
  navSlot?: 'home-sections-dropdown' | 'primary' | 'none';
  dynamic?: boolean;
  resolver?: string;
  lgpdSensitive?: boolean;
}

export interface ItemAccessibility {
  visible: boolean;
  enabled: boolean;
  requiredTier: AccessTier;
}

export const TIER_RANK: Record<AccessTier, number> = {
  visitor: 0,
  member: 1,
  observer: 2,
  leader: 3,
  admin: 4,
  superadmin: 5,
};

export const NAV_ITEMS: NavItem[] = [
  // ─── Home anchor links (always visible) ───
  // Polish C4 (Ciclo 4, 2026-06-21): menu curado ao funil anon, em ORDEM de página (PD-NAV).
  // Removidos: #quadrants (âncora interna redundante de #verticals), #breakout/networking (seção
  // não renderizada na home = link morto), #resources (zona de membro, fim da home). Adicionados:
  // #platform-stats, #capitulos, #join, #agenda. #trail usa ladder.label ("A escada"), não nav.trail.
  { key: 'verticals',      labelKey: 'nav.verticals',     href: '/#verticals',      minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },
  { key: 'platform-stats', labelKey: 'nav.platformStats', href: '/#platform-stats', minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },
  { key: 'trail',          labelKey: 'ladder.label',      href: '/#trail',          minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },
  { key: 'chapters',       labelKey: 'nav.chapters',      href: '/#capitulos',      minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },
  { key: 'join',           labelKey: 'nav.join',          href: '/#join',           minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },
  { key: 'partners',       labelKey: 'nav.partners',      href: '/#partners',       minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },
  { key: 'agenda',         labelKey: 'nav.agenda',        href: '/#agenda',         minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },
  { key: 'team',           labelKey: 'nav.team',          href: '/#team',           minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors', navSlot: 'home-sections-dropdown' },

  // ─── Workspace ───
  { key: 'workspace', labelKey: 'nav.workspace', href: '/workspace', minTier: 'visitor', requiresAuth: true, section: 'both', group: 'member', navSlot: 'primary', drawerSection: 'meu-espaco' }, // #867 pre-term journey — guest-reachable (page self-gates own data; RLS/SECDEF is the boundary, not nav)

  // ─── Tool pages (public) ───
  { key: 'library',      labelKey: 'nav.library',      href: '/library',      minTier: 'visitor', requiresAuth: false, section: 'both', group: 'tools', navSlot: 'none', drawerSection: 'explorar' },
  { key: 'onboarding',   labelKey: 'nav.onboarding',   href: '/workspace',   minTier: 'visitor', requiresAuth: true,  section: 'main', group: 'profile', navSlot: 'none' }, // #867 pre-term journey — guest-reachable
  { key: 'gamification', labelKey: 'nav.gamification',  href: '/gamification', minTier: 'visitor', requiresAuth: false, section: 'both', group: 'tools', navSlot: 'none', drawerSection: 'explorar' },
  // #701 Agenda Viva — public General Meetings agenda (anon-OK; reservation gated in-page).
  { key: 'reunioes-gerais', labelKey: 'nav.reunioesGerais', href: '/reunioes-gerais', minTier: 'visitor', requiresAuth: false, section: 'both', group: 'tools', navSlot: 'none', drawerSection: 'explorar' },
  { key: 'presentations', labelKey: 'nav.presentations', href: '/presentations', minTier: 'member', requiresAuth: true, section: 'main', group: 'tools', navSlot: 'none' },

  // ─── Authenticated pages ───
  { key: 'attendance', labelKey: 'nav.attendance',  href: '/attendance', minTier: 'member', requiresAuth: true, section: 'both', group: 'member', badge: 'crimson', drawerSection: 'meu-espaco', navSlot: 'primary' },
  { key: 'meetings',   labelKey: 'nav.meetings',   href: '/meetings',   minTier: 'member', requiresAuth: true, section: 'both', group: 'member', drawerSection: 'minha-tribo', navSlot: 'none' },
  { key: 'my-initiatives', labelKey: 'nav.myInitiatives', href: '/initiatives', minTier: 'member', requiresAuth: true, section: 'both', group: 'member', drawerSection: 'meu-espaco', navSlot: 'none' },
  { key: 'my-tribe',   labelKey: 'nav.myTribe',    href: '/tribe/',     minTier: 'member', requiresAuth: true, section: 'both', group: 'member', badge: 'teal', drawerSection: 'minha-tribo', navSlot: 'primary', dynamic: true, resolver: 'resolveMyTribeHref' },
  { key: 'webinars',   labelKey: 'nav.adminWebinars', href: '/webinars', minTier: 'leader', requiresAuth: true, section: 'main', group: 'subprojects', navSlot: 'none', allowedDesignations: ['comms_leader', 'comms_member', 'curator', 'co_gp'], allowedOperationalRoles: ['facilitator'] },
  { key: 'publications', labelKey: 'nav.publications', href: '/publications', minTier: 'leader', requiresAuth: true, section: 'both', group: 'subprojects', drawerSection: 'producao', navSlot: 'none', allowedDesignations: ['curator', 'co_gp', 'comms_leader', 'comms_member'], allowedOperationalRoles: ['communicator'] },
  { key: 'board-comms',    labelKey: 'nav.boardComms',      href: '/initiative/9ea82b09-55c6-4cc3-ab7f-178518d0ab47', minTier: 'member', requiresAuth: true, section: 'drawer', group: 'subprojects', drawerSection: 'producao', allowedDesignations: ['comms_leader', 'comms_member', 'curator', 'co_gp'] },
  { key: 'board-publications', labelKey: 'nav.boardPublications', href: '/initiative/e885525e-a0f1-4e16-813c-497047209047', minTier: 'member', requiresAuth: true, section: 'drawer', group: 'subprojects', drawerSection: 'producao', allowedDesignations: ['comms_leader', 'comms_member', 'curator', 'co_gp'] },
  { key: 'ia-pilots',    labelKey: 'nav.projects',     href: '/projects',      minTier: 'visitor', requiresAuth: false, section: 'main', group: 'subprojects', navSlot: 'none' },
  { key: 'blog',         labelKey: 'nav.blog',         href: '/blog',          minTier: 'visitor', requiresAuth: false, section: 'main',   group: 'tools', navSlot: 'primary' },

  // ─── Profile drawer only ───
  { key: 'profile', labelKey: 'nav.profile', href: '/profile', minTier: 'visitor', requiresAuth: true, section: 'drawer', group: 'profile', drawerSection: 'meu-espaco' }, // #867 pre-term journey — guest-reachable (profile.astro self-gates via isRegisteredMember; own-row SECDEF)

  // ─── Admin area ───
  { key: 'admin',           labelKey: 'nav.admin',          href: '/admin',           minTier: 'observer', requiresAuth: true, section: 'both',   group: 'admin', badge: 'purple', drawerSection: 'admin', navSlot: 'primary' },
  { key: 'admin-analytics', labelKey: 'nav.adminAnalytics', href: '/admin/analytics', minTier: 'admin',    requiresAuth: true, section: 'drawer', group: 'admin-sub', drawerSection: 'admin', allowedDesignations: ['sponsor', 'chapter_liaison', 'curator', 'chapter_board'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-comms',     labelKey: 'nav.adminComms',     href: '/admin/comms',     minTier: 'admin',    requiresAuth: true, section: 'drawer', group: 'admin-sub', drawerSection: 'admin', allowedDesignations: ['comms_leader', 'comms_member', 'sponsor'], lgpdSensitive: true },
  { key: 'admin-comms-ops', labelKey: 'nav.adminCommsOps',  href: '/admin/comms-ops', minTier: 'admin',    requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['comms_leader', 'comms_member', 'sponsor'], lgpdSensitive: true },
  { key: 'stakeholder-dashboard', labelKey: 'nav.stakeholder', href: '/stakeholder', minTier: 'member', requiresAuth: true, section: 'drawer', group: 'profile', drawerSection: 'meu-espaco', navSlot: 'none', allowedDesignations: ['sponsor', 'chapter_liaison', 'chapter_board'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-portfolio', labelKey: 'nav.adminPortfolio', href: '/admin/portfolio', minTier: 'admin',    requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['sponsor', 'chapter_liaison', 'curator', 'chapter_board'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-cycle-report', labelKey: 'nav.adminCycleReport', href: '/report', minTier: 'admin', requiresAuth: true, section: 'drawer', group: 'admin-sub', drawerSection: 'admin', allowedDesignations: ['sponsor', 'chapter_liaison'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-exec-report', labelKey: 'nav.adminReport', href: '/admin/report', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['sponsor', 'chapter_liaison'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'boards', labelKey: 'nav.boards', href: '/boards', minTier: 'member', requiresAuth: true, section: 'both', group: 'member', drawerSection: 'meu-espaco', navSlot: 'primary' },
  { key: 'governance', labelKey: 'nav.governance', href: '/governance', minTier: 'visitor', requiresAuth: false, section: 'both', group: 'tools', drawerSection: 'explorar', navSlot: 'none' },
  { key: 'cpmai',      labelKey: 'nav.cpmai',      href: '/cpmai',      minTier: 'visitor', requiresAuth: false, section: 'drawer', group: 'tools', drawerSection: 'explorar', navSlot: 'none' },
  { key: 'docs-mcp',   labelKey: 'nav.docsMcp',    href: '/docs/mcp',   minTier: 'visitor', requiresAuth: false, section: 'drawer', group: 'tools', drawerSection: 'explorar', navSlot: 'none' },
  { key: 'admin-governance-v2', labelKey: 'nav.adminBoardGovernance', href: '/admin/governance-v2', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['curator', 'co_gp', 'sponsor'] },
  { key: 'admin-curatorship', labelKey: 'nav.adminCuratorship', href: '/admin/curatorship', minTier: 'observer', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none' },
  // #701 Agenda Viva coordination — manage_event holders (org-scope: manager/deputy_manager/co_gp/comms_leader). UX gate only; reorder/confirm/revoke RPCs are the real boundary.
  { key: 'admin-agenda-viva', labelKey: 'nav.adminAgendaViva', href: '/admin/agenda-viva', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['deputy_manager', 'co_gp', 'comms_leader', 'sponsor'], allowedOperationalRoles: ['manager'] },
  { key: 'admin-partnerships', labelKey: 'nav.adminPartnerships', href: '/admin/partnerships', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['sponsor', 'chapter_liaison'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-chapter-report', labelKey: 'nav.adminChapterReport', href: '/admin/chapter-report', minTier: 'observer', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['sponsor', 'chapter_liaison'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-sustainability', labelKey: 'nav.adminSustainability', href: '/admin/sustainability', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['sponsor', 'chapter_liaison', 'curator'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-cross-tribes', labelKey: 'nav.adminCrossTribes', href: '/admin/tribes', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['sponsor'] },
  { key: 'admin-tribe-dashboard', labelKey: 'nav.adminTribeDashboard', href: '/admin/tribe/', minTier: 'leader', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', dynamic: true, resolver: 'resolveMyTribeDashboard', allowedDesignations: ['sponsor', 'chapter_liaison'], allowedOperationalRoles: ['chapter_liaison'] },
  { key: 'admin-selection', labelKey: 'nav.adminSelection', href: '/admin/selection', minTier: 'admin', requiresAuth: true, section: 'drawer', group: 'admin-sub', drawerSection: 'admin', allowedDesignations: ['sponsor'], lgpdSensitive: true }, // sponsor = host/chapter president full read (Wave 1 — Ivan/LIM; RPC data already gated view_chapter_dashboards which sponsor holds)
  { key: 'admin-vep-reconciliation', labelKey: 'nav.adminVepReconciliation', href: '/admin/vep-reconciliation', minTier: 'admin', requiresAuth: true, section: 'drawer', group: 'admin-sub', drawerSection: 'admin', allowedDesignations: ['sponsor'] },
  { key: 'admin-campaigns', labelKey: 'nav.adminCampaigns', href: '/admin/campaigns', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['comms_team'] },
  { key: 'admin-blog', labelKey: 'nav.adminBlog', href: '/admin/blog', minTier: 'admin', requiresAuth: true, section: 'main', group: 'admin-sub', navSlot: 'none', allowedDesignations: ['comms_team'] },
  { key: 'admin-settings',  labelKey: 'nav.adminSettings',  href: '/admin/settings', minTier: 'superadmin', requiresAuth: true, section: 'drawer', group: 'admin-sub', drawerSection: 'admin' },
  { key: 'notifications',   labelKey: 'nav.notifications', href: '/notifications',  minTier: 'member',   requiresAuth: true, section: 'main', group: 'member', navSlot: 'none' },
  { key: 'help',            labelKey: 'nav.adminHelp',     href: '/help',           minTier: 'visitor',  requiresAuth: false, section: 'both', group: 'member', navSlot: 'none', drawerSection: 'meu-espaco' },

  // ─── Drawer-only secondary links (R4) ───
  { key: 'certificates',        labelKey: 'nav.certificates',  href: '/certificates',        minTier: 'visitor', requiresAuth: true,  section: 'drawer', group: 'profile', drawerSection: 'meu-espaco' }, // #867 pre-term journey — guest-reachable (own-scope SECDEF)
  { key: 'volunteer-agreement', labelKey: 'nav.volunteer',     href: '/volunteer-agreement', minTier: 'visitor', requiresAuth: true,  section: 'drawer', group: 'profile', drawerSection: 'meu-espaco' }, // #867 pre-term journey — guest-reachable (signing surface; term body gated in-page)
  { key: 'changelog',           labelKey: 'nav.changelog',     href: '/changelog',           minTier: 'visitor', requiresAuth: false, section: 'drawer', group: 'tools',   drawerSection: 'explorar' },
  { key: 'my-pending',          labelKey: 'nav.myPending',     href: '/governance/my-pending', minTier: 'member', requiresAuth: true,  section: 'drawer', group: 'profile', drawerSection: 'meu-espaco' },
];

export function getItemAccessibility(
  item: NavItem,
  tier: AccessTier,
  designations: string[],
  isLoggedIn: boolean,
  operationalRole?: string
): ItemAccessibility {
  if (item.requiresAuth && !isLoggedIn) {
    return { visible: false, enabled: false, requiredTier: item.minTier };
  }

  const meetsMinTier = TIER_RANK[tier] >= TIER_RANK[item.minTier];
  const hasDesig = item.allowedDesignations?.length
    ? item.allowedDesignations.some(d => designations.includes(d))
    : false;
  const hasOperationalRole = item.allowedOperationalRoles?.length
    ? item.allowedOperationalRoles.includes(operationalRole || '')
    : false;
  const enabled = meetsMinTier || hasDesig || hasOperationalRole;

  if (item.lgpdSensitive && !enabled) {
    return { visible: false, enabled: false, requiredTier: item.minTier };
  }

  if (isLoggedIn && item.requiresAuth) {
    return { visible: true, enabled, requiredTier: item.minTier };
  }

  return { visible: enabled, enabled, requiredTier: item.minTier };
}

export function isItemVisible(item: NavItem, tier: AccessTier, designations: string[], isLoggedIn: boolean): boolean {
  return getItemAccessibility(item, tier, designations, isLoggedIn).visible;
}

export function getVisibleItems(
  section: NavItem['section'] | 'all',
  tier: AccessTier,
  designations: string[],
  isLoggedIn: boolean
): NavItem[] {
  return NAV_ITEMS.filter(item => {
    if (section !== 'all' && item.section !== section && item.section !== 'both') return false;
    return isItemVisible(item, tier, designations, isLoggedIn);
  });
}

export function getItemsByGroup(items: NavItem[], group: string): NavItem[] {
  return items.filter(i => i.group === group);
}

export function getItemsByDrawerSection(items: NavItem[], section: NavItem['drawerSection']): NavItem[] {
  return items.filter(i => i.drawerSection === section);
}
