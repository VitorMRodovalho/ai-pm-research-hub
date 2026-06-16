/**
 * @typedef {{ id?: string | null, operational_role?: string | null, role?: string | null }} MemberLike
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
 * Is this a registered member? A member record returned by `get_member_by_auth`
 * carries an `id`, which means the person IS registered — regardless of
 * `operational_role`. Pre-onboarding members carry `operational_role='guest'`,
 * so the role MUST NOT be used as a "not a member" proxy: they need /profile to
 * complete consent, Credly, alternate emails, name fixes and the volunteer-term
 * signature BEFORE being promoted out of the guest role. The genuine
 * authenticated-but-no-member case yields a null member (handled separately via
 * the WS-B account-claim flow).
 * @param {MemberLike | null | undefined} member
 * @returns {boolean}
 */
export function isRegisteredMember(member) {
  return !!(member && member.id);
}

/**
 * @param {MemberLike | null | undefined} member
 * @returns {boolean}
 */
export function shouldRedirectFromProfile(member) {
  return !isRegisteredMember(member);
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
