import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// SPEC #348 Child #3 — Admin UI surface for members.interview_booking_url.
// Locks: migration body extensions (admin_update_member_audited allowlist +
// get_member_detail return shape), MemberDetailIsland.tsx form field, plural
// wrapper page-i18n injection, i18n 6 keys × 3 langs, and forward-defense
// regressions against future drift that would re-introduce the bugs SPEC #348
// §3 Q2 explicitly forbids (no DB CHECK, no stricter-than-^https?:// regex).

const MIGRATION_PATH = 'supabase/migrations/20260805000031_p252_356_spec_348_v1_admin_member_booking_url.sql';
const SPEC_PATH = 'docs/specs/SPEC_348_BOOKING_URL_PER_EVALUATOR.md';
const ISLAND_PATH = 'src/components/admin/members/MemberDetailIsland.tsx';
const WRAPPER_PATH = 'src/pages/admin/members/[id].astro';
const DICT_PT = 'src/i18n/pt-BR.ts';
const DICT_EN = 'src/i18n/en-US.ts';
const DICT_ES = 'src/i18n/es-LATAM.ts';

const MIGRATION_SQL = readFileSync(MIGRATION_PATH, 'utf8');
const ISLAND_SRC = readFileSync(ISLAND_PATH, 'utf8');
const WRAPPER_SRC = readFileSync(WRAPPER_PATH, 'utf8');
const DICT_PT_SRC = readFileSync(DICT_PT, 'utf8');
const DICT_EN_SRC = readFileSync(DICT_EN, 'utf8');
const DICT_ES_SRC = readFileSync(DICT_ES, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

const I18N_KEYS = [
  'admin.member.bookingUrl.label',
  'admin.member.bookingUrl.placeholder',
  'admin.member.bookingUrl.help',
  'admin.member.bookingUrl.invalid',
  'admin.member.bookingUrl.empty',
  'admin.member.bookingUrl.savedToast',
];

describe('p252 #356 — SPEC #348 Child #3 admin UI (interview_booking_url)', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH), `migration expected at ${MIGRATION_PATH}`);
      assert.ok(MIGRATION_SQL.length > 0, 'migration file must not be empty');
    });

    it('header documents WHAT / WHY / SPEC DRIFT / ROLLBACK / INVARIANTS + cross-refs', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- SPEC DRIFT RESOLVED:/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK:/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /#348/, 'parent issue #348 must be referenced');
      assert.match(MIGRATION_SQL, /#356/, 'this issue #356 must be referenced');
      assert.match(MIGRATION_SQL, /#354/, 'predecessor #354 must be referenced');
      assert.match(MIGRATION_SQL, /#355/, 'predecessor #355 must be referenced');
    });

    it('spec doc exists at canonical path (cross-ref anchor)', () => {
      assert.ok(existsSync(SPEC_PATH), `spec doc expected at ${SPEC_PATH}`);
    });
  });

  describe('signature preservation (SEDIMENT-238.C — CREATE OR REPLACE same-sig)', () => {
    it('admin_update_member_audited uses CREATE OR REPLACE (preserves ACL)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.admin_update_member_audited\s*\(\s*p_member_id\s+uuid\s*,\s*p_changes\s+jsonb\s*\)/,
        'must keep canonical 2-arg signature (p_member_id uuid, p_changes jsonb)'
      );
      assert.doesNotMatch(
        MIGRATION_SQL,
        /DROP\s+FUNCTION\s+(?:IF EXISTS\s+)?public\.admin_update_member_audited/i,
        'DROP would force re-GRANT; SEDIMENT-238.C requires CREATE OR REPLACE'
      );
    });

    it('get_member_detail uses CREATE OR REPLACE (preserves ACL)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.get_member_detail\s*\(\s*p_member_id\s+uuid\s*\)/,
        'must keep canonical 1-arg signature (p_member_id uuid)'
      );
      assert.doesNotMatch(
        MIGRATION_SQL,
        /DROP\s+FUNCTION\s+(?:IF EXISTS\s+)?public\.get_member_detail/i,
        'DROP would force re-GRANT'
      );
    });

    it('both RPCs preserve SECURITY DEFINER + pinned search_path', () => {
      // admin_update_member_audited: 'public', 'pg_temp'
      // get_member_detail: '' (empty, schema-qualified everywhere)
      const updateBlock = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.admin_update_member_audited')[1]?.split('CREATE OR REPLACE FUNCTION public.get_member_detail')[0] || '';
      assert.match(updateBlock, /SECURITY DEFINER/);
      assert.match(updateBlock, /SET search_path TO 'public', 'pg_temp'/);

      const detailBlock = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.get_member_detail')[1] || '';
      assert.match(detailBlock, /SECURITY DEFINER/);
      assert.match(detailBlock, /SET search_path = ''/);
    });
  });

  describe('admin_update_member_audited body — interview_booking_url branch', () => {
    const updateBlock = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.admin_update_member_audited')[1]?.split('CREATE OR REPLACE FUNCTION public.get_member_detail')[0] || '';

    it('v_old_record SELECT includes interview_booking_url for audit diff', () => {
      assert.match(
        updateBlock,
        /jsonb_build_object\([\s\S]*?'interview_booking_url'\s*,\s*m\.interview_booking_url[\s\S]*?\)\s*INTO\s+v_old_record/i,
        'audit FOR-loop needs old value pulled into v_old_record so member.interview_booking_url_changed rows fire'
      );
    });

    it('UPDATE SET branch handles interview_booking_url with NULLIF empty->NULL', () => {
      assert.match(
        updateBlock,
        /interview_booking_url\s*=\s*CASE\s+WHEN\s+p_changes\s*\?\s*'interview_booking_url'\s+THEN\s+NULLIF\(p_changes->>'interview_booking_url',\s*''\)\s+ELSE\s+interview_booking_url\s+END/i,
        'cleared form (empty string from input) must store SQL NULL via NULLIF; absent key must preserve current value'
      );
    });

    it('manage_member gate preserved (no privilege expansion)', () => {
      assert.match(
        updateBlock,
        /can_by_member\(v_actor_id,\s*'manage_member'\)/,
        'V4 authority gate must remain manage_member — privilege escalation guard'
      );
    });

    it('audit FOR-loop preserved (generic member.<field>_changed dispatch)', () => {
      assert.match(
        updateBlock,
        /'member\.'\s*\|\|\s*v_field\s*\|\|\s*'_changed'/,
        'dynamic audit action prefix must remain — no hardcoded allowlist per field'
      );
    });
  });

  describe('get_member_detail body — surfaces interview_booking_url', () => {
    const detailBlock = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.get_member_detail')[1] || '';

    it('member jsonb_build_object exposes interview_booking_url', () => {
      assert.match(
        detailBlock,
        /'interview_booking_url'\s*,\s*m\.interview_booking_url/,
        'React island reads m.interview_booking_url from this payload to populate the form'
      );
    });

    it('view_internal_analytics V4 gate preserved (ADR-0036)', () => {
      assert.match(
        detailBlock,
        /can_by_member\(v_caller_id,\s*'view_internal_analytics'\)/,
        'no privilege expansion; ADR-0036 ladder preserved'
      );
    });

    it('REVOKE EXECUTE re-issued (defense-in-depth)', () => {
      assert.match(
        detailBlock,
        /REVOKE\s+EXECUTE\s+ON\s+FUNCTION\s+public\.get_member_detail\(uuid\)\s+FROM\s+PUBLIC,\s*anon/i,
        'must re-issue REVOKE since CREATE OR REPLACE preserves grants but does not re-apply revocations'
      );
    });

    it('NOTIFY pgrst issued (PostgREST schema cache reload)', () => {
      assert.match(MIGRATION_SQL, /NOTIFY\s+pgrst,\s*'reload schema'/i);
    });
  });

  describe('MemberDetailIsland.tsx — form field plumbing', () => {
    it('MemberDetail.member type carries interview_booking_url', () => {
      assert.match(
        ISLAND_SRC,
        /interview_booking_url:\s*string\s*\|\s*null/,
        'type must allow null (column nullable; new members default to NULL)'
      );
    });

    it('editBookingUrl state declared with empty-string default', () => {
      assert.match(
        ISLAND_SRC,
        /const\s+\[editBookingUrl,\s*setEditBookingUrl\]\s*=\s*useState\(\s*['"]['"]\s*\)/,
        'empty string default; openEdit re-initializes from m.interview_booking_url || ""'
      );
    });

    it('openEdit initializes editBookingUrl from member.interview_booking_url', () => {
      assert.match(
        ISLAND_SRC,
        /setEditBookingUrl\(m\.interview_booking_url\s*\|\|\s*['"]['"]/,
        'COALESCE to empty string for input value'
      );
    });

    it('saveEdit detects change against current value and includes in p_changes', () => {
      assert.match(
        ISLAND_SRC,
        /editBookingUrl\s*!==\s*\(m\.interview_booking_url\s*\|\|\s*['"]['"]\)\s*\)\s*changes\.interview_booking_url\s*=\s*editBookingUrl/,
        'unchanged value must not appear in p_changes — keeps audit log clean'
      );
    });

    it('save handler wires admin_update_member_audited (canonical RPC; not bare UPDATE)', () => {
      assert.match(
        ISLAND_SRC,
        /sb\.rpc\(\s*['"]admin_update_member_audited['"]/,
        'preserve audit trail via canonical RPC; do not switch to bare table UPDATE'
      );
    });

    it('input has id="interview_booking_url" and HTML5 url type', () => {
      assert.match(
        ISLAND_SRC,
        /id=["']interview_booking_url["']/,
        'stable id for label association + DOM probing'
      );
      assert.match(
        ISLAND_SRC,
        /<input[\s\S]*?id=["']interview_booking_url["'][\s\S]*?type=["']url["']/,
        'type="url" gives browser-native validation'
      );
    });

    it('input has pattern="^https?://.*" (HTML5 client-side validation)', () => {
      assert.match(
        ISLAND_SRC,
        /pattern=["']\^https\?:\/\/\.\*["']/,
        'matches SPEC #348 §3 Q2 — http or https, no stricter constraints'
      );
    });

    it('input renders i18n placeholder + title (validation message) + help span', () => {
      assert.match(
        ISLAND_SRC,
        /placeholder=\{t\(\s*['"]admin\.member\.bookingUrl\.placeholder['"]/,
        'placeholder shows example URL via i18n'
      );
      assert.match(
        ISLAND_SRC,
        /title=\{t\(\s*['"]admin\.member\.bookingUrl\.invalid['"]/,
        'title supplies validation message for pattern violation'
      );
      assert.match(
        ISLAND_SRC,
        /t\(\s*['"]admin\.member\.bookingUrl\.help['"]/,
        'help text below input clarifies leader-track uses cycle-level URL'
      );
    });
  });

  describe('plural wrapper [id].astro — i18n bundle injection', () => {
    it('imports buildPageI18n', () => {
      assert.match(
        WRAPPER_SRC,
        /import\s+\{\s*buildPageI18n\s*\}\s+from\s+['"][./]+i18n\/pageI18n['"]/,
        'page-i18n requires buildPageI18n helper'
      );
    });

    it('bundle covers admin.member namespace (required for new keys)', () => {
      assert.match(
        WRAPPER_SRC,
        /buildPageI18n\(\s*\[[^\]]*['"]admin\.member['"][^\]]*\]/,
        'admin.member.bookingUrl.* keys depend on admin.member namespace being in bundle'
      );
    });

    it('script id="page-i18n" injected so usePageI18n picks up bundle', () => {
      assert.match(
        WRAPPER_SRC,
        /<script\s+id=["']page-i18n["']\s+type=["']application\/json["']\s+set:html=\{i18nBundle\}/,
        'usePageI18n queries DOM for script#page-i18n; missing tag leaves keys at English fallback'
      );
    });
  });

  describe('i18n parity — all 6 keys × 3 langs', () => {
    for (const key of I18N_KEYS) {
      it(`${key} exists in pt-BR`, () => {
        assert.ok(
          DICT_PT_SRC.includes(`'${key}'`),
          `key ${key} missing from pt-BR dictionary`
        );
      });
      it(`${key} exists in en-US`, () => {
        assert.ok(
          DICT_EN_SRC.includes(`'${key}'`),
          `key ${key} missing from en-US dictionary`
        );
      });
      it(`${key} exists in es-LATAM`, () => {
        assert.ok(
          DICT_ES_SRC.includes(`'${key}'`),
          `key ${key} missing from es-LATAM dictionary`
        );
      });
    }
  });

  describe('forward-defense regressions (lock PM rules permanently)', () => {
    it('input pattern is NOT stricter than ^https?:// (SPEC #348 §3 Q2)', () => {
      // PM rule: deep links / Google Meet / Calendly URLs differ wildly; UI
      // must NOT impose a domain whitelist or trailing-slash mandate. Any
      // attempt to tighten the pattern beyond ^https?://.* is a regression.
      const STRICT_PATTERNS = [
        /pattern=["']\^https:\/\/[^"']*["']/, // https-only is too strict
        /pattern=["']\^https\?:\/\/[a-z]/i,    // anchoring a TLD is too strict
        /pattern=["']\^https\?:\/\/[^.]+\.[^"']*["']/, // mandates a dot is too strict
      ];
      for (const p of STRICT_PATTERNS) {
        assert.doesNotMatch(
          ISLAND_SRC,
          p,
          'spec forbids stricter regex — keep deep-link / arbitrary-provider flexibility'
        );
      }
    });

    it('migration does NOT introduce a DB CHECK constraint on interview_booking_url', () => {
      // SPEC #348 §3 Q2: ratified NO DB CHECK to keep flexibility. A regression
      // would be adding ALTER TABLE ... ADD CONSTRAINT in this file. Allow the
      // canonical comparison m.interview_booking_url IS DISTINCT FROM ... but
      // forbid CHECK / column constraint introductions.
      assert.doesNotMatch(
        MIGRATION_SQL,
        /ALTER\s+TABLE\s+public\.members[\s\S]*?ADD\s+CONSTRAINT[\s\S]*?interview_booking_url/i,
        'no CHECK constraint; UI handles format'
      );
      assert.doesNotMatch(
        MIGRATION_SQL,
        /CHECK\s*\([\s\S]*?interview_booking_url\s*~/i,
        'no CHECK using regex against interview_booking_url'
      );
    });

    it('saveEdit does NOT bypass admin_update_member_audited with a bare UPDATE', () => {
      // Regression watch: a future "simpler" save path that calls
      // sb.from('members').update({interview_booking_url:...}) would bypass the
      // audit log and the V4 manage_member gate. Forbidden.
      assert.doesNotMatch(
        ISLAND_SRC,
        /sb\s*\.\s*from\(\s*['"]members['"]\s*\)\s*\.\s*update\(\s*\{[^}]*interview_booking_url/,
        'saveEdit must keep going through admin_update_member_audited (canonical audit + gate)'
      );
    });

    it('admin_update_member_audited does NOT widen V4 gate beyond manage_member', () => {
      const updateBlock = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.admin_update_member_audited')[1]?.split('CREATE OR REPLACE FUNCTION public.get_member_detail')[0] || '';
      // Forbid silently swapping the gate to a broader capability that would
      // bypass GP-only member lifecycle rule (LGPD Art. 18).
      assert.doesNotMatch(
        updateBlock,
        /can_by_member\(v_actor_id,\s*'manage_platform'\)/,
        'do not relax to manage_platform — keeps GP-only invariant'
      );
      assert.doesNotMatch(
        updateBlock,
        /can_by_member\(v_actor_id,\s*'write'\)/,
        'do not relax to generic write — manage_member is the canonical gate'
      );
    });
  });

  describe('live DB body parity (skips if no SUPABASE env)', () => {
    if (!sb) {
      it.skip('live body checks skipped — SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
      return;
    }

    // NOTE: do NOT chain .catch() on sb.rpc() — PostgrestBuilder is a thenable,
    // not a Promise, so .catch() throws "not a function". Use try/catch around
    // await (or just check the {error} envelope returned by await).

    it('live admin_update_member_audited contains interview_booking_url branch', async () => {
      const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
      if (error || !Array.isArray(data)) return; // helper RPC absent — static body assertion still authoritative
      const fn = data.find(r => r.function_name === 'admin_update_member_audited');
      if (fn) {
        assert.match(fn.body, /interview_booking_url/, 'live body must contain new field');
      }
    });

    it('live get_member_detail member jsonb exposes interview_booking_url', async () => {
      const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
      if (error || !Array.isArray(data)) return; // helper RPC absent — static body assertion still authoritative
      const fn = data.find(r => r.function_name === 'get_member_detail');
      if (fn) {
        assert.match(fn.body, /'interview_booking_url'\s*,\s*m\.interview_booking_url/);
      }
    });
  });
});
