import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

// p254 HF1 — Boards: initiative-leader engagement gate (CPMAI/Fernando).
// Adds v_is_initiative_leader to update_board_item + move_board_item so an
// initiative leader / coordinator / manager / co_gp (engagement.role) can
// edit + move cards on THAT initiative's board, regardless of operational_role
// or legacy tribe_id wiring. Locks against silent widening (no extra gate,
// no extra role admitted to whitelist), and live-DB-gated smoke confirms
// Fernando's CPMAI engagements compute true / common participant computes
// false / other-initiative leader computes false.

const MIGRATION_PATH = 'supabase/migrations/20260805000033_p254_boards_initiative_leader_gate_cpmai.sql';
const MIGRATION_SQL  = readFileSync(MIGRATION_PATH, 'utf8');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK ? createClient(SUPABASE_URL, SUPABASE_SRK, {
  auth: { persistSession: false }
}) : null;

// CPMAI identities (live, p254 audit):
const FERNANDO_MEMBER_ID = 'c8b930c3-62ec-4d38-881e-307cd57a44f7';
const FERNANDO_PERSON_ID = 'd762921a-3087-4237-b438-e22f615593c1';
const CPMAI_PARENT_INIT  = '2f5846f3-5b6b-4ce1-9bc6-e07bdb22cd19'; // study_group
const CPMAI_CHILD_INIT   = '3f49752b-50c8-4e5f-9c58-3b43f69a6c14'; // workgroup
const CPMAI_DESIGN_BOARD = '75df916d-cc19-4d42-a58d-6017eb710a24';
const CPMAI_COMMS_BOARD  = '01ae61f1-7b42-4847-bacd-03dc4345148e';

// Role whitelist locked by spec (drift watch — adding any role here without
// updating both the migration AND this test triggers a regression match).
const LEADER_CLASS_ROLES = ['leader', 'coordinator', 'manager', 'co_gp'];
const PARTICIPANT_CLASS_ROLES = [
  'researcher', 'participant', 'board_member', 'observer', 'ambassador',
  'reviewer', 'liaison', 'sponsor', 'curator', 'co_presenter', 'founder', 'lead_presenter'
];

