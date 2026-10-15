/**
 * #2704 — varredura das chamadas do front a RPCs que GRAVAM e devolvem a recusa NO CORPO
 * (`{error}` / `{success:false}` com HTTP 200). O supabase-js só preenche `error` em falha de
 * transporte ou do PostgREST, então quem testa só `error` mostra sucesso numa recusa.
 *
 * A classificação vem da captura MAIS NOVA de cada função nas migrations, nunca de lista escrita
 * à mão: uma lista apodrece na primeira função nova.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { buildNewestDefinitions, maskLineComments, maskJsComments } from './guard-pin-staleness.mjs';

const WRITE_RE = /\b(insert\s+into|update\s+[a-z_."]+\s+set|delete\s+from)\b/i;
const BODY_ERROR_RE = /\bjsonb?_build_object\s*\(\s*'error'/i;

/** Corpo da definição de `name` dentro de UM arquivo (o último bloco, que é o vigente). */
export function functionBlock(sql, name) {
  const header = new RegExp(
    `\\bCREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:"?public"?\\s*\\.\\s*)?"?${name}"?\\s*\\(`,
    'gi',
  );
  let start = -1;
  let m;
  while ((m = header.exec(sql)) !== null) start = m.index;
  if (start < 0) return null;
  const tag = sql.slice(start).match(/AS\s+(\$[A-Za-z0-9_]*\$)/i);
  if (!tag) return null;
  const open = start + tag.index + tag[0].length;
  const close = sql.indexOf(tag[1], open);
  return { head: sql.slice(start, open), body: sql.slice(open, close < 0 ? undefined : close) };
}

/** Funções que gravam E devolvem erro no corpo, segundo a captura mais nova. */
export function bodyErrorWriters(root, migrationsDir = join(root, 'supabase/migrations')) {
  const { newest } = buildNewestDefinitions(migrationsDir);
  const out = new Set();
  const cache = new Map();
  for (const [name, { file }] of newest) {
    if (!cache.has(file)) cache.set(file, maskLineComments(readFileSync(join(migrationsDir, file), 'utf8')));
    const blk = functionBlock(cache.get(file), name);
    if (!blk) continue;
    if (!/RETURNS\s+jsonb?\b/i.test(blk.head)) continue;
    if (WRITE_RE.test(blk.body) && BODY_ERROR_RE.test(blk.body)) out.add(name);
  }
  return out;
}

function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|astro)$/.test(e.name)) out.push(p);
  }
  return out;
}

/**
 * Decide se UMA chamada lê o erro do corpo, amarrando a leitura à MESMA variável que recebeu o
 * resultado, dentro da janela que vai até a próxima `.rpc(`. Aceita:
 *  - `const { data: X, error } = await ....rpc('fn')` e depois `X?.error`, `X.success`, `X.ok`,
 *    `(X as any).error` ou `rpcBodyError(X)`;
 *  - `const R = await ....rpc('fn')` e depois `R.data?.error` (ou `.success`/`.ok`), ou um alias
 *    `const Y = R.data` lido como acima.
 * Chamadas por `rpcChecked(sb, 'fn')` não passam por aqui: não têm `.rpc('fn'` literal e são
 * seguras por construção.
 */
// A leitura só conta onde DECIDE: na condição de um `if`, num ternário, ou entregue a
// `rpcBodyError`. Solta numa mensagem de log ela sobrevive com o desvio removido (mutação do probe).
const readOf = (v) => {
  const e = v.replace(/\$/g, '\\$');
  const read = `(?:\\b${e}|\\(\\s*${e}\\s+as\\s+any\\s*\\))\\??\\.(?:error|success|ok)\\b`;
  return new RegExp(
    `\\bif\\s*\\((?:[^()]|\\([^()]*\\))*?${read}` +
      `|${read}[^;\\n?]*\\?(?!\\.)` +
      `|rpcBodyError\\(\\s*${e}\\s*\\)`,
  );
};

export function readsBodyError(src, callIndex) {
  const before = src.slice(Math.max(0, callIndex - 200), callIndex);
  const rest = src.slice(callIndex + 5);
  const next = rest.search(/\.rpc\(/);
  const win = next < 0 ? rest : rest.slice(0, next);

  const destr = before.match(/const\s*\{([^}]*)\}\s*=\s*await\s+[\w.()?!]*$/);
  if (destr) {
    const dm = destr[1].match(/\bdata\s*(?::\s*(\w+))?/);
    return !!dm && readOf(dm[1] || 'data').test(win);
  }
  const whole = before.match(/const\s+(\w+)\s*=\s*await\s+[\w.()?!]*$/);
  if (whole) {
    const r = whole[1];
    if (readOf(`${r}\\??\\.data`).test(win)) return true;
    const alias = win.match(new RegExp(`const\\s+(\\w+)\\s*=\\s*\\(?\\s*${r}\\??\\.data\\b`));
    return !!alias && readOf(alias[1]).test(win);
  }
  return false;
}

/** Chamadas do front a `targets` que NÃO leem o erro do corpo, como `arquivo|função#ordem`. */
export function scanUncheckedCalls(root, targets, srcDir = join(root, 'src')) {
  const offenders = [];
  let checked = 0;
  for (const f of walk(srcDir).sort()) {
    const src = maskJsComments(readFileSync(f, 'utf8'));
    const rel = relative(root, f);
    const seen = new Map();
    const re = /\.rpc\(\s*(['"`])([A-Za-z0-9_]+)\1/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const fn = m[2];
      if (!targets.has(fn)) continue;
      const n = (seen.get(fn) || 0) + 1;
      seen.set(fn, n);
      if (readsBodyError(src, m.index)) checked++;
      else offenders.push(`${rel}|${fn}#${n}`);
    }
  }
  return { offenders, checked };
}
