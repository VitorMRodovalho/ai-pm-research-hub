// _shared/webhook-parser.ts
// Extracted from resend-webhook (GC-083)
// Pure JS — no Deno APIs, no esm.sh imports

/** Valid Resend webhook event types that trigger processing */
export const VALID_WEBHOOK_EVENTS = [
  'email.delivered',
  'email.opened',
  'email.clicked',
  'email.bounced',
  'email.complained',
] as const

export type WebhookEventType = typeof VALID_WEBHOOK_EVENTS[number]

export interface ParsedWebhookEvent {
  eventType: string
  resendId: string | undefined
  recipientEmail: string | undefined
  isValid: boolean
  bounceType: string | undefined
}

/**
 * Parse a Resend webhook payload into a structured event.
 * Returns isValid=true only for recognized event types with a resend_id.
 */
export function parseWebhookEvent(payload: Record<string, unknown>): ParsedWebhookEvent {
  const eventType = String(payload.type || '')
  const data = (payload.data || {}) as Record<string, unknown>
  const resendId = data.email_id as string | undefined
  const toArray = data.to as string[] | undefined
  const recipientEmail = Array.isArray(toArray) ? toArray[0] : undefined

  const isValid = !!(resendId && eventType && VALID_WEBHOOK_EVENTS.includes(eventType as WebhookEventType))

  let bounceType: string | undefined
  if (eventType === 'email.bounced') {
    const bounce = data.bounce as Record<string, unknown> | undefined
    bounceType = (bounce?.type as string) || 'unknown'
  }

  return { eventType, resendId, recipientEmail, isValid, bounceType }
}
