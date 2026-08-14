/**
 * Contract: #1656 — uma escala no contrato de exibicao de presenca.
 *
 * Regra: a chave de EXIBICAO e percentual 0-100 e o NOME declara a escala (`*_pct`).
 * As primitivas continuam fracao 0-1 (`get_attendance_rate`, `get_attendance_engagement_rate`,
 * `avg_rate`) — contrato ja afirmado por p277-419-m3b. O front nunca mais adivinha a escala:
 * o coalesce `rate <= 1 ? rate * 100 : rate` lia uma taxa legitima de 1% como 100%.
 *
 * Tres camadas, porque nenhuma sozinha observa o mundo:
 *   A. estatica sobre a captura MAIS RECENTE de cada funcao — ponteiro DERIVADO de
 *      loadLatestCaptures(), nunca um caminho de migration escrito a mao (#1682/#569:
 *      um ponteiro hardcoded fica vermelho quando alguem recaptura a funcao corretamente).
 *   A'. md5 do corpo VIVO == a mesma captura (DB-gated). Sem isto, A ficaria verde com o
 *      contrato removido do banco — guard ancorado num arquivo nao observa o mundo (#1649).
 *   B. varredura do front: nenhuma chave `*_pct` multiplicada por 100, e o coalesce de escala
 *      nao volta. Com CONTROLE POSITIVO, que e o que pega o scanner quebrado (#1636).
 *   C. faixa medida no vivo onde o service_role alcanca (as grades sao gateadas em auth.uid()).
 *
 * Migration: 20260810120000_1656_uma_escala_no_contrato_de_presenca.sql
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import {
  loadLatestCaptures, parseMigration, normalizeBody, md5,
} from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIGRATIONS_DIR = resolve(ROOT, 'supabase/migrations');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

/** name@normalized_args -> chave *_pct que a funcao TEM de publicar */
const EXIGE_PCT = {
  'get_tribe_attendance_grid@p_tribe_id integer, p_event_type text': ['rate_pct', 'overall_rate_pct'],
  'get_attendance_grid@p_tribe_id integer, p_event_type text': ['rate_pct', 'overall_rate_pct', 'avg_rate_pct'],
  'get_initiative_attendance_grid@p_initiative_id uuid, p_event_type text': ['rate_pct', 'overall_rate_pct'],
  'exec_tribe_dashboard@p_tribe_id integer, p_cycle text': ['attendance_pct', 'rate_pct'],
  'exec_cross_initiative_comparison@p_kind text, p_cycle text': ['attendance_pct'],
  'exec_all_tribes_summary@': ['attendance_pct'],
  'get_cycle_attendance_overview@p_cycle_code text': ['attendance_pct'],
  'get_tribe_gamification@p_tribe_id integer': ['attendance_pct'],
  'get_initiative_gamification@p_initiative_id uuid': ['attendance_pct'],
  'get_attendance_engagement_summary@p_scope text, p_scope_id integer, p_cycle_start date, p_chapter text': ['avg_pct'],
  'get_attendance_reliability_summary@p_scope text, p_scope_id integer, p_cycle_start date, p_chapter text': ['avg_pct'],
  'get_tribe_stats@p_tribe_id integer': ['attendance_pct'],
  'get_initiative_stats@p_initiative_id uuid': ['attendance_pct'],
};

/** Corpo da captura mais recente, por ponteiro DERIVADO (nunca caminho escrito a mao). */
function corpoDaCapturaMaisRecente() {
  const { latest } = loadLatestCaptures(MIGRATIONS_DIR);
  const porArquivo = new Map();
  for (const [key, cap] of latest) {
    if (!EXIGE_PCT[key]) continue;
    if (!porArquivo.has(cap.file)) {
      porArquivo.set(cap.file, parseMigration(cap.file, readFileSync(join(MIGRATIONS_DIR, cap.file), 'utf8')));
    }
    const bloco = porArquivo.get(cap.file).find(b => `${b.name}@${b.args}` === key);
    latest.get(key).body = bloco ? bloco.body : null;
  }
  return latest;
}

