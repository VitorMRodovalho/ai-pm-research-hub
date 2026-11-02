// tests/contracts/2909-set-site-config-uma-versao.test.mjs
// Hermetic (reads migrations and source, calls one pure module). Lands in the structural bucket by content.
/**
 * set_site_config keeps ONE version, (text, jsonb), and it writes jsonb; /admin/settings can then change the
 * onboarding group invite on its own, refusing anything the reader would not serve.
 *
 * Measured 2026-11-01: migration 20260426212845 had recreated set_site_config(p_key text, p_value text) and
 * set_site_config(p_key text, p_value jsonb). PostgREST does not support same-named overloads with different
 * types (PGRST203, read in its docs), so the screens' calls by name reached neither; and both bodies inserted a
 * text expression into site_config.value, which is jsonb (text to jsonb is explicit-only in Postgres). Live, no
 * key the screen saves had been written after 2026-04-26 and no row had updated_by (orchestrator's read).
 *
 * latestFunctionCapture refuses this function on purpose (two signatures in one migration), so this guard reads
 * the CREATE and DROP events by signature, in migration order.
 *
 * Layers:
 *   A  the last event on the (text, text) signature is a DROP, and no later migration creates it again;
 *   B  the current (text, jsonb) body checks manage_platform before writing, and writes the jsonb itself
 *      (JSON null for a null), with updated_by; it never casts the value to text;
 *   C  the migration that holds the current body keeps anon out and grants authenticated;
 *   D  /admin/settings refuses a changed invite that is not a group invite BEFORE any write, and writes the
 *      invite only when it changed;
 *   E  the screen's invite pattern is the reader's pattern (#740), by source and by behaviour.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { maskLineComments, maskJsComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG = join(ROOT, 'supabase/migrations');
const SETTINGS = maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/settings.astro'), 'utf8'));
const INVITE_MODULE = 'src/lib/whatsapp-invite.ts';

// Every CREATE of set_site_config (with its signature) and every DROP of the (text, text) version, in order.
function events() {
  const out = [];
  const files = readdirSync(MIG).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    const original = readFileSync(join(MIG, file), 'utf8');
    const sql = maskLineComments(original);
    const re = /\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.set_site_config\s*\(([^)]*)\)|\bDROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?public\.set_site_config\s*\(\s*text\s*,\s*text\s*\)/gi;
    let m;
    while ((m = re.exec(sql)) !== null) {
      if (m[0].toUpperCase().startsWith('DROP')) out.push({ file, at: m.index, kind: 'drop_text' });
      else {
        const sig = /p_value\s+jsonb/i.test(m[1]) ? 'jsonb' : /p_value\s+text/i.test(m[1]) ? 'text' : 'other';
        out.push({ file, at: m.index, kind: `create_${sig}`, original, sql });
      }
    }
  }
  return out;
}

function currentJsonb() {
  const ev = events().filter((e) => e.kind === 'create_jsonb');
  assert.ok(ev.length > 0, 'no migration creates set_site_config(text, jsonb)');
  const last = ev[ev.length - 1];
  const after = last.sql.slice(last.at);
  const as = after.match(/\bAS\s+(\$[a-zA-Z_]*\$)/);
  assert.ok(as, `no body found for set_site_config(text, jsonb) in ${last.file}`);
  const open = as.index + as[0].length;
  const close = after.indexOf(as[1], open);
  return { file: last.file, body: after.slice(open, close), fileSql: last.sql };
}

test('A: the (text, text) version is dropped last and never created again', () => {
  const ev = events().filter((e) => e.kind === 'drop_text' || e.kind === 'create_text');
  assert.ok(ev.length >= 2, `expected the old CREATE and a DROP of set_site_config(text, text), found ${ev.length} events`);
  const last = ev[ev.length - 1];
  assert.equal(last.kind, 'drop_text', `the last event on set_site_config(text, text) is ${last.kind} in ${last.file}`);
  const all = events();
  assert.equal(all.filter((e) => e.kind === 'create_other').length, 0, 'set_site_config gained a third signature');
});

test('B: the current body gates on manage_platform, then writes the jsonb itself with updated_by', () => {
  const { file, body } = currentJsonb();
  assert.match(
    body,
    /IF NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN\s+RAISE EXCEPTION[^;]*;\s+END IF;[\s\S]*INSERT INTO public\.site_config \(key, value, updated_at, updated_by\)\s+VALUES \(p_key, COALESCE\(p_value, 'null'::jsonb\), now\(\), v_caller_id\)\s+ON CONFLICT \(key\) DO UPDATE SET\s+value = EXCLUDED\.value,\s+updated_at = now\(\),\s+updated_by = EXCLUDED\.updated_by;/,
    `${file}: the write must come after the gate and store the jsonb value and the caller`,
  );
  assert.doesNotMatch(body, /p_value\s*::\s*text/i, `${file}: the value is cast to text again, which a jsonb column refuses`);
});

test('C: the migration with the current body keeps anon out and grants authenticated', () => {
  const { file, fileSql } = currentJsonb();
  assert.match(fileSql, /REVOKE ALL ON FUNCTION public\.set_site_config\(text, jsonb\) FROM PUBLIC, anon;/, `${file}: anon is not revoked`);
  assert.match(fileSql, /GRANT EXECUTE ON FUNCTION public\.set_site_config\(text, jsonb\) TO authenticated, service_role;/, `${file}: authenticated is not granted`);
  assert.doesNotMatch(fileSql, /GRANT[^;]*set_site_config[^;]*\banon\b/i, `${file}: anon is granted`);
});

test('D: /admin/settings refuses a bad invite before any write, and writes the invite only when it changed', () => {
  const start = SETTINGS.indexOf('async function saveConfig()');
  assert.ok(start > 0, 'saveConfig is gone');
  const end = SETTINGS.indexOf('async function boot()', start);
  const save = SETTINGS.slice(start, end > 0 ? end : undefined);
  const refuse = save.search(/if \(inviteChanged && !isWhatsAppGroupInvite\(onboardingInvite\)\) \{\s+\(window as any\)\.toast\?\.\(T\.whatsappInviteInvalid, 'error'\);\s+return;\s+\}/);
  assert.ok(refuse > 0, 'a changed invite that is not a group invite is not refused with a return');
  const firstWrite = save.indexOf("rpcChecked(sb, 'set_site_config'");
  assert.ok(firstWrite > refuse, 'something is written before the invite is checked');
  assert.match(
    save,
    /if \(inviteChanged\) \{\s+await rpcChecked\(sb, 'set_site_config', \{ p_key: 'whatsapp_group_onboarding', p_value: onboardingInvite \}\);/,
    'the invite is written outside the "changed" branch',
  );
  assert.match(save, /const inviteChanged = onboardingInvite !== loadedOnboardingInvite;/, '"changed" no longer compares with what was loaded');
});

test('E: the screen accepts exactly what the reader serves', async () => {
  const reader = maskLineComments(latestFunctionCapture(ROOT, 'get_community_group_link').body);
  const sqlPattern = reader.match(/v_link !~ '([^']+)'/);
  assert.ok(sqlPattern, 'the reader no longer filters the invite with a regex');
  const { WHATSAPP_GROUP_INVITE_RE, isWhatsAppGroupInvite } = await import(pathToFileURL(resolve(ROOT, INVITE_MODULE)).href);
  assert.equal(WHATSAPP_GROUP_INVITE_RE.source.replace(/\\\//g, '/'), sqlPattern[1], 'the screen and the reader use different invite patterns');
  const serverRe = new RegExp(sqlPattern[1]);
  // Built at run time: an invite-shaped literal in a versioned file fails guard 740 (H), fake or not.
  const host = ['chat', 'whatsapp', 'com'].join('.');
  const code = 'Ab'.repeat(11);
  for (const [url, ok] of [
    [`https://${host}/${code}`, true],
    [`https://${host}/${code}?mode=r_c`, true],
    [`http://${host}/${code}`, false],
    [`https://${host}/short`, false],
    ['https://wa.me/0000000000', false],
    [`https://${host}.evil.example/${code}`, false],
    ['', false],
  ]) {
    assert.equal(isWhatsAppGroupInvite(url), ok, `screen on ${JSON.stringify(url)}`);
    assert.equal(serverRe.test(url), ok, `reader on ${JSON.stringify(url)}`);
  }
});
