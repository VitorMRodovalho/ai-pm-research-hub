// #2553 PR 2, pacote DB-3: get_public_research_lines, as linhas de pesquisa da home numa leitura pública só (D5).
//
// Nome e quadrante das linhas vinham de src/data/tribes.ts. O guard afirma (A) estático: SECURITY DEFINER, só linha
// ativa e visível, horário só do slot ativo, vagas da contagem canônica, nenhum nome de pessoa; (B) com banco, como
// anon: uma linha por linha ativa (a mesma contagem do hero), nome nos 3 idiomas, vagas como contagem.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const DIR = 'supabase/migrations';
const FILE = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort().find((f) => /_2553_linhas_de_pesquisa_publicas\.sql$/.test(f));
const SQL = FILE ? maskLineComments(readFileSync(join(DIR, FILE), 'utf8')) : '';
const body = SQL.match(/CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.get_public_research_lines\(\)[\s\S]*?\$function\$;/i)?.[0] ?? '';
const KEYS = ['capacity', 'deliverables_i18n', 'description_i18n', 'members', 'name_i18n', 'quadrant', 'quadrant_name_i18n', 'slots', 'tribe_id'];

describe('#2553 DB-3 linhas de pesquisa, estático', () => {
  it('a função existe, é SECURITY DEFINER com search_path fixo, e o anon executa', () => {
    assert.ok(FILE, 'migration *_2553_linhas_de_pesquisa_publicas.sql ausente');
    assert.ok(body, 'get_public_research_lines não está definida');
    assert.match(body, /\bSECURITY DEFINER\b/);
    assert.match(body, /SET search_path TO 'public', 'pg_temp'/);
    assert.match(SQL, /REVOKE ALL ON FUNCTION public\.get_public_research_lines\(\) FROM PUBLIC;\s*GRANT EXECUTE ON FUNCTION public\.get_public_research_lines\(\) TO anon, authenticated, service_role;/);
  });

  it('só linha ativa e visível, horário só do slot ativo, vagas da contagem canônica', () => {
    assert.match(body, /RETURNS TABLE\(tribe_id integer, name_i18n jsonb, quadrant text, quadrant_name_i18n jsonb,\s+description_i18n jsonb, deliverables_i18n jsonb, slots jsonb, members integer, capacity integer\)/);
    assert.match(body, /WHERE t\.is_active = true\s+AND coalesce\(i\.visibility, 'standard'\) <> 'confidential'\s+AND public\.rls_can_see_initiative\(i\.id\)/);
    assert.match(body, /WHERE s\.tribe_id = t\.id AND s\.is_active = true/);
    assert.match(body, /WITH seats AS \(SELECT public\.count_tribe_slots\(\)::jsonb AS j\),\s+cap AS \(SELECT public\.tribe_capacity_limit\(\) AS n\)/);
    assert.match(body, /coalesce\(\(seats\.j->>t\.id::text\)::integer, 0\),\s+cap\.n/);
  });

  it('nenhum nome de pessoa (D3)', () => {
    // o nome da linha (t.name) entra como reserva do name_i18n; nome de pessoa não entra
    assert.doesNotMatch(body, /leader|public\.members|public_members|linkedin|photo/i);
  });
});

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const ANON_KEY = process.env.PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const anon = SUPABASE_URL && ANON_KEY ? createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } }) : null;

describe('#2553 DB-3 linhas de pesquisa, como anon', { skip: !anon && 'sem SUPABASE_URL + chave anon' }, () => {
  it('uma por linha ativa (a contagem do hero), nome nos 3 idiomas, vagas como contagem', async () => {
    const stats = await anon.rpc('get_homepage_stats');
    assert.equal(stats.error, null, `controle positivo: ${stats.error?.message}`);
    const { data: rows, error } = await anon.rpc('get_public_research_lines');
    assert.equal(error, null, error?.message);
    assert.equal(rows.length, stats.data.tribes, 'linhas da home diferente da contagem do hero');
    for (const r of rows) {
      assert.deepEqual(Object.keys(r).sort(), KEYS);
      for (const l of ['pt', 'en', 'es']) assert.ok(typeof r.name_i18n?.[l] === 'string' && r.name_i18n[l].trim(), `T${r.tribe_id} sem nome em ${l}`);
      assert.ok(Number.isInteger(r.members) && r.members >= 0 && r.capacity > 0);
    }
  });
});