test('#1656 A: toda RPC de exibicao publica a chave *_pct na captura mais recente', () => {
  const latest = corpoDaCapturaMaisRecente();
  const faltando = [];
  for (const [key, chaves] of Object.entries(EXIGE_PCT)) {
    const cap = latest.get(key);
    if (!cap) { faltando.push(`${key}: SEM CAPTURA`); continue; }
    // comentarios fora ANTES de assertar: um guard de presenca/ausencia que le o texto cru
    // casa o proprio comentario (#1586b).
    const codigo = cap.body.replace(/--[^\n]*/g, '');
    for (const chave of chaves) {
      if (!codigo.includes(`'${chave}'`)) faltando.push(`${key}: falta '${chave}' (${cap.file})`);
    }
  }
  assert.deepEqual(faltando, [], `chaves *_pct ausentes:\n${faltando.join('\n')}`);
});

test('#1656 A: a grade de tribo e o painel usam a MESMA formula (0-100, ROUND 1)', () => {
  const latest = corpoDaCapturaMaisRecente();
  const grade = latest.get('get_tribe_attendance_grid@p_tribe_id integer, p_event_type text').body;
  // rate_pct = present / (present+absent+unrecorded) * 100, ROUND 1 — identico ao combined_pct
  // do get_attendance_panel. E o que leva a divergencia painel x grade a 0 (era 27 em 10/08).
  assert.match(
    grade.replace(/\s+/g, ' '),
    /NULLIF\(COUNT\(\*\) FILTER \(WHERE cs\.status IN \('present', 'absent', 'unrecorded'\)\), 0\) \* 100, 1\) AS rate_pct/i,
    'rate_pct tem de sair do denominador do #1657 com ROUND 1 em 0-100',
  );
});

test('#1656 A: as tres grades tratam evento nao selado como unrecorded, nao como falta', () => {
  const latest = corpoDaCapturaMaisRecente();
  const grades = [
    'get_tribe_attendance_grid@p_tribe_id integer, p_event_type text',
    'get_attendance_grid@p_tribe_id integer, p_event_type text',
    'get_initiative_attendance_grid@p_initiative_id uuid, p_event_type text',
  ];
  for (const key of grades) {
    const codigo = latest.get(key).body.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ');
    assert.match(codigo, /roster_sealed_at IS NULL THEN 'unrecorded'/i, `${key}: sem o ramo unrecorded`);
    assert.match(
      codigo,
      /FILTER \(WHERE cs\.status IN \('present', 'absent', 'unrecorded'\)\), 0\)/i,
      `${key}: 'unrecorded' tem de PERMANECER no denominador (senao a taxa infla)`,
    );
  }
});

// ── B: o front nao adivinha mais a escala ────────────────────────────────────
const EXT = ['.ts', '.tsx', '.astro'];
function arquivosDoFront(dir = resolve(ROOT, 'src')) {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...arquivosDoFront(p));
    else if (EXT.some(x => e.name.endsWith(x)) && !e.name.endsWith('database.gen.ts')) out.push(p);
  }
  return out;
}
/** comentarios de linha e de bloco fora — senao o scanner acusa a propria explicacao. */
function semComentarios(src) {
  return src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
}
const COALESCE_DE_ESCALA = /\brate\w*\s*<=\s*1\b|\braw\s*<=\s*1\b|normalizeRate/;
// LEITURA de uma chave `*_pct` (acesso a propriedade, que e como a RPC entrega) multiplicada
// por 100. Nao casa `const progressPct = (feitos / total) * 100`, que e uma fracao calculada
// localmente e nao uma chave do contrato — foi o falso positivo da primeira versao.
const PCT_VEZES_100 = /\.\w*_pct\b[^\n;]{0,80}\*\s*100/;

function varre(regex) {
  const achados = [];
  for (const f of arquivosDoFront()) {
    const src = semComentarios(readFileSync(f, 'utf8'));
    for (const [i, linha] of src.split('\n').entries()) {
      if (regex.test(linha)) achados.push(`${f.replace(ROOT + '/', '')}:${i + 1}: ${linha.trim().slice(0, 120)}`);
    }
  }
  return achados;
}

test('#1656 B: o coalesce de escala nao volta ao front', () => {
  assert.deepEqual(varre(COALESCE_DE_ESCALA), [], 'front voltou a adivinhar a escala');
});

test('#1656 B: nenhuma chave *_pct e multiplicada por 100 no front', () => {
  assert.deepEqual(varre(PCT_VEZES_100), [], 'chave ja em 0-100 sendo multiplicada de novo');
});

