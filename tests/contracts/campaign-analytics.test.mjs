/**
 * W-CAMP-ANALYTICS Contract Tests: Resend Webhook Analytics
 * Static analysis — reads migration files, Edge Functions, UI files.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

function readFile(rel) {
  const p = resolve(ROOT, rel);
  assert.ok(existsSync(p), `${rel} must exist`);
  return readFileSync(p, 'utf8');
}

// ═══════════════════════════════════════════════
// Schema
// ═══════════════════════════════════════════════

test('campaign_recipients has tracking columns', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  const cols = ['resend_id', 'delivered_at', 'opened_at', 'open_count', 'clicked_at', 'click_count', 'bounced_at', 'bounce_type', 'complained_at'];
  for (const c of cols) {
    assert.ok(mig.includes(c), `Migration must add ${c} column`);
  }
});

test('resend_id index exists', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  assert.ok(mig.includes('idx_campaign_recipients_resend_id'), 'Must create resend_id index');
});

test('email_webhook_events table exists with RLS', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  assert.ok(mig.includes('email_webhook_events'), 'Must create email_webhook_events table');
  assert.ok(mig.includes('ENABLE ROW LEVEL SECURITY'), 'Must enable RLS on webhook events');
  assert.ok(mig.includes('is_superadmin'), 'RLS must restrict to superadmin');
});

// ═══════════════════════════════════════════════
// RPCs
// ═══════════════════════════════════════════════

test('process_email_webhook RPC handles all 5 event types', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  const events = ['email.delivered', 'email.opened', 'email.clicked', 'email.bounced', 'email.complained'];
  for (const e of events) {
    assert.ok(mig.includes(e), `process_email_webhook must handle ${e}`);
  }
});

test('process_email_webhook is SECURITY DEFINER', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  assert.ok(/process_email_webhook[\s\S]*?SECURITY\s+DEFINER/i.test(mig));
});

test('process_email_webhook uses COALESCE for idempotent timestamps', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  const coalesceCount = (mig.match(/COALESCE\(delivered_at|COALESCE\(opened_at|COALESCE\(clicked_at|COALESCE\(bounced_at|COALESCE\(complained_at/g) || []).length;
  assert.ok(coalesceCount >= 4, 'Must use COALESCE for idempotent timestamp updates');
});

test('get_campaign_analytics RPC exists and requires admin', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  assert.ok(mig.includes('get_campaign_analytics'), 'Must create get_campaign_analytics RPC');
  assert.ok(mig.includes('auth.uid()'), 'Must check auth');
  assert.ok(mig.includes('RAISE EXCEPTION'), 'Must raise on unauthorized');
  assert.ok(mig.includes('is_superadmin'), 'Must check superadmin');
});

test('get_campaign_analytics returns funnel data', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  const fields = ['funnel', 'rates', 'recipients', 'by_role', 'delivery_rate', 'open_rate', 'click_rate'];
  for (const f of fields) {
    assert.ok(mig.includes(`'${f}'`), `get_campaign_analytics must include ${f}`);
  }
});

test('get_campaign_analytics supports both specific and aggregate mode', () => {
  const mig = readFile('supabase/migrations/20260319100061_w_camp_analytics_resend_webhooks.sql');
  assert.ok(mig.includes('p_send_id uuid DEFAULT NULL'), 'Must accept optional send_id');
  assert.ok(mig.includes('recent_sends'), 'Aggregate mode must include recent_sends');
  assert.ok(mig.includes('total_sends'), 'Aggregate mode must include total_sends');
});

// ═══════════════════════════════════════════════
// Edge Functions
// ═══════════════════════════════════════════════

test('resend-webhook Edge Function exists', () => {
  readFile('supabase/functions/resend-webhook/index.ts');
});

test('resend-webhook processes valid event types', () => {
  const ef = readFile('supabase/functions/resend-webhook/index.ts');
  assert.ok(ef.includes('email.delivered'), 'Must handle email.delivered');
  assert.ok(ef.includes('email.opened'), 'Must handle email.opened');
  assert.ok(ef.includes('email.clicked'), 'Must handle email.clicked');
  assert.ok(ef.includes('email.bounced'), 'Must handle email.bounced');
  assert.ok(ef.includes('email.complained'), 'Must handle email.complained');
});

test('resend-webhook logs raw events', () => {
  const ef = readFile('supabase/functions/resend-webhook/index.ts');
  assert.ok(ef.includes('email_webhook_events'), 'Must log to email_webhook_events');
});

test('resend-webhook calls process_email_webhook RPC', () => {
  const ef = readFile('supabase/functions/resend-webhook/index.ts');
  assert.ok(ef.includes('process_email_webhook'), 'Must call process_email_webhook RPC');
});

test('resend-webhook accepts svix headers (Resend webhook signatures)', () => {
  const ef = readFile('supabase/functions/resend-webhook/index.ts');
  assert.ok(ef.includes('svix-id'), 'Must accept svix-id header');
  assert.ok(ef.includes('svix-timestamp'), 'Must accept svix-timestamp header');
  assert.ok(ef.includes('svix-signature'), 'Must accept svix-signature header');
});

test('send-campaign stores resend_id on success', () => {
  const ef = readFile('supabase/functions/send-campaign/index.ts');
  assert.ok(ef.includes('resend_id'), 'Must store resend_id');
  assert.ok(ef.includes('JSON.parse(rt)'), 'Must parse Resend response for ID');
});

// ═══════════════════════════════════════════════
// Frontend
// ═══════════════════════════════════════════════

test('/admin/campaigns has analytics modal', () => {
  const page = readFile('src/pages/admin/campaigns.astro');
  assert.ok(page.includes('analytics-modal'), 'Must have analytics modal');
  assert.ok(page.includes('analytics-funnel'), 'Must have funnel container');
  assert.ok(page.includes('analytics-by-role'), 'Must have by-role container');
  assert.ok(page.includes('analytics-recipients'), 'Must have recipients container');
});

test('/admin/campaigns calls get_campaign_analytics RPC', () => {
  const page = readFile('src/pages/admin/campaigns.astro');
  assert.ok(page.includes('get_campaign_analytics'), 'Must call get_campaign_analytics');
});

test('/admin/campaigns shows mini-stats in history rows', () => {
  const page = readFile('src/pages/admin/campaigns.astro');
  assert.ok(page.includes('miniStats'), 'Must show mini-stats in history');
});

// ═══════════════════════════════════════════════
// i18n
// ═══════════════════════════════════════════════

test('i18n keys exist for campaign analytics', () => {
  const keys = ['campaigns.analytics', 'campaigns.funnel', 'campaigns.delivered', 'campaigns.opened',
    'campaigns.clicked', 'campaigns.bounced', 'campaigns.byTier', 'campaigns.recipients'];
  for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
    const content = readFile(`src/i18n/${lang}.ts`);
    for (const k of keys) {
      assert.ok(content.includes(k), `${lang} must have ${k}`);
    }
  }
});

// ═══════════════════════════════════════════════
// Governance
// ═══════════════════════════════════════════════

test('GC-071 governance entry exists', () => {
  const gc = readFile('docs/GOVERNANCE_CHANGELOG.md');
  assert.ok(gc.includes('GC-071'), 'Must have GC-071 entry');
  assert.ok(gc.includes('W-CAMP-ANALYTICS'), 'GC-071 must reference W-CAMP-ANALYTICS');
  assert.ok(gc.includes('Resend webhook'), 'GC-071 must mention Resend webhooks');
});
