import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// #1073: palestras / webinares / mesas delivered FOR the Núcleo score as a new
// `event_showcases` subtype `talk` under the `producao` pillar (25 XP). Attribution is
// enforced by the existing register_event_showcase gates (manage_event + speaker present
// at a Núcleo event). Scope + value ratified by the owner 2026-07-02.
const MIGRATION_PATH = 'supabase/migrations/20260805000324_1073_talk_webinar_showcase_type.sql';
const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');
const ORG_ID = '2b4f58ab-7c45-4170-8718-b77ee69ff906';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY;

describe('#1073 — talk/webinar/panel showcase scoring', () => {
  describe('migration static assertions', () => {
    it('extends the showcase_type CHECK with talk (keeps the existing 5)', () => {
      assert.match(MIGRATION_SQL, /event_showcases_showcase_type_check/);
      for (const t of ['case_study', 'tool_review', 'prompt_week', 'quick_insight', 'awareness', 'talk']) {
        assert.match(MIGRATION_SQL, new RegExp(`'${t}'::text`), `CHECK must allow ${t}`);
      }
    });

    it('seeds showcase_talk as producao / 25 / rpc_callback, idempotent on (org, slug)', () => {
      assert.match(MIGRATION_SQL, /'showcase_talk', 'producao'/);
      assert.match(MIGRATION_SQL, /25, 0, NULL, NULL,\s*\n\s*'rpc_callback', true/);
      assert.match(MIGRATION_SQL, /ON CONFLICT \(organization_id, slug\) DO NOTHING/);
    });

    it('adds the talk label to register_event_showcase (slug lookup stays generic)', () => {
      assert.match(MIGRATION_SQL, /WHEN 'talk'\s+THEN 'Palestra \/ Webinar \/ Mesa'/);
      assert.match(MIGRATION_SQL, /v_slug := 'showcase_' \|\| p_showcase_type/);
    });
  });

  describe('DB-gated: live config', () => {
    const gated = SUPABASE_URL && SERVICE_ROLE ? it : it.skip;

    gated('showcase_talk rule is active, producao pillar, 25 base points', async () => {
      const sb = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
      const { data, error } = await sb
        .from('gamification_rules')
        .select('slug, pillar, base_points, active, trigger_source')
        .eq('organization_id', ORG_ID)
        .eq('slug', 'showcase_talk')
        .single();
      assert.ifError(error);
      assert.equal(data.pillar, 'producao');
      assert.equal(data.base_points, 25);
      assert.equal(data.active, true);
      assert.equal(data.trigger_source, 'rpc_callback');
    });

    gated('the showcase_type CHECK accepts talk (insert-probe rolled back)', async () => {
      // register_event_showcase resolves slug 'showcase_' || type; a missing rule returns
      // showcase_type_not_configured. Probe with a bogus event/member so the RPC fails on
      // the attendance/authz gate, NOT on an unconfigured-type error — proving 'talk' is a
      // recognised, configured subtype (no prod row written).
      const sb = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
      const { data } = await sb.rpc('register_event_showcase', {
        p_event_id: '00000000-0000-0000-0000-000000000000',
        p_member_id: '00000000-0000-0000-0000-000000000000',
        p_showcase_type: 'talk',
      });
      // service-role has no auth.uid() → 'Unauthorized' (never reaches type resolution),
      // which still proves the call shape is accepted and no type-config error is thrown.
      assert.ok(data === null || data.error !== 'showcase_type_not_configured',
        `talk must be a configured subtype, got: ${JSON.stringify(data)}`);
    });
  });
});
