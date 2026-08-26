// tests/contracts/2013-lembrete-de-reagendamento-com-teto-e-diagnostico.test.mjs
// Register in BOTH the "test:behavioural" and "test:contracts" whitelists in package.json (#1109).
/**
 * #2013 — o lembrete de reagendamento para de ser assédio.
 *
 * SINTOMA (26/08/2026): uma candidata recebeu "mais um lembrete automático pedindo para remarcar
 * em 48 horas", depois de já ter respondido ao e-mail do Núcleo sem retorno. O canal não estava
 * morto — a cadência estava.
 *
 * QUATRO DEFEITOS, e o que este arquivo afirma sobre cada um:
 *   (1) prazo falso: o texto prometia 48h e "sua candidatura pode ficar pausada". A cadência real
 *       é de 3 dias, indefinida, e NÃO EXISTE estado de pausa. Decisão do PM (26/08): o texto para
 *       de prometer; o estado de pausa não é criado.
 *   (2) sem teto: o laço só parava por mudança de status. Agora há teto por EPISÓDIO, lido do
 *       SSOT (`platform_settings`), com escalação única ao comitê.
 *   (3) `open_count` já estava gravado e ninguém lia: dois padrões opostos recebiam o mesmo
 *       e-mail. O diagnóstico agora vai na escalação — e SEMPRE filtrando por `instrumented`,
 *       porque `open_count = 0` num despacho não medido significa "não medi", não "não abriu".
 *   (4) `interview_status` nunca se limpava: nem `schedule_interview` nem
 *       `submit_interview_scores` escreviam a coluna. O dono passa a ser o trigger canônico.
 *
 * ⚠️ O item 5 do aceite (quem RESPONDE ao e-mail fica invisível) NÃO é fechado por esta onda, e
 * o arquivo não finge que é.
 *
 * Cross-ref: #2013, #2012, #1595, #1855 (catálogo de entrega), #1978 (escada de destinatários).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const capCron = () => latestFunctionCapture(ROOT, 'process_pending_reschedule_nudges');
const capTrg = () => latestFunctionCapture(ROOT, '_trg_sync_interview_to_app_status');

/** Violações do desenho do cron. Lista vazia = saudável (serve ao corpo real e ao adulterado). */
function violacoesCron(corpo) {
  const v = [];

  // (2) o teto vem do SSOT, não de literal no corpo.
  if (!/platform_settings[\s\S]{0,200}selection\.reschedule_nudge_max_dispatches/.test(corpo)) {
    v.push('o teto não é lido de platform_settings — virou hardcode');
  }
  // (2) o teto é comparado contra o que já saiu NO EPISÓDIO
  if (!/dispatched_at >= v_app\.interview_reschedule_requested_at/.test(corpo)) {
    v.push('a contagem de despachos não está escopada ao episódio de reagendamento');
  }
  if (!/v_ep\.despachos >= v_max_dispatches/.test(corpo)) {
    v.push('o teto não é aplicado');
  }
  // (2) ao estourar, NÃO despacha: o CONTINUE tem de vir antes do envio.
  const iTeto = corpo.indexOf('v_ep.despachos >= v_max_dispatches');
  const iDispatch = corpo.indexOf('_dispatch_interview_booking_link');
  if (!(iTeto > 0 && iDispatch > iTeto)) {
    v.push('o teto não precede o despacho — o candidato continuaria recebendo');
  }
  // (2) escalação UMA vez por episódio
  if (!/interview_reschedule_escalated_at IS NULL[\s\S]{0,160}< v_app\.interview_reschedule_requested_at/.test(corpo)) {
    v.push('a escalação não está escopada ao episódio — o comitê seria notificado todo dia');
  }
  if (!/'selection_reschedule_escalated'/.test(corpo)) {
    v.push('a escalação não usa o tipo de notificação próprio');
  }
  if (!/_selection_cycle_recipients/.test(corpo)) {
    v.push('a escalação não usa a escada de destinatários do comitê (#1978)');
  }
  // (3) diagnóstico por open_count, SEMPRE sobre o que foi medido
  if (!/FILTER \(WHERE d\.instrumented\)/.test(corpo)) {
    v.push('o agregado de aberturas não filtra por instrumented — mede "não medi" como "não abriu"');
  }
  for (const code of ['sem_medicao', 'nao_abriu', 'abriu_e_nao_agendou']) {
    if (!corpo.includes(code)) v.push(`o diagnóstico não distingue o caso ${code}`);
  }
  // controle negativo: o que a #1595 garantiu continua de pé
  if (!/Sem link governado não sai cutucão/.test(corpo)) {
    v.push('a garantia do link governado (#1595) saiu do corpo');
  }
  return v;
}

