import { resolveTribes } from '../../data/tribes';
import type { Lang } from '../../i18n/utils';

const QUADRANT_COLORS: Record<number, string> = {
  1: '#00799E',
  2: '#FF610F',
  3: '#4F17A8',
  4: '#10B981',
};

const STATIC_TRIBE_COLORS: Record<number, string> = {
  1: '#00799E',
  2: '#00799E',
  3: '#FF610F',
  4: '#FF610F',
  5: '#4F17A8',
  6: '#4F17A8',
  7: '#10B981',
  8: '#10B981',
};

export function getQuadrantColor(quadrant?: number | null): string {
  return QUADRANT_COLORS[Number(quadrant) || 0] || '#94A3B8';
}

export function getTribeColor(tribeOrId: number | { id?: number | null; quadrant?: number | null } | null | undefined): string {
  if (typeof tribeOrId === 'number') {
    return STATIC_TRIBE_COLORS[tribeOrId] || '#94A3B8';
  }
  if (!tribeOrId) return '#94A3B8';
  if (tribeOrId.id && STATIC_TRIBE_COLORS[tribeOrId.id]) return STATIC_TRIBE_COLORS[tribeOrId.id];
  return getQuadrantColor(tribeOrId.quadrant);
}

export function getStaticTribeFallback(tribeId: number, lang: Lang) {
  return resolveTribes(lang).find((tribe) => tribe.id === tribeId) || null;
}

export function buildTribeLabel(
  tribeOrId: number | { id?: number | null; name?: string | null },
  options?: { prefix?: string; fallbackNames?: Record<number, string> }
): string {
  const prefix = options?.prefix || 'Tribo';
  const fallbackNames = options?.fallbackNames || {};
  if (typeof tribeOrId === 'number') {
    return fallbackNames[tribeOrId] || `${prefix} ${tribeOrId}`;
  }
  const id = Number(tribeOrId?.id || 0);
  if (tribeOrId?.name && String(tribeOrId.name).trim()) return String(tribeOrId.name).trim();
  if (id > 0) return fallbackNames[id] || `${prefix} ${id}`;
  return prefix;
}

export function isRuntimeTribeActive(tribe: any): boolean {
  return tribe?.is_active !== false;
}
