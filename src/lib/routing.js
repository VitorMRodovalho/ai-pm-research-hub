/**
 * @typedef {{ operational_role?: string | null, role?: string | null }} MemberLike
 */

/**
 * @param {MemberLike | null | undefined} member
 * @returns {string}
 */
export function getMemberRole(member) {
  if (!member) return 'guest';
  return member.operational_role || 'guest';
}

/**
 * @param {MemberLike | null | undefined} member
 * @returns {boolean}
 */
export function shouldRedirectFromProfile(member) {
  return getMemberRole(member) === 'guest';
}

/**
 * @param {string} currentPath
 * @param {string} prefix
 * @returns {string}
 */
export function buildLanguageHref(currentPath, prefix) {
  const normalizedPath = currentPath?.startsWith('/') ? currentPath : `/${currentPath || ''}`;
  const basePath = normalizedPath.replace(/^\/(en|es)(?=\/|$)/, '') || '/';

  if (basePath === '/') {
    return prefix ? `/${prefix}/` : '/';
  }
  return prefix ? `/${prefix}${basePath}` : basePath;
}
