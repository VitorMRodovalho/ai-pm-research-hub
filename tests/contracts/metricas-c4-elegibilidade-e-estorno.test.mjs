// tests/contracts/metricas-c4-elegibilidade-e-estorno.test.mjs
/**
 * Metricas do ciclo 4: presenca devida so a partir da ENTRADA no Nucleo, e presenca desfeita
 * estorna o credito de XP.
 *
 * SINTOMA 1: `_attendance_eligible_events` contava reuniao geral e kickoff para toda pessoa desde o
 * inicio do ciclo, e lideranca pela autoridade de HOJE. O selo grava linha justificada para quem
 * entrou depois do evento (#1948), mas sela cada evento uma vez: quem entra depois do selo fica sem
 * linha, e o LEFT JOIN dos leitores contava isso como falta. Medido em 16/11/2026: 6 pessoas abaixo
 * de 50% so por isso.
 *
 * SINTOMA 2: trocar presente por falta ou justificativa sem apagar a linha nao estornava o credito,
 * e o placar contava presenca que a tabela nega (o defeito 1 da #2292).
 *
 * REGRA: a data de entrada e `_member_operational_since`, a MESMA que o selo usa. Presenca registrada
 * nunca some. O estorno e linha nova negativa (ledger append-only, #1087 onda 3).
 *
 * O detector recebe os corpos como dado: julga as capturas correntes E as adulteradas do teste de
 * mutacao pela MESMA funcao.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const TRIGGER = 'trg_reverse_attendance_credit_on_presence_withdrawn';

const NOMES = {
  central: '_attendance_eligible_events',
  painel: 'get_attendance_panel',
  geral: 'get_attendance_grid',
  tribo: 'get_tribe_attendance_grid',
  selo: '_seal_event_attendance_apply',
  estorno: '_reverse_attendance_credit_on_presence_withdrawn',
};

/** A ULTIMA migration que cria o gatilho, e se alguma depois dela o derruba sem recriar. */
function capturaDoGatilho() {
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  let cria = null;
  let derrubadoDepois = false;
  for (const f of files) {
    const sql = maskLineComments(readFileSync(join(MIG_DIR, f), 'utf8'));
    const m = sql.match(new RegExp(`CREATE TRIGGER ${TRIGGER}[\\s\\S]*?;`));
    if (m) { cria = m[0]; derrubadoDepois = false; continue; }
    if (cria && new RegExp(`DROP TRIGGER (IF EXISTS )?${TRIGGER}`).test(sql)) derrubadoDepois = true;
  }
  return derrubadoDepois ? '' : (cria ?? '');
}

export function capturas() {
  const c = Object.fromEntries(Object.entries(NOMES).map(([k, n]) => [k, latestFunctionCapture(ROOT, n).body]));
  c.gatilho = capturaDoGatilho();
  return c;
}

const PRESENTE = (mem, ev, alias) =>
  `EXISTS \\(SELECT 1 FROM public\\.attendance ${alias} WHERE ${alias}\\.member_id = ${mem} AND ${alias}\\.event_id = ${ev} AND ${alias}\\.present\\)`;

