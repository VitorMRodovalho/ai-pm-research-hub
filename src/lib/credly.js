const USERNAME_RE = /^[A-Za-z0-9._-]{2,100}$/;

function stripInvisible(input) {
  return (input || '').replace(/[\u200B-\u200D\uFEFF]/g, '');
}

export function extractCredlyUsername(input) {
  const raw = stripInvisible(String(input || '')).trim();
  if (!raw) return null;

  if (USERNAME_RE.test(raw) && !raw.includes('/')) {
    return raw;
  }

  const withScheme = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
  try {
    const url = new URL(withScheme);
    const host = url.hostname.toLowerCase().replace(/^www\./, '');
    if (!host.endsWith('credly.com')) return null;

    const segments = url.pathname.split('/').filter(Boolean);
    const usersIdx = segments.findIndex((s) => s.toLowerCase() === 'users');
    if (usersIdx === -1 || !segments[usersIdx + 1]) return null;

    const username = decodeURIComponent(segments[usersIdx + 1]).trim();
    return USERNAME_RE.test(username) ? username : null;
  } catch {
    return null;
  }
}

export function isCredlyDomainUrl(input) {
  const raw = stripInvisible(String(input || '')).trim();
  if (!raw) return false;
  const withScheme = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
  try {
    const url = new URL(withScheme);
    const host = url.hostname.toLowerCase().replace(/^www\./, '');
    return host.endsWith('credly.com');
  } catch {
    return false;
  }
}

export function normalizeCredlyUrl(input) {
  const raw = stripInvisible(String(input || '')).trim();
  const username = extractCredlyUsername(input);
  if (username) return `https://www.credly.com/users/${username}`;
  if (!isCredlyDomainUrl(raw)) return null;

  // Accept only badge/earner links as-is; backend will attempt username resolution fallback.
  const withScheme = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
  try {
    const url = new URL(withScheme);
    const p = url.pathname.toLowerCase();
    const isSharePath = p.includes('/badges/') || p.includes('/badge/') || p.includes('/earner/');
    if (!isSharePath) return null;
    url.search = '';
    url.hash = '';
    return url.toString().replace(/\/$/, '');
  } catch {
    return null;
  }
}
