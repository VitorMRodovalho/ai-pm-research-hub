// supabase/functions/_shared/suppression.ts
// #2130 E-b: the one question every send path asks before sending, answered by `email_suppressed_among()`.
//
// Rule (decisions of the GP, 2026-10-08): a complaint, a provider suppression or a permanent bounce stops every email to
// the address until a later delivery releases it; an unsubscribe stops campaigns and broadcasts only
// (`includeUnsubscribed`). A link the person asked for (email verification, account claim, competition registration)
// does not ask, on purpose.
//
// Returns the suppressed subset as a Set of lowercased addresses, or `null` when the answer could not be read.
// What to do with `null` is the caller's decision: a path with a retry holds the send, a one-shot path sends and logs.

type Client = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { message?: string } | null }> }

export const normalizeEmail = (email: string): string => email.trim().toLowerCase()

export async function suppressedAmong(
  sb: Client,
  emails: (string | null | undefined)[],
  includeUnsubscribed: boolean,
): Promise<Set<string> | null> {
  const list = [...new Set(emails.filter((e): e is string => !!e && e.trim() !== '').map(normalizeEmail))]
  if (list.length === 0) return new Set()
  const { data, error } = await sb.rpc('email_suppressed_among', {
    p_emails: list,
    p_include_unsubscribed: includeUnsubscribed,
  })
  if (error || !Array.isArray(data)) {
    console.error('[suppression] unreadable:', error?.message ?? 'no value')
    return null
  }
  return new Set((data as string[]).map(normalizeEmail))
}