/** Violacoes por superficie. Lista vazia = saudavel. */
export function violacoes(corpos) {
  const v = [];
  const c = Object.fromEntries(Object.entries(corpos).map(([k, b]) => [k, maskLineComments(b)]));

  // 1. metrica central: a data de entrada vem do helper do selo, e CORTA os dois ramos.
  if (!/COALESCE\(public\._member_operational_since\(p_member_id\), '-infinity'::date\) AS since/.test(c.central)) {
    v.push('central: a data de entrada nao vem de _member_operational_since (a regra do selo)');
  }
  const corte = `\\(e\\.date >= win\\.since\\s*OR ${PRESENTE('p_member_id', 'e\\.id', 'a_ent')}\\)`;
  if (!new RegExp(`\\(e\\.type IN \\('geral', 'kickoff'\\)\\s*AND ${corte}\\)`).test(c.central)) {
    v.push('central: reuniao geral/kickoff voltou a ser devida antes da entrada no Nucleo');
  }
  if (!new RegExp(`OR \\(e\\.type = 'lideranca' AND public\\.can_by_member\\(p_member_id, 'manage_event'\\)\\s*AND ${corte}\\)`).test(c.central)) {
    v.push('central: reuniao de lideranca voltou a ser devida antes da entrada no Nucleo');
  }

  // 2. painel: p_cycle_end corta, DENTRO do bloco que conta (entre o LATERAL e o GROUP BY).
  if (!/CROSS JOIN LATERAL public\._attendance_eligible_events\(a\.id, p_cycle_start\) el\s+LEFT JOIN public\.attendance att ON att\.member_id = a\.id AND att\.event_id = el\.event_id\s+WHERE p_cycle_end IS NULL OR el\.event_date <= p_cycle_end\s+GROUP BY a\.id/.test(c.painel)) {
    v.push('painel: p_cycle_end voltou a ser aceito e ignorado');
  }

  // 3. grades: o corte decide 'false' ANTES do ramo que diz 'true' para geral/kickoff, e a data e
  //    a mesma do selo, resolvida por pessoa.
  for (const [k, mem] of [['geral', 'cohort_members'], ['tribo', 'grid_members']]) {
    const corteGrade = c[k].search(new RegExp(
      `WHEN ge\\.type IN \\('geral', 'kickoff', 'lideranca'\\) AND ge\\.date < ent\\.since\\s+AND NOT ${PRESENTE('m\\.id', 'ge\\.id', 'a_ent')} THEN false`));
    const verdadeiro = c[k].search(/WHEN ge\.type IN \('geral', 'kickoff'\) THEN true/);
    if (corteGrade < 0) v.push(`grade ${k}: geral/kickoff/lideranca voltou a ser devida antes da entrada`);
    else if (verdadeiro < 0 || corteGrade > verdadeiro) v.push(`grade ${k}: o corte por entrada vem DEPOIS do 'true' e nao decide nada`);
    if (!new RegExp(`FROM ${mem} m CROSS JOIN LATERAL \\(SELECT COALESCE\\(public\\._member_operational_since\\(m\\.id\\), '-infinity'::date\\) AS since\\) ent CROSS JOIN grid_events ge`).test(c[k])) {
      v.push(`grade ${k}: a data de entrada nao vem de _member_operational_since`);
    }
  }

  // 4. selo: continua decidindo "ingresso posterior" pela MESMA funcao, no ensaio e no ato.
  const selo = c.selo.match(/v_date < public\._member_operational_since\(m\.id\)/g) || [];
  if (selo.length !== 2) v.push(`selo: a regra de entrada aparece ${selo.length} vez(es); leitores e selo divergiriam`);

  // 5. estorno: saldo POSITIVO do evento, negado, pelos dois formatos de ref_id; nunca DELETE.
  if (!/SELECT s\.member_id, s\.organization_id, -s\.pts, 'attendance'/.test(c.estorno)) v.push('estorno: a linha nova nao carrega o saldo NEGADO');
  if (!/COALESCE\(a2\.event_id, gp\.ref_id\) = NEW\.event_id\s+GROUP BY gp\.member_id, gp\.organization_id\s+HAVING SUM\(gp\.points\) > 0/.test(c.estorno)) {
    v.push('estorno: o saldo nao e o do evento por (pessoa, evento), ou estorna saldo nao positivo');
  }
  if (/DELETE\s+FROM\s+public\.gamification_points/i.test(c.estorno)) v.push('estorno: apaga do ledger (append-only, #1087 onda 3)');

  // 6. gatilho: dispara na TRANSICAO presente -> nao presente, depois da escrita.
  if (!new RegExp(`CREATE TRIGGER ${TRIGGER}\\s+AFTER UPDATE OF present ON public\\.attendance\\s+FOR EACH ROW\\s+WHEN \\(OLD\\.present IS TRUE AND NEW\\.present IS NOT TRUE\\)\\s+EXECUTE FUNCTION public\\._reverse_attendance_credit_on_presence_withdrawn\\(\\)`).test(c.gatilho)) {
    v.push('gatilho: nao dispara na transicao presente -> falta/justificativa');
  }
  return v;
}

test('estatico: capturas correntes cortam pela entrada e estornam presenca desfeita', () => {
  assert.deepEqual(violacoes(capturas()), []);
});

