import * as Sentry from '@sentry/browser';

export function initSentry() {
  const dsn = (import.meta as any).env?.PUBLIC_SENTRY_DSN;
  console.log('[Sentry] init called, DSN:', dsn ? dsn.slice(0, 20) + '...' : 'MISSING');
  if (!dsn) return;

  Sentry.init({
    dsn,
    environment: (import.meta as any).env?.MODE || 'production',
    tracesSampleRate: 0.1,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
    beforeSend(event) {
      if (event.user) {
        delete event.user.email;
        delete event.user.ip_address;
      }
      return event;
    },
  });
}

export { Sentry };
