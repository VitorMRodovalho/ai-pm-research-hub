// Shared scanner for the #1545 undefined-CSS-token guard and its baseline generator.
// Kept in one place so the guard and the audit script can never disagree about what "used" means
// (the RPC body-drift parser learned this the hard way — see .claude/rules/database.md).
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname } from 'node:path';

// Comments are prose, not code. A scanner that cannot tell them apart flags the documentation
// that explains it — theme.css literally contains `bg-[var(--xxx)]` in a comment as an example.
export const stripComments = (src) => src
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');

export function definedTokens(stylesDir) {
  const css = readdirSync(stylesDir)
    .filter((f) => f.endsWith('.css'))
    .map((f) => stripComments(readFileSync(join(stylesDir, f), 'utf8')))
    .join('\n');
  return new Set([...css.matchAll(/(--[a-z0-9-]+)\s*:/gi)].map((m) => m[1]));
}

export function sourceFiles(root) {
  const out = [];
  (function walk(dir) {
    for (const entry of readdirSync(dir)) {
      if (entry === 'node_modules' || entry.startsWith('.')) continue;
      const full = join(dir, entry);
      if (statSync(full).isDirectory()) walk(full);
      else if (['.astro', '.tsx', '.ts', '.css'].includes(extname(full))) out.push(full);
    }
  })(root);
  return out;
}

/** @returns {{ undefinedTokens: Map<string, string[]>, invisibleControls: Array<{file:string, tokens:string[]}> }} */
export function scanTokens(root, stylesDir) {
  const defined = definedTokens(stylesDir);
  const undefinedTokens = new Map();
  const invisibleControls = [];

  for (const file of sourceFiles(root)) {
    const src = stripComments(readFileSync(file, 'utf8'));

    for (const m of src.matchAll(/var\((--[a-z0-9-]+)/gi)) {
      const token = m[1];
      if (token.startsWith('--tw-') || defined.has(token)) continue; // --tw-* are Tailwind runtime vars
      if (!undefinedTokens.has(token)) undefinedTokens.set(token, []);
      const rel = file.replace(root.replace(/\/src$/, '') + '/', '');
      if (!undefinedTokens.get(token).includes(rel)) undefinedTokens.get(token).push(rel);
    }

    // The ACUTE class: an undefined background in the SAME class attribute as white text.
    // The declaration is invalid → transparent background → white-on-near-white → the control
    // is present in the DOM and invisible on screen. This is what hid the Salvar of #1545.
    for (const m of src.matchAll(/class(?:Name)?=(?:"|'|\{`)([^"'`]*)/g)) {
      const cls = m[1];
      const bad = [...cls.matchAll(/bg-\[var\((--[a-z0-9-]+)\)\]/g)]
        .map((x) => x[1]).filter((t) => !t.startsWith('--tw-') && !defined.has(t));
      if (bad.length && /text-white/.test(cls)) invisibleControls.push({ file, tokens: bad });
    }
  }
  return { undefinedTokens, invisibleControls };
}
