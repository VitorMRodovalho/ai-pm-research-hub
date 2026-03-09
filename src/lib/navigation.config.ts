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
  minTier: AccessTier;
  allowedDesignations?: string[];
  requiresAuth: boolean;
  section: 'main' | 'drawer' | 'both';
  group?: string;
  badge?: 'crimson' | 'purple' | 'teal';
  dynamic?: boolean;
  resolver?: string;
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
  { key: 'agenda',     labelKey: 'nav.agenda',     href: '/#agenda',     minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'quadrants',  labelKey: 'nav.quadrants',  href: '/#quadrants',  minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'tribes',     labelKey: 'nav.tribes',     href: '/#tribes',     minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'kpis',       labelKey: 'nav.kpis',       href: '/#kpis',       minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'networking', labelKey: 'nav.networking',  href: '/#breakout',   minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'rules',      labelKey: 'nav.rules',      href: '/#rules',      minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'trail',      labelKey: 'nav.trail',      href: '/#trail',      minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'team',       labelKey: 'nav.team',       href: '/#team',       minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'vision',     labelKey: 'nav.vision',     href: '/#vision',     minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },
  { key: 'resources',  labelKey: 'nav.resources',  href: '/#resources',  minTier: 'visitor', requiresAuth: false, section: 'main', group: 'home-anchors' },

  // ─── Tool pages (public) ───
  { key: 'workspace',    labelKey: 'nav.workspace',    href: '/workspace',    minTier: 'visitor', requiresAuth: false, section: 'main', group: 'tools' },
  { key: 'onboarding',   labelKey: 'nav.onboarding',   href: '/onboarding',   minTier: 'visitor', requiresAuth: false, section: 'main', group: 'tools' },
  { key: 'artifacts',    labelKey: 'nav.artifacts',     href: '/artifacts',    minTier: 'visitor', requiresAuth: false, section: 'main', group: 'tools' },
  { key: 'gamification', labelKey: 'nav.gamification',  href: '/gamification', minTier: 'visitor', requiresAuth: false, section: 'main', group: 'tools' },

  // ─── Authenticated pages ───
  { key: 'attendance', labelKey: 'nav.attendance',  href: '/attendance', minTier: 'member', requiresAuth: true, section: 'both', group: 'member', badge: 'crimson' },
  { key: 'my-tribe',   labelKey: 'nav.myTribe',    href: '/tribe/',     minTier: 'member', requiresAuth: true, section: 'both', group: 'member', badge: 'teal', dynamic: true, resolver: 'resolveMyTribeHref' },

  // ─── Profile drawer only ───
  { key: 'profile', labelKey: 'nav.profile', href: '/profile', minTier: 'member', requiresAuth: true, section: 'drawer', group: 'profile' },

  // ─── Admin area ───
  { key: 'admin',           labelKey: 'nav.admin',          href: '/admin',           minTier: 'observer', requiresAuth: true, section: 'both',   group: 'admin', badge: 'purple' },
  { key: 'admin-analytics', labelKey: 'nav.adminAnalytics', href: '/admin/analytics', minTier: 'admin',    requiresAuth: true, section: 'drawer', group: 'admin-sub' },
  { key: 'admin-comms',     labelKey: 'nav.adminComms',     href: '/admin/comms',     minTier: 'admin',    requiresAuth: true, section: 'drawer', group: 'admin-sub', allowedDesignations: ['comms_leader', 'comms_member'] },
];

export function isItemVisible(item: NavItem, tier: AccessTier, designations: string[], isLoggedIn: boolean): boolean {
  if (item.requiresAuth && !isLoggedIn) return false;
  const meetsMinTier = TIER_RANK[tier] >= TIER_RANK[item.minTier];
  if (item.allowedDesignations?.length) {
    const hasDesig = item.allowedDesignations.some(d => designations.includes(d));
    return meetsMinTier || hasDesig;
  }
  return meetsMinTier;
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
