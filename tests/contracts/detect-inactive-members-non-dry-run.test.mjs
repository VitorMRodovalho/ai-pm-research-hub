/**
 * detect_inactive_members non-dry-run pre-cron safety contract
 *
 * Forward-defense for the cron-scheduled non-dry-run execution that will run
 * for the first time at sat 2026-05-23 09:30 BRT (5 days after p185 boot).
 *
 * Context:
 *   - p179 introduced detect_inactive_members(p_dry_run boolean DEFAULT true)
 *     with `INSERT INTO admin_audit_log (..., target_type, ...) VALUES (..., NULL, ...)`.
 *     The fn only ran with p_dry_run=true in prod (skips the INSERT block), so
 *     the latent bug (23502 NOT NULL violation on admin_audit_log.target_type)
 *     was invisible at runtime.
 *   - p180 council mid-sweep caught the latent bug via static review.
 *     Migration 20260690000000 fixed: NULL → 'system_event' explicit.
 *   - The fix has NEVER been exercised at runtime — every call so far is dry_run=true.
 *
 * Runtime exercise (one-time, p185 boot 2026-05-17 via MCP execute_sql):
 *   BEGIN; UPDATE site_config SET value='0'::jsonb WHERE key='inactivity_threshold_days';
 *   SELECT detect_inactive_members(false); ROLLBACK;
 *   → candidates_count=49, managers_notified=2, success=true, ZERO constraint errors.
 *   Confirmed INSERTs into notifications + admin_audit_log (target_type='system_event')
 *   work correctly. ROLLBACK reverted threshold to 180 + 0 persisted rows.
 *   Cron sat 2026-05-23 09:30 BRT is now GREEN for first multi-leader V4 execution.
 *
 * Coverage gap (p185) → CLOSED p186 (OPP-185.A):
 *   Originally, with production threshold=180, candidates_count may be 0 at CI
 *   time, skipping the IF block and bypassing INSERT-path coverage. p186 added
 *   the test helper RPC _test_detect_inactive_with_threshold(int) which forces
 *   candidates>0 by lowering the threshold within a tx=rollback request. Test #3
 *   below uses it to deterministically exercise the INSERT branch in CI.
 *
 * Misuse-path defensive restore (p187 LOW-186.E):
 *   Test #4 below verifies that even when the caller forgets Prefer: tx=rollback,
 *   the helper's defensive site_config restore at end-of-function body fires and
 *   the inactivity_threshold_days override does not leak into prod state. Uses
 *   threshold=10000 (no candidates → no INSERTs) so no cleanup is needed.
 *
 * What this test does:
 *   1. Calls detect_inactive_members(p_dry_run := true) via service_role:
 *      validates response shape (candidates array, counters, no errors).
 *   2. Calls detect_inactive_members(p_dry_run := false) with `Prefer: tx=rollback`
 *      header so all INSERT side effects (notifications + admin_audit_log) are
 *      rolled back at request end. PostgREST honors tx=rollback for stateless
 *      RPC calls when the role can use it (service_role permitted).
 *   3. Calls _test_detect_inactive_with_threshold(0) with `Prefer: tx=rollback`:
 *      forces candidates>0 so the INSERT branch executes deterministically in CI.
 *      Asserts managers_notified>0 and candidates_count>0 — hermetic INSERT-path
 *      coverage that doesn't depend on prod state at test time.
 *   4. Calls _test_detect_inactive_with_threshold(100000) WITHOUT tx=rollback
 *      so the request runs in PostgREST commit mode. Asserts threshold_days
 *      echoes 100000 (override active) and post-call
 *      site_config.inactivity_threshold_days = 180 (defensive restore worked).
 *      threshold=100000 (~274 years; physically unreachable) keeps candidates=0
 *      so the INSERT branch never fires and no cleanup is needed.
 *   In all four cases, if the contract breaks at runtime the test fails BEFORE
 *   the next scheduled cron run (no 23502, no other constraint violation, no
 *   Unauthorized given service_role bypass).
 *
 * tx=rollback does NOT hold here — explicit cleanup is mandatory (#1170 / #231):
 *   The original design assumed `Prefer: tx=rollback` would undo the notifications +
 *   admin_audit_log INSERTs. It does NOT. detect_inactive_members is SECURITY DEFINER,
 *   and this Supabase's PostgREST does not roll back SECDEF INSERTs on tx=rollback —
 *   the same class the sibling behavioural invariants test hit (Issue #231, which
 *   switched to explicit cleanup). Consequence: for ~2 months every CI push/PR AND
 *   every local `npm test` run committed arm9_inactivity_alert rows to prod. Measured
 *   2026-07-21: 4216 rows, 100% titled "…há mais de 0 dias" (the threshold=0 helper is
 *   the only producer of that signature — the weekly cron uses 180 days and yields 0
 *   candidates), first seen 2026-05-21 (before the cron's first fire), timing correlated
 *   with ci.yml runs. THIS TEST was the "rogue caller" behind #1170. The #1170 dedup
 *   (6-day window) only throttled the in-app noise; it did not stop the writes.
 *   Fix (mirrors #231): each non-dry-run test anchors a cleanup window to SERVER time,
 *   then DELETEs the arm9 rows it commits and asserts zero residue. tx=rollback is left
 *   on the calls as harmless belt, but correctness no longer depends on it.
 *
 * Requires: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY. Skipped otherwise.
 *
 * Origin: WATCH-180.F closure (handoff p184 TIER A); prod-leak remediation #1170.
 */
