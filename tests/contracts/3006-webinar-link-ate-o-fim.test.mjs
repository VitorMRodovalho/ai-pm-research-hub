/**
 * #3006: o webinar confirmado conta como próximo ou ao vivo até scheduled_at + duration_min, e o link vale nesse intervalo.
 * Antes, get_public_webinars só dava o link com scheduled_at > now(), e a página cortava a lista pelo relógio do
 * Worker: o botão de entrar sumia do site no instante em que o webinar começava.
 *
 * O QUE ESTE GUARD AFIRMA
 *   H. _meeting_window_phase decide a fase na ordem certa, com o fim = início + duração (nula conta 0), não é
 *      SECURITY DEFINER, e só service_role a executa direto (PUBLIC, anon e authenticated, não);
 *   P. a página monta "Próximos" pela phase do banco (upcoming ou live), sem relógio próprio, e mostra o selo de ao
 *      vivo só em live; a chave do selo existe nos 3 dicionários;
 *   L. (banco) o helper nas bordas, chamado pela service_role, e recusado ao anon. Controles: a mesma chamada sabe
 *      dizer 'live' e nulo, e a recusa ao anon mostra que o grant decide.
 * O vínculo phase → link dentro da RPC fica no guard 2554 (B), que lê a captura vigente.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { maskLineComments, latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const CAP = latestFunctionCapture(ROOT, '_meeting_window_phase');
const FN = maskLineComments(CAP.block);
const MIG = maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', CAP.file), 'utf8'));
// Regex montada a partir de texto: escape completo de cada pedaço, e espaço vira \s+ (.claude/rules/guards.md).
const esc = (txt) => txt.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const flex = (sql) => sql.trim().split(/\s+/).map(esc).join('\\s+');
const SIG = flex('public._meeting_window_phase(timestamptz, integer, timestamptz, interval, interval)');
const DECIDE = flex(`
  SELECT CASE
    WHEN p_starts_at IS NULL OR p_now IS NULL THEN NULL
    WHEN p_open_before IS NOT NULL AND p_now < p_starts_at - p_open_before THEN NULL
    WHEN p_now < p_starts_at THEN 'upcoming'
    WHEN p_now < p_starts_at + make_interval(mins => GREATEST(COALESCE(p_duration_min, 0), 0)) THEN 'live'
    WHEN p_now < p_starts_at + make_interval(mins => GREATEST(COALESCE(p_duration_min, 0), 0))
                 + COALESCE(p_close_after, '0 minutes'::interval) THEN 'ended'
    ELSE NULL
  END`);
const PAGE = readFileSync(resolve(ROOT, 'src/pages/webinars.astro'), 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .replace(/^\s*\/\/.*$/gm, '')
  .replace(/<!--[\s\S]*?-->/g, '');

test('H: o helper decide a fase na ordem certa, e só service_role o executa direto', () => {
  assert.match(FN, /RETURNS text\s+LANGUAGE sql\s+STABLE\s+SET search_path = pg_catalog, pg_temp\s+AS \$function\$/);
  assert.doesNotMatch(FN, /SECURITY DEFINER/, 'o helper roda com o papel de quem chama');
  assert.match(FN, new RegExp(DECIDE), 'a ordem dos ramos e o fim = início + duração');
  assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION ${SIG}\\s+FROM PUBLIC, anon, authenticated;`));
  assert.match(MIG, new RegExp(`GRANT EXECUTE ON FUNCTION ${SIG}\\s+TO service_role;`));
  assert.doesNotMatch(MIG, new RegExp(`GRANT EXECUTE ON FUNCTION ${SIG}\\s+TO [^;]*\\b(anon|authenticated)\\b`));
});

test('P: "Próximos" sai da phase do banco, sem relógio próprio, e o selo só em live', () => {
  assert.match(
    PAGE,
    /const upcoming = webinars\.filter\(\(w: any\) =>\s*w\.status === 'confirmed' && \(w\.phase === 'upcoming' \|\| w\.phase === 'live'\)\s*\);/,
  );
  assert.doesNotMatch(PAGE, /Date\.now\(\)/, 'a página não decide a lista pelo relógio do Worker');
  assert.doesNotMatch(PAGE, /scheduled_at\)\.getTime\(\)\s*[<>]/, 'nem compara scheduled_at com um relógio');
  assert.match(
    PAGE,
    /\{w\.phase === 'live' && \(\s*<span[^>]*>[\s\S]{0,200}?\{t\('webinars\.liveNow', lang\)\}\s*<\/span>\s*\)\}/,
    'o selo de ao vivo só existe dentro do ramo live',
  );
  for (const dict of ['pt-BR', 'en-US', 'es-LATAM']) {
    const src = readFileSync(resolve(ROOT, `src/i18n/${dict}.ts`), 'utf8');
    assert.match(src, /'webinars\.liveNow': '[^']+',/, `webinars.liveNow em ${dict}`);
  }
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;

test('L: o helper nas bordas pela service_role, e recusado ao anon', {
  skip: (!URL || !SERVICE || !ANON) ? 'sem SUPABASE_URL + service_role + chave anon (baseline offline)' : false,
}, async () => {
  const call = (key, body) => fetch(`${URL}/rest/v1/rpc/_meeting_window_phase`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: key, Authorization: `Bearer ${key}` },
    body: JSON.stringify(body),
  });
  const t0 = Date.parse('2026-11-26T22:00:00Z');
  const at = (min) => new Date(t0 + min * 60000).toISOString();
  const base = { p_starts_at: at(0) };
  const cases = [
    [{ ...base, p_duration_min: 180, p_now: at(-1440) }, 'upcoming'],
    [{ ...base, p_duration_min: 180, p_now: at(-1 / 60) }, 'upcoming'],
    [{ ...base, p_duration_min: 180, p_now: at(0) }, 'live'],
    [{ ...base, p_duration_min: 180, p_now: at(179) }, 'live'],
    [{ ...base, p_duration_min: 180, p_now: at(180) }, null],
    [{ ...base, p_duration_min: null, p_now: at(-1 / 60) }, 'upcoming'],
    [{ ...base, p_duration_min: null, p_now: at(0) }, null],
    [{ ...base, p_duration_min: 90, p_now: at(-61), p_open_before: '1 hour', p_close_after: '1 hour' }, null],
    [{ ...base, p_duration_min: 90, p_now: at(-60), p_open_before: '1 hour', p_close_after: '1 hour' }, 'upcoming'],
    [{ ...base, p_duration_min: 90, p_now: at(90), p_open_before: '1 hour', p_close_after: '1 hour' }, 'ended'],
    [{ ...base, p_duration_min: 90, p_now: at(150), p_open_before: '1 hour', p_close_after: '1 hour' }, null],
  ];
  for (const [body, want] of cases) {
    const r = await call(SERVICE, body);
    assert.equal(r.status, 200, `service_role chama o helper (status ${r.status})`);
    assert.equal(await r.json(), want, `fase em ${body.p_now} para ${JSON.stringify(body)}`);
  }
  const denied = await call(ANON, { ...base, p_duration_min: 60, p_now: at(0) });
  assert.ok([401, 403, 404].includes(denied.status), `anon não executa o helper direto (status ${denied.status})`);
});
