// tests/contracts/2477-lane-nao-escreve-pelo-mcp-do-nucleo.test.mjs
// Register in BOTH the "test:structural" and "test:contracts" whitelists in package.json (#1109).
// (Hermetic: runs the hook script with synthetic stdin, a temporary designation and a temporary lane registry.)
/**
 * #2477 — a lane does not write through the Nucleo MCP; the orchestrator does.
 *
 * 2026-10-09: the lanes run in auto mode, and the platform's own MCP (wiki, cards, minutes, attendance...) writes to the
 * shared database without going through Supabase, so the rule "the lane prepares, the orchestrator applies" had no lock
 * there. Decision of the GP the same day: deny Nucleo MCP writes to a non-orchestrator session that runs in a clone or
 * worktree of this repo or in a registered lane path; reads stay free; other projects are not affected.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const GATE = resolve(ROOT, '.claude/hooks/db-write-gate.py');
const DIR = mkdtempSync(join(tmpdir(), 'gate-nucleo-'));
const LANE = join(DIR, 'lane-x');
const OTHER = join(DIR, 'outro-projeto');
mkdirSync(LANE); mkdirSync(OTHER);
writeFileSync(join(DIR, 'orq'), 'sess-orq\t2026-10-09\tteste\n');
writeFileSync(join(DIR, 'reg.tsv'), `caminho\tbranch\taberta_em\tproposito\n${LANE}\tx\tx\tx\n`);

function decision(tool, input, session, cwd, gate = GATE) {
  const r = spawnSync('python3', [gate], {
    input: JSON.stringify({ tool_name: tool, tool_input: input, session_id: session, cwd }),
    env: { ...process.env, LANE_ORCH_FILE: join(DIR, 'orq'), LANE_REGISTRY: join(DIR, 'reg.tsv'), DB_GATE_QUEUE: '0,0' },
    encoding: 'utf8',
  });
  return r.stdout.trim() ? JSON.parse(r.stdout).hookSpecificOutput.permissionDecision : '-';
}
const N = 'mcp__claude_ai_Nucleo-ia__';

test('#2477 lane writes through the Nucleo MCP are denied (always-write and mixed tools, both server spellings)', () => {
  for (const [tool, input] of [
    [`${N}card_write`, { action: 'create' }],
    [`${N}wiki_write`, { action: 'draft' }],
    [`${N}meeting_minutes`, { action: 'write' }],
    [`${N}meeting_actions`, { action: 'acao-nova' }],
    ['mcp__claude_ai_nucleo-ia__attendance_record', {}],
  ]) assert.equal(decision(tool, input, 'lane', LANE), 'deny', `${tool} ${JSON.stringify(input)}`);
});

test('#2477 lane reads through the Nucleo MCP stay free', () => {
  for (const [tool, input] of [
    [`${N}card_get`, { card_id: 'x' }],
    [`${N}wiki_write`, { action: 'context' }],
    [`${N}meeting_minutes`, { action: 'read' }],
    [`${N}meeting_actions`, { action: 'list' }],
  ]) assert.equal(decision(tool, input, 'lane', LANE), '-', `${tool} ${JSON.stringify(input)}`);
});

test('#2477 controls: orchestrator writes, other projects are not affected', () => {
  assert.equal(decision(`${N}card_write`, { action: 'create' }, 'sess-orq', LANE), '-', 'orchestrator');
  assert.equal(decision(`${N}card_write`, { action: 'create' }, 'outra', OTHER), '-', 'session of another project');
});

test('#2477 mutation: a gate that ignores the registry lets a lane write', () => {
  const src = readFileSync(GATE, 'utf8');
  const mut = src.replace('if repo_is_this(cwd) or is_lane(cwd) or lane_registered(cwd):', 'if False:');
  assert.notEqual(mut, src, 'mutation did not apply');
  const p = join(DIR, 'gate-mut.py');
  writeFileSync(p, mut);
  assert.equal(decision(`${N}card_write`, { action: 'create' }, 'lane', LANE, p), '-', 'the mutated gate lets the lane write');
});