import test from 'node:test';
import assert from 'node:assert/strict';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function callDetectInactive(dryRun, options = {}) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/detect_inactive_members`;
  const headers = {
    'Content-Type': 'application/json',
    'apikey': SERVICE_ROLE_KEY,
    'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
  };
  if (options.rollback) headers['Prefer'] = 'tx=rollback';

  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({ p_dry_run: dryRun }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC failed (dryRun=${dryRun}, rollback=${!!options.rollback}): HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

async function callTestHelperWithThreshold(threshold, options = {}) {
  // p186 OPP-185.A: helper RPC that forces candidates>0 by temporarily
  // overriding site_config.inactivity_threshold_days. Default: invoke with
  // Prefer: tx=rollback to guarantee zero persisted side effects.
  // Pass `{ rollback: false }` to test the misuse path (p187 LOW-186.E).
  const rollback = options.rollback !== false;
  const url = `${SUPABASE_URL}/rest/v1/rpc/_test_detect_inactive_with_threshold`;
  const headers = {
    'Content-Type': 'application/json',
    'apikey': SERVICE_ROLE_KEY,
    'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
  };
  if (rollback) headers['Prefer'] = 'tx=rollback';

  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify({ p_threshold: threshold }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Helper RPC failed (threshold=${threshold}, rollback=${rollback}): HTTP ${res.status} — ${text}`);
  }
  return await res.json();
}

