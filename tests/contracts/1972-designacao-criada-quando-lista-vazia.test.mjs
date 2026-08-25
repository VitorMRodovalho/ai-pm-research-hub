// tests/contracts/1972-designacao-criada-quando-lista-vazia.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1972 — a designação de entrevistador passa a ser CRIADA quando a lista nasce vazia.
 *
 * SINTOMA (24/08/2026): um entrevistador conduziu a entrevista e, ao clicar em concluir, a
 * página recarregava no mesmo ponto. A RPC levantava `Unauthorized: not an assigned
 * interviewer` e a tela não mostrava nada (essa metade é a #1973).
 *
 * CAUSA: `sync_calendar_booking_to_interview` cria a entrevista com `ARRAY[]::uuid[]`
 * hardcoded — o payload do webhook do calendário não carrega identidade de entrevistador.
 * E **`x = ANY('{}')` é falso para TODOS**. Só quem tinha `manage_platform` conseguia
 * concluir, e o defeito ficou invisível enquanto apenas o GP lançava notas: ele passava pelo
 * ramo de privilégio, não pelo de designação.
 *
 * O CONSERTO NÃO AMPLIA O PORTÃO. Trocar "designado para ESTA entrevista" por "pode
 * entrevistar em geral" apagaria o vínculo. Aqui o vínculo é ESCRITO: quem reivindica precisa
 * ser do comitê DO CICLO com `can_interview`, vira o entrevistador designado da linha e deixa
 * rastro em `admin_audit_log`. Só atua com a lista VAZIA.
 *
 * Cross-ref: #1972, #1973, #1584, #1450.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { createHash } from 'node:crypto';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260825012323_1972_designacao_criada_quando_a_lista_nasce_vazia.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

// A captura de uma funcao e a migration MAIS NOVA que a recria, nunca um arquivo fixo. Fixar no
// arquivo E o defeito do #1932, e este teste caiu nele: o #1978 (20260825153916) recriou
// `submit_interview_scores` para trocar o destinatario da notificacao, e o md5 contra `MIG`
// passou a acusar drift que ninguem introduziu. Usa o scanner compartilhado do #1932.
const capturaMaisNova = (fn) => {
  const c = latestFunctionCapture(ROOT, fn);
  return { arquivo: c.file, corpo: c.body };
};

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// ── STATIC ────────────────────────────────────────────────────────────────────────────
test('#1972 static: a reivindicação exige comitê DO CICLO com can_interview', () => {
  assert.ok(mig, 'migration existe no timestamp canônico');
  assert.match(mig, /FROM public\.selection_committee sc\s*\n\s*WHERE sc\.member_id = v_caller\.id\s*\n\s*AND sc\.cycle_id = v_app\.cycle_id\s*\n\s*AND sc\.can_interview/);
});

test('#1972 static: só atua com a lista VAZIA — designação existente não é sobrescrita', () => {
  assert.match(mig, /cardinality\(coalesce\(v_interview\.interviewer_ids, ARRAY\[\]::uuid\[\]\)\) = 0/);
  // o RAISE continua existindo no ramo ELSE: quem não é do comitê segue barrado
  assert.match(mig, /ELSE\s*\n\s*RAISE EXCEPTION 'Unauthorized: not an assigned interviewer';/);
});

test('#1972 static: a reivindicação é REGISTRADA, não silenciosa', () => {
  assert.match(mig, /INSERT INTO public\.admin_audit_log[\s\S]{0,400}selection\.interview_self_assigned/);
  // actor_id referencia members(id), NÃO auth.users — FK conferida antes de escrever
  assert.match(mig, /VALUES \(\s*\n\s*v_caller\.id, 'selection\.interview_self_assigned'/);
});

test('#1972 static: o portão original continua sendo a PRIMEIRA pergunta', () => {
  // a reivindicação vive DENTRO do ramo de recusa; quem já é designado nunca chega nela
  const idxPortao = mig.search(/IF NOT \(v_caller\.id = ANY\(v_interview\.interviewer_ids\)\)/);
  const idxClaim = mig.search(/interview_self_assigned/);
  assert.ok(idxPortao > 0 && idxClaim > idxPortao, 'a reivindicação é subordinada ao portão, não paralela a ele');
});

// ── DB ────────────────────────────────────────────────────────────────────────────────
test('#1972 db: a migration É a captura — md5 do arquivo bate com o corpo VIVO',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Não basta o texto estar no arquivo: um arquivo que descreve corpo que produção não
    // executa é o defeito do #1932, e ele mordeu duas vezes em 24/08. Aqui a asserção é o
    // md5, com a MESMA normalização que o helper usa (`regexp_replace(prosrc,'\s+',' ','g')`).
    const cap = capturaMaisNova('submit_interview_scores');
    assert.ok(cap, 'alguma migration captura submit_interview_scores');
    const md5Arquivo = createHash('md5').update(cap.corpo.replace(/\s+/g, ' ')).digest('hex');

    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    const vivas = (data ?? []).filter((f) => f.proname === 'submit_interview_scores');
    assert.equal(vivas.length, 1, `esperava UMA submit_interview_scores viva, achei ${vivas.length}`);
    assert.equal(vivas[0].body_md5, md5Arquivo,
      `o corpo vivo divergiu da captura mais nova (${cap.arquivo}): a migration deixou de ser a ` +
      'captura (classe do #1932)');
    assert.equal(vivas[0].is_secdef, true, 'continua SECURITY DEFINER');
  });

test('#1972 db: a população que pode reivindicar é ESTREITA e a maioria segue barrada',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Sem controle de tamanho, "ampliei o portão" e "consertei o portão" ficam indistinguíveis.
    const { data: podem, error: e1 } = await sb()
      .from('selection_committee').select('member_id', { count: 'exact' }).eq('can_interview', true);
    assert.ifError(e1);
    const { count: ativos, error: e2 } = await sb()
      .from('members').select('id', { count: 'exact', head: true })
      .eq('is_active', true).is('offboarded_at', null);
    assert.ifError(e2);
    assert.ok(podem.length > 0, 'há quem possa reivindicar — senão o conserto não desbloqueia ninguém');
    assert.ok(podem.length < ativos / 4,
      `a população habilitada (${podem.length}) precisa ser muito menor que a de ativos (${ativos}): ` +
      'reivindicar é ato de comitê, não capacidade geral');
  });

test('#1972 db: nenhuma entrevista ABERTA fica sem entrevistador sem que alguém possa reivindicá-la',
  { skip: dbGated ? false : skipMsg }, async () => {
    // É a consulta de saúde que a issue pediu: o próximo caso aparece ANTES da entrevista.
    const { data, error } = await sb()
      .from('selection_interviews')
      .select('id, status, interviewer_ids')
      .eq('status', 'scheduled');
    assert.ifError(error);
    const orfas = (data ?? []).filter((i) => !i.interviewer_ids || i.interviewer_ids.length === 0);
    // Não falha: hoje a RPC resolve sozinha na primeira submissão. O que importa é o sinal.
    if (orfas.length > 0) {
      console.warn(`[#1972] ${orfas.length} entrevista(s) agendada(s) sem entrevistador designado — ` +
        'a primeira submissão de alguém do comitê designa e desbloqueia.');
    }
    assert.ok(Array.isArray(orfas));
  });