test('#1656 B: CONTROLE POSITIVO — o scanner pega o padrao quando ele existe', () => {
  // sem isto, um scanner quebrado (regex que nao casa nada) passaria verde para sempre.
  const amostraCoalesce = 'const x = member.rate <= 1 ? member.rate * 100 : member.rate;';
  const amostraPct = 'const y = Math.round(it.attendance_pct * 100);';
  assert.ok(COALESCE_DE_ESCALA.test(amostraCoalesce), 'scanner do coalesce esta inerte');
  assert.ok(PCT_VEZES_100.test(amostraPct), 'scanner do *_pct * 100 esta inerte');
  // e os negativos: nem a forma CORRETA nem uma fracao calculada localmente podem acusar
  assert.ok(!PCT_VEZES_100.test('const z = it.attendance_pct.toFixed(1);'), 'scanner acusa a forma correta');
  assert.ok(!PCT_VEZES_100.test('const progressPct = total > 0 ? (feitos / total) * 100 : 0;'),
    'scanner acusa fracao calculada localmente, que nao e chave do contrato');
});

// ── A' + C: DB-gated ─────────────────────────────────────────────────────────
test("#1656 A': o corpo VIVO bate com a captura que os testes acima leem", { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
  assert.ok(!error, error?.message);

  const latest = corpoDaCapturaMaisRecente();
  const drift = [];
  for (const key of Object.keys(EXIGE_PCT)) {
    const cap = latest.get(key);
    const [nome] = key.split('@');
    const viva = (data || []).find(r => r.proname === nome && `${nome}@${r.identity_args}` === key);
    if (!viva) { drift.push(`${key}: nao encontrada no banco`); continue; }
    if (viva.body_md5 !== cap.bodyHash) drift.push(`${key}: vivo ${viva.body_md5} != captura ${cap.bodyHash} (${cap.file})`);
  }
  assert.deepEqual(drift, [], `captura estatica nao reflete o banco:\n${drift.join('\n')}`);
});

test('#1656 C: no vivo, *_pct fica em 0-100 e a primitiva *_rate em 0-1', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

  for (const rpc of ['get_attendance_engagement_summary', 'get_attendance_reliability_summary']) {
    const { data, error } = await sb.rpc(rpc, { p_scope: 'global' });
    assert.ok(!error, `${rpc}: ${error?.message}`);
    if (data?.avg_rate != null) {
      const r = Number(data.avg_rate); const p = Number(data.avg_pct);
      assert.ok(r >= 0 && r <= 1, `${rpc}.avg_rate deve ser fracao 0-1, veio ${r}`);
      assert.ok(p >= 0 && p <= 100, `${rpc}.avg_pct deve ser 0-100, veio ${p}`);
      // `avg_pct` e `avg_rate` na escala de exibicao, arredondado a 1 casa — entao o delta maximo
      // legitimo e EXATAMENTE 0.05, e um `<= 0.05` cru vive na fronteira: `0.7415 * 100` da
      // 74.15000000000001 em ponto flutuante, o delta sai 0.050000000000011 e o guard estoura sem
      // que nada esteja errado. Medido em 14/08/2026 com avg_rate=0.7415 / avg_pct=74.1: o teste
      // passava por SORTE e so falhava quando a media caia num `.x5` (a asserção irmã de
      // attendance_pct, logo abaixo, ja usava 0.5 e nunca esbarrou nisso).
      // NAO fixar um modo de arredondamento aqui: `Math.round` sobe no `.5` e o numeric do Postgres
      // desceu (74.15 → 74.1), entao comparar contra um valor "esperado" trocaria este defeito por
      // outro. O invariante e "cabe em uma casa decimal", nos DOIS sentidos — a tolerancia e 0.05
      // mais folga de ponto flutuante.
      assert.ok(Math.abs(p - r * 100) <= 0.05 + 1e-9,
        `${rpc}: avg_pct (${p}) nao e avg_rate*100 (${r * 100}) dentro de uma casa decimal`);
    }
  }

  const ov = await sb.rpc('get_cycle_attendance_overview', {});
  assert.ok(!ov.error, ov.error?.message);
  const membros = ov.data?.members || [];
  assert.ok(membros.length > 0, 'overview sem membros — o teste passaria por vacuidade');
  for (const m of membros) {
    if (m.attendance_pct == null) continue;
    const p = Number(m.attendance_pct);
    assert.ok(p >= 0 && p <= 100, `attendance_pct fora de 0-100: ${p}`);
    if (m.attendance_rate != null) {
      assert.ok(Math.abs(p - Number(m.attendance_rate) * 100) <= 0.5,
        `attendance_pct (${p}) diverge de attendance_rate*100 (${Number(m.attendance_rate) * 100}) alem do arredondamento`);
    }
  }
});
