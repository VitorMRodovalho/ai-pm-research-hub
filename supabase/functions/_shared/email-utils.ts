// _shared/email-utils.ts
// Extracted from send-campaign (GC-083)
// Pure JS — no Deno APIs, no esm.sh imports

/**
 * Detect if the sender address is Resend sandbox mode.
 * Sandbox mode means emails can only be sent to the account owner.
 */
export function isSandboxMode(fromAddress: string): boolean {
  return fromAddress.includes('onboarding@resend.dev')
}

/**
 * Render a template string by replacing variable placeholders.
 * Replaces all occurrences of each key with its value.
 */
export function renderTemplate(
  template: string,
  vars: Record<string, string>,
): string {
  let result = template
  for (const [key, value] of Object.entries(vars)) {
    result = result.split(key).join(value)
  }
  return result
}
