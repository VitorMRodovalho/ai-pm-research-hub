import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

/**
 * #1205 — guard da FIACAO do gate de identificador livre em <script> de .astro.
 *
 * O gate (`npm run lint:client-scripts`) existe porque um `<script>` de .astro e
 * empacotado como modulo ES: roda em strict mode, e um identificador livre vira
 * ReferenceError em runtime, nao global silencioso. Foi assim que `shareWa` viveu
 * em producao de 24/03/2026 ate 29/07/2026 em src/pages/profile.astro — clicar
 * "Salvar" sem alterar nenhum campo morria sem toast nenhum.
 *
 * Um gate que existe mas nao roda em CI e zero protecao (ver a licao
 * `reference-guard-test-never-wired-into-ci`), entao este arquivo afirma as tres
 * pontas da fiacao — script no package.json, step no workflow, config presente —
 * e ainda executa o gate para provar que ele passa hoje.
 */

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const ci = readFileSync('.github/workflows/ci.yml', 'utf8');

test('package.json expoe o script lint:client-scripts apontando para a config do gate', () => {
  const script = pkg.scripts?.['lint:client-scripts'];
  assert.ok(script, 'script lint:client-scripts ausente do package.json');
  assert.match(script, /eslint/, 'o gate precisa rodar eslint');
  assert.match(
    script,
    /eslint\.client-scripts\.config\.mjs/,
    'o gate precisa usar a config dedicada (a config principal cobre frontmatter e enterraria o achado)',
  );
  assert.match(script, /src\/\*\*\/\*\.astro/, 'o gate precisa varrer todos os .astro de src/');
});

test('o CI executa o gate (senao ele nao protege nada)', () => {
  assert.match(
    ci,
    /npm run lint:client-scripts/,
    'nenhum step do ci.yml roda `npm run lint:client-scripts`',
  );
});

test('a config do gate liga no-undef nos blocos de script virtuais', () => {
  const cfg = readFileSync('eslint.client-scripts.config.mjs', 'utf8');
  assert.match(cfg, /'no-undef':\s*'error'/, "no-undef precisa estar em 'error'");
  assert.match(
    cfg,
    /\*\.astro\/\*\.ts/,
    'a config precisa mirar os arquivos virtuais de <script> (**/*.astro/*.ts)',
  );
});

test('o gate passa no estado atual do repo', () => {
  // Se um <script> ganhar identificador livre, este subteste fica vermelho com o
  // arquivo e a linha — que e exatamente o ponto do gate.
  execFileSync('npm', ['run', '--silent', 'lint:client-scripts'], { stdio: 'pipe' });
});
