// ─── i18n utilities ───
// PT-BR = default (root /), EN = /en/, ES = /es/

import ptBR from './pt-BR';
import enUS from './en-US';
import esLATAM from './es-LATAM';

export type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';

export const LANGUAGES: { code: Lang; label: string; prefix: string; flag: string }[] = [
  { code: 'pt-BR',    label: 'Português',  prefix: '',   flag: '🇧🇷' },
  { code: 'en-US',    label: 'English',     prefix: 'en', flag: '🇺🇸' },
  { code: 'es-LATAM', label: 'Español',     prefix: 'es', flag: '🇪🇸' },
];

export const DEFAULT_LANG: Lang = 'pt-BR';

const dictionaries: Record<Lang, Record<string, string>> = {
  'pt-BR': ptBR,
  'en-US': enUS,
  'es-LATAM': esLATAM,
};

/**
 * Translate a key. Falls back to PT-BR, then returns the key itself.
 */
export function t(key: string, lang: Lang = DEFAULT_LANG): string {
  return dictionaries[lang]?.[key] ?? dictionaries['pt-BR']?.[key] ?? key;
}

/**
 * Get lang from URL prefix. '' = pt-BR, 'en' = en-US, 'es' = es-LATAM.
 */
export function getLangFromPrefix(prefix: string): Lang {
  const map: Record<string, Lang> = { '': 'pt-BR', 'en': 'en-US', 'es': 'es-LATAM' };
  return map[prefix] || DEFAULT_LANG;
}

/**
 * Get URL prefix from lang code.
 */
export function getPrefix(lang: Lang): string {
  return LANGUAGES.find(l => l.code === lang)?.prefix || '';
}

/**
 * Build a localized path. e.g. localePath('/attendance', 'en-US') → '/en/attendance'
 */
export function localePath(path: string, lang: Lang): string {
  const prefix = getPrefix(lang);
  if (!prefix) return path; // PT-BR = root
  return `/${prefix}${path}`;
}

/**
 * Get all language info for language switcher.
 */
export function getLanguageSwitcherLinks(currentPath: string, currentLang: Lang) {
  // Strip current lang prefix from path
  const prefix = getPrefix(currentLang);
  let basePath = currentPath;
  if (prefix && basePath.startsWith(`/${prefix}`)) {
    basePath = basePath.slice(prefix.length + 1) || '/';
  }

  return LANGUAGES.map(l => ({
    ...l,
    href: localePath(basePath, l.code),
    active: l.code === currentLang,
  }));
}

/**
 * Get localized role label. Uses 'role.<roleName>' translation keys.
 */
export function getRoleLabel(role: string, lang: Lang = DEFAULT_LANG): string {
  return t(`role.${role}`, lang);
}

/**
 * Get localized role labels map (for use in client-side JS).
 */
export function getRoleLabelsMap(lang: Lang = DEFAULT_LANG): Record<string, string> {
  const roles = [
    'manager', 'tribe_leader', 'researcher', 'ambassador',
    'curator', 'sponsor', 'founder', 'facilitator', 'communicator', 'guest'
  ];
  const map: Record<string, string> = {};
  for (const r of roles) {
    map[r] = t(`role.${r}`, lang);
  }
  return map;
}

/**
 * Detect lang from URL path (works for both index and internal pages).
 * e.g. '/en/attendance' → 'en-US', '/attendance' → 'pt-BR', '/es/' → 'es-LATAM'
 */
export function getLangFromURL(pathname: string): Lang {
  const segments = pathname.split('/').filter(Boolean);
  if (segments[0] === 'en') return 'en-US';
  if (segments[0] === 'es') return 'es-LATAM';
  return 'pt-BR';
}