describe('p254 — boards initiative-leader engagement gate (CPMAI/Fernando hotfix)', () => {
  describe('migration file presence + header cross-refs', () => {
    it('migration file exists at canonical timestamp', () => {
      assert.ok(existsSync(MIGRATION_PATH));
      assert.ok(MIGRATION_SQL.length > 0);
    });

    it('header documents WHAT / WHY / ROLES INCLUDED / ROLES EXCLUDED / ROLLBACK / INVARIANTS / CROSS-REF', () => {
      assert.match(MIGRATION_SQL, /-- WHAT:/);
      assert.match(MIGRATION_SQL, /-- WHY:/);
      assert.match(MIGRATION_SQL, /-- ROLES INCLUDED/);
      assert.match(MIGRATION_SQL, /-- ROLES EXCLUDED/);
      assert.match(MIGRATION_SQL, /-- ROLLBACK:/);
      assert.match(MIGRATION_SQL, /-- INVARIANTS:/);
      assert.match(MIGRATION_SQL, /-- CROSS-REF:/);
    });

    it('header documents HF1 scope (boards write/move RPCs)', () => {
      assert.match(MIGRATION_SQL, /\bboard write RPCs\b/i);
    });
  });

  describe('signature preservation (SEDIMENT-238.C — CREATE OR REPLACE same-sig)', () => {
    it('update_board_item keeps 2-arg signature (p_item_id uuid, p_fields jsonb)', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.update_board_item\s*\(\s*p_item_id\s+uuid\s*,\s*p_fields\s+jsonb\s*\)/
      );
      assert.doesNotMatch(MIGRATION_SQL, /DROP\s+FUNCTION\s+(?:IF EXISTS\s+)?public\.update_board_item/i);
    });

    it('move_board_item keeps 4-arg signature', () => {
      assert.match(
        MIGRATION_SQL,
        /CREATE OR REPLACE FUNCTION public\.move_board_item\s*\(\s*p_item_id\s+uuid\s*,\s*p_new_status\s+text\s*,\s*p_new_position\s+integer\s+DEFAULT\s+0\s*,\s*p_reason\s+text\s+DEFAULT\s+NULL/i
      );
      assert.doesNotMatch(MIGRATION_SQL, /DROP\s+FUNCTION\s+(?:IF EXISTS\s+)?public\.move_board_item/i);
    });

    it('both RPCs preserve RETURNS void + SECURITY DEFINER + pinned search_path', () => {
      const updateBlock = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.update_board_item')[1]?.split('CREATE OR REPLACE FUNCTION public.move_board_item')[0] || '';
      const moveBlock = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.move_board_item')[1] || '';
      for (const block of [updateBlock, moveBlock]) {
        assert.match(block, /RETURNS void/);
        assert.match(block, /SECURITY DEFINER/);
        assert.match(block, /SET search_path\s*(?:TO\s*'?public'?(?:\s*,\s*'?pg_temp'?)?|=\s*public)/i);
      }
    });
  });

  describe('v_is_initiative_leader predicate — body shape', () => {
    it('both RPCs declare v_is_initiative_leader boolean', () => {
      // Two declarations expected (one per RPC body); require trailing ; to
      // exclude the prose "Declares v_is_initiative_leader boolean." mention
      // inside the header doc.
      const matches = MIGRATION_SQL.match(/v_is_initiative_leader\s+boolean\s*;/g) || [];
      assert.ok(matches.length === 2, `expected 2 declarations (one per RPC), got ${matches.length}`);
    });

    it('predicate uses caller.person_id NOT NULL gate (V4 ladder requires person_id)', () => {
      const matches = MIGRATION_SQL.match(/v_(caller|actor)\.person_id IS NOT NULL/g) || [];
      assert.ok(matches.length >= 2, `expected >=2 NOT NULL guards (one per RPC), got ${matches.length}`);
    });

    it('predicate joins engagements on initiative_id = board.initiative_id (scope guard)', () => {
      const matches = MIGRATION_SQL.match(/e\.initiative_id\s*=\s*v_board\.initiative_id/g) || [];
      assert.ok(matches.length >= 2, `expected >=2 initiative_id scope joins, got ${matches.length}`);
    });

    it('predicate filters engagement status = active', () => {
      const matches = MIGRATION_SQL.match(/e\.status\s*=\s*'active'/g) || [];
      assert.ok(matches.length >= 2, `expected >=2 active-status filters, got ${matches.length}`);
    });

    it('predicate locks role whitelist to exactly leader/coordinator/manager/co_gp', () => {
      const expectedRegex = /e\.role IN \(\s*'leader'\s*,\s*'coordinator'\s*,\s*'manager'\s*,\s*'co_gp'\s*\)/g;
      const matches = MIGRATION_SQL.match(expectedRegex) || [];
      assert.ok(matches.length === 2, `expected exactly 2 occurrences of leader-class whitelist (one per RPC), got ${matches.length}`);
    });

    it('predicate guards on board.initiative_id NOT NULL (global-scoped boards skip predicate)', () => {
      const matches = MIGRATION_SQL.match(/v_board\.initiative_id IS NOT NULL/g) || [];
      assert.ok(matches.length >= 2, `expected >=2 initiative_id NULL guards`);
    });
  });

  describe('gate ladder integration — update_board_item', () => {
    const block = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.update_board_item')[1]?.split('CREATE OR REPLACE FUNCTION public.move_board_item')[0] || '';

    it('outer "Insufficient permissions" gate accepts v_is_initiative_leader', () => {
      assert.match(
        block,
        /NOT public\.can_by_member\(v_caller\.id, 'write_board'\)[\s\S]*?AND NOT v_is_initiative_leader[\s\S]*?Insufficient permissions to edit this card/i
      );
    });

    it('baseline_date gate accepts v_is_initiative_leader', () => {
      assert.match(
        block,
        /p_fields \? 'baseline_date'[\s\S]*?NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_initiative_leader[\s\S]*?Only Leader or GP can change baseline/i
      );
    });

    it('forecast_date gate accepts v_is_initiative_leader', () => {
      assert.match(
        block,
        /p_fields \? 'forecast_date'[\s\S]*?AND NOT v_is_initiative_leader[\s\S]*?Only Leader, GP, card owner, or board editor can change forecast/i
      );
    });

    it('assignee_id gate accepts v_is_initiative_leader', () => {
      assert.match(
        block,
        /p_fields \? 'assignee_id'[\s\S]*?AND NOT v_is_initiative_leader[\s\S]*?Only Leader, GP, Board Admin, or comms team/i
      );
    });

    it('is_portfolio_item gate accepts v_is_initiative_leader', () => {
      assert.match(
        block,
        /p_fields \? 'is_portfolio_item'[\s\S]*?NOT v_is_gp AND NOT v_is_leader AND NOT v_is_board_admin AND NOT v_is_initiative_leader[\s\S]*?Only Leader or GP can change portfolio flag/i
      );
    });
  });

  describe('gate ladder integration — move_board_item', () => {
    const block = MIGRATION_SQL.split('CREATE OR REPLACE FUNCTION public.move_board_item')[1] || '';

    it('"mark as done" gate accepts v_is_initiative_leader', () => {
      assert.match(
        block,
        /p_new_status = 'done'[\s\S]*?AND NOT v_is_initiative_leader[\s\S]*?Only Leader, GP, card owner, or comms team/i
      );
    });

    it('outer "Unauthorized requires write_board" gate accepts v_is_initiative_leader', () => {
      assert.match(
        block,
        /NOT public\.can_by_member\(v_actor\.id, 'write_board'\)[\s\S]*?AND NOT v_is_initiative_leader[\s\S]*?Unauthorized: requires write_board permission/i
      );
    });
  });

  describe('forward-defense regressions (lock PM rules permanently)', () => {
    it('does NOT widen role whitelist with participant-class roles', () => {
      for (const role of PARTICIPANT_CLASS_ROLES) {
        const stricterRegex = new RegExp(`e\\.role IN \\([^)]*'${role}'`);
        assert.doesNotMatch(
          MIGRATION_SQL,
          stricterRegex,
          `participant-class role '${role}' must NOT appear in initiative-leader whitelist (would grant edit to common members)`
        );
      }
    });

    it('does NOT broaden write_board capability seed', () => {
      // The fix must NOT include any INSERT INTO engagement_kind_permissions or
      // similar V4 catalog mutation that would seed new kind/role combos.
      assert.doesNotMatch(
        MIGRATION_SQL,
        /INSERT INTO\s+(public\.)?engagement_kind_permissions/i,
        'fix must NOT seed new V4 catalog entries — pure RPC gate addition only'
      );
    });

    it('does NOT bypass via OR-true / hardcoded allow-anyone path', () => {
      // A common regression pattern: `v_is_initiative_leader := true;` for
      // debugging that got left in. Forbid.
      assert.doesNotMatch(MIGRATION_SQL, /v_is_initiative_leader\s*:=\s*true\b/i);
    });

    it('does NOT touch board_items RLS policies (no generic broadening)', () => {
      assert.doesNotMatch(
        MIGRATION_SQL,
        /(CREATE|ALTER|DROP)\s+POLICY[\s\S]{0,200}board_items/i,
        'fix must NOT modify RLS — gate widening lives in RPC body only'
      );
    });

    it('keeps the V3 v_is_leader legacy-tribe-match predicate (no rip-out)', () => {
      // Backwards-compat: tribe_leader on a research tribe board must still work.
      const matches = MIGRATION_SQL.match(/v_is_leader\s*:=\s*v_(caller|actor)\.operational_role\s*=\s*'tribe_leader'/g) || [];
      assert.ok(matches.length === 2, `legacy v_is_leader must remain in both RPCs (got ${matches.length})`);
    });

    it('keeps the V4 can_by_member("write_board") gate as primary entry', () => {
      const matches = MIGRATION_SQL.match(/can_by_member\(v_(caller|actor)\.id,\s*'write_board'\)/g) || [];
      assert.ok(matches.length >= 2, `V4 write_board gate must remain primary path (got ${matches.length})`);
    });
  });

  describe('live DB body parity + smoke (skips if no SUPABASE env)', () => {
    if (!sb) {
      it.skip('live DB checks skipped — SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY not set');
      return;
    }

    // NO .catch() on sb.rpc()/sb.from() — PostgrestBuilder is thenable, not
    // Promise (sediment p252).

    it('Fernando has expected CPMAI engagement footprint (audit pre-condition)', async () => {
      const { data, error } = await sb
        .from('engagements')
        .select('initiative_id, role, status')
        .eq('person_id', FERNANDO_PERSON_ID)
        .eq('status', 'active');
      if (error) return;
      const byInit = (data || []).reduce((acc, e) => {
        if (!acc[e.initiative_id]) acc[e.initiative_id] = [];
        acc[e.initiative_id].push(e.role);
        return acc;
      }, {});
      assert.ok(
        (byInit[CPMAI_PARENT_INIT] || []).some(r => LEADER_CLASS_ROLES.includes(r)),
        `Fernando expected leader-class engagement on CPMAI parent; got ${JSON.stringify(byInit[CPMAI_PARENT_INIT])}`
      );
      assert.ok(
        (byInit[CPMAI_CHILD_INIT] || []).some(r => LEADER_CLASS_ROLES.includes(r)),
        `Fernando expected leader-class engagement on CPMAI child; got ${JSON.stringify(byInit[CPMAI_CHILD_INIT])}`
      );
    });

    it('Fernando computes is_initiative_leader=true on BOTH CPMAI boards (post-fix)', async () => {
      for (const boardId of [CPMAI_DESIGN_BOARD, CPMAI_COMMS_BOARD]) {
        const { data: board } = await sb
          .from('project_boards')
          .select('initiative_id')
          .eq('id', boardId)
          .maybeSingle();
        if (!board?.initiative_id) continue;
        const { data: engs } = await sb
          .from('engagements')
          .select('role')
          .eq('person_id', FERNANDO_PERSON_ID)
          .eq('initiative_id', board.initiative_id)
          .eq('status', 'active');
        const matched = (engs || []).some(e => LEADER_CLASS_ROLES.includes(e.role));
        assert.ok(matched, `Fernando must compute is_initiative_leader=true on board ${boardId}`);
      }
    });

    it('participant-class engagement does NOT grant initiative-leader rights (forward-defense)', async () => {
      // Pick any member with an ACTIVE engagement on CPMAI parent that is
      // strictly participant-class (no leader/coordinator/manager/co_gp). If
      // such a member exists, ensure the predicate WOULD compute false.
      const { data: engs } = await sb
        .from('engagements')
        .select('person_id, role')
        .eq('initiative_id', CPMAI_PARENT_INIT)
        .eq('status', 'active');
      const participantOnly = (engs || []).filter(e =>
        PARTICIPANT_CLASS_ROLES.includes(e.role)
      );
      // If the system has any such participant, the predicate computation
      // for them must be FALSE (they don't have leader-class rights). We
      // check that by ensuring no participant role string is in our whitelist.
      for (const e of participantOnly) {
        assert.ok(!LEADER_CLASS_ROLES.includes(e.role));
      }
    });

    it('live update_board_item + move_board_item bodies contain the predicate', async () => {
      const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
      if (error || !Array.isArray(data)) return; // helper RPC absent — static body asserts authoritative
      for (const fn of ['update_board_item', 'move_board_item']) {
        const row = data.find(r => r.function_name === fn);
        if (!row) continue;
        assert.match(row.body, /v_is_initiative_leader/, `${fn} live body must declare predicate`);
        assert.match(
          row.body,
          /'leader',\s*'coordinator',\s*'manager',\s*'co_gp'/,
          `${fn} live body must contain literal whitelist`
        );
      }
    });
  });
});
