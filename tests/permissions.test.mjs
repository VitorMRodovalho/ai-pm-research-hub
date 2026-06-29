import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

// We test the permission logic directly
import {
  hasPermission,
  setSimulation,
  clearSimulation,
  getEffectivePermissions,
  TIER_PERMISSIONS,
  DESIGNATION_PERMISSIONS,
  TIER_LABELS,
  DESIGNATION_LABELS,
} from '../src/lib/permissions.ts';

// ── Types sanity ──
describe('permissions types', () => {
  it('all 12 tiers defined', () => {
    assert.equal(Object.keys(TIER_PERMISSIONS).length, 12);
  });

  it('all 13 designations defined', () => {
    assert.equal(Object.keys(DESIGNATION_PERMISSIONS).length, 13);
  });

  it('sponsor designation grants full read (no write) — Wave 1 Ivan/LIM', () => {
    const perms = DESIGNATION_PERMISSIONS.sponsor;
    // read surface present
    for (const p of ['admin.access', 'admin.members.view', 'admin.portfolio', 'admin.partners',
                     'admin.governance.view', 'board.view_all', 'board.view_global',
                     'data.view_members', 'event.view_all']) {
      assert.ok(perms.includes(p), `sponsor read perm missing: ${p}`);
    }
    // never any write/manage
    for (const p of perms) {
      assert.ok(!/\.(manage|create|edit|delete|anonymize)$/.test(p) && p !== 'admin.campaigns',
        `sponsor must be read-only, found write perm: ${p}`);
    }
  });

  it('tier labels cover all tiers', () => {
    for (const tier of Object.keys(TIER_PERMISSIONS)) {
      assert.ok(TIER_LABELS[tier], `Missing label for tier: ${tier}`);
      assert.ok(TIER_LABELS[tier].pt, `Missing pt label for tier: ${tier}`);
    }
  });

  it('designation labels cover all designations', () => {
    for (const d of Object.keys(DESIGNATION_PERMISSIONS)) {
      assert.ok(DESIGNATION_LABELS[d], `Missing label for designation: ${d}`);
    }
  });
});

// ── hasPermission real mode ──
describe('hasPermission (real mode)', () => {
  it('superadmin has all permissions', () => {
    const member = { is_superadmin: true, operational_role: 'guest' };
    assert.ok(hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'system.global_config'));
    assert.ok(hasPermission(member, 'board.delete_item'));
  });

  it('#670 chapter_liaison designation = ponto focal visibility (chapter/program analytics, NOT admin.access)', () => {
    const focal = { operational_role: 'candidate', designations: ['chapter_liaison'] };
    // grants the program/chapter VISIBILITY the focal point needs...
    assert.ok(hasPermission(focal, 'admin.analytics.chapter'), 'ponto focal must see Meu Capítulo');
    assert.ok(hasPermission(focal, 'admin.analytics'), 'ponto focal sees program analytics');
    assert.ok(hasPermission(focal, 'admin.portfolio'), 'ponto focal sees program portfolio');
    assert.ok(hasPermission(focal, 'admin.partners'), 'ponto focal sees partnerships read surface');
    assert.ok(hasPermission(focal, 'admin.sustainability'), 'ponto focal sees sustainability read surface');
    assert.ok(hasPermission(focal, 'admin.governance.view'), 'governance read');
    // ...but the designation does NOT grant broad admin shell-entry.
    assert.ok(!hasPermission(focal, 'admin.access'), 'designation must NOT grant admin.access');
    assert.ok(!hasPermission(focal, 'admin.members.manage'), 'no member management');
    assert.ok(!hasPermission(focal, 'content.curate'), 'no curation write');
    assert.ok(!hasPermission(focal, 'event.view_all'), 'no global event read');
    assert.ok(!hasPermission(focal, 'gamification.view_ranking'), 'no global ranking read');
  });

  it('#670 chapter_liaison operational_role is narrow read-only, not admin shell', () => {
    const focal = { operational_role: 'chapter_liaison', designations: [] };
    assert.ok(hasPermission(focal, 'admin.analytics.chapter'), 'operational role sees Meu Capítulo');
    assert.ok(hasPermission(focal, 'admin.analytics'), 'operational role sees program analytics');
    assert.ok(hasPermission(focal, 'admin.portfolio'), 'operational role sees program portfolio');
    assert.ok(hasPermission(focal, 'admin.partners'), 'operational role sees partnerships read surface');
    assert.ok(hasPermission(focal, 'admin.sustainability'), 'operational role sees sustainability read surface');
    assert.ok(hasPermission(focal, 'admin.governance.view'), 'operational role has governance read');
    assert.ok(!hasPermission(focal, 'admin.access'), 'operational role must NOT grant admin.access');
    assert.ok(!hasPermission(focal, 'admin.members.manage'), 'no member management');
    assert.ok(!hasPermission(focal, 'content.curate'), 'no curation write');
    assert.ok(!hasPermission(focal, 'event.view_all'), 'no global event read');
    assert.ok(!hasPermission(focal, 'gamification.view_ranking'), 'no global ranking read');
  });

  it('manager has admin.access', () => {
    const member = { operational_role: 'manager' };
    assert.ok(hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'admin.analytics'));
  });

  it('FU-3 institutional_auditor = aggregate read-only, no admin shell, no PII/write', () => {
    const auditor = { operational_role: 'institutional_auditor', designations: [] };
    // sees the curated AGGREGATE analytics surface...
    assert.ok(hasPermission(auditor, 'admin.analytics'), 'auditor sees program analytics');
    assert.ok(hasPermission(auditor, 'admin.analytics.chapter'), 'auditor sees chapter analytics');
    assert.ok(hasPermission(auditor, 'admin.portfolio'), 'auditor sees portfolio');
    assert.ok(hasPermission(auditor, 'data.view_analytics'), 'auditor sees analytics data');
    assert.ok(hasPermission(auditor, 'workspace.access'), 'auditor has workspace access');
    // ...but NEVER the admin shell, the member directory, finance/partner, governance, or any write.
    assert.ok(!hasPermission(auditor, 'admin.access'), 'auditor must NOT have admin shell entry');
    assert.ok(!hasPermission(auditor, 'admin.members.view'), 'auditor must NOT see member directory (PII)');
    assert.ok(!hasPermission(auditor, 'data.view_members'), 'auditor must NOT read members PII');
    assert.ok(!hasPermission(auditor, 'admin.partners'), 'auditor must NOT see partner management');
    assert.ok(!hasPermission(auditor, 'admin.sustainability'), 'auditor must NOT see finance');
    assert.ok(!hasPermission(auditor, 'admin.governance.view'), 'auditor must NOT read governance docs');
    // no write/manage of any kind
    for (const p of getEffectivePermissions(auditor)) {
      assert.ok(!/\.(manage|create|edit|delete|anonymize|sync|calculate)$/.test(p) && p !== 'admin.campaigns',
        `institutional_auditor must be read-only, found: ${p}`);
    }
  });

  it('researcher does NOT have admin.access', () => {
    const member = { operational_role: 'researcher' };
    assert.ok(!hasPermission(member, 'admin.access'));
  });

  it('researcher has board.view_own_tribe', () => {
    const member = { operational_role: 'researcher' };
    assert.ok(hasPermission(member, 'board.view_own_tribe'));
  });

  it('visitor has NO permissions', () => {
    const member = { operational_role: 'visitor' };
    assert.ok(!hasPermission(member, 'admin.access'));
    assert.ok(!hasPermission(member, 'workspace.access'));
    assert.ok(!hasPermission(member, 'board.view_own_tribe'));
  });

  it('designation adds permissions: researcher + curator gets admin.curation', () => {
    const member = { operational_role: 'researcher', designations: ['curator'] };
    assert.ok(hasPermission(member, 'admin.curation'));
    assert.ok(hasPermission(member, 'content.curate'));
  });

  it('curator gets admin.governance.view (governance dashboard access) without admin.access', () => {
    // Bug A (p65): curator needs to see Governança item in admin sidebar to read
    // pending IP ratification chains, signoffs status, comments — without relying
    // on email magic links. admin.governance.view is the surgical gate.
    const member = { operational_role: 'researcher', designations: ['curator'] };
    assert.ok(hasPermission(member, 'admin.governance.view'),
      'curator must have admin.governance.view (Bug A — Sarah governance flow)');
    assert.ok(!hasPermission(member, 'admin.access'),
      'curator must NOT have admin.access (would expose admin-only items)');
  });

  it('manager has admin.governance.view (preserves access after gate switch)', () => {
    const member = { operational_role: 'manager' };
    assert.ok(hasPermission(member, 'admin.governance.view'));
  });

  it('deputy_manager designation adds admin.access to tribe_leader', () => {
    const member = { operational_role: 'tribe_leader', designations: ['deputy_manager'] };
    assert.ok(hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'admin.analytics'));
    assert.ok(hasPermission(member, 'admin.governance.view'));
  });
});

