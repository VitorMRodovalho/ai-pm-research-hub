// tests/contracts/2477-gate-falha-fechada-na-escrita.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
// (Hermetic: runs the hook script with synthetic stdin and a temporary designation file; no network, no DB.)
/**
 * #2477 — when the DB write gate itself fails, a WRITE path fails closed and ordinary Bash fails open.
 *
 * Until 2026-10-09 every failure let the call through: unreadable stdin returned 0, and an exception inside decide()
 * made Python exit 1, which Claude Code treats as a NON-blocking error (code.claude.com/docs/en/hooks). Decision of the
 * GP the same day: fail closed on write paths (exit 2 blocks whatever the JSON says), fail open with a loud warning on
 * everything else, because the hook runs on every Bash call of the machine.
 *
 * Each case runs the real script. The controls at the end prove the normal decisions did not move.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const GATE = resolve(ROOT, '.claude/hooks/db-write-gate.py');
const DIR = mkdtempSync(join(tmpdir(), 'gate-'));
const ORQ = join(DIR, 'orq');
writeFileSync(ORQ, 'sess-orq\t2026-10-09\tteste\n');

function run(stdin, { inject = false, queue = '0,0', gate = GATE } = {}) {
  const r = spawnSync('python3', [gate], {
    input: stdin,
    env: { ...process.env, LANE_ORCH_FILE: ORQ, DB_GATE_QUEUE: queue, DB_GATE_INJECT_ERROR: inject ? '1' : '' },
    encoding: 'utf8',
  });
  let decision = '-';
  if (r.stdout.trim()) decision = JSON.parse(r.stdout).hookSpecificOutput.permissionDecision;
  return { rc: r.status, decision, stderr: r.stderr };
}
const ev = (tool, input, session = 'sess-orq') => JSON.stringify({ tool_name: tool, tool_input: input, session_id: session, cwd: ROOT });
const APPLY = (s) => ev('mcp__supabase__apply_migration', { name: 'x', query: 'select 1' }, s);

test('#2477 write path + gate error -> blocked (exit 2), reason on stderr', () => {
  for (const stdin of [APPLY('sess-orq'), ev('mcp__supabase__execute_sql', { query: 'select 1' }),
    ev('Bash', { command: 'psql -c 1' }), ev('mcp__github__merge_pull_request', { repo: 'ai-pm-research-hub' })]) {
    const r = run(stdin, { inject: true });
    assert.equal(r.rc, 2, `expected exit 2 for ${stdin.slice(0, 60)}`);
    assert.match(r.stderr, /CAMINHO DE ESCRITA/);
  }
});

test('#2477 ordinary Bash + gate error -> proceeds (exit 0) with a warning', () => {
  const r = run(ev('Bash', { command: 'ls -la' }), { inject: true });
  assert.equal(r.rc, 0);
  assert.equal(r.decision, '-');
  assert.match(r.stderr, /AVISO DB-WRITE-GATE/);
});

test('#2477 unreadable stdin: write text -> blocked, other text -> warning', () => {
  assert.equal(run('lixo { apply_migration').rc, 2);
  const r = run('lixo { qualquer coisa');
  assert.equal(r.rc, 0);
  assert.match(r.stderr, /AVISO DB-WRITE-GATE/);
});

test('#2477 controls: normal decisions unchanged', () => {
  assert.deepEqual([run(APPLY('sess-orq')).rc, run(APPLY('sess-orq')).decision], [0, '-'], 'orchestrator, empty queue: allow');
  assert.equal(run(APPLY('sess-orq'), { queue: '1,0' }).decision, 'ask', 'orchestrator, busy queue: ask');
  assert.equal(run(APPLY('outra')).decision, 'deny', 'other session: deny');
});

test('#2477 mutation: a gate that fails open on write paths is caught', () => {
  const src = readFileSync(GATE, 'utf8');
  const mut = src.replace('        return 2\n    print(f"AVISO', '        return 0\n    print(f"AVISO');
  assert.notEqual(mut, src, 'mutation did not apply');
  const p = join(DIR, 'gate-mut.py');
  writeFileSync(p, mut);
  assert.equal(run(APPLY('sess-orq'), { inject: true, gate: p }).rc, 0, 'the mutated gate lets the write through');
});
