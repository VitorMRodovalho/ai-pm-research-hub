/**
 * Avatar resolution — ONE source of truth for "which image represents this member".
 *
 * #1205: the nav read `user.user_metadata.avatar_url` (the OAuth identity's picture) while the
 * profile card read `members.photo_url` (what the member uploads on the platform). A member who
 * uploads a photo therefore saw it on /profile and kept seeing initials in the nav next to their
 * role badge — reported as "minha foto não aparece". Worse, the nav's XSS allowlist only permitted
 * OAuth provider hosts, so even reading photo_url would have been rejected there.
 *
 * Order is deliberate: the photo the member uploaded HERE wins over whatever the identity provider
 * happens to carry, because that upload is the explicit act of choosing an avatar on this platform.
 */
import { getSupabasePublicUrl } from './supabase.ts';

/**
 * Hosts allowed to serve an avatar. `photo_url` is member-editable, so the allowlist stays: it is
 * what keeps a crafted value from becoming an arbitrary outbound request or a `javascript:` URL.
 */
const OAUTH_AVATAR_HOSTS = [
  'lh3.googleusercontent.com',
  'avatars.githubusercontent.com',
  'platform-lookaside.fbsbx.com',
  'media.licdn.com',
];

/**
 * Host of the project's own Storage, derived from the configured Supabase URL (never hardcoded —
 * see the no-hardcode rule). Returns null when no URL can be resolved, which only happens outside
 * the browser/Vite runtime; callers may pass the host explicitly in that case.
 */
export function derivedStorageHost(): string | null {
  try {
    const url = getSupabasePublicUrl();
    if (url) return new URL(url).hostname;
  } catch {
    /* not in a Vite runtime — fall through to env */
  }
  const env = (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env;
  const fromEnv = env?.PUBLIC_SUPABASE_URL || env?.SUPABASE_URL;
  if (!fromEnv) return null;
  try {
    return new URL(fromEnv).hostname;
  } catch {
    return null;
  }
}

/** Returns the URL when its host is allowed, else null. Rejects non-http(s) schemes. */
export function sanitizeAvatarUrl(
  url: string | null | undefined,
  storageHost: string | null = derivedStorageHost(),
): string | null {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return null;
    const allowed = storageHost ? [...OAUTH_AVATAR_HOSTS, storageHost] : OAUTH_AVATAR_HOSTS;
    return allowed.includes(parsed.hostname) ? url : null;
  } catch {
    return null;
  }
}

/**
 * The avatar to render for a member: their uploaded platform photo first, the OAuth identity
 * picture as fallback, null when neither is usable (caller renders initials).
 */
export function resolveAvatarUrl(
  member: { photo_url?: string | null } | null | undefined,
  user?: { user_metadata?: { avatar_url?: string | null } | null } | null,
  storageHost: string | null = derivedStorageHost(),
): string | null {
  return (
    sanitizeAvatarUrl(member?.photo_url, storageHost) ??
    sanitizeAvatarUrl(user?.user_metadata?.avatar_url, storageHost) ??
    null
  );
}

/** Two-letter initials fallback, matching what the nav and team cards already render. */
export function initialsFor(name: string | null | undefined): string {
  const letters = String(name || '')
    .split(' ')
    .filter(Boolean)
    .map((w) => w[0])
    .join('')
    .substring(0, 2)
    .toUpperCase();
  return letters || '?';
}
