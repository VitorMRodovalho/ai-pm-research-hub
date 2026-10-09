/**
 * #1742 — a varredura de leitura por nao-membro roda quando muda acesso, nao em todo push.
 *
 * MEDIDO em 09/10/2026 (pg_stat_statements, desde o reinicio do Postgres as 06:12Z): a RPC
 * `_audit_ghost_read_probe`, chamada uma vez por relacao do catalogo por
 * `leitura-por-nao-membro-derivada-do-catalogo.test.mjs`, leu 191.075 blocos em 2.464 chamadas, o
 * maior consumo constante de IO de disco do projeto (o Supabase alertou falta de orcamento de IO).
 * O que ela mede so muda com migration (ou com mudanca fora de PR, que a rodada noturna cobre).
 *
 * O que este guard prova, executando em vez de procurar string onde da:
 *   1. o passo de decisao do CI, extraido do ci.yml e rodado contra um `git` falso: migration no
 *      diff => 1; diff sem migration => 0; base ausente ou fetch que falha => 1 (na duvida, varre);
 *   2. o passo roda ANTES dos testes no job validate e exporta por GITHUB_ENV;
 *   3. o teste so pula com GHOST_READ_SWEEP=0 explicito, e os controles nao dependem dele;
 *   4. a rodada noturna existe, agendada, e roda o arquivo com GHOST_READ_SWEEP=1.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, chmodSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const ROOT = process.cwd();
const CI = resolve(ROOT, '.github/workflows/ci.yml');
const NIGHTLY = resolve(ROOT, '.github/workflows/ghost-read-sweep-nightly.yml');
const SWEEP = resolve(ROOT, 'tests/contracts/leitura-por-nao-membro-derivada-do-catalogo.test.mjs');
const STEP = 'Decide a varredura de leitura por nao-membro (#1742)';

/** Script do passo de decisao, lido do YAML (o mesmo texto que o runner executa). */
function stepScript(ciPath = CI) {
  const out = execFileSync('python3', ['-c', `
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
for st in d['jobs']['validate']['steps']:
    if st.get('name') == sys.argv[2]:
        print(st['run'], end='')
`, ciPath, STEP], { encoding: 'utf8' });
  assert.ok(out.length > 0, 'passo de decisao sumiu do job validate');
  return out;
}

/** Roda o passo com um `git` falso. files = saida de `git diff --name-only`; fetchFails = fetch sai 1. */
function decide({ base = 'abc123', files = '', fetchFails = false, ciPath } = {}) {
  const work = mkdtempSync(join(tmpdir(), 'varredura-'));
  mkdirSync(join(work, 'bin'));
  const git = join(work, 'bin', 'git');
  writeFileSync(git, `#!/usr/bin/env bash
case "$1" in
  fetch) ${fetchFails ? 'exit 1' : 'exit 0'} ;;
  diff) printf '%b' ${JSON.stringify(files)} ;;
esac
`);
  chmodSync(git, 0o755);
  const script = join(work, 'step.sh');
  writeFileSync(script, stepScript(ciPath));
  const envFile = join(work, 'github_env');
  writeFileSync(envFile, '');
  execFileSync('bash', ['-e', '-o', 'pipefail', script], {
    encoding: 'utf8',
    env: { PATH: `${join(work, 'bin')}:${process.env.PATH}`, BASE_SHA: base, GITHUB_ENV: envFile },
  });
  return readFileSync(envFile, 'utf8').match(/^GHOST_READ_SWEEP=(\d)$/m)?.[1];
}

test('#1742 (1) decisao: migration no diff varre; diff sem migration nao varre', () => {
  assert.equal(decide({ files: 'src/a.ts\nsupabase/migrations/20261009_x.sql\n' }), '1');
  assert.equal(decide({ files: 'src/a.ts\ntests/contracts/x.test.mjs\n' }), '0');
});

test('#1742 (1) na duvida, varre: base ausente, base zerada ou fetch que falha', () => {
  assert.equal(decide({ base: '', files: 'src/a.ts\n' }), '1');
  assert.equal(decide({ base: '0000000000000000000000000000000000000000', files: 'src/a.ts\n' }), '1');
  assert.equal(decide({ fetchFails: true, files: 'src/a.ts\n' }), '1');
});

test('#1742 (1) mutacao: um passo que comeca em 0 deixaria de varrer quando o diff falha', () => {
  const src = readFileSync(CI, 'utf8');
  const mut = src.replace('sweep=1; why="padrao: na duvida, varre"', 'sweep=0; why="padrao"');
  assert.notEqual(mut, src, 'mutacao nao aplicou');
  const p = join(mkdtempSync(join(tmpdir(), 'ci-mut-')), 'ci.yml');
  writeFileSync(p, mut);
  assert.equal(decide({ fetchFails: true, files: 'src/a.ts\n', ciPath: p }), '0',
    'o passo mutado deveria cair para 0, e e isso que as asserções acima impedem');
});

test('#1742 (2) o passo roda antes dos testes no job validate', () => {
  const nomes = execFileSync('python3', ['-c', `
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
print('\\n'.join(st.get('name', '') for st in d['jobs']['validate']['steps']))
`, CI], { encoding: 'utf8' }).split('\n');
  const i = nomes.indexOf(STEP), j = nomes.indexOf('Run Unit Tests');
  assert.ok(i >= 0 && j >= 0 && i < j, `ordem errada: decisao em ${i}, testes em ${j}`);
});

test('#1742 (3) o teste so pula com 0 explicito, e os controles nao dependem disso', () => {
  const src = readFileSync(SWEEP, 'utf8');
  assert.match(src, /const sweepOff = process\.env\.GHOST_READ_SWEEP === '0';/);
  assert.match(src, /test\('nenhuma relacao fora da allowlist e legivel por nao-membro', \{ skip: sweepSkip \}/);
  assert.match(src, /test\('controles: o instrumento diz SIM \(br_holidays\) e diz NAO \(persons\)', \{ skip: dbGated \? false : skipMsg \}/);
});

test('#1742 (4) a rodada noturna existe e varre o arquivo inteiro', () => {
  const y = readFileSync(NIGHTLY, 'utf8');
  assert.match(y, /schedule:\s*\n\s*- cron: '[^']+'/);
  assert.match(y, /GHOST_READ_SWEEP: '1'\s*\n\s*run: node --test [^\n]*tests\/contracts\/leitura-por-nao-membro-derivada-do-catalogo\.test\.mjs/);
});
