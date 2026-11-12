// tests/contracts/3048-presenca-pelo-periodo-do-vinculo.test.mjs
/**
 * #3048 — reuniao de tribo e devida pelo PERIODO do vinculo com aquela tribo, nao pela tribo atual.
 *
 * SINTOMA: quem entrou numa tribo no meio do ciclo aparecia na grade de presenca devendo todas as
 * reunioes da tribo desde o inicio do ciclo, e a metrica geral contava essas reunioes contra a
 * pessoa. Quem trocou de tribo perdia da metrica geral as reunioes (e as presencas) da tribo anterior.
 * Medido em 12/11/2026: 18 pessoas com reunioes anteriores a entrada contando contra elas.
 *
 * REGRA: `_member_engaged_on(membro, iniciativa, data, kind)` diz se o vinculo cobria a data. As cinco
 * superficies decidem reuniao de tribo por ela, e presenca registrada nunca some (cobre vinculo com
 * data de inicio cadastrada depois da presenca real: 4 pessoas no dia da medicao).
 *
 * O detector recebe os corpos como dado: julga as capturas correntes E as adulteradas do teste de
 * mutacao pela MESMA funcao.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const NOMES = {
  helper: '_member_engaged_on',
  central: '_attendance_eligible_events',
  tribo: 'get_tribe_attendance_grid',
  geral: 'get_attendance_grid',
  iniciativa: 'get_initiative_attendance_grid',
  selo: '_seal_event_attendance_apply',
};

export function capturas() {
  return Object.fromEntries(Object.entries(NOMES).map(([k, n]) => [k, latestFunctionCapture(ROOT, n).body]));
}

const PRESENTE = (mem, ev) =>
  `EXISTS \\(SELECT 1 FROM public\\.attendance a3048 WHERE a3048\\.member_id = ${mem} AND a3048\\.event_id = ${ev} AND a3048\\.present\\)`;

/** Violacoes por superficie. Lista vazia = saudavel. */
export function violacoes(corpos) {
  const v = [];
  const c = Object.fromEntries(Object.entries(corpos).map(([k, b]) => [k, maskLineComments(b)]));

  // 1. o helper: inicio, fim (end_date, pausa, encerramento sem fim) e os status que contam.
  if (!/p_date\s*>=\s*en\.start_date/.test(c.helper)) v.push('helper: a data nao e cortada pelo INICIO do vinculo');
  if (!/p_date\s*<=\s*COALESCE\(\s*en\.end_date,\s*CASE WHEN en\.status = 'suspended' THEN \(en\.metadata -> 'pause' ->> 'since'\)::date - 1 END,\s*CASE WHEN en\.status IN \('offboarded', 'expired'\) THEN en\.updated_at::date END,\s*'infinity'::date\)/.test(c.helper)) {
    v.push('helper: o FIM do periodo perdeu end_date, a pausa ou o encerramento sem end_date');
  }
  if (!/en\.status IN \('active', 'suspended', 'offboarded', 'expired'\)/.test(c.helper)) {
    v.push('helper: vinculo encerrado ou pausado deixou de contar para o periodo em que existiu');
  }

  // 2. metrica geral: o ramo 'tribo' decide pelo periodo, com pre-filtro, ou pela presenca.
  const central = new RegExp(
    `e\\.type = 'tribo' AND e\\.initiative_id IS NOT NULL AND \\(\\s*\\(EXISTS \\(SELECT 1 FROM public\\.engagements v3048[^)]*\\)\\s*AND public\\._member_engaged_on\\(p_member_id, e\\.initiative_id, e\\.date, 'volunteer'\\)\\)\\s*OR ${PRESENTE('p_member_id', 'e\\.id')}\\)\\)`);
  if (!central.test(c.central)) v.push('metrica geral: o ramo tribo nao decide pelo periodo do vinculo (ou perdeu a presenca registrada)');
  if (/get_member_tribe/.test(c.central)) v.push('metrica geral: voltou a decidir pela tribo ATUAL (get_member_tribe)');

  // 3. grade da tribo
  const tribo = new RegExp(
    `WHEN ge\\.type = 'tribo' AND ge\\.tribe_id = p_tribe_id THEN \\(\\s*public\\._member_engaged_on\\(m\\.id, ge\\.initiative_id, ge\\.date, 'volunteer'\\)\\s*OR ${PRESENTE('m\\.id', 'ge\\.id')}\\)`);
  if (!tribo.test(c.tribo)) v.push('grade da tribo: reuniao de tribo voltou a ser devida sem olhar o periodo do vinculo');

  // 4. grade geral
  const geral = new RegExp(
    `WHEN ge\\.type = 'tribo' AND ge\\.initiative_id IS NOT NULL THEN \\(\\s*\\(EXISTS \\(SELECT 1 FROM public\\.engagements v3048[^)]*\\)\\s*AND public\\._member_engaged_on\\(m\\.id, ge\\.initiative_id, ge\\.date, 'volunteer'\\)\\)\\s*OR ${PRESENTE('m\\.id', 'ge\\.id')}\\)`);
  if (!geral.test(c.geral)) v.push('grade geral: reuniao de tribo voltou a ser devida pela tribo atual');

  // 5. grade de iniciativa: o 'na' fora do periodo vem ANTES de qualquer leitura da linha.
  const naIni = c.iniciativa.search(/WHEN NOT \(public\._member_engaged_on\(gm\.id, p_initiative_id, ge\.date\)\s*OR \(a\.id IS NOT NULL AND a\.present = true\)\) THEN 'na'/);
  const leitura = c.iniciativa.search(/WHEN a\.id IS NOT NULL AND a\.excused = true THEN 'excused'/);
  if (naIni < 0) v.push("grade de iniciativa: fora do periodo do vinculo a celula deixou de ser 'na'");
  else if (leitura < 0 || naIni > leitura) v.push("grade de iniciativa: o 'na' do periodo vem DEPOIS da leitura da linha e nao decide nada");

  // 6. selo: ensaio e ato com o MESMO predicado de periodo (#2426), e a iniciativa resolvida.
  const pred = c.selo.match(/\(v_type = 'tribo' AND v_tribe_id IS NOT NULL AND public\._member_engaged_on\(m\.id, v_initiative_id, v_date, 'volunteer'\)\)/g) || [];
  if (pred.length !== 2) v.push(`selo: o predicado de periodo aparece ${pred.length} vez(es), devia estar no ensaio E no ato`);
  if (/get_member_tribe/.test(c.selo)) v.push('selo: voltou a decidir a coorte de tribo pela tribo ATUAL');
  if (!/SELECT i\.legacy_tribe_id, i\.id INTO v_tribe_id, v_initiative_id/.test(c.selo)) v.push('selo: v_initiative_id nao e resolvido');
  return v;
}

