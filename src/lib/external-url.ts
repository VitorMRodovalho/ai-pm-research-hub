/**
 * Normalize a user-entered external profile URL (e.g. members.linkedin_url) for use in an href.
 *
 * Profile URLs are typed by people and some are stored without a scheme
 * ("www.linkedin.com/in/..."). As an href, that is RELATIVE: on /es/ it resolves to
 * /es/www.linkedin.com/in/... and 404s. This prefixes https:// when the value is not already an
 * absolute http(s) URL. Display-time only: the stored value is not changed.
 *
 * - empty / whitespace-only -> '' (callers already skip the link when falsy)
 * - http:// or https:// -> returned as-is (trimmed)
 * - protocol-relative ("//host/...") -> 'https:' + value
 * - anything else -> 'https://' + value. A host with a port ("www.x.com:443/...") is not
 *   mistaken for a scheme, and a non-http scheme cannot become an active link.
 */
export function withScheme(url: string | null | undefined): string {
  const v = (url ?? '').trim();
  if (!v) return '';
  if (/^https?:\/\//i.test(v)) return v;
  if (v.startsWith('//')) return `https:${v}`;
  return `https://${v}`;
}
