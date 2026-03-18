/**
 * PostHog custom event tracking helper.
 * Silent fail — analytics should never break the app.
 */
export function trackEvent(name: string, properties?: Record<string, any>) {
  try {
    if (typeof window !== 'undefined' && (window as any).posthog) {
      (window as any).posthog.capture(name, properties);
    }
  } catch {
    // Silent fail
  }
}
