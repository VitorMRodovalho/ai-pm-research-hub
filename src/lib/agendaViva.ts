// #2783: regras puras da Agenda Viva pública (AgendaVivaPublic), testáveis sem navegador.

/** slug do formato → rótulo por língua (agenda_block_formats.label_i18n, chaves 'pt-BR' | 'en-US' | 'es-LATAM'). */
export type FormatCatalog = Record<string, Record<string, string>>;

/**
 * O rótulo de um formato de bloco. O catálogo do banco manda; enquanto ele não chegou (ou se a leitura falhou),
 * vale o dicionário (comp.agendaViva.format.<slug>), e o código cru só aparece para formato que nenhum dos dois
 * conhece. Antes o código cru era o que aparecia sempre que o catálogo não tinha carregado.
 */
export function resolveFormatLabel(
  slug: string,
  lang: string,
  catalog: FormatCatalog,
  dictionary: (key: string) => string | null,
): string {
  return catalog[slug]?.[lang] || dictionary(`comp.agendaViva.format.${slug}`) || catalog[slug]?.['pt-BR'] || slug;
}

/** Só link https do YouTube vira botão de gravação: a coluna é texto livre. */
export function safeRecordingUrl(raw: unknown): string | null {
  if (typeof raw !== 'string' || !raw.trim()) return null;
  try {
    const url = new URL(raw.trim());
    const host = url.hostname.replace(/^www\./, '').replace(/^m\./, '');
    if (url.protocol !== 'https:') return null;
    return host === 'youtu.be' || host === 'youtube.com' ? url.href : null;
  } catch {
    return null;
  }
}
