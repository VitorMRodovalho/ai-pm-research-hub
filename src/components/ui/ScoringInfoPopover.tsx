import { useEffect, useState } from 'react';
import InfoPopover from './InfoPopover';
import {
  localizeI18n, ruleXpRange, rulesByPillar,
  type GamificationCatalog,
} from '../../lib/gamification-catalog';

// #1087 wave 2 (G1) — the scoring table derives 100% from the live rules
// catalog (get_gamification_rules_catalog). The page-level script fetches the
// catalog once after the member session is confirmed and exposes it via
// window.__GAM_CATALOG + the 'gam:catalog' event; this island only renders it.

interface Props {
  lang: string;
  i18n: {
    title: string;
    goal: string;
    loading: string;
    onTimeBonus: string;      // '+{n} no prazo'
    perCriterion: string;     // '+{n} por critério'
    pillars: Record<string, string>;
  };
}

const PILLAR_EMOJI: Record<string, string> = {
  presenca: '📅', trilha: '🧭', certificacoes: '🏅', producao: '🏗️',
  curadoria: '📚', champions: '🏆', protagonismo: '🎤',
};

export default function ScoringInfoPopover({ lang, i18n }: Props) {
  const [catalog, setCatalog] = useState<GamificationCatalog | null>(
    () => (typeof window !== 'undefined' ? (window as any).__GAM_CATALOG || null : null),
  );

  useEffect(() => {
    if (catalog) return;
    const onCatalog = (e: Event) => setCatalog((e as CustomEvent).detail);
    window.addEventListener('gam:catalog', onCatalog);
    return () => window.removeEventListener('gam:catalog', onCatalog);
  }, [catalog]);

  const groups = catalog ? rulesByPillar(catalog) : [];

  return (
    <InfoPopover title={i18n.title}>
      <div className="max-h-[420px] overflow-y-auto pr-1">
        {!catalog && (
          <p className="text-[11px] text-[var(--text-muted)] py-2 text-center">{i18n.loading}</p>
        )}
        {groups.map(({ pillar, rules }) => (
          <div key={pillar} className="mb-2 last:mb-0">
            <div className="text-[10px] font-bold uppercase tracking-wide text-[var(--text-muted)] pt-1.5 pb-0.5">
              {PILLAR_EMOJI[pillar] || '⭐'} {i18n.pillars[pillar] || pillar}
            </div>
            {rules.map((r) => {
              const notes: string[] = [];
              if ((r.on_time_bonus_points ?? 0) > 0) {
                notes.push(i18n.onTimeBonus.replace('{n}', String(r.on_time_bonus_points)));
              }
              if ((r.bonus_per_criterion ?? 0) > 0) {
                notes.push(i18n.perCriterion.replace('{n}', String(r.bonus_per_criterion)));
              }
              const desc = localizeI18n(r.description_i18n, lang);
              return (
                <div key={r.slug} className="flex items-center justify-between py-1.5 border-b border-[var(--border-subtle)] last:border-b-0">
                  <div className="min-w-0 pr-2">
                    <span className="font-semibold text-[var(--text-primary)] text-[12px]">
                      {localizeI18n(r.display_name_i18n, lang, r.slug)}
                    </span>
                    {(desc || notes.length > 0) && (
                      <div className="text-[11px] text-[var(--text-muted)]">
                        {desc}{desc && notes.length > 0 ? ' · ' : ''}{notes.join(' · ')}
                      </div>
                    )}
                  </div>
                  <span className="text-[11px] font-bold text-[var(--text-secondary)] whitespace-nowrap ml-2">
                    {ruleXpRange(r)} XP
                  </span>
                </div>
              );
            })}
          </div>
        ))}
      </div>
      <div className="mt-3 pt-2 border-t border-[var(--border-default)] text-[11px] text-[var(--text-muted)] font-medium">
        {i18n.goal}
      </div>
    </InfoPopover>
  );
}
