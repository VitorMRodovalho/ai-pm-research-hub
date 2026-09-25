/**
 * #2477: lane não escreve no banco compartilhado. O gate é MECÂNICO (hook PreToolUse), não prosa.
 *
 * Em 25/09/2026 uma sessão de lane aplicou 2 migrations direto em produção. O hook antigo só
 * perguntava, e só com fila ocupada; com fila vazia liberava em silêncio, e nada olhava QUEM pedia.
 *
 * Este teste EXERCITA o script (.claude/hooks/db-write-gate.py) com o mesmo JSON que o Claude Code
 * envia, a partir de um repositório git real com um worktree de lane, nos dois sentidos:
 *   - lane: apply_migration e execute_sql com escrita são NEGADOS; leitura passa;
 *   - principal: apply_migration e execute_sql passam (a checagem de fila fica desligada no teste).
 * E confere que o settings.json liga o script às ferramentas dos dois servidores MCP.
 *
 * Offline: git local e python3; nenhuma chamada ao banco nem ao GitHub.
 */
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const HOOK = resolve(ROOT, '.claude/hooks/db-write-gate.py');
let base; let main; let lane;

before(() => {
  base = mkdtempSync(join(tmpdir(), 'db-gate-'));
  main = join(base, 'main');
  lane = join(base, 'wt-lane');
  const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { stdio: 'pipe' });
  execFileSync('git', ['init', '-q', main]);
  git(main, 'config', 'user.email', 't@example.invalid');
  git(main, 'config', 'user.name', 't');
  writeFileSync(join(main, 'f'), 'x');
  git(main, 'add', 'f');
  git(main, 'commit', '-q', '-m', 'init');
  git(main, 'worktree', 'add', '-q', lane, '-b', 'lane');
});
after(() => { if (base) rmSync(base, { recursive: true, force: true }); });

function runHook(tool, cwd, toolInput = {}) {
  const r = spawnSync('python3', [HOOK], {
    input: JSON.stringify({ tool_name: tool, cwd, tool_input: toolInput }),
    env: { ...process.env, DB_GATE_SKIP_QUEUE: '1' },
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, `hook exits 0 (stderr: ${r.stderr})`);
  const out = (r.stdout || '').trim();
  return out ? JSON.parse(out).hookSpecificOutput : null;
}

const APPLY = 'mcp__supabase__apply_migration';
const SQL = 'mcp__claude_ai_Supabase__execute_sql';

test('lane: apply_migration é NEGADO, com o motivo que manda o pacote para a main', () => {
  const d = runHook(APPLY, lane, { name: 'x', query: 'create table t(i int)' });
  assert.ok(d, 'lane recebe uma decisão');
  assert.equal(d.permissionDecision, 'deny');
  assert.match(d.permissionDecisionReason, /LANE NAO ESCREVE NO BANCO/);
});

test('lane: execute_sql com escrita é NEGADO; leitura passa, e literal ou comentário não contam', () => {
  const w = runHook(SQL, lane, { query: 'update members set name = name where false' });
  assert.equal(w?.permissionDecision, 'deny', 'UPDATE em lane é negado');
  const ddl = runHook(SQL, lane, { query: '/* só olhando */ ALTER TABLE t ADD COLUMN c int' });
  assert.equal(ddl?.permissionDecision, 'deny', 'DDL em lane é negada');
  const r = runHook(SQL, lane, { query: "select 'DROP TABLE x' as txt -- delete everything\nfrom pg_class limit 1" });
  assert.equal(r, null, 'SELECT com DROP/DELETE só em literal e comentário passa');
});

test('principal: apply_migration e execute_sql passam (fila desligada no teste)', () => {
  assert.equal(runHook(APPLY, main, { name: 'x', query: 'create table t(i int)' }), null);
  assert.equal(runHook(SQL, main, { query: 'update members set name = name where false' }), null);
});

test('settings.json liga o gate às ferramentas dos dois servidores MCP', () => {
  const s = JSON.parse(readFileSync(resolve(ROOT, '.claude/settings.json'), 'utf8'));
  const entry = (s.hooks?.PreToolUse ?? []).find((h) => /db-write-gate\.py/.test(JSON.stringify(h.hooks)));
  assert.ok(entry, 'existe um PreToolUse que chama db-write-gate.py');
  for (const tool of [
    'mcp__claude_ai_Supabase__apply_migration', 'mcp__supabase__apply_migration',
    'mcp__claude_ai_Supabase__execute_sql', 'mcp__supabase__execute_sql',
  ]) {
    assert.ok(new RegExp(`^(?:${entry.matcher})$`).test(tool), `matcher cobre ${tool}`);
  }
});

// ── Registro de lanes (scripts/lane-registry.sh) ─────────────────────────────────────────────
// Exercitado de verdade: repositório temporário com um worktree e um registro temporário.
function registry(args, cwd, reg) {
  return spawnSync('bash', [resolve(ROOT, 'scripts/lane-registry.sh'), ...args], {
    cwd, env: { ...process.env, LANE_REGISTRY: reg }, encoding: 'utf8',
  });
}

test('registro: worktree fora do registro vira alerta na sessão principal; registrada, silêncio', () => {
  const reg = join(base, 'registro.tsv');
  const antes = registry(['check', main], main, reg);
  assert.equal(antes.status, 0);
  assert.match(antes.stdout, /LANES FORA DO REGISTRO \(1\)/, 'a worktree não registrada aparece');
  assert.ok(antes.stdout.includes('wt-lane'), 'o alerta nomeia o caminho da worktree');

  const r = registry(['register', lane, 'teste do registro'], main, reg);
  assert.equal(r.status, 0, r.stderr);
  const depois = registry(['check', main], main, reg);
  assert.equal(depois.stdout.trim(), '', 'registrada, a checagem fica em silêncio');
});

test('registro: dentro da própria lane a checagem não roda; registrar exige propósito', () => {
  const reg = join(base, 'registro-2.tsv');
  assert.equal(registry(['check', lane], lane, reg).stdout.trim(), '', 'sessão de lane não checa');
  const semProposito = registry(['register', lane], main, reg);
  assert.equal(semProposito.status, 2, 'sem propósito, o registro recusa');
});