test('#3048 estatico: as seis capturas correntes decidem reuniao de tribo pelo periodo do vinculo', () => {
  assert.deepEqual(violacoes(capturas()), []);
});

test('#3048 mutacao: o detector reprova cada defeito, pela MESMA funcao', () => {
  const base = capturas();
  const mut = (k, de, para) => {
    assert.ok(base[k].includes(de), `mutacao sem alvo em ${k}: ${de}`);
    const corpos = { ...base, [k]: base[k].replace(de, para) };
    assert.notEqual(corpos[k], base[k], 'a mutacao nao mudou o corpo');
    return violacoes(corpos).join(' | ');
  };
  assert.match(mut('helper', 'p_date >= en.start_date', 'true'), /INICIO do vinculo/);
  assert.match(mut('helper', "'suspended', 'offboarded'", "'offboarded'"), /encerrado ou pausado/);
  assert.match(mut('central', "public._member_engaged_on(p_member_id, e.initiative_id, e.date, 'volunteer')", 'true'), /metrica geral: o ramo tribo/);
  assert.match(mut('tribo', "public._member_engaged_on(m.id, ge.initiative_id, ge.date, 'volunteer')", 'true'), /grade da tribo/);
  assert.match(mut('geral', "AND public._member_engaged_on(m.id, ge.initiative_id, ge.date, 'volunteer')", ''), /grade geral/);
  assert.match(mut('iniciativa', "WHEN NOT (public._member_engaged_on(gm.id, p_initiative_id, ge.date)", 'WHEN false AND (true'), /grade de iniciativa/);
  assert.match(mut('selo', "public._member_engaged_on(m.id, v_initiative_id, v_date, 'volunteer')", 'public.get_member_tribe(m.id) = v_tribe_id'), /selo/);
  assert.deepEqual(violacoes(base), [], 'controle final');
});

test('#3048 vivo: quem entrou no meio do ciclo nao deve as reunioes da tribo anteriores a entrada',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: ciclo, error: e0 } = await sb.from('cycles').select('cycle_start').eq('is_current', true).single();
    assert.ok(!e0, e0?.message);
    const { data: vincs, error: e1 } = await sb.from('engagements')
      .select('person_id, initiative_id, start_date, initiatives!inner(kind)')
      .eq('kind', 'volunteer').eq('status', 'active').eq('initiatives.kind', 'research_tribe')
      .gt('start_date', ciclo.cycle_start).order('start_date', { ascending: false }).limit(40);
    assert.ok(!e1, e1?.message);

    let exercidos = 0;
    let positivos = 0;
    for (const v of vincs ?? []) {
      const { data: m } = await sb.from('members').select('id').eq('person_id', v.person_id).maybeSingle();
      if (!m) continue;
      const { data: antes } = await sb.from('events').select('id')
        .eq('initiative_id', v.initiative_id).eq('type', 'tribo')
        .gte('date', ciclo.cycle_start).lt('date', v.start_date).neq('status', 'cancelled');
      if (!antes?.length) continue;
      const { data: pres } = await sb.from('attendance').select('event_id')
        .eq('member_id', m.id).eq('present', true).in('event_id', antes.map((x) => x.id));
      const presentes = new Set((pres ?? []).map((p) => p.event_id));
      const devidas = antes.filter((x) => !presentes.has(x.id)).map((x) => x.id);
      if (!devidas.length) continue;

      const { data: el, error: e2 } = await sb.rpc('_attendance_eligible_events', { p_member_id: m.id, p_cycle_start: null });
      assert.ok(!e2, e2?.message);
      const ids = new Set((el ?? []).map((r) => r.event_id));
      const vazadas = devidas.filter((id) => ids.has(id));
      assert.deepEqual(vazadas, [], 'reuniao anterior a entrada, sem presenca, continua devida');
      exercidos += 1;
      // controle positivo: a mesma chamada DEVOLVE reuniao da mesma tribo dentro do periodo, ou o
      // "nao devolveu" acima poderia ser so a funcao devolvendo nada.
      const { data: depois } = await sb.from('events').select('id')
        .eq('initiative_id', v.initiative_id).eq('type', 'tribo')
        .gte('date', v.start_date).lt('date', new Date(Date.now() - 86400000).toISOString().slice(0, 10))
        .neq('status', 'cancelled');
      positivos += (depois ?? []).filter((x) => ids.has(x.id)).length;
      if (exercidos >= 5) break;
    }
    assert.ok(exercidos > 0, 'nenhuma pessoa exercida: o guard passaria por vacuidade');
    assert.ok(positivos > 0, 'nenhuma reuniao dentro do periodo foi devolvida: o instrumento nao sabe dizer sim');
  });
