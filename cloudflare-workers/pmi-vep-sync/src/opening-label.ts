/**
 * #2847 — the label the welcome email gives the opening ({{role_label}}).
 *
 * The VEP title carries the Núcleo suffix (" - Núcleo IA & GP - 2026/27",
 * " - Núcleo de Estudo e Pesquisa de IA - PMI GO 2026"); the part before it names the
 * role. A title without that suffix is used whole. Without a title, the label falls back
 * to the fixed map by role_applied, which is all the email had before #2847.
 *
 * No imports on purpose: tests/contracts imports this file directly and runs it.
 */

export const ROLE_LABEL: Record<string, string> = {
  leader: 'Líder de Tribo',
  researcher: 'Pesquisador',
  manager: 'Gerente de Projeto',
  both: 'Pesquisador / Líder',
};

export function openingLabel(title: string | null | undefined, roleApplied: string): string {
  const t = (title ?? '').trim();
  if (!t) return ROLE_LABEL[roleApplied] ?? roleApplied;
  const cut = t.search(/\s+-\s+Núcleo\b/);
  return cut > 0 ? t.slice(0, cut).trim() : t;
}