// ── hasPermission simulation mode ──
describe('hasPermission (simulation mode)', () => {
  it('simulation overrides real permissions', () => {
    const member = { is_superadmin: true, operational_role: 'manager' };

    // Before simulation: superadmin has everything
    assert.ok(hasPermission(member, 'admin.access'));

    // Start simulation as visitor
    setSimulation({ active: true, tier: 'visitor', designations: [], tribe_id: null });
    assert.ok(!hasPermission(member, 'admin.access'));
    assert.ok(!hasPermission(member, 'workspace.access'));

    clearSimulation();
  });

  it('simulation as researcher shows correct permissions', () => {
    const member = { is_superadmin: true, operational_role: 'manager' };

    setSimulation({ active: true, tier: 'researcher', designations: [], tribe_id: 3 });
    assert.ok(!hasPermission(member, 'admin.access'));
    assert.ok(hasPermission(member, 'workspace.access'));
    assert.ok(hasPermission(member, 'board.view_own_tribe'));
    assert.ok(!hasPermission(member, 'board.view_all'));

    clearSimulation();
  });

  it('simulation with designation adds permissions', () => {
    const member = { is_superadmin: true, operational_role: 'manager' };

    setSimulation({ active: true, tier: 'researcher', designations: ['curator'], tribe_id: null });
    assert.ok(hasPermission(member, 'admin.curation'));
    assert.ok(hasPermission(member, 'content.curate'));
    assert.ok(!hasPermission(member, 'admin.access'));

    clearSimulation();
  });
});

// ── getEffectivePermissions ──
describe('getEffectivePermissions', () => {
  it('returns correct count for researcher', () => {
    const member = { operational_role: 'researcher' };
    const perms = getEffectivePermissions(member);
    assert.ok(perms.length > 0);
    assert.ok(perms.includes('workspace.access'));
    assert.ok(!perms.includes('admin.access'));
  });

  it('superadmin gets all unique permissions', () => {
    const member = { is_superadmin: true, operational_role: 'guest' };
    const perms = getEffectivePermissions(member);
    // Should have no duplicates
    assert.equal(perms.length, new Set(perms).size);
    assert.ok(perms.length > 30);
  });
});
