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

export function normalizeCredlyUrl(input) {
  const username = extractCredlyUsername(input);
  if (!username) return null;
  return `https://www.credly.com/users/${username}`;
}
