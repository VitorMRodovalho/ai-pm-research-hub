// tests/contracts/2461-roster-externo-e-presenca.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * A contagem da iniciativa inclui o participante externo, e a presenca nao passa de 100%.
 *
 * O CASO (#2461, medido 25/09/2026 no Hackathon):
 *  - a tela mostrou 140% de presenca: 7 presencas / (5 do roster x 1 evento). As 2 extras eram de
 *    vinculos role='observer', fora do roster, contadas no numerador e nao no denominador;
 *  - os externos do Student Club (kind='observer', role participant/coordinator) nao contavam como
 *    membros. Desde a #2400, kind='observer' significa vinculo EXTERNO (ADR-0131), e o dono decidiu
 *    que o externo que participa conta.
 *
 * O guard afirma:
 *  1. a taxa de presenca (rate e pct) le o numerador restrito ao roster, e esse recorte filtra por
 *     init_members;
 *  2. pelo EFEITO na view: um observer x participant ativo esta no roster; um visitante nao;
 *  3. alargar a view nao concede autoridade: os dois portoes que a leem exigem role='leader'.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** A taxa le o numerador do roster, nos dois nomes, e o recorte filtra por init_members. */
export function presenca(body) {
  const c = sql(body);
  const bloco = (nome) => (c.match(new RegExp(`'${nome}', \\(SELECT round\\((.*?)\\) FROM (\\w+) a\\)`)) || [])[2];
  return {
    rateDoRoster: bloco('attendance_rate') === 'att_roster',
    pctDoRoster: bloco('attendance_pct') === 'att_roster',
    recorteNoRoster: /att_roster AS \( SELECT a\.event_id, a\.member_id FROM att a WHERE a\.member_id IN \(SELECT im\.id FROM init_members im\) \)/.test(c),
  };
}

/** O portao de autoridade que le a view exige role='leader' no mesmo EXISTS. */
export function portaoSoLider(body) {
  return /FROM public\.v_initiative_roster r WHERE r\.initiative_id = [\w.]+ AND r\.member_id = [\w.]+ AND r\.role = 'leader'/.test(sql(body));
}

const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#2461: a taxa de presenca conta so quem esta no denominador' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const p = presenca(await corpo('get_initiative_stats'));
    assert.deepEqual(p, allTrue(p));
  });

test(dbGated ? '#2461: participante externo esta no roster, visitante nao (pelo efeito)' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const c = sb();
    const { data: ext, error } = await c.from('engagements').select('person_id, initiative_id, role')
      .eq('status', 'active').eq('kind', 'observer').in('role', ['participant', 'coordinator'])
      .not('initiative_id', 'is', null);
    assert.equal(error, null);
    // controle: sem externo ativo, "esta no roster" passaria por vacuidade
    assert.ok(ext.length > 0, 'nenhum observer x participant/coordinator ativo para medir');
    for (const e of ext) {
      const { data: r } = await c.from('v_initiative_roster').select('person_id')
        .eq('initiative_id', e.initiative_id).eq('person_id', e.person_id);
      assert.equal(r?.length, 1, `externo ${e.role} fora do roster da iniciativa ${e.initiative_id}`);
    }
    const { data: vis } = await c.from('engagements').select('person_id, initiative_id')
      .eq('status', 'active').eq('role', 'observer').not('initiative_id', 'is', null).limit(5);
    assert.ok(vis.length > 0, 'controle: nenhum visitante (role=observer) ativo para medir');
    for (const v of vis) {
      const { data: r } = await c.from('v_initiative_roster').select('person_id')
        .eq('initiative_id', v.initiative_id).eq('person_id', v.person_id).eq('role', 'observer');
      assert.equal(r?.length, 0, 'role=observer entrou no roster');
    }
  });

test(dbGated ? '#2461: os portoes de autoridade que leem o roster exigem lider' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    for (const fn of ['_can_manage_recurring_rule', '_can_sign_gate']) {
      assert.equal(portaoSoLider(await corpo(fn)), true, `${fn} deixou de exigir role='leader' ao ler o roster`);
    }
  });

test('#2461 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const S = `att_roster AS (
      SELECT a.event_id, a.member_id FROM att a
      WHERE a.member_id IN (SELECT im.id FROM init_members im)
    ),
    'attendance_rate', (SELECT round(
        count(a.*)::numeric / NULLIF(x, 0) * 100, 0
      ) FROM att_roster a),
      -- #1656
      'attendance_pct', (SELECT round(
        count(a.*)::numeric / NULLIF(x, 0) * 100, 0
      ) FROM att_roster a),`;
  assert.deepEqual(presenca(S), allTrue(presenca(S)));
  // 1: a taxa volta a ler todos os presentes (o defeito original)
  assert.equal(presenca(m(S, "'attendance_rate', (SELECT round(\n        count(a.*)::numeric / NULLIF(x, 0) * 100, 0\n      ) FROM att_roster a)", "'attendance_rate', (SELECT round(\n        count(a.*)::numeric / NULLIF(x, 0) * 100, 0\n      ) FROM att a)")).rateDoRoster, false);
  assert.equal(presenca(m(S, /FROM att_roster a\),$/, 'FROM att a),')).pctDoRoster, false);
  // 2: o recorte perde o filtro
  assert.equal(presenca(m(S, '\n      WHERE a.member_id IN (SELECT im.id FROM init_members im)', '')).recorteNoRoster, false);
  // 3: o portao deixa de exigir lider
  const G = "EXISTS (SELECT 1 FROM public.v_initiative_roster r WHERE r.initiative_id = p_initiative_id AND r.member_id = p_member_id AND r.role = 'leader')";
  assert.equal(portaoSoLider(G), true);
  assert.equal(portaoSoLider(m(G, " AND r.role = 'leader'", '')), false);
});
