/**
 * A main só recebe mudança pela orquestradora (#2477; decisão do GP, 06/10/2026).
 *
 * Lane nenhuma sobe nada para a main em paralelo ao trabalho da orquestradora. O db-write-gate, que já
 * barrava escrita no banco para quem não é a orquestradora, passa a barrar também o que chega à main:
 * mergear PR, push para a main ou estando nela, push forçado ou de todas as branches, --admin, e pelo
 * MCP do GitHub o merge de PR e o arquivo gravado direto na main.
 *
 * O QUE ESTE GUARD AFIRMA, rodando o hook de verdade contra repositórios de mentira:
 *   A. a lane não mergeia nem sobe para a main; a orquestradora sim;
 *   B. push da própria branch e comandos de leitura seguem livres para a lane;
 *   C. outro repositório do portfólio não é afetado, a menos que o comando de gh cite este; cada ação é
 *      medida no diretório em que roda (cwd, `cd` anterior, `git -C`);
 *   D. sem orquestradora designada, ninguém mergeia (fecha por padrão);
 *   E. o MCP do GitHub segue a mesma regra;
 *   F. o settings.json leva as ferramentas do MCP do GitHub ao hook.
 *
 * Offline: git local e python3; nenhuma chamada ao banco nem ao GitHub.
 */

import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const HOOK = resolve(ROOT, '.claude/hooks/db-write-gate.py');
const ORQ_SID = '11111111-aaaa-4bbb-8ccc-000000000001';
const LANE_SID = '22222222-aaaa-4bbb-8ccc-000000000002';
let base; let principal; let lane; let outro; let orqFile; let semOrq;

before(() => {
  base = mkdtempSync(join(tmpdir(), 'main-gate-'));
  principal = join(base, 'principal');
  lane = join(base, 'wt-lane');
  outro = join(base, 'outro-repo');
  orqFile = join(base, 'orquestrador');
  semOrq = join(base, 'nao-existe.orquestrador');
  const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { stdio: 'pipe' });
  execFileSync('git', ['init', '-q', '-b', 'main', principal]);
  git(principal, 'config', 'user.email', 't@example.invalid');
  git(principal, 'config', 'user.name', 't');
  writeFileSync(join(principal, 'f'), 'x');
  git(principal, 'add', 'f');
  git(principal, 'commit', '-q', '-m', 'init');
  git(principal, 'remote', 'add', 'origin', 'https://github.com/exemplo/ai-pm-research-hub.git');
  git(principal, 'worktree', 'add', '-q', lane, '-b', 'lane');
  execFileSync('git', ['init', '-q', '-b', 'main', outro]);
  git(outro, 'remote', 'add', 'origin', 'https://github.com/exemplo/meridianiq.git');
  writeFileSync(orqFile, `${ORQ_SID}\t2026-10-06T00:00Z\tteste\n`);
});
after(() => { if (base) rmSync(base, { recursive: true, force: true }); });

function runHook(tool, cwd, sessionId, toolInput = {}, orch = orqFile) {
  const r = spawnSync('python3', [HOOK], {
    input: JSON.stringify({ tool_name: tool, cwd, session_id: sessionId, tool_input: toolInput }),
    env: { ...process.env, DB_GATE_SKIP_QUEUE: '1', LANE_ORCH_FILE: orch },
    encoding: 'utf8',
  });
  assert.equal(r.status, 0, `o hook sai com 0 (stderr: ${r.stderr})`);
  const out = (r.stdout || '').trim();
  return out ? JSON.parse(out).hookSpecificOutput : null;
}
const bash = (cwd, sid, command, orch) => runHook('Bash', cwd, sid, { command }, orch);
const negado = (out, oQue) => {
  assert.equal(out?.permissionDecision, 'deny', `${oQue}: tem de ser negado`);
  assert.match(out.permissionDecisionReason, /SO A ORQUESTRADORA MERGEIA E SOBE PARA A MAIN/);
};

test('A: a lane não mergeia nem sobe para a main; a orquestradora sim', () => {
  const proibidos = [
    'gh pr merge 12 --squash',
    'gh api -X PUT repos/VitorMRodovalho/ai-pm-research-hub/pulls/5/merge',
    'gh api repos/x/y/merges -f base=main -f head=lane',
    `gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: "x"}) { clientMutationId } }'`,
    `gh api graphql -f query='\nmutation {\n  enablePullRequestAutoMerge(input: {pullRequestId: "x"}) {\n    clientMutationId\n  }\n}'`,
    'gh pr review 5 --approve --admin',
    'git push origin main',
    'git push origin HEAD:main',
    'git push origin lane:refs/heads/main',
    'git push origin :main',
    'git push --force origin lane',
    'git push --force-with-lease origin lane',
    'git push -f origin lane',
    'git push origin +lane',
    'git push --all origin',
    'git push --mirror origin',
  ];
  for (const cmd of proibidos) {
    negado(bash(lane, LANE_SID, cmd), cmd);
    assert.equal(bash(lane, ORQ_SID, cmd), null, `${cmd}: a orquestradora passa`);
  }
  negado(bash(principal, LANE_SID, 'git push'), 'push sem refspec estando na main');
  negado(bash(principal, LANE_SID, 'git push origin HEAD'), 'push de HEAD estando na main');
  negado(bash(principal, LANE_SID, 'git push -u origin @'), 'push de @ estando na main');
  negado(bash(lane, LANE_SID, `git -C ${principal} push`), 'push com -C para um diretório que está na main');
  // O shell volta ao diretório da sessão a cada comando, então `cd <dir> && ...` é o padrão: a ação é
  // medida onde roda, não no cwd.
  negado(bash(lane, LANE_SID, `cd ${principal} && git push`), 'cd para o clone principal, que está na main');
  negado(bash(outro, LANE_SID, `cd ${lane} && git push origin main`), 'cd de outro repositório para a lane');
  negado(bash(outro, LANE_SID, `cd ${lane} && gh pr merge 5 --squash`), 'merge depois de cd para a lane');
  negado(bash(principal, LANE_SID, 'git commit -m "cd nada" ; git push'), 'cd citado em texto não desvia a medida');
});

