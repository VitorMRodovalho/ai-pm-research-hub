import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

/**
 * #1513 — guard da FIACAO dos smokes de EF deployada.
 *
 * `tests/edge-functions/ef-smoke.test.mjs` e o unico lugar do repo que verifica
 * auth de Edge Function DEPLOYADA (bate em producao). Ele ficou mudo por meses:
 * o step `Run Unit Tests` nunca exportou SUPABASE_ANON_KEY, entao o arquivo
 * rodava, pulava, e o CI ficava verde sem ter testado nada — a lacuna que os 4
 * PRs do #1513 declararam como limite conhecido.
 *
 * Sao DUAS maneiras independentes de voltar ao mudo, e uma nao cobre a outra:
 *   (a) tirar a env var do step   -> o proprio ef-smoke grita (assert IS_CI),
 *                                    desde que ele ainda rode;
 *   (b) tirar o arquivo do `npm test` -> (a) nunca executa, logo nao pode gritar.
 *       Essa e a classe "guard test nunca foi ligado no CI".
 *
 * Este arquivo fecha as duas de fora.
 */

const repoRoot = new URL('../../', import.meta.url);
const readRepo = (rel) => readFileSync(new URL(rel, repoRoot), 'utf8');

const EF_SMOKE_PATH = 'tests/edge-functions/ef-smoke.test.mjs';

/**
 * Remove linhas de comentario YAML antes de auditar o step.
 *
 * Sem isso o guard e falsificavel pelo comentario que explica o proprio guard: o
 * bloco acima do `env:` cita SUPABASE_ANON_KEY em prosa, e um `includes()` cru
 * daria verde mesmo com a variavel apagada. Mesma classe do comentario que
 * inverteu a auditoria de ordem em #1513, e do texto de migration que flipou o
 * veredito em #1483. Auditar codigo, nunca a prosa ao lado dele.
 */
function stripYamlComments(text) {
  return text
    .split('\n')
    .filter((line) => !/^\s*#/.test(line))
    .join('\n');
}

/** Fatia do ci.yml correspondente a um step, do `- name: X` ate o proximo step. */
function stepBlock(yaml, stepName) {
  const lines = yaml.split('\n');
  const start = lines.findIndex((l) => l.trim() === `- name: ${stepName}`);
  assert.notEqual(start, -1, `step "${stepName}" nao encontrado em ci.yml`);
  const indent = lines[start].indexOf('- name:');
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i].indexOf('- name:') === indent && lines[i].trim().startsWith('- name:')) {
      end = i;
      break;
    }
  }
  return lines.slice(start, end).join('\n');
}

test('#1513: ef-smoke.test.mjs esta no script `npm test` (senao nunca roda em CI)', () => {
  const pkg = JSON.parse(readRepo('package.json'));
  const files = pkg.scripts.test.split(/\s+/).filter((f) => f.endsWith('.mjs'));
  assert.ok(
    files.includes(EF_SMOKE_PATH),
    `${EF_SMOKE_PATH} saiu do script "test" do package.json. O CI so roda esse script; ` +
      'fora dele o smoke de EF deployada nao executa e nada verifica auth em producao.',
  );
});

test('#1513: o step `Run Unit Tests` exporta SUPABASE_ANON_KEY do secret', () => {
  const yaml = readRepo('.github/workflows/ci.yml');
  const block = stripYamlComments(stepBlock(yaml, 'Run Unit Tests'));

  // Confirma que a fatia e mesmo o step que roda a suite, e nao um homonimo.
  assert.match(block, /run:\s*npm test\b/, 'a fatia auditada nao e o step que roda `npm test`');

  assert.match(
    block,
    /^\s*SUPABASE_ANON_KEY:\s*\$\{\{\s*secrets\.SUPABASE_ANON_KEY\s*\}\}\s*$/m,
    'sem SUPABASE_ANON_KEY no env do step, ef-smoke.test.mjs pula em silencio e o CI ' +
      'fica verde sem verificar auth de nenhuma EF deployada (#1513).',
  );
});

test('#1518: nenhum teste gateia anon so em PUBLIC_SUPABASE_ANON_KEY (o CI exporta SUPABASE_ANON_KEY)', () => {
  // O secret do repo se chama SUPABASE_ANON_KEY, e e esse nome que o step exporta.
  // Um arquivo que le apenas PUBLIC_SUPABASE_ANON_KEY continua pulando em CI mesmo
  // com a credencial presente — e some justamente a classe de teste que afirma que
  // anon esta trancado fora. Era o caso de 1294-responsibility-handoffs (1 de 25).
  const dir = new URL('./', import.meta.url);
  const offenders = readdirSync(dir)
    .filter((f) => f.endsWith('.test.mjs'))
    .filter((f) => {
      const src = readFileSync(new URL(f, dir), 'utf8');
      return (
        src.includes('process.env.PUBLIC_SUPABASE_ANON_KEY') &&
        !src.includes('process.env.SUPABASE_ANON_KEY')
      );
    });

  assert.deepEqual(
    offenders,
    [],
    'estes arquivos leem so PUBLIC_SUPABASE_ANON_KEY e por isso pulam em CI; use ' +
      '`process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY`',
  );
});

test('#1513: ef-smoke falha alto em CI quando falta credencial', () => {
  const src = readRepo(EF_SMOKE_PATH);
  assert.match(
    src,
    /GITHUB_ACTIONS/,
    'ef-smoke.test.mjs perdeu a deteccao de CI: sem ela, credencial ausente volta a ser um ' +
      'skip silencioso indistinguivel de pass.',
  );
  assert.match(
    src,
    /assert\.ok\(\s*canRun\b/,
    'ef-smoke.test.mjs perdeu a assercao que exige credencial em CI.',
  );
});
