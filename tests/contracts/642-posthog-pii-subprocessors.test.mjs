import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();

function read(path) {
  return readFileSync(resolve(ROOT, path), 'utf8');
}

function walk(dir, acc = []) {
  for (const entry of readdirSync(resolve(ROOT, dir))) {
    const full = join(dir, entry);
    if (full.includes('database.gen.ts')) continue;
    const st = statSync(resolve(ROOT, full));
    if (st.isDirectory()) walk(full, acc);
    else if (/\.(astro|tsx?|mjs)$/.test(entry)) acc.push(full);
  }
  return acc;
}

test('#642 PostHog identify is pseudonymous and does not include name/email properties', () => {
  const base = read('src/layouts/BaseLayout.astro');
  const nav = read('src/components/nav/Nav.astro');
  assert.match(base, /safePH\('identify', `member:\$\{m\.id\}`/);
  assert.equal(nav.includes('posthog.identify'), false, 'Nav must not duplicate identify with member name/email');

  const identifyBlock = base.slice(base.indexOf("safePH('identify'"), base.indexOf("safePH('group'"));
  assert.equal(/\bname\s*:/.test(identifyBlock), false, 'identify properties must not include name');
  assert.equal(/\bemail\s*:/.test(identifyBlock), false, 'identify properties must not include email');
});

test('#642 direct PostHog capture calls are centralized through analytics helper', () => {
  const offenders = walk('src')
    .filter((path) => path !== 'src/lib/analytics.ts')
    .filter((path) => /posthog(?:\?\.)?\.capture|posthog\)\.posthog\.capture/.test(read(path)));

  assert.deepEqual(offenders, [], `direct posthog.capture calls must use __nucleoTrack: ${offenders.join(', ')}`);
});

test('#642 free-text search is not sent to PostHog', () => {
  const library = read('src/pages/library.astro');
  assert.equal(
    /library_search'[\s\S]{0,160}\bquery\s*:\s*searchQuery/.test(library),
    false,
    'library_search must not send raw query text',
  );
  assert.match(library, /library_search', \{ query_length: searchQuery\.length, results: data\.length \}/);
});

test('#642 analytics sanitizer redacts sensitive keys and obvious PII values', () => {
  const analytics = read('src/lib/analytics.ts');
  for (const token of ['email', 'name', 'phone', 'linkedin', 'pmi_id', 'query', 'member_id', 'person_id']) {
    assert.match(analytics, new RegExp(token), `sanitizer must mention sensitive token: ${token}`);
  }
  assert.match(analytics, /EMAIL_VALUE_RE/);
  assert.match(analytics, /PHONE_VALUE_RE/);
  assert.match(analytics, /URL_VALUE_RE/);
  assert.match(analytics, /sanitizeAnalyticsProperties/);
});

test('#642 DPA sub-operator inventory exists with core providers and official source links', () => {
  const doc = read('docs/legal/642_DPA_SUBPROCESSOR_INVENTORY.md');
  for (const provider of ['Supabase', 'Cloudflare', 'PostHog', 'Sentry', 'Resend', 'Google', 'Microsoft', 'LinkedIn', 'OpenAI', 'Anthropic']) {
    assert.match(doc, new RegExp(`\\| ${provider} \\|`), `inventory missing provider row: ${provider}`);
  }
  for (const url of [
    'https://posthog.com/subprocessors',
    'https://www.cloudflare.com/gdpr/subprocessors/cloudflare-services/',
    'https://sentry.io/legal/subprocessors/',
    'https://resend.com/legal/subprocessors',
    'https://openai.com/policies/sub-processor-list/',
    'https://trust.anthropic.com/subprocessors',
  ]) {
    assert.ok(doc.includes(url), `inventory missing source URL: ${url}`);
  }
});