test('B: push da própria branch e leitura seguem livres para a lane', () => {
  for (const cmd of [
    'git push -u origin lane',
    'git push',
    'git push origin lane:lane',
    'git push origin HEAD',
    'git push origin HEAD:refs/heads/lane',
    'git push origin --delete lane',
    `gh api graphql -f query='query { viewer { login } }'`,
    'gh pr create --title t --body b',
    'gh pr view 5',
    'gh pr checks 5',
    'git status',
  ]) {
    assert.equal(bash(lane, LANE_SID, cmd), null, `${cmd}: livre`);
  }
  assert.equal(bash(principal, LANE_SID, 'git push origin feature'), null, 'push de outra branch a partir do principal');
  assert.equal(bash(outro, LANE_SID, `cd ${lane} && git push`), null, 'cd para a lane e push da branch dela');
});

test('C: outro repositório não é afetado, a menos que o comando cite este', () => {
  assert.equal(bash(outro, LANE_SID, 'gh pr merge 3 --squash'), null);
  assert.equal(bash(outro, LANE_SID, 'git push origin main'), null);
  negado(bash(outro, LANE_SID, 'gh pr merge 3 -R VitorMRodovalho/ai-pm-research-hub'), 'comando que cita este repositório');
  assert.equal(bash(lane, LANE_SID, `git -C ${outro} push origin main`), null, 'push na main de outro repo a partir da lane');
  assert.equal(bash(lane, LANE_SID, `cd ${outro} && git push origin main`), null, 'cd para outro repo e push na main dele');
  assert.equal(bash(outro, LANE_SID, 'git commit -m "ver ai-pm-research-hub#1" && git push origin main'), null,
    'push de outro repo cujo texto de commit cita este');
});

test('D: sem orquestradora designada, ninguém mergeia', () => {
  negado(bash(lane, ORQ_SID, 'gh pr merge 12 --squash', semOrq), 'sem designação');
});

test('E: o MCP do GitHub segue a mesma regra', () => {
  const merge = { owner: 'VitorMRodovalho', repo: 'ai-pm-research-hub', pullNumber: 1 };
  negado(runHook('mcp__github__merge_pull_request', lane, LANE_SID, merge), 'merge pelo MCP');
  assert.equal(runHook('mcp__github__merge_pull_request', lane, ORQ_SID, merge), null);
  assert.equal(runHook('mcp__github__merge_pull_request', lane, LANE_SID, { ...merge, repo: 'meridianiq' }), null);
  const arquivo = { owner: 'VitorMRodovalho', repo: 'ai-pm-research-hub', path: 'x.md', content: 'x', message: 'm' };
  negado(runHook('mcp__github__create_or_update_file', lane, LANE_SID, { ...arquivo, branch: 'main' }), 'arquivo na main');
  negado(runHook('mcp__github__create_or_update_file', lane, LANE_SID, arquivo), 'sem branch, vale a main');
  assert.equal(runHook('mcp__github__create_or_update_file', lane, LANE_SID, { ...arquivo, branch: 'lane' }), null);
  negado(runHook('mcp__github__push_files', lane, LANE_SID, { ...arquivo, branch: 'main', files: [] }), 'push_files na main');
  assert.equal(runHook('mcp__github__create_pull_request', lane, LANE_SID, { ...arquivo, head: 'lane', base: 'main' }), null,
    'abrir PR pelo MCP segue livre');
});

test('F: o settings.json leva as ferramentas do MCP do GitHub ao hook', () => {
  const pre = JSON.parse(readFileSync(resolve(ROOT, '.claude/settings.json'), 'utf8')).hooks.PreToolUse;
  const gh = pre.find((e) => /mcp__github__merge_pull_request/.test(e.matcher || ''));
  assert.ok(gh, 'entrada do MCP do GitHub');
  for (const t of ['merge_pull_request', 'push_files', 'create_or_update_file', 'delete_file']) {
    assert.match(gh.matcher, new RegExp(`mcp__github__${t}`), `${t} no matcher`);
  }
  assert.match(gh.hooks[0].command, /db-write-gate\.py/);
  assert.ok(pre.some((e) => e.matcher === 'Bash' && /db-write-gate\.py/.test(e.hooks[0].command)), 'o Bash continua no gate');
});
