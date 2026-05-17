/**
 * Shared migration parser for body-hash drift detection.
 *
 * Consumed by:
 *   - scripts/audit-rpc-body-drift.mjs (one-shot inventory + report)
 *   - tests/contracts/rpc-migration-coverage.test.mjs (Phase C contract)
 *
 * Normalization invariants (must match the SQL side byte-for-byte):
 *   - normalizeBody mirrors `regexp_replace(prosrc, '\s+', ' ', 'g')` in
 *     `_audit_list_public_function_bodies()` (migration
 *     20260680000000). NO trim — PG side does not trim.
 *   - md5 over the normalized bytes — same algorithm as `md5()` in PG.
 *
 * Anything that breaks this byte-equivalence (a different regex, an extra
 * trim, a different hash) will cause every function to appear drifted on
 * the next test run. If you need to change normalization, update BOTH
 * sides + bump baseline atomically.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

export function normalizeBody(s) {
  return s.replace(/\s+/g, ' ');
}

export function md5(s) {
  return createHash('md5').update(s).digest('hex');
}

export function normalizeArgs(s) {
  if (!s) return '';
  let out = s.toLowerCase();
  out = out.replace(/\s+default\s+[^,)]+/g, '');
  out = out.replace(/\s+/g, ' ').trim();
  out = out.replace(/,$/, '');
  out = out.replace(/\b(in|out|inout|variadic)\s+/g, '');
  return out;
}

export function parseMigration(filename, sql) {
  const blocks = [];
  const headerRe = /\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"?public"?\.)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi;

  let match;
  while ((match = headerRe.exec(sql)) !== null) {
    const name = match[1].toLowerCase();
    const argStart = headerRe.lastIndex;

    let depth = 1;
    let i = argStart;
    while (i < sql.length && depth > 0) {
      const c = sql[i];
      if (c === '(') depth++;
      else if (c === ')') depth--;
      i++;
      if (depth === 0) break;
    }
    if (depth !== 0) continue;
    const argEnd = i - 1;
    const args = sql.slice(argStart, argEnd);

    const afterArgs = sql.slice(i);
    const asMatch = afterArgs.match(/\bAS\s+(\$[a-zA-Z_]*\$)/);
    if (!asMatch) continue;

    const delim = asMatch[1];
    const bodyStart = i + asMatch.index + asMatch[0].length;
    const closeIdx = sql.indexOf(delim, bodyStart);
    if (closeIdx === -1) continue;
    const body = sql.slice(bodyStart, closeIdx);

    blocks.push({
      name,
      args: normalizeArgs(args),
      bodyHash: md5(normalizeBody(body)),
      bodyLen: body.length,
      file: filename,
    });
  }

  return blocks;
}

/**
 * Walk every *.sql in MIGRATIONS_DIR (chronological by filename) and return
 * a Map of `${name}@${normalizedArgs}` → { bodyHash, bodyLen, file, touchCount }
 * where the values reflect the LATEST capture (last file in sort order wins).
 */
export function loadLatestCaptures(migrationsDir) {
  const files = readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  const latest = new Map();
  const touchCount = new Map();

  for (const f of files) {
    const sql = readFileSync(join(migrationsDir, f), 'utf8');
    const blocks = parseMigration(f, sql);
    for (const b of blocks) {
      const key = `${b.name}@${b.args}`;
      latest.set(key, { bodyHash: b.bodyHash, bodyLen: b.bodyLen, file: b.file });
      touchCount.set(key, (touchCount.get(key) || 0) + 1);
    }
  }

  return { latest, touchCount, fileCount: files.length };
}

/**
 * Diff live inventory against latest migration captures.
 *
 * @param liveRows  Array of { proname, identity_args, body_md5, prosrc_len, is_secdef }
 *                  from `_audit_list_public_function_bodies()`.
 * @param latestCaptures  Output of loadLatestCaptures().
 * @returns { clean, driftedDefinite, driftedSuspect, orphansTrue, orphansOverload, extinct }
 */
export function diffLiveVsCaptures(liveRows, latestCaptures) {
  const { latest, touchCount } = latestCaptures;

  const liveMap = new Map();
  for (const row of liveRows) {
    const key = `${row.proname.toLowerCase()}@${normalizeArgs(row.identity_args)}`;
    liveMap.set(key, row);
  }

  const namesWithAnyCapture = new Set();
  for (const key of latest.keys()) {
    namesWithAnyCapture.add(key.split('@')[0]);
  }

  const driftedDefinite = [];
  const driftedSuspect = [];
  const orphansTrue = [];
  const orphansOverload = [];
  const extinct = [];
  let cleanCount = 0;

  for (const [key, liveRow] of liveMap.entries()) {
    const cap = latest.get(key);
    if (!cap) {
      const name = key.split('@')[0];
      const row = { key, name: liveRow.proname, args: liveRow.identity_args, is_secdef: liveRow.is_secdef };
      if (namesWithAnyCapture.has(name)) orphansOverload.push(row);
      else orphansTrue.push(row);
      continue;
    }
    if (cap.bodyHash !== liveRow.body_md5) {
      const row = {
        key,
        name: liveRow.proname,
        args: liveRow.identity_args,
        live_md5: liveRow.body_md5,
        migration_md5: cap.bodyHash,
        live_len: liveRow.prosrc_len,
        migration_len: cap.bodyLen,
        latest_file: cap.file,
        touch_count: touchCount.get(key),
        is_secdef: liveRow.is_secdef,
      };
      if (liveRow.prosrc_len !== cap.bodyLen) driftedDefinite.push(row);
      else driftedSuspect.push(row);
    } else {
      cleanCount++;
    }
  }

  for (const [key, cap] of latest.entries()) {
    if (!liveMap.has(key)) extinct.push({ key, ...cap });
  }

  return {
    clean: cleanCount,
    driftedDefinite,
    driftedSuspect,
    orphansTrue,
    orphansOverload,
    extinct,
  };
}