async function readInactivityThreshold() {
  // Read site_config.inactivity_threshold_days via PostgREST as service_role.
  const url = `${SUPABASE_URL}/rest/v1/site_config?key=eq.inactivity_threshold_days&select=value`;
  const res = await fetch(url, {
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Read site_config failed: HTTP ${res.status} — ${text}`);
  }
  const rows = await res.json();
  if (!rows || rows.length !== 1) {
    throw new Error(`Expected exactly 1 site_config row for inactivity_threshold_days, got ${rows.length}`);
  }
  return rows[0].value;
}

// --- #1170 prod-leak remediation: explicit arm9 cleanup (tx=rollback is not honored
// for SECDEF INSERTs — see header + Issue #231). Each non-dry-run test commits real
// arm9_inactivity_alert rows and MUST remove them.

async function serverNowMinusMinutesIso(minutes) {
  // Anchor the cleanup window to SERVER time (PostgREST Date response header), never the
  // runner's local clock, so runner/DB skew can never let the window miss the rows we
  // just committed. Returns an ISO timestamp `minutes` before server-now.
  const res = await fetch(`${SUPABASE_URL}/rest/v1/`, {
    headers: { 'apikey': SERVICE_ROLE_KEY, 'Authorization': `Bearer ${SERVICE_ROLE_KEY}` },
  });
  const serverDate = res.headers.get('date');
  const base = serverDate ? Date.parse(serverDate) : Date.now();
  return new Date(base - minutes * 60 * 1000).toISOString();
}

async function deleteArm9Since(sinceIso) {
  // Remove only arm9 rows committed in this test's own window (type + created_at scope),
  // so a legitimate weekly-cron alert (different signature/window) is never touched.
  const url = `${SUPABASE_URL}/rest/v1/notifications`
    + `?type=eq.arm9_inactivity_alert&created_at=gte.${encodeURIComponent(sinceIso)}`;
  const res = await fetch(url, {
    method: 'DELETE',
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Prefer': 'return=minimal',
    },
  });
  if (!res.ok && res.status !== 404) {
    const text = await res.text();
    throw new Error(`arm9 cleanup DELETE failed: HTTP ${res.status} — ${text}`);
  }
}

/**
 * #2405 — a janela de dedup que a #1170 colocou DENTRO de `detect_inactive_members`:
 * um gestor que já recebeu alerta arm9 nos últimos 6 dias não recebe outro. O número 6 é o
 * mesmo literal do corpo da função; se ele mudar lá, este teste passa a medir a janela errada,
 * e é por isso que o nome da constante diz de onde ela veio.
 */
const DEDUP_WINDOW_DAYS_FROM_FUNCTION_BODY = 6;

/**
 * #2407 — quantas linhas de audit o HELPER já despejou (`threshold_days = 0` é a assinatura dele;
 * o cron semanal usa 180). Serve de asserção FALSIFICÁVEL depois que a subtransação passou a
 * desfazer as escritas: se alguém tirar a sentinela, este número cresce e o teste reprova.
 */
async function countHelperAuditRows() {
  const url = `${SUPABASE_URL}/rest/v1/admin_audit_log`
    + `?action=eq.arm9.inactivity_detection_run&changes-%3E%3Ethreshold_days=eq.0&select=id`;
  const res = await fetch(url, {
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Prefer': 'count=exact',
      'Range': '0-0',
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`helper audit count failed: HTTP ${res.status} — ${text}`);
  }
  const total = parseInt((res.headers.get('content-range') || '*/0').split('/')[1], 10);
  return Number.isFinite(total) ? total : 0;
}

async function countArm9Since(sinceIso) {
  const url = `${SUPABASE_URL}/rest/v1/notifications`
    + `?type=eq.arm9_inactivity_alert&created_at=gte.${encodeURIComponent(sinceIso)}&select=id`;
  const res = await fetch(url, {
    headers: {
      'apikey': SERVICE_ROLE_KEY,
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'Prefer': 'count=exact',
      'Range': '0-0',
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`arm9 residue count failed: HTTP ${res.status} — ${text}`);
  }
  // content-range header: "0-0/N" (or "*/0" when empty) — N is the exact total.
  const total = parseInt((res.headers.get('content-range') || '*/0').split('/')[1], 10);
  return Number.isFinite(total) ? total : 0;
}

test(
  canRun ? 'detect_inactive_members dry_run=true returns valid shape' : skipMsg,
  { skip: !canRun },
  async () => {
    const result = await callDetectInactive(true);
    assert.equal(result.success, true, 'success flag should be true');
    assert.equal(result.dry_run, true, 'dry_run flag should echo true');
    assert.equal(typeof result.threshold_days, 'number', 'threshold_days should be number');
    assert.ok(result.threshold_days > 0, 'threshold_days should be positive');
    assert.equal(typeof result.candidates_count, 'number', 'candidates_count should be number');
    assert.ok(result.candidates_count >= 0, 'candidates_count should be non-negative');
    assert.ok(Array.isArray(result.candidates), 'candidates should be array');
    assert.equal(result.managers_notified, 0, 'dry_run skips INSERT block → managers_notified must be 0');
  }
);

test(
  canRun ? 'detect_inactive_members dry_run=false with tx=rollback executes without constraint errors' : skipMsg,
  { skip: !canRun },
  async () => {
    // Pre-cron safety: validates that the runtime INSERT path (notifications +
    // admin_audit_log) does not throw 23502 or any other constraint violation.
    // #1170: tx=rollback does NOT undo the SECDEF INSERTs, so we clean up explicitly.
    // At prod threshold (180d) this call typically commits 0 rows, but guard anyway so
    // a future genuinely-inactive member cannot start leaking here.
    const since = await serverNowMinusMinutesIso(5);
    // #2405 — medir a janela ANTES da chamada, porque a própria chamada pode inserir linhas
    // e então a contagem passaria a incluir o que ela acabou de criar.
    const janelaIso = await serverNowMinusMinutesIso(DEDUP_WINDOW_DAYS_FROM_FUNCTION_BODY * 24 * 60);
    const suprimidosNaJanela = await countArm9Since(janelaIso);
    try {
      const result = await callDetectInactive(false, { rollback: true });
      assert.equal(result.success, true, 'success flag should be true (no INSERT errors)');
      assert.equal(result.dry_run, false, 'dry_run flag should echo false');
      assert.equal(typeof result.candidates_count, 'number', 'candidates_count should be number');
      assert.equal(typeof result.managers_notified, 'number', 'managers_notified should be number');
      assert.ok(result.managers_notified >= 0, 'managers_notified should be non-negative');

      // #2405 — TRÊS estados, não dois. `managers_notified = 0` é ambíguo entre "ninguém tem
      // manage_platform / o filtro quebrou" e "a janela de dedup de 6 dias da #1170 suprimiu,
      // que é o comportamento DESENHADO". A versão anterior tratava os dois como defeito e
      // nomeava a hipótese errada na mensagem.
      //
      // Medido em 21/09/2026: o cron `detect-inactive-members-weekly` (`0 12 * * 1`) rodou às
      // 12:00 UTC e notificou os 2 gestores; o CI rodou às 13:15 e recebeu 0, corretamente.
      // Reprovava de forma determinística de toda segunda 12:00 até 6 dias depois, ou seja a
      // semana inteira, em qualquer PR. Só não aparecia antes porque `candidates_count` era 0
      // e a asserção era condicional a uma condição que nunca ocorria: não podia falhar.
      if (result.candidates_count > 0) {
        if (suprimidosNaJanela === 0) {
          // A pré-condição agora é MEDIDA, não suposta: sem alerta na janela, quem tem a
          // capability tinha de receber.
          assert.ok(
            result.managers_notified > 0,
            `candidates_count=${result.candidates_count}, nenhum alerta arm9 na janela de `
            + `${DEDUP_WINDOW_DAYS_FROM_FUNCTION_BODY} dias, e ainda assim managers_notified=0: `
            + 'aí sim é manage_platform ausente ou filtro quebrado'
          );
        } else {
          // Janela ocupada: zero é o desfecho CORRETO. O teste afirma isso em vez de reprovar,
          // e continua reprovando se a supressão deixar passar alguém.
          assert.equal(
            result.managers_notified, 0,
            `havia ${suprimidosNaJanela} alerta(s) arm9 dentro da janela de `
            + `${DEDUP_WINDOW_DAYS_FROM_FUNCTION_BODY} dias, então a dedup da #1170 devia ter `
            + `suprimido TODOS, e ainda saíram ${result.managers_notified}`
          );
        }
      }
    } finally {
      await deleteArm9Since(since);
    }
    const residue = await countArm9Since(since);
    assert.equal(residue, 0,
      `test left ${residue} committed arm9 row(s) in prod (#1170/#231): detect_inactive_members ` +
      'is SECDEF and tx=rollback does not undo it — the test must delete what it commits.');
  }
);