/** Violações do desenho do trigger dono de `interview_status`. */
function violacoesTrigger(corpo) {
  const v = [];
  if (!/interview_status = 'completed'/.test(corpo)) {
    v.push('o trigger não marca a entrevista como concluída');
  }
  // A ordem é o ponto inteiro: escrever DEPOIS do portão terminal não alcança approved/final_eval.
  const iEscrita = corpo.indexOf("interview_status = 'completed'");
  const iPortao = corpo.indexOf("v_app_status IN (");
  if (!(iEscrita > 0 && iPortao > iEscrita)) {
    v.push('a escrita de interview_status não precede o portão terminal — não alcança approved/final_eval');
  }
  // e não pode encostar na coluna do funil antes do portão
  const antesDoPortao = iPortao > 0 ? corpo.slice(0, iPortao) : corpo;
  if (/SET status = /.test(antesDoPortao)) {
    v.push('o trecho antes do portão terminal escreve selection_applications.status');
  }
  // a regra do webhook é espelhada, não duplicada com outro significado
  if (!/WHEN interview_status = 'needs_reschedule'\s*\n?\s*THEN 'rescheduled'/.test(corpo)) {
    v.push('a regra needs_reschedule -> rescheduled do webhook não foi espelhada');
  }
  return v;
}

// ── estático ─────────────────────────────────────────────────────────────────────────
test('#2013 static: o cron tem teto, escalação por episódio e diagnóstico medido', () => {
  const c = capCron();
  assert.ok(c?.body, 'alguma migration captura process_pending_reschedule_nudges');
  assert.deepEqual(violacoesCron(c.body), []);
});

test('#2013 static: o trigger é o dono de interview_status, e escreve ANTES do portão terminal', () => {
  const t = capTrg();
  assert.ok(t?.body, 'alguma migration captura _trg_sync_interview_to_app_status');
  assert.deepEqual(violacoesTrigger(t.body), []);
});

test('#2013 static: reprova o cron que volta a despachar depois do teto', () => {
  const { body } = capCron();
  const adulterado = body.replace('IF v_ep.despachos >= v_max_dispatches THEN', 'IF false THEN');
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoesCron(adulterado);
  assert.ok(v.some((m) => m.includes('teto não é aplicado')),
    `esperava a violação do teto, e veio: ${JSON.stringify(v)}`);
});

test('#2013 static: reprova o agregado que larga o filtro de instrumented', () => {
  const { body } = capCron();
  const adulterado = body.split('FILTER (WHERE d.instrumented)').join('');
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoesCron(adulterado);
  assert.ok(v.some((m) => m.includes('instrumented')),
    `esperava a violação do instrumented, e veio: ${JSON.stringify(v)}`);
});

test('#2013 static: reprova o trigger que escreve interview_status DEPOIS do portão terminal', () => {
  const { body } = capTrg();
  // Recorte por ÍNDICE, não por regex: a asserção é sobre ORDEM, e uma regex sensível a
  // indentação faria a injeção falhar em silêncio — que se leria como "a asserção não pega".
  const i1 = body.indexOf("IF NEW.conducted_at IS NOT NULL OR NEW.status = 'completed' THEN");
  const i2 = body.indexOf('SELECT status INTO v_app_status');
  assert.ok(i1 > 0 && i2 > i1, 'não achei o bloco de interview_status para mover');
  const bloco = body.slice(i1, i2);
  assert.match(bloco, /interview_status = 'completed'/, 'o recorte não pegou o bloco certo');
  const adulterado = body.slice(0, i1) + body.slice(i2) + bloco;
  const v = violacoesTrigger(adulterado);
  assert.ok(v.some((m) => m.includes('precede o portão terminal')),
    `esperava a violação de ordem, e veio: ${JSON.stringify(v)}`);
});

// ── item 5 do aceite: a métrica de despacho não pode ser lida sem separar `instrumented` ──
test('#2013 static: quem lê open_count de selection_dispatch_url_log tem de ler instrumented', () => {
  // Derivado do NOME DA TABELA, não de lista de arquivos: um leitor novo cai no guard sozinho.
  const alvos = [];
  const varrer = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (e.name === 'node_modules' || e.name === 'dist' || e.name.startsWith('.')) continue;
      const p = join(dir, e.name);
      if (e.isDirectory()) varrer(p);
      else if (/\.(sql|ts|tsx|astro|mjs)$/.test(e.name)) alvos.push(p);
    }
  };
  for (const d of ['supabase/migrations', 'supabase/functions', 'src', 'scripts']) {
    const abs = resolve(ROOT, d);
    if (existsSync(abs)) varrer(abs);
  }

  const infratores = [];
  let examinados = 0;
  for (const p of alvos) {
    const src = read(p);
    if (!src.includes('selection_dispatch_url_log')) continue;
    if (!/open_count/.test(src)) continue;
    examinados += 1;
    // Um arquivo que agrega aberturas TEM de saber o que foi medido.
    if (!/instrumented/.test(src)) infratores.push(p.replace(ROOT + '/', ''));
  }

  // Controle POSITIVO: um scanner que não acha nada passaria por vacuidade, que é exatamente o
  // modo de falha que este repo já pagou. Medido em 26/08/2026: 3 arquivos casam a pré-condição.
  assert.ok(examinados >= 3,
    `o scanner examinou ${examinados} arquivo(s): se caiu para zero, o predicado deixou de casar ` +
    'e o guard virou decorativo — conserte o scanner, não a asserção');

  assert.deepEqual(
    infratores, [],
    'estes arquivos leem open_count de selection_dispatch_url_log sem mencionar instrumented — ' +
    'a leitura ingênua dá 4% de conversão onde a correta dá 38%, e o diagnóstico sai OPOSTO: ' +
    JSON.stringify(infratores),
  );
});

