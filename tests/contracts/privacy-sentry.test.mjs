/**
 * W126 Contract Tests: Privacy Policy + Sentry Integration
 * Static analysis — reads source files and verifies structure.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

// ═══════════════════════════════════════════════════
// Privacy Policy Page
// ═══════════════════════════════════════════════════

test('/privacy page exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/pages/privacy.astro')), '/privacy page must exist');
});

test('/privacy page references LGPD via i18n keys', () => {
  // GC-080 restructured sections: LGPD rights is now s7rights
  const ptBR = readFileSync(resolve(ROOT, 'src/i18n/pt-BR.ts'), 'utf8');
  assert.ok(ptBR.includes('LGPD'), 'pt-BR i18n must reference LGPD');
  const content = readFileSync(resolve(ROOT, 'src/pages/privacy.astro'), 'utf8');
  assert.ok(content.includes('privacy.s7rights.title'), 'Page must use s7rights (LGPD rights section)');
});

test('/privacy page has nucleoia@pmigo.org.br contact', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/privacy.astro'), 'utf8');
  assert.ok(content.includes('nucleoia@pmigo.org.br'), 'Must include contact email');
});

test('/privacy page has all 13 sections (GC-080 v2.0)', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/privacy.astro'), 'utf8');
  // GC-080 restructured: s1, s2, s3, s4, s5int, s6ret, s7rights, s8auto, s9sec, s10track, s11, s12, s13
  const sections = [
    's1.title', 's2.title', 's3.title', 's4.title',
    's5int.title', 's6ret.title', 's7rights.title', 's8auto.title',
    's9sec.title', 's10track.title', 's11.title', 's12.title', 's13.title',
  ];
  for (const key of sections) {
    assert.ok(content.includes(`privacy.${key}`), `Must include privacy.${key}`);
  }
});

test('/privacy page has noindex meta', () => {
  const content = readFileSync(resolve(ROOT, 'src/pages/privacy.astro'), 'utf8');
  assert.ok(content.includes('noindex'), 'Privacy page must have noindex meta');
});

test('privacy policy i18n keys exist in all languages', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const content = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    assert.ok(content.includes('privacy.title'), `${lang} must have privacy.title key`);
    assert.ok(content.includes('privacy.s1.title'), `${lang} must have privacy.s1.title`);
    assert.ok(content.includes('privacy.s7rights.title'), `${lang} must have privacy.s7rights.title (LGPD rights)`);
    assert.ok(content.includes('privacy.s9sec.title'), `${lang} must have privacy.s9sec.title (security)`);
    assert.ok(content.includes('privacy.s13.title'), `${lang} must have privacy.s13.title (contact)`);
  }
});

test('privacy policy mentions all data processors', () => {
  const content = readFileSync(resolve(ROOT, 'src/i18n/pt-BR.ts'), 'utf8');
  assert.ok(content.includes('Supabase'), 'Must mention Supabase as processor');
  assert.ok(content.includes('Cloudflare'), 'Must mention Cloudflare as processor');
  assert.ok(content.includes('PostHog'), 'Must mention PostHog as processor');
  assert.ok(content.includes('Sentry'), 'Must mention Sentry as processor');
});

// ═══════════════════════════════════════════════════
// Footer Link
// ═══════════════════════════════════════════════════

test('BaseLayout has footer link to /privacy', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes('/privacy'), 'BaseLayout must link to /privacy');
  assert.ok(content.includes('footer.privacy'), 'Must use footer.privacy i18n key');
});

test('footer.privacy i18n key exists in all languages', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const content = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    assert.ok(content.includes('footer.privacy'), `${lang} must have footer.privacy key`);
  }
});

// ═══════════════════════════════════════════════════
// Sentry Integration
// ═══════════════════════════════════════════════════

test('sentry.ts exists and exports initSentry', () => {
  const path = resolve(ROOT, 'src/lib/sentry.ts');
  assert.ok(existsSync(path), 'sentry.ts must exist');
  const content = readFileSync(path, 'utf8');
  assert.ok(content.includes('export function initSentry'), 'Must export initSentry');
});

test('sentry.ts imports @sentry/browser', () => {
  const content = readFileSync(resolve(ROOT, 'src/lib/sentry.ts'), 'utf8');
  assert.ok(content.includes('@sentry/browser'), 'Must import @sentry/browser');
});

test('sentry.ts strips PII (email and ip_address)', () => {
  const content = readFileSync(resolve(ROOT, 'src/lib/sentry.ts'), 'utf8');
  assert.ok(content.includes('beforeSend'), 'Must have beforeSend hook');
  assert.ok(content.includes('email'), 'Must strip email');
  assert.ok(content.includes('ip_address'), 'Must strip ip_address');
});

test('sentry.ts disables session replay', () => {
  const content = readFileSync(resolve(ROOT, 'src/lib/sentry.ts'), 'utf8');
  assert.ok(content.includes('replaysSessionSampleRate: 0'), 'Session replay must be disabled');
  assert.ok(content.includes('replaysOnErrorSampleRate: 0'), 'Error replay must be disabled');
});

test('sentry.ts uses PUBLIC_SENTRY_DSN env var', () => {
  const content = readFileSync(resolve(ROOT, 'src/lib/sentry.ts'), 'utf8');
  assert.ok(content.includes('PUBLIC_SENTRY_DSN'), 'Must use PUBLIC_SENTRY_DSN');
});

test('sentry.ts guards init when DSN is empty', () => {
  const content = readFileSync(resolve(ROOT, 'src/lib/sentry.ts'), 'utf8');
  assert.ok(content.includes('if (!dsn)') || content.includes('if (dsn)') || content.includes('if (!'), 'Must guard init when DSN is empty');
});

test('BaseLayout initializes Sentry', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes('initSentry'), 'BaseLayout must call initSentry');
  assert.ok(content.includes("from '../lib/sentry'") || content.includes("from \"../lib/sentry\""), 'Must import from lib/sentry');
});

test('PUBLIC_SENTRY_DSN documented in .env.example', () => {
  const content = readFileSync(resolve(ROOT, '.env.example'), 'utf8');
  assert.ok(content.includes('PUBLIC_SENTRY_DSN'), 'Must document PUBLIC_SENTRY_DSN in .env.example');
});

// ═══════════════════════════════════════════════════
// Error Boundary
// ═══════════════════════════════════════════════════

test('ErrorBoundary component exists', () => {
  const path = resolve(ROOT, 'src/components/ErrorBoundary.tsx');
  assert.ok(existsSync(path), 'ErrorBoundary.tsx must exist');
});

test('ErrorBoundary captures exceptions with Sentry', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/ErrorBoundary.tsx'), 'utf8');
  assert.ok(content.includes('captureException'), 'Must call Sentry.captureException');
  assert.ok(content.includes('componentDidCatch') || content.includes('componentStack'), 'Must implement componentDidCatch');
});

test('ErrorBoundary has fallback UI', () => {
  const content = readFileSync(resolve(ROOT, 'src/components/ErrorBoundary.tsx'), 'utf8');
  assert.ok(content.includes('hasError'), 'Must track hasError state');
  assert.ok(content.includes('fallback') || content.includes('Erro ao carregar'), 'Must show fallback UI');
});

// ═══════════════════════════════════════════════════
// Cookie Consent Banner
// ═══════════════════════════════════════════════════

test('BaseLayout has consent banner', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes('consent-banner'), 'Must have consent-banner element');
  assert.ok(content.includes('consent-accept'), 'Must have consent accept button');
});

test('consent banner links to /privacy', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes('consent.privacyLink'), 'Consent banner must link to privacy policy');
});

test('consent banner uses localStorage to remember choice', () => {
  const content = readFileSync(resolve(ROOT, 'src/layouts/BaseLayout.astro'), 'utf8');
  assert.ok(content.includes('localStorage') && content.includes('cookie_consent_accepted'), 'Must use localStorage for consent persistence');
});

test('consent.message i18n key exists in all languages', () => {
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const content = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
    assert.ok(content.includes('consent.message'), `${lang} must have consent.message`);
    assert.ok(content.includes('consent.accept'), `${lang} must have consent.accept`);
  }
});

// ═══════════════════════════════════════════════════
// Package dependency
// ═══════════════════════════════════════════════════

test('@sentry/browser is in package.json dependencies', () => {
  const pkg = JSON.parse(readFileSync(resolve(ROOT, 'package.json'), 'utf8'));
  assert.ok(pkg.dependencies['@sentry/browser'], '@sentry/browser must be in dependencies');
});
