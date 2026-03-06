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