// ── o texto para de prometer o que não existe ────────────────────────────────────────
test('#2013 db: o template não promete mais 48h nem pausa, nos três idiomas',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb()
      .from('campaign_templates').select('body_html, body_text')
      .eq('slug', 'interview_reschedule_nudge').single();
    assert.ifError(error);
    const tudo = JSON.stringify(data);
    for (const proibido of ['48 horas', '48h', '48 hours', 'pode ficar pausada', 'may be paused', 'quedar en pausa']) {
      assert.ok(!tudo.includes(proibido), `o template ainda promete "${proibido}"`);
    }
    for (const loc of ['pt', 'en', 'es']) {
      assert.ok((data.body_html?.[loc] || '').length > 0, `body_html.${loc} vazio`);
      assert.ok((data.body_text?.[loc] || '').length > 0, `body_text.${loc} vazio`);
    }
  });

test('#2013 db: o teto existe no SSOT e é um inteiro >= 1',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb()
      .from('platform_settings').select('value')
      .eq('key', 'selection.reschedule_nudge_max_dispatches').single();
    assert.ifError(error);
    const n = Number(data.value);
    assert.ok(Number.isInteger(n) && n >= 1, `teto inválido: ${JSON.stringify(data.value)}`);
  });

test('#2013 db: o tipo novo está no CATÁLOGO de entrega, não caindo no ELSE',
  { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb().rpc('_audit_function_source', { p_proname: '_delivery_mode_for' });
    assert.ifError(error);
    const corpo = (data ?? []).map((r) => r.prosrc).join('\n');
    assert.match(corpo, /WHEN 'selection_reschedule_escalated'\s+THEN 'transactional_immediate'/,
      'o tipo novo cairia no ELSE (digest_weekly), e o digest só entrega a quem tem OUTRO conteúdo (#2010)');
  });

// ── corpo vivo == captura ────────────────────────────────────────────────────────────
for (const fn of ['process_pending_reschedule_nudges', '_trg_sync_interview_to_app_status', '_delivery_mode_for']) {
  test(`#2013 db: md5 do corpo VIVO de ${fn} bate com a captura vigente`,
    { skip: dbGated ? false : skipMsg }, async () => {
      const cap = latestFunctionCapture(ROOT, fn);
      assert.ok(cap?.body, `alguma migration captura ${fn}`);
      const md5Arquivo = createHash('md5').update(cap.body.replace(/\s+/g, ' ')).digest('hex');
      const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
      assert.ifError(error);
      const vivas = (data ?? []).filter((f) => f.proname === fn);
      assert.equal(vivas.length, 1, `esperava UMA ${fn} viva, achei ${vivas.length}`);
      assert.equal(vivas[0].body_md5, md5Arquivo,
        `${fn}: o corpo vivo divergiu da captura (${cap.file}) — classe do #1932`);
    });
}

// ── o efeito, medido ─────────────────────────────────────────────────────────────────
test('#2013 db: nenhuma candidatura com entrevista CONDUZIDA fica em needs_reschedule',
  { skip: dbGated ? false : skipMsg }, async () => {
    // É a invariante que o item 4 cria. Sem ela, a proteção volta a depender do acidente do
    // filtro de status do cron.
    const { data: conduzidas, error: e1 } = await sb()
      .from('selection_interviews').select('application_id')
      .or('conducted_at.not.is.null,status.eq.completed');
    assert.ifError(e1);
    const ids = [...new Set((conduzidas ?? []).map((r) => r.application_id).filter(Boolean))];
    assert.ok(ids.length > 0, 'sem entrevista conduzida não há o que afirmar');

    const sujas = [];
    for (let i = 0; i < ids.length; i += 100) {
      const { data, error } = await sb()
        .from('selection_applications').select('id, interview_status')
        .in('id', ids.slice(i, i + 100))
        .neq('interview_status', 'completed');
      assert.ifError(error);
      sujas.push(...(data ?? []));
    }
    assert.deepEqual(sujas, [],
      `candidaturas com entrevista conduzida e interview_status != completed: ${JSON.stringify(sujas)}`);
  });

test('#2013 db: quem ainda está em needs_reschedule NÃO tem entrevista conduzida',
  { skip: dbGated ? false : skipMsg }, async () => {
    // O outro lado: o guard não pode "limpar tudo". Quem legitimamente precisa remarcar continua
    // marcado — é o controle que separa consertar de apagar.
    const { data, error } = await sb()
      .from('selection_applications').select('id, applicant_name')
      .eq('interview_status', 'needs_reschedule');
    assert.ifError(error);
    for (const a of data ?? []) {
      const { count, error: e2 } = await sb()
        .from('selection_interviews').select('id', { count: 'exact', head: true })
        .eq('application_id', a.id).not('conducted_at', 'is', null);
      assert.ifError(e2);
      assert.equal(count, 0, `${a.id} está em needs_reschedule mas tem entrevista conduzida`);
    }
  });
