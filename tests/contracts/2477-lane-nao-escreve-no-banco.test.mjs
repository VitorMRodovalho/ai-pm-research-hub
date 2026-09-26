/**
 * #2477: só a sessão ORQUESTRADORA escreve no banco compartilhado. O gate é MECÂNICO (hook
 * PreToolUse), não prosa.
 *
 * Em 25/09/2026 duas migrations foram para produção a partir de uma sessão que NÃO era a
 * orquestradora. Ela rodava no clone principal, não numa worktree de lane. A primeira versão deste
 * gate decidia por DIRETÓRIO e não a teria barrado, por isso o discriminador agora é a SESSÃO.
 *
 * Este teste EXERCITA o script (.claude/hooks/db-write-gate.py) com o mesmo JSON que o Claude Code
 * envia, a partir de um repositório git real com um worktree de lane:
 *   - sessão que não é a orquestradora: negada no clone principal E na lane (o caso do incidente);
 *   - sem orquestradora designada: todos negados (falha fechada);
 *   - a orquestradora: passa (a checagem de fila fica desligada no teste);
 *   - leitura passa; literal e comentário não contam como escrita;
 *   - o servidor claude_ai só é barrado quando aponta para ESTE projeto.
 * E exercita o registro de lanes e a designação da orquestradora (scripts/lane-registry.sh).
 *
 * Offline: git local, bash e python3; nenhuma chamada ao banco nem ao GitHub.
 */
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const HOOK = resolve(ROOT, '.claude/hooks/db-write-gate.py');
const REGISTRY = resolve(ROOT, 'scripts/lane-registry.sh');
const THIS_PROJECT = 'ldrfrvwhxsmgaabwmaik';
const ORQ_SID = '11111111-aaaa-4bbb-8ccc-000000000001';
const OUTRA_SID = '22222222-aaaa-4bbb-8ccc-000000000002';
let base; let main; let lane; let outro; let orqFile; let semOrq;

before(() => {
  base = mkdtempSync(join(tmpdir(), 'db-gate-'));
  main = join(base, 'main');
  lane = join(base, 'wt-lane');
  orqFile = join(base, 'orquestrador');
  semOrq = join(base, 'nao-existe.orquestrador');
  const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { stdio: 'pipe' });
  execFileSync('git', ['init', '-q', main]);
  git(main, 'config', 'user.email', 't@example.invalid');
  git(main, 'config', 'user.name', 't');
  writeFileSync(join(main, 'f'), 'x');
  git(main, 'add', 'f');
  git(main, 'commit', '-q', '-m', 'init');
  git(main, 'worktree', 'add', '-q', lane, '-b', 'lane');
  // O Bash e decidido pelo REMOTO do repositorio (vale igual para clone e worktree) ou pela citacao do ref.
  git(main, 'remote', 'add', 'origin', 'https://github.com/exemplo/ai-pm-research-hub.git');
  outro = join(base, 'outro-repo');
  execFileSync('git', ['init', '-q', outro]);
  git(outro, 'remote', 'add', 'origin', 'https://github.com/exemplo/meridianiq.git');
  writeFileSync(orqFile, `${ORQ_SID}\t2026-09-25T00:00Z\tteste\n`);
});
after(() => { if (base) rmSync(base, { recursive: true, force: true }); });

