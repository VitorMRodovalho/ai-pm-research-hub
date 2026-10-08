/**
 * #2365: get_public_impact_data (lida pelo /about e por consumidores externos) usa as mesmas fontes que a home.
 *
 * Antes, a mesma visita mostrava numeros diferentes para o mesmo conceito: capitulos 5 contra 15, membros por outra
 * populacao, tribos inativas no contador e horas de impacto por uma formula propria.
 *
 * O QUE ESTE GUARD AFIRMA
 *   A. chapters le engaged (decisao do GP, 03/10/2026) e chapters_signed le signed;
 *   B. active_members conta v_operational_members (ADR-0126);
 *   C. tribes e tribes_summary filtram tribos ativas;
 *   D. impact_hours chama get_impact_hours_canonical acumulado, sem soma inline (ADR-0100 2C), e
 *      impact_hours_since sai do mesmo predicado (presente, nao justificado, nao confidencial);
 *   E. timeline_is_narrative = true;
 *   F. (banco) como anon, os valores batem com as fontes canonicas lidas na mesma rodada.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const DIR = resolve(process.cwd(), 'supabase/migrations');
const files = readdirSync(DIR).filter((f) => /^\d{14}_2365_impacto_publico_fontes_canonicas\.sql$/.test(f));
const SQL = files.length === 1 ? maskLineComments(readFileSync(join(DIR, files[0]), 'utf8')) : '';
// O bloco que decide: o jsonb_build_object do corpo da funcao.
const FN = (SQL.match(/CREATE OR REPLACE FUNCTION public\.get_public_impact_data\(\)[\s\S]*?\$function\$[\s\S]*?\$function\$/) || [''])[0];

test('a migration existe e o corpo foi recortado', () => {
  assert.equal(files.length, 1, `esperava 1 migration da #2365, achei ${files.length}`);
  assert.ok(FN.length > 1000, 'corpo de get_public_impact_data nao encontrado');
});

test('A. chapters = engaged, chapters_signed = signed', () => {
  assert.match(FN, /'chapters',\s*\(v_chapters->>'engaged'\)::int,/);
  assert.match(FN, /'chapters_signed',\s*\(v_chapters->>'signed'\)::int,/);
});

test('B. active_members = v_operational_members', () => {
  assert.match(FN, /'active_members',\s*\(SELECT COUNT\(\*\) FROM public\.v_operational_members\),/);
});

test('C. tribes e tribes_summary so com tribos ativas', () => {
  assert.match(FN, /'tribes',\s*\(SELECT COUNT\(\*\) FROM tribes WHERE is_active\),/);
  assert.match(FN, /'tribes_summary',[\s\S]*?\) ORDER BY t\.id\)\s+FROM tribes t\s+WHERE t\.is_active\s+\), '\[\]'::jsonb\),/);
});

test('D. impact_hours canonico acumulado, impact_hours_since com o mesmo predicado', () => {
  assert.match(FN, /'impact_hours',\s*public\.get_impact_hours_canonical\('2000-01-01'::date,\s*CURRENT_DATE\),/);
  const since = (FN.match(/'impact_hours_since',\s*\([\s\S]*?\n\s{4}\),/) || [''])[0];
  assert.match(since, /min\(e\.date\)[\s\S]*WHERE a\.present AND a\.excused IS NOT TRUE AND e\.date <= CURRENT_DATE[\s\S]*ci\.visibility = 'confidential'/,
    'impact_hours_since sem o predicado canonico');
  assert.doesNotMatch(FN, /'impact_hours',\s*\(\s*SELECT/, 'impact_hours nao pode ser soma inline');
});

test('E. timeline marcada como narrativa', () => {
  assert.match(FN, /'timeline_is_narrative',\s*true,\s*'timeline',/);
});

const URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ANON = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const dbGated = !!(URL && SERVICE && ANON);

test('F. (banco) como anon, os valores batem com as fontes canonicas', { skip: dbGated ? false : 'SUPABASE_URL + service role + anon key required' }, async () => {
  const anon = createClient(URL, ANON, { auth: { persistSession: false } });
  const svc = createClient(URL, SERVICE, { auth: { persistSession: false } });
  const { data: imp, error } = await anon.rpc('get_public_impact_data');
  assert.ifError(error);
  const { data: m, error: e1 } = await svc.rpc('get_chapter_metrics');
  assert.ifError(e1);
  const { data: home, error: e2 } = await svc.rpc('get_homepage_stats');
  assert.ifError(e2);
  const { data: canon, error: e3 } = await svc.rpc('get_impact_hours_canonical', {
    p_start_date: '2000-01-01', p_end_date: new Date().toISOString().slice(0, 10),
  });
  assert.ifError(e3);
  const { count: ativas, error: e4 } = await svc.from('tribes').select('id', { count: 'exact', head: true }).eq('is_active', true);
  assert.ifError(e4);

  assert.equal(Number(imp.chapters), Number(m.engaged), 'chapters == engaged');
  assert.equal(Number(imp.chapters_signed), Number(m.signed), 'chapters_signed == signed');
  assert.equal(Number(imp.active_members), Number(home.members), 'active_members == home.members');
  assert.equal(Number(imp.tribes), Number(home.tribes), 'tribes == home.tribes');
  assert.equal(imp.tribes_summary.length, ativas, 'tribes_summary == tribos ativas');
  assert.equal(Number(imp.impact_hours), Number(canon), 'impact_hours == canonical acumulado');
  assert.ok(Number.isInteger(imp.impact_hours_since) && imp.impact_hours_since >= 2020, 'impact_hours_since e um ano');
  assert.equal(imp.timeline_is_narrative, true, 'timeline_is_narrative');
  // Controle: o instrumento sabe dizer nao. Assinados e engajados sao diferentes hoje; se fossem iguais, A nao provaria nada.
  assert.notEqual(Number(m.signed), Number(m.engaged), 'controle: signed == engaged, a asserção de chapters nao discrimina');
});