test(
  canRun
    ? 'detect_inactive_members INSERT path hermetically exercised via _test helper (threshold=0)'
    : skipMsg,
  { skip: !canRun },
  async () => {
    // p186 OPP-185.A: hermetic INSERT-path coverage. The previous tx=rollback
    // test only exercises the INSERT block if prod has candidates_count > 0
    // at CI time. This test calls _test_detect_inactive_with_threshold(0)
    // which forces every active member to qualify as a candidate (last
    // attendance > 0 days ago is trivially true), guaranteeing v_count > 0
    // and the IF NOT p_dry_run AND v_count > 0 branch executes. The helper
    // restores site_config.inactivity_threshold_days defensively before
    // returning AND tx=rollback drops every persisted row at request end.
    // #1170: this is THE call that leaked to prod for ~2 months — threshold=0 makes
    // every active member a candidate, so the INSERT branch always fires and commits
    // arm9 rows that tx=rollback does not undo. Anchor the cleanup window to server
    // time BEFORE the call, then delete the committed rows and assert zero residue.
    const since = await serverNowMinusMinutesIso(5);
    // #2407 — o helper passa a ABORTAR a própria subtransação, então ele não commita mais nada.
    // Isso torna `residue === 0` abaixo verdadeiro por CONSTRUÇÃO, e um controle que não pode
    // falhar é decoração. As duas contagens abaixo são o controle que ficou no lugar dele: se a
    // sentinela sair do corpo, o audit cresce e este teste reprova.
    const auditAntes = await countHelperAuditRows();
    try {
      const result = await callTestHelperWithThreshold(0);

      assert.equal(result.success, true, 'success flag should be true');
      assert.equal(result.dry_run, false, 'dry_run must echo false (helper passes false)');
      assert.equal(result.threshold_days, 0, 'threshold_days should reflect the override value (0)');
      assert.ok(result.candidates_count > 0, 'threshold=0 must produce at least one candidate');
      assert.ok(Array.isArray(result.candidates), 'candidates should be array');
      assert.ok(
        result.managers_notified > 0,
        `INSERT path coverage requires managers_notified > 0 (got ${result.managers_notified}). ` +
        'On prod this is invariant (manage_platform is required for the platform to be ' +
        'operational). On CI/seed DBs: verify engagement_kind_permissions seeds at least ' +
        '1 row with manage_platform capability before treating this as a notifications ' +
        'INSERT branch regression.'
      );
    } finally {
      await deleteArm9Since(since);
    }
    const residue = await countArm9Since(since);
    assert.equal(residue, 0,
      `test left ${residue} committed arm9 row(s) in prod (#1170/#231): the threshold=0 ` +
      'helper commits real arm9 notifications and tx=rollback does not undo SECDEF INSERTs — ' +
      'the test must delete every row it commits, else it silently spams the admin inbox.');

    // #2407 — a asserção que PODE falhar. Desde a subtransação, o helper não deixa rastro
    // nenhum: nem notificação, nem linha de audit. Medido em 21/09/2026 ao aplicar a migration,
    // com um alerta de produção plantado na janela: ele SOBREVIVEU (2 antes, 2 depois), o audit
    // ficou em 3684 nas duas pontas, e o retorno continuou trazendo managers_notified = 2.
    const auditDepois = await countHelperAuditRows();
    assert.equal(auditDepois, auditAntes,
      `o helper gravou ${auditDepois - auditAntes} linha(s) de audit em produção (${auditAntes} -> ` +
      `${auditDepois}). Ele deveria abortar a própria subtransação e não deixar rastro: se a ` +
      'sentinela ND407 saiu do corpo, o DELETE de alertas alheios voltou junto (#2407).');
  }
);

