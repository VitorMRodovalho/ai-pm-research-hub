/**
 * #2854 — o que uma migration declara, por papel, sobre cada tabela, view e sequência NOVA em `public`.
 *
 * A partir de 30/10/2026 o Supabase deixa de dar GRANT automático a `anon`, `authenticated` e
 * `service_role` em tabela e sequência novas de `public` (`ALTER DEFAULT PRIVILEGES FOR ROLE postgres
 * IN SCHEMA public REVOKE ... ON TABLES / ON SEQUENCES`). `ON TABLES` cobre também view (doc do
 * Postgres 18, ALTER DEFAULT PRIVILEGES: "tables (including views and foreign tables)"). Objeto que já
 * existe mantém o que tem. Sem GRANT, o PostgREST responde 42501 a quem lê ou escreve, inclusive ao
 * `service_role`, e o RLS nem chega a ser avaliado.
 *
 * A regra: depois de criar o objeto, a MESMA migration diz o que cada um dos três papéis recebe, com
 * `GRANT ... ON <obj> TO <papel>` ou `REVOKE ... ON <obj> FROM <papel>`. Um REVOKE só de `anon` e
 * `authenticated` deixa o `service_role` no default, que era "tudo" e passou a ser "nada"; é o caso
 * que a regra existe para pegar.
 *
 * Só conta o que é executado no topo da migration: comentário, string e corpo `$...$` (função, DO) são
 * mascarados antes da leitura, porque um GRANT descrito num comentário, num COMMENT ON ou dentro de
 * um corpo de função não concede nada quando a migration roda.
 */

export const PAPEIS = ['anon', 'authenticated', 'service_role'];

/**
 * Mascara comentário (`--`, `/* *\/` com aninhamento), string ('...', E'...') e corpo `$tag$...$tag$`,
 * preservando offsets e quebras de linha. Identificador entre aspas duplas fica, porque é nome.
 */
export function maskSqlNonCode(sql) {
  const out = sql.split('');
  const blank = (from, to) => {
    for (let k = from; k < to; k++) if (out[k] !== '\n') out[k] = ' ';
  };
  let i = 0;
  const n = sql.length;
  while (i < n) {
    const c = sql[i];
    const c2 = sql[i + 1];
    if (c === '-' && c2 === '-') {
      const end = sql.indexOf('\n', i);
      const stop = end === -1 ? n : end;
      blank(i, stop);
      i = stop;
    } else if (c === '/' && c2 === '*') {
      let depth = 1;
      let j = i + 2;
      while (j < n && depth > 0) {
        if (sql[j] === '/' && sql[j + 1] === '*') { depth++; j += 2; }
        else if (sql[j] === '*' && sql[j + 1] === '/') { depth--; j += 2; }
        else j++;
      }
      blank(i, j);
      i = j;
    } else if (c === "'") {
      const escapes = i > 0 && /[eE]/.test(sql[i - 1]) && !/[\w$]/.test(sql[i - 2] ?? '');
      let j = i + 1;
      while (j < n) {
        if (escapes && sql[j] === '\\') { j += 2; continue; }
        if (sql[j] === "'") {
          if (sql[j + 1] === "'") { j += 2; continue; }
          break;
        }
        j++;
      }
      blank(i, Math.min(j + 1, n));
      i = j + 1;
    } else if (c === '"') {
      const end = sql.indexOf('"', i + 1);
      i = end === -1 ? n : end + 1;
    } else if (c === '$' && !/[\w$]/.test(sql[i - 1] ?? '')) {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 64));
      if (!m) { i++; continue; }
      const tag = m[0];
      const end = sql.indexOf(tag, i + tag.length);
      const stop = end === -1 ? n : end + tag.length;
      blank(i, stop);
      i = stop;
    } else {
      i++;
    }
  }
  return out.join('');
}

/** Divide o texto JÁ MASCARADO em comandos de topo, com o offset de início de cada um. */
export function splitStatements(masked) {
  const stmts = [];
  let start = 0;
  for (let i = 0; i <= masked.length; i++) {
    if (i === masked.length || masked[i] === ';') {
      const raw = masked.slice(start, i);
      const lead = raw.length - raw.trimStart().length;
      const text = raw.trim();
      if (text) stmts.push({ text, offset: start + lead });
      start = i + 1;
    }
  }
  return stmts;
}

const IDENT = String.raw`(?:"[^"]+"|[A-Za-z_][\w$]*)`;
const QNAME = String.raw`${IDENT}(?:\s*\.\s*${IDENT})?`;

/** `public.x`, `x`, `"public"."x"` → { schema, name }. Sem esquema, vale o `public` do search_path. */
export function normalizeName(qname) {
  const parts = qname.split(/\s*\.\s*/).map((p) => (p.startsWith('"') ? p.slice(1, -1) : p.toLowerCase()));
  return parts.length === 2 ? { schema: parts[0], name: parts[1] } : { schema: 'public', name: parts[0] };
}

function splitList(s) {
  return s.split(',').map((x) => x.trim()).filter(Boolean);
}