function runHook(tool, cwd, sessionId, toolInput = {}, orch = orqFile) {
  const r = spawnSync('python3', [HOOK], {
    input: JSON.stringify({ tool_name: tool, cwd, session_id: sessionId, tool_input: toolInput }),
    env: { ...process.env, DB_GATE_SKIP_QUEUE: '1', LANE_ORCH_FILE: orch },
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, `hook exits 0 (stderr: ${r.stderr})`);
  const out = (r.stdout || '').trim();
  return out ? JSON.parse(out).hookSpecificOutput : null;
}

const APPLY = 'mcp__supabase__apply_migration';
const SQL = 'mcp__claude_ai_Supabase__execute_sql';
const CREATE = { name: 'x', query: 'create table t(i int)', project_id: THIS_PROJECT };
const UPDATE = { query: 'update members set name = name where false', project_id: THIS_PROJECT };

test('não-orquestradora NO CLONE PRINCIPAL é negada (o caso de 25/09 que a v1 deixava passar)', () => {
  const d = runHook(APPLY, main, OUTRA_SID, CREATE);
  assert.equal(d?.permissionDecision, 'deny', 'apply_migration do clone principal por outra sessão');
  assert.match(d.permissionDecisionReason, /SO A ORQUESTRADORA ESCREVE NO BANCO COMPARTILHADO/);
  assert.match(d.permissionDecisionReason, /clone principal/, 'o motivo diz onde a sessão roda');
  assert.ok(d.permissionDecisionReason.includes(ORQ_SID.slice(0, 8)), 'o motivo nomeia a orquestradora');
  assert.equal(runHook(SQL, main, OUTRA_SID, UPDATE)?.permissionDecision, 'deny', 'UPDATE idem');
});

test('não-orquestradora numa LANE ou fora de repositório é negada, e o motivo diz onde ela roda', () => {
  const d = runHook(APPLY, lane, OUTRA_SID, CREATE);
  assert.equal(d?.permissionDecision, 'deny');
  assert.match(d.permissionDecisionReason, /worktree de LANE/);
  // O hook de usuário roda em qualquer diretório: fora de repo, o motivo não pode dizer "clone principal".
  const fora = join(base, 'fora-de-repo'); mkdirSync(fora, { recursive: true });
  const f = runHook(APPLY, fora, OUTRA_SID, CREATE);
  assert.equal(f?.permissionDecision, 'deny');
  assert.match(f.permissionDecisionReason, /fora de um repositorio git/);
  assert.doesNotMatch(f.permissionDecisionReason, /clone principal/);
});

test('sem orquestradora designada, todos são negados, inclusive a sessão que seria a dela', () => {
  const d = runHook(APPLY, main, ORQ_SID, CREATE, semOrq);
  assert.equal(d?.permissionDecision, 'deny', 'falha fechada');
  assert.match(d.permissionDecisionReason, /NENHUMA sessao orquestradora/);
});

test('a orquestradora passa, no clone principal ou numa lane (fila desligada no teste)', () => {
  assert.equal(runHook(APPLY, main, ORQ_SID, CREATE), null);
  assert.equal(runHook(SQL, main, ORQ_SID, UPDATE), null);
  assert.equal(runHook(SQL, lane, ORQ_SID, UPDATE), null, 'a decisão é por sessão, não por diretório');
});

test('leitura passa para qualquer sessão; literal e comentário não contam; DDL em comentário de bloco conta', () => {
  const leitura = { query: "select 'DROP TABLE x' as txt -- delete everything\nfrom pg_class limit 1", project_id: THIS_PROJECT };
  assert.equal(runHook(SQL, lane, OUTRA_SID, leitura), null, 'SELECT com DROP/DELETE só em literal e comentário');
  const ddl = { query: '/* só olhando */ ALTER TABLE t ADD COLUMN c int', project_id: THIS_PROJECT };
  assert.equal(runHook(SQL, lane, OUTRA_SID, ddl)?.permissionDecision, 'deny', 'ALTER depois do comentário');
});

test('servidor claude_ai: só barra quando o project_id é ESTE projeto', () => {
  const outro = { query: 'update t set i = 1', project_id: 'aaaaaaaaaaaaaaaaaaaa' };
  assert.equal(runHook(SQL, main, OUTRA_SID, outro), null, 'escrita em outro projeto não é deste gate');
  assert.equal(runHook(SQL, main, OUTRA_SID, UPDATE)?.permissionDecision, 'deny', 'mesmo SQL, este projeto');
  // O servidor do .mcp.json (mcp__supabase__) não leva project_id: o gate lê o project_ref do
  // .mcp.json mais próximo. Sem referência, barra; com OUTRO projeto (o hook de usuário roda em todo
  // o portfólio), não é deste gate.
  const upd = { query: 'update t set i = 1' };
  assert.equal(runHook('mcp__supabase__execute_sql', main, OUTRA_SID, upd)?.permissionDecision, 'deny', 'sem .mcp.json');
  const outroRepo = join(base, 'outro-projeto'); mkdirSync(join(outroRepo, 'sub'), { recursive: true });
  writeFileSync(join(outroRepo, '.mcp.json'), JSON.stringify({ mcpServers: { supabase: { url: 'https://mcp.supabase.com/mcp?project_ref=zzzzzzzzzzzzzzzzzzzz' } } }));
  assert.equal(runHook('mcp__supabase__execute_sql', join(outroRepo, 'sub'), OUTRA_SID, upd), null, '.mcp.json de outro projeto');
  const esteRepo = join(base, 'este-projeto'); mkdirSync(esteRepo, { recursive: true });
  writeFileSync(join(esteRepo, '.mcp.json'), JSON.stringify({ mcpServers: { supabase: { url: `https://mcp.supabase.com/mcp?project_ref=${THIS_PROJECT}` } } }));
  assert.equal(runHook('mcp__supabase__execute_sql', esteRepo, OUTRA_SID, upd)?.permissionDecision, 'deny', '.mcp.json deste projeto');
});

// ── Bash (pacote A, 25/09): token de gestao, CLI do Supabase e psql ──────────────────────────────
const bash = (cwd, sid, command, orch) => runHook('Bash', cwd, sid, { command }, orch);
const ARRISCADOS = [
  'curl -s -X POST https://api.supabase.com/v1/projects/x/database/query -d @q.json',
  'supabase db push --linked',
  'npx supabase migration list',
  'supabase functions deploy nucleo-mcp --no-verify-jwt',
  'psql "$DATABASE_URL" -c "select 1"',
  'npm run db:types',
  'with-supabase-token supabase gen types typescript',
  'cat ~/.config/supabase-mgmt/token',
  'echo $SUPABASE_ACCESS_TOKEN | wc -c',
];

test('Bash: nao-orquestradora neste repositorio e negada nos caminhos com token, CLI ou psql', () => {
  for (const cwd of [main, lane]) {
    for (const cmd of ARRISCADOS) {
      const d = bash(cwd, OUTRA_SID, cmd);
      assert.equal(d?.permissionDecision, 'deny', `negado: ${cmd} (${cwd === lane ? 'lane' : 'principal'})`);
    }
  }
  assert.match(bash(lane, OUTRA_SID, 'supabase db push').permissionDecisionReason, /NAO e a orquestradora/);
});

test('Bash: comando comum passa, e a orquestradora passa em tudo', () => {
  for (const cmd of ['git status --short', 'ls supabase/migrations | tail -3', 'npm test', 'node --test tests/contracts/x.test.mjs']) {
    assert.equal(bash(lane, OUTRA_SID, cmd), null, `livre: ${cmd}`);
  }
  for (const cmd of ARRISCADOS) assert.equal(bash(main, ORQ_SID, cmd), null, `orquestradora: ${cmd}`);
});

test('Bash: outro repositorio do portfolio mantem a propria CLI, salvo se citar ESTE projeto', () => {
  assert.equal(bash(outro, OUTRA_SID, 'supabase db push --linked'), null, 'CLI do outro projeto');
  assert.equal(bash(outro, OUTRA_SID, 'with-supabase-token supabase functions deploy f'), null, 'wrapper no outro projeto');
  const d = bash(outro, OUTRA_SID, `curl https://api.supabase.com/v1/projects/${THIS_PROJECT}/database/query`);
  assert.equal(d?.permissionDecision, 'deny', 'citar o ref deste projeto de outro lugar continua negado');
});

test('Bash: sem orquestradora designada, os caminhos arriscados sao negados a todos', () => {
  assert.equal(bash(main, ORQ_SID, 'supabase db push', semOrq)?.permissionDecision, 'deny');
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
  const bashEntry = (s.hooks?.PreToolUse ?? []).find((h) => h.matcher === 'Bash' && /db-write-gate\.py/.test(JSON.stringify(h.hooks)));
  assert.ok(bashEntry, 'existe um PreToolUse de Bash que chama db-write-gate.py');
});

// ── Registro de lanes e designação da orquestradora (scripts/lane-registry.sh) ─────────────────
// Exercitado de verdade: repositório temporário com um worktree, registro e designação temporários.
function registry(args, cwd, env, input = '') {
  return spawnSync('bash', [REGISTRY, ...args], {
    cwd, input, encoding: 'utf8',
    env: { ...process.env, LANE_GATE_COPY: join(base, 'sem-copia.py'), ...env },
  });
}

test('registro: worktree fora do registro vira alerta na sessão principal; registrada, silêncio', () => {
  const env = { LANE_REGISTRY: join(base, 'registro.tsv'), LANE_ORCH_FILE: orqFile };
  const antes = registry(['check', main], main, env);
  assert.equal(antes.status, 0);
  assert.match(antes.stdout, /LANES FORA DO REGISTRO \(1\)/, 'a worktree não registrada aparece');
  assert.ok(antes.stdout.includes('wt-lane'), 'o alerta nomeia o caminho da worktree');

  const r = registry(['register', lane, 'teste do registro'], main, env);
  assert.equal(r.status, 0, r.stderr);
  const depois = registry(['check', main], main, env);
  assert.equal(depois.stdout.trim(), '', 'registrada e com orquestradora designada, a checagem fica em silêncio');
});

test('registro: dentro da própria lane a checagem não roda; registrar exige propósito', () => {
  const env = { LANE_REGISTRY: join(base, 'registro-2.tsv'), LANE_ORCH_FILE: semOrq };
  assert.equal(registry(['check', lane], lane, env).stdout.trim(), '', 'sessão de lane não checa');
  assert.equal(registry(['register', lane], main, env).status, 2, 'sem propósito, o registro recusa');
});

test('orquestradora: designar exige nota; o SessionStart diz a cada sessão se ela é ou não', () => {
  const orq = join(base, 'designada.orquestrador');
  const env = { LANE_REGISTRY: join(base, 'registro.tsv'), LANE_ORCH_FILE: orq };
  assert.match(registry(['check', main], main, env).stdout, /NENHUMA SESSAO ORQUESTRADORA/, 'sem designação, alerta');

  assert.equal(registry(['orquestrador', ORQ_SID], main, env).status, 2, 'sem nota, recusa');
  const d = registry(['orquestrador', ORQ_SID, 'GP, teste'], main, env);
  assert.equal(d.status, 0, d.stderr);
  assert.equal(readFileSync(orq, 'utf8').split('\t')[0], ORQ_SID, 'o primeiro campo é o session_id');

  const ela = registry(['check', main], main, env, JSON.stringify({ session_id: ORQ_SID }));
  assert.match(ela.stdout, /e a ORQUESTRADORA designada/);
  const outra = registry(['check', main], main, env, JSON.stringify({ session_id: OUTRA_SID }));
  assert.match(outra.stdout, /NAO e a orquestradora/);

  // E o gate lê a mesma designação que o registro escreveu.
  assert.equal(runHook(APPLY, main, ORQ_SID, CREATE, orq), null);
  assert.equal(runHook(APPLY, main, OUTRA_SID, CREATE, orq)?.permissionDecision, 'deny');
});

test('cópia do gate usada pelo hook de usuário: divergir do repo vira alerta', () => {
  mkdirSync(join(main, '.claude/hooks'), { recursive: true });
  writeFileSync(join(main, '.claude/hooks/db-write-gate.py'), 'versao-do-repo\n');
  const copia = join(base, 'copia.py');
  const env = { LANE_REGISTRY: join(base, 'registro.tsv'), LANE_ORCH_FILE: orqFile, LANE_GATE_COPY: copia };
  writeFileSync(copia, 'versao-antiga\n');
  assert.match(registry(['check', main], main, env).stdout, /copia do gate .* difere/);
  writeFileSync(copia, 'versao-do-repo\n');
  assert.equal(registry(['check', main], main, env).stdout.trim(), '', 'iguais, silêncio');
});
