import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { scanTokens } from '../helpers/css-token-scan.mjs';

const ROOT = process.cwd();
const BASELINE = resolve(ROOT, 'docs/audit/CSS_UNDEFINED_TOKEN_BASELINE_1545.txt');

/**
 * #1545 — `--accent` was referenced by 34 call sites and defined NOWHERE. CSS treats an undefined
 * custom property as an invalid declaration, so `bg-[var(--accent)] text-white` painted a
 * transparent background under white text: the Salvar of the agenda-block editor was in the DOM
 * and invisible on the near-white card. The PM reported "there is no Save button", and from the
 * outside that is exactly what it was.
 *
 * Nothing catches this class today — the build succeeds, TypeScript never type-checks a class
 * string, and no test renders. Scanning found `--accent` was not alone: 19 other tokens are used
 * and never defined.
 *
 * Two different strengths, on purpose:
 *  1. INVISIBLE CONTROL (undefined background + white text) → hard zero, no allowlist. This is the
 *     class that hides a button from a human, and it must never be one entry away from returning.
 *  2. Everything else (text/border/hover colours — degrade to inherited, ugly but visible) →
 *     RATCHET against a dated baseline, same shape as the RPC body-drift allowlist.
 */

const parseBaseline = () => new Set(
  readFileSync(BASELINE, 'utf8').split('\n')
    .filter((l) => l.startsWith('--'))
    .map((l) => l.split(/\s+/)[0]),
);

test('#1545 no control is invisible — undefined background under white text is always zero', () => {
  const { invisibleControls } = scanTokens('src', 'src/styles');
  const detail = invisibleControls.map((c) => `  ${c.file} → ${c.tokens.join(', ')}`).join('\n');
  assert.equal(
    invisibleControls.length, 0,
    'Um fundo `bg-[var(--x)]` com token indefinido junto de `text-white` renderiza branco no ' +
    'branco: o controle existe no DOM e some da tela (#1545). Defina o token em src/styles ou ' +
    'aponte a classe para --accent. NÃO existe allowlist para esta classe.\n' + detail,
  );
});

test('#1545 undefined-token ratchet — nothing new, and the baseline only shrinks', () => {
  const baseline = parseBaseline();
  const { undefinedTokens } = scanTokens('src', 'src/styles');

  const novos = [...undefinedTokens.keys()].filter((t) => !baseline.has(t));
  assert.deepEqual(
    novos, [],
    `Token(s) usados mas nunca definidos e FORA do baseline:\n` +
    novos.map((t) => `  ${t} — ${undefinedTokens.get(t).join(', ')}`).join('\n') +
    '\n\nDuas saídas: definir o token em src/styles/theme.css (nos DOIS blocos, claro e escuro), ' +
    'ou apontar o uso para um token que já existe. Aumentar o baseline não é uma delas.',
  );

  assert.ok(
    undefinedTokens.size <= baseline.size,
    `o baseline é um ratchet: ${undefinedTokens.size} tokens indefinidos contra ${baseline.size} ` +
    'no arquivo. Se você RESOLVEU algum, apague a linha dele do baseline no mesmo PR.',
  );
});

test('#1545 --accent exists in BOTH theme blocks and points at an AA-safe CTA colour', () => {
  const theme = readFileSync(resolve(ROOT, 'src/styles/theme.css'), 'utf8');
  const hits = [...theme.matchAll(/--accent:\s*([^;]+);/g)].map((m) => m[1].trim());
  assert.equal(
    hits.length, 2,
    '--accent precisa existir no bloco claro E no escuro, como os outros aliases ' +
    '(--surface/--fg/--border). Definir só num deles deixa o botão invisível no outro tema.',
  );
  for (const value of hits) {
    assert.match(
      value, /--color-orange-deep/,
      'texto branco sobre --color-orange (#FF610F) é 3.01:1 e reprova no WCAG AA; o token do tema ' +
      'para CTA com texto é --color-orange-deep (5.18:1). Ver o comentário em theme.css.',
    );
  }
});

test('#1545 o scanner ignora comentário — guard que confunde prosa com código ensina a relaxar', () => {
  // theme.css documenta a sintaxe com `bg-[var(--xxx)]` DENTRO de um comentário. A primeira
  // versão deste guard contou esse exemplo como uso real. Mesma lição do #1513/#963/#1546.
  const { undefinedTokens } = scanTokens('src', 'src/styles');
  assert.ok(
    !undefinedTokens.has('--xxx'),
    '--xxx só existe num comentário de theme.css; contá-lo significa que o scanner lê prosa como código',
  );
});