const CREATE_TABLE = new RegExp(
  String.raw`^CREATE\s+(?:(?:GLOBAL|LOCAL)\s+)?(?:(TEMP|TEMPORARY|UNLOGGED)\s+)?TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(${QNAME})`,
  'i',
);
const CREATE_VIEW = new RegExp(
  String.raw`^CREATE\s+(?:OR\s+REPLACE\s+)?(?:(TEMP|TEMPORARY)\s+)?(?:RECURSIVE\s+)?(MATERIALIZED\s+)?VIEW\s+(?:IF\s+NOT\s+EXISTS\s+)?(${QNAME})`,
  'i',
);
const CREATE_SEQUENCE = new RegExp(
  String.raw`^CREATE\s+(?:(TEMP|TEMPORARY|UNLOGGED)\s+)?SEQUENCE\s+(?:IF\s+NOT\s+EXISTS\s+)?(${QNAME})`,
  'i',
);
// Coluna serial: a sequência implícita `<tabela>_<coluna>_seq` nasce junto e também perde o default;
// o `nextval()` do DEFAULT exige USAGE dela para quem insere.
const SERIAL_COLUMN = new RegExp(String.raw`[(,]\s*(${IDENT})\s+(?:small|big)?serial[248]?\b`, 'gi');

const GRANT = /^GRANT\s+([\s\S]+?)\s+ON\s+([\s\S]+?)\s+TO\s+([\s\S]+)$/i;
const REVOKE = /^REVOKE\s+(GRANT\s+OPTION\s+FOR\s+)?([\s\S]+?)\s+ON\s+([\s\S]+?)\s+FROM\s+([\s\S]+)$/i;
// Alvo de GRANT que não é relação. `ALL TABLES IN SCHEMA` não precisa de exceção: não nomeia o objeto, e por
// isso nunca casa com ele.
const NON_RELATION_TARGET = /^(?:FUNCTION\b|PROCEDURE\b|ROUTINE\b|SCHEMA\b|DATABASE\b|TYPE\b|DOMAIN\b|LANGUAGE\b|LARGE\b|FOREIGN\b|TABLESPACE\b|PARAMETER\b)/i;

/**
 * Objetos novos em `public` e declarações por papel de um texto de migration.
 * Retorna { created: [{ kind, name, offset }], declared: [{ name, role, offset }] }.
 */
export function analyzeMigration(sql) {
  const masked = maskSqlNonCode(sql);
  const created = [];
  const declared = [];
  for (const { text, offset } of splitStatements(masked)) {
    let m;
    if ((m = CREATE_TABLE.exec(text))) {
      if (/^TEMP/i.test(m[1] ?? '')) continue;
      const { schema, name } = normalizeName(m[2]);
      if (schema !== 'public') continue;
      created.push({ kind: 'table', name, offset });
      for (const col of text.matchAll(SERIAL_COLUMN)) {
        created.push({ kind: 'sequence', name: `${name}_${normalizeName(col[1]).name}_seq`, offset });
      }
    } else if ((m = CREATE_VIEW.exec(text))) {
      if (m[1]) continue;
      const { schema, name } = normalizeName(m[3]);
      if (schema !== 'public') continue;
      created.push({ kind: m[2] ? 'materialized view' : 'view', name, offset });
    } else if ((m = CREATE_SEQUENCE.exec(text))) {
      if (/^TEMP/i.test(m[1] ?? '')) continue;
      const { schema, name } = normalizeName(m[2]);
      if (schema !== 'public') continue;
      created.push({ kind: 'sequence', name, offset });
    } else if ((m = GRANT.exec(text)) || (m = REVOKE.exec(text))) {
      const isRevoke = /^REVOKE/i.test(text);
      if (isRevoke && m[1]) continue; // REVOKE GRANT OPTION FOR só tira a opção de repassar
      let target = isRevoke ? m[3] : m[2];
      const roles = (isRevoke ? m[4] : m[3])
        .replace(/\s+(?:WITH\s+GRANT\s+OPTION|GRANTED\s+BY\s+\S+|CASCADE|RESTRICT)\b[\s\S]*$/i, '');
      if (NON_RELATION_TARGET.test(target)) continue;
      target = target.replace(/^(?:TABLE|SEQUENCE)\s+/i, '');
      for (const obj of splitList(target)) {
        const { schema, name } = normalizeName(obj);
        if (schema !== 'public') continue;
        for (const role of splitList(roles)) {
          declared.push({ name, role: role.replace(/"/g, '').toLowerCase(), offset });
        }
      }
    }
  }
  return { created, declared };
}

/**
 * Para cada objeto novo, os papéis que a migration NÃO declara depois de criá-lo.
 * Retorna só os objetos com pendência: [{ kind, name, missing: [papel...] }].
 */
export function undeclaredRoles(sql) {
  const { created, declared } = analyzeMigration(sql);
  const findings = [];
  for (const obj of created) {
    const missing = PAPEIS.filter(
      (role) => !declared.some((d) => d.name === obj.name && d.role === role && d.offset > obj.offset),
    );
    if (missing.length) findings.push({ kind: obj.kind, name: obj.name, missing });
  }
  return findings;
}
