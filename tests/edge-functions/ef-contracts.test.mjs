import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const EF_ROOT = join(import.meta.dirname, '..', '..', 'supabase', 'functions');

/**
 * Static contract tests for all Edge Functions in repo.
 * Verifies structural integrity without importing Deno code.
 */

const EF_CONTRACTS = [
  {
    name: 'sync-credly-all',
    tables: ['members', 'gamification_points'],
    imports: ['_shared/cors.ts', '_shared/classify-badge.ts'],
  },
  {
    name: 'sync-attendance-points',
    tables: ['attendance', 'gamification_points'],
    imports: ['_shared/cors.ts', '_shared/attendance-xp.ts'],
  },
  {
    name: 'verify-credly',
    tables: ['members', 'gamification_points'],
    imports: ['_shared/classify-badge.ts'],
  },
  {
    name: 'resend-webhook',
    tables: ['email_webhook_events'],
    imports: ['_shared/webhook-parser.ts'],
    externalServices: ['process_email_webhook'],
  },
  {
    name: 'send-campaign',
    tables: ['campaign_sends', 'campaign_recipients', 'members'],
    imports: ['_shared/email-utils.ts'],
    externalServices: ['api.resend.com'],
  },
  {
    name: 'send-tribe-broadcast',
    tables: ['members'],
    imports: [],
    externalServices: ['api.resend.com'],
  },
  {
    name: 'send-global-onboarding',
    tables: ['members'],
    imports: [],
    externalServices: ['api.resend.com'],
  },
  {
    name: 'send-allocation-notify',
    tables: ['members'],
    imports: [],
    externalServices: ['api.resend.com'],
  },
  {
    name: 'sync-comms-metrics',
    tables: ['comms_channel_config', 'comms_metrics_daily'],
    imports: ['_shared/cors.ts'],
  },
  {
    name: 'get-comms-metrics',
    tables: ['comms_metrics_daily'],
    imports: ['_shared/cors.ts'],
  },
  {
    name: 'sync-knowledge-youtube',
    tables: ['knowledge_assets', 'knowledge_chunks', 'knowledge_ingestion_runs'],
    imports: ['_shared/cors.ts'],
  },
  {
    name: 'sync-knowledge-insights',
    tables: ['knowledge_chunks', 'knowledge_insights'],
    imports: ['_shared/cors.ts'],
  },
  {
    name: 'sync-knowledge-social-content',
    tables: ['hub_resources', 'members'],
    imports: [],
  },
  {
    name: 'send-notification-digest',
    tables: ['notification_preferences', 'members', 'notifications'],
    imports: [],
    externalServices: ['api.resend.com'],
  },
  {
    name: 'import-trello-legacy',
    tables: [],
    imports: [],
    deprecated: true,
  },
  {
    name: 'import-calendar-legacy',
    tables: [],
    imports: [],
    deprecated: true,
  },
];

for (const ef of EF_CONTRACTS) {
  test(`EF contract: ${ef.name}`, async (t) => {
    const filePath = join(EF_ROOT, ef.name, 'index.ts');

    await t.test('file exists', () => {
      assert.ok(existsSync(filePath), `${filePath} should exist`);
    });

    const content = readFileSync(filePath, 'utf-8');

    await t.test('contains Deno.serve entry point', () => {
      assert.ok(content.includes('Deno.serve'), `${ef.name} must have Deno.serve`);
    });

    for (const imp of ef.imports) {
      await t.test(`imports ${imp}`, () => {
        assert.ok(content.includes(imp), `${ef.name} must import ${imp}`);
      });
    }

    for (const table of ef.tables) {
      await t.test(`references table: ${table}`, () => {
        assert.ok(
          content.includes(`'${table}'`) || content.includes(`"${table}"`),
          `${ef.name} must reference table '${table}'`,
        );
      });
    }

    await t.test('no hardcoded secrets', () => {
      // Check for common secret patterns (base64 JWT, API keys)
      const secretPatterns = [
        /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/,  // JWT token
        /sk_live_[A-Za-z0-9]{20,}/,                       // Stripe-like key
        /re_[A-Za-z0-9]{20,}/,                            // Resend-like key
      ];
      for (const pattern of secretPatterns) {
        assert.ok(!pattern.test(content), `${ef.name} must not contain hardcoded secrets`);
      }
    });

    if (ef.externalServices) {
      for (const svc of ef.externalServices) {
        await t.test(`references external service: ${svc}`, () => {
          assert.ok(content.includes(svc), `${ef.name} must reference ${svc}`);
        });
      }
    }
  });
}

// Verify _shared modules exist
test('_shared/classify-badge.ts exists', () => {
  assert.ok(existsSync(join(EF_ROOT, '_shared', 'classify-badge.ts')));
});

test('_shared/attendance-xp.ts exists', () => {
  assert.ok(existsSync(join(EF_ROOT, '_shared', 'attendance-xp.ts')));
});

test('_shared/email-utils.ts exists', () => {
  assert.ok(existsSync(join(EF_ROOT, '_shared', 'email-utils.ts')));
});

test('_shared/webhook-parser.ts exists', () => {
  assert.ok(existsSync(join(EF_ROOT, '_shared', 'webhook-parser.ts')));
});

test('_shared/cors.ts exists', () => {
  assert.ok(existsSync(join(EF_ROOT, '_shared', 'cors.ts')));
});