test(
  canRun
    ? '_test_detect_inactive_with_threshold defensive site_config restore (misuse path: no tx=rollback)'
    : skipMsg,
  { skip: !canRun },
  async () => {
    // p187 LOW-186.E: misuse-path coverage. The helper documents that callers
    // MUST use Prefer: tx=rollback to avoid persisting notifications +
    // admin_audit_log INSERTs. The defensive restore of site_config at the
    // end of the function body is belt+suspenders that runs regardless of
    // whether the caller used tx=rollback. This test exercises that path:
    //   1. Choose threshold=100000 (~274 years; physically unreachable for any
    //      member record → 0 candidates → no INSERTs → no cleanup needed).
    //   2. Call the helper WITHOUT Prefer: tx=rollback so the request runs in
    //      PostgREST commit mode.
    //   3. Verify result.threshold_days = 10000 (proves the override was
    //      active during the call).
    //   4. Verify site_config.inactivity_threshold_days = 180 post-call
    //      (proves the defensive restore at end of function body fired and
    //      the override didn't leak into prod state).
    // If the defensive restore is removed in a future refactor, this test
    // fails by surfacing site_config still at 10000.
    const PROBE_THRESHOLD = 100000;
    const result = await callTestHelperWithThreshold(PROBE_THRESHOLD, { rollback: false });

    assert.equal(result.success, true, 'helper should succeed even without tx=rollback');
    assert.equal(result.threshold_days, PROBE_THRESHOLD, 'override should be active during call');
    assert.equal(result.candidates_count, 0,
      'threshold=100000 (~274 years) should produce 0 candidates (physically unreachable) — ' +
      'if this fails, the test threshold no longer prevents INSERTs and needs cleanup logic');

    const restoredValue = await readInactivityThreshold();
    assert.equal(restoredValue, 180,
      `defensive restore failed: site_config.inactivity_threshold_days = ${restoredValue}, ` +
      'expected 180 (prod default). The helper function body MUST restore the prior value ' +
      'before return so misuse (forgotten tx=rollback) does not leak the override into prod state.');
  }
);
