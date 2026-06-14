/**
 * PostHog custom event tracking helper.
 * Silent fail — analytics should never break the app.
 */
const SENSITIVE_KEY_RE = /(email|e-mail|mail|name|full_name|phone|whatsapp|linkedin|pmi_id|cpf|cnpj|address|birth|birthday|query|search|title|url|photo|avatar|signature|applicant|candidate|member_id|person_id|auth_id|user_id)/i;
const EMAIL_VALUE_RE = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i;
const PHONE_VALUE_RE = /(?:\+?\d[\d\s().-]{7,}\d)/;
const URL_VALUE_RE = /https?:\/\/|www\./i;

function sanitizeValue(value: any): any {
  if (value == null) return value;
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    if (EMAIL_VALUE_RE.test(value) || PHONE_VALUE_RE.test(value) || URL_VALUE_RE.test(value) || SENSITIVE_KEY_RE.test(value)) {
      return '[redacted]';
    }
    return value.length > 120 ? `${value.slice(0, 120)}...` : value;
  }
  if (Array.isArray(value)) return value.map(sanitizeValue);
  if (typeof value === 'object') return sanitizeAnalyticsProperties(value);
  return String(value);
}

export function sanitizeAnalyticsProperties(properties?: Record<string, any>): Record<string, any> {
  if (!properties || typeof properties !== 'object') return {};

  const sanitized: Record<string, any> = {};
  for (const [key, value] of Object.entries(properties)) {
    if (SENSITIVE_KEY_RE.test(key)) {
      sanitized[key] = '[redacted]';
      if (typeof value === 'string') sanitized[`${key}_length`] = value.length;
      continue;
    }
    sanitized[key] = sanitizeValue(value);
  }
  return sanitized;
}

export function trackEvent(name: string, properties?: Record<string, any>) {
  try {
    if (typeof window !== 'undefined' && (window as any).posthog) {
      const globalTrack = (window as any).__nucleoTrack;
      if (typeof globalTrack === 'function') {
        globalTrack(name, properties);
      } else {
        (window as any).posthog.capture(name, sanitizeAnalyticsProperties(properties));
      }
    }
  } catch {
    // Silent fail
  }
}
