/**
 * #2840: corpo de notificação que é DADO, não texto. Os resumos (`management_daily_digest`, `weekly_member_digest`,
 * `weekly_tribe_digest_leader`) gravam em `body` o JSON que o e-mail consome, e /notifications imprimia esse JSON
 * cru. Aqui o corpo estruturado vira um resumo legível (o diário da gestão) ou nenhum corpo (os outros: o título e o
 * link já dizem o que é). Texto comum passa intacto, inclusive o que começa com chave e não é JSON.
 *
 * Devolve TEXTO, nunca marcação: quem imprime continua escapando.
 */

/** Objeto ou lista JSON; `undefined` quando o corpo é texto. */
function parseStructuredBody(text: string): Record<string, unknown> | unknown[] | undefined {
  const trimmed = text.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return undefined;
  try {
    const parsed = JSON.parse(trimmed);
    return parsed !== null && typeof parsed === 'object' ? parsed : undefined;
  } catch {
    return undefined;
  }
}

function countOf(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/**
 * @param managementDigestTemplate texto do dicionário com `{open}`, `{resolved}` e `{items}`.
 */
export function notificationBodyText(
  type: unknown,
  body: unknown,
  managementDigestTemplate: string,
): string | null {
  if (body === null || body === undefined) return null;
  const text = String(body);
  if (!text.trim()) return null;

  const parsed = parseStructuredBody(text);
  if (parsed === undefined) return text;

  if (type === 'management_daily_digest' && !Array.isArray(parsed)) {
    const items = Array.isArray(parsed.items) ? parsed.items.length : 0;
    return managementDigestTemplate
      .replace('{open}', String(countOf(parsed.open_count)))
      .replace('{resolved}', String(countOf(parsed.resolved_24h)))
      .replace('{items}', String(items)) || null;
  }
  return null;
}