test('mutacao: o detector reprova cada defeito, pela MESMA funcao', () => {
  const base = capturas();
  const mut = (k, de, para) => {
    assert.ok(base[k].includes(de), `mutacao sem alvo em ${k}: ${de}`);
    const corpos = { ...base, [k]: base[k].replace(de, para) };
    assert.notEqual(corpos[k], base[k], 'a mutacao nao mudou o corpo');
    return violacoes(corpos).join(' | ');
  };
  assert.match(mut('central', "public._member_operational_since(p_member_id)", 'NULL::date'), /central: a data de entrada/);
  assert.match(mut('central', "(e.type IN ('geral', 'kickoff')\n       AND (e.date >= win.since", "(e.type IN ('geral', 'kickoff')\n       AND (true"), /geral\/kickoff voltou/);
  assert.match(mut('central', "public.can_by_member(p_member_id, 'manage_event')\n          AND (e.date >= win.since", "public.can_by_member(p_member_id, 'manage_event')\n          AND (true"), /lideranca voltou/);
  assert.match(mut('painel', 'WHERE p_cycle_end IS NULL OR el.event_date <= p_cycle_end', ''), /painel/);
  assert.match(mut('geral', 'AND ge.date < ent.since', 'AND false'), /grade geral: geral\/kickoff/);
  assert.match(mut('tribo', 'AND ge.date < ent.since', 'AND false'), /grade tribo: geral\/kickoff/);
  assert.match(mut('geral', "COALESCE(public._member_operational_since(m.id), '-infinity'::date)", "'-infinity'::date"), /grade geral: a data de entrada/);
  assert.match(mut('selo', 'v_date < public._member_operational_since(m.id)', 'false'), /selo/);
  assert.match(mut('estorno', '-s.pts', 's.pts'), /saldo NEGADO/);
  assert.match(mut('estorno', 'HAVING SUM(gp.points) > 0', 'HAVING true'), /saldo nao e o do evento/);
  assert.match(mut('gatilho', 'OLD.present IS TRUE AND NEW.present IS NOT TRUE', 'true'), /gatilho/);
  // ordem: o mesmo corte, movido para depois do 'true', nao decide nada.
  {
    const de = "        WHEN ge.type IN ('geral', 'kickoff') THEN true";
    const b = base.tribo;
    const i = b.indexOf("        WHEN ge.type IN ('geral', 'kickoff', 'lideranca') AND ge.date < ent.since");
    const j = b.indexOf(de);
    assert.ok(i >= 0 && j > i, 'alvo da mutacao de ordem');
    const corteTxt = b.slice(i, j);
    const trocado = b.slice(0, i) + de + '\n' + corteTxt + b.slice(j + de.length + 1);
    assert.notEqual(trocado, b);
    assert.match(violacoes({ ...base, tribo: trocado }).join(' | '), /grade tribo: o corte por entrada vem DEPOIS/);
  }
  assert.deepEqual(violacoes(base), [], 'controle final');
});

test('vivo: quem entrou no ciclo nao deve reuniao geral/kickoff anterior a entrada sem presenca',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    const { data: ciclo, error: e0 } = await sb.from('cycles').select('cycle_start').eq('is_current', true).single();
    assert.ok(!e0, e0?.message);
    const { data: membros, error: e1 } = await sb.from('members').select('id')
      .eq('is_active', true).eq('current_cycle_active', true).limit(200);
    assert.ok(!e1, e1?.message);
    const hoje = new Date(Date.now() - 86400000).toISOString().slice(0, 10);

    let exercidos = 0;
    let positivos = 0;
    for (const m of membros ?? []) {
      const { data: desde, error: e2 } = await sb.rpc('_member_operational_since', { p_member_id: m.id });
      assert.ok(!e2, e2?.message);
      if (!desde || desde <= ciclo.cycle_start) continue;
      const { data: antes } = await sb.from('events').select('id')
        .in('type', ['geral', 'kickoff']).neq('status', 'cancelled')
        .gte('date', ciclo.cycle_start).lt('date', desde);
      if (!antes?.length) continue;
      const { data: pres } = await sb.from('attendance').select('event_id')
        .eq('member_id', m.id).eq('present', true).in('event_id', antes.map((x) => x.id));
      const presentes = new Set((pres ?? []).map((p) => p.event_id));
      const indevidas = antes.filter((x) => !presentes.has(x.id)).map((x) => x.id);
      if (!indevidas.length) continue;

      const { data: el, error: e3 } = await sb.rpc('_attendance_eligible_events', { p_member_id: m.id, p_cycle_start: null });
      assert.ok(!e3, e3?.message);
      const ids = new Set((el ?? []).map((r) => r.event_id));
      assert.deepEqual(indevidas.filter((id) => ids.has(id)), [], 'reuniao geral anterior a entrada, sem presenca, continua devida');
      exercidos += 1;
      // controle positivo: a MESMA chamada devolve reuniao geral depois da entrada, ou o "nao
      // devolveu" acima poderia ser so a funcao devolvendo nada.
      const { data: depois } = await sb.from('events').select('id')
        .in('type', ['geral', 'kickoff']).neq('status', 'cancelled')
        .gte('date', desde).lte('date', hoje);
      positivos += (depois ?? []).filter((x) => ids.has(x.id)).length;
      if (exercidos >= 5) break;
    }
    assert.ok(exercidos > 0, 'nenhuma pessoa exercida: o teste passaria por vacuidade');
    assert.ok(positivos > 0, 'controle positivo: nenhuma reuniao geral depois da entrada foi devolvida');
  });
