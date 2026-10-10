/**
 * #2658 — data e hora dos instrumentos exportados (PDF oficial, rascunho, DOCX).
 *
 * Antes cada exportação chamava toLocale*String sem timeZone, então a hora saía no fuso
 * do navegador de quem GERAVA o arquivo, sem rótulo: o mesmo documento mostrava horas
 * diferentes conforme quem o baixava. O fuso é fixo e declarado no próprio texto.
 */
export const BRASILIA_TIME_ZONE = 'America/Sao_Paulo';
export const BRASILIA_LABEL = 'horário de Brasília';

export function fmtBrasilia(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  const text = d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRASILIA_TIME_ZONE,
  });
  return `${text} (${BRASILIA_LABEL})`;
}
