import { QUADRANTS, type Quadrant } from './quadrants';
import { resolveTribes, type ResolvedTribe } from './tribes';
import { t, type Lang } from '../i18n/utils';

export interface ResolvedQuadrant {
  key: Quadrant['key'];
  color: string;
  cssVar: string;
  label: string;
  title: string;
  subtitle: string;
}

export interface TribesViewModel {
  quadrants: ResolvedQuadrant[];
  tribes: ResolvedTribe[];
  warnings: string[];
}

function hasText(value: unknown): boolean {
  return typeof value === 'string' && value.trim().length > 0;
}

export function buildTribesViewModel(lang: Lang): TribesViewModel {
  const warnings: string[] = [];

  const quadrants = QUADRANTS.map((q) => {
    const resolved: ResolvedQuadrant = {
      key: q.key,
      color: q.color,
      cssVar: q.cssVar,
      label: t(q.labelKey, lang),
      title: t(q.titleKey, lang),
      subtitle: t(q.subtitleKey, lang),
    };
    if (!hasText(resolved.label) || !hasText(resolved.title) || !hasText(resolved.subtitle)) {
      warnings.push(`Quadrant i18n missing for ${q.key}`);
    }
    return resolved;
  });

  const tribes = resolveTribes(lang).filter((tribe) => {
    const valid =
      hasText(tribe.name) &&
      hasText(tribe.description) &&
      Array.isArray(tribe.deliverables) &&
      tribe.deliverables.length > 0 &&
      hasText(tribe.meetingSchedule) &&
      hasText(tribe.videoUrl);
    if (!valid) warnings.push(`Tribe payload incomplete for T${String(tribe.id).padStart(2, '0')}`);
    return valid;
  });

  return { quadrants, tribes, warnings };
}
