// tests/contracts/1978-paridade-do-portao-de-marcacao.test.mjs
// Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
/**
 * #1978 — `mark_interview_status` ganha o ramo de reivindicação que o #1972 criou só em
 * `submit_interview_scores`.
 *
 * MEDIDO em 25/08/2026: o único ciclo ABERTO (`cycle4-2026`, phase=evaluating) tinha 7 pessoas
 * no comitê e ZERO com `role='lead'` — os papéis usados eram só `evaluator` e `observer`. Nesse
 * estado, 5 dos 7 podiam lançar nota de entrevista e NÃO podiam marcar no-show, cancelamento ou
 * reagendamento; só os 2 com `manage_platform` passavam.
 *
 * POR QUE O #1972 NÃO COBRIU: lá a reivindicação nasce dentro de `submit_interview_scores`, então
 * quem submete nota vira o entrevistador designado e passa a partir dali. Em `noshow`,
 * `cancelled` e `rescheduled` a entrevista NÃO aconteceu, logo não existe submissão de nota que
 * crie a designação antes. Para esses três status não havia caminho nenhum fora do GP.
 *
 * O CONSERTO NÃO AMPLIA O PORTÃO — mesmo critério do #1972: comitê DO CICLO com `can_interview`,
 * só com a lista VAZIA, designação existente nunca sobrescrita, e a reivindicação deixa rastro em
 * `admin_audit_log`.
 *
 * Cross-ref: #1978, #1972, #1932 (a migration precisa SER a captura), #1838.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { createHash } from 'node:crypto';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260825034018_1978_paridade_do_portao_de_marcacao_de_entrevista.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

// A captura de uma funcao e a migration MAIS NOVA que a recria, nunca um arquivo fixo: fixar no
// arquivo foi o defeito do #1932, e este proprio teste caiu nele quando o #1978 (fallback de
// destinatario, 20260825153916) recriou `mark_interview_status` num timestamp posterior ao de
// `MIG`. Usa o scanner compartilhado do #1932, que mascara comentario antes de procurar, trata
// sobrecarga e LANCA em vez de devolver vazio (um helper que devolvesse '' faria todo
// `doesNotMatch` passar sem medir nada).
const DIR_MIG = resolve(ROOT, 'supabase/migrations');
const capturaMaisNova = (fn) => {
  const c = latestFunctionCapture(ROOT, fn);
  return { arquivo: c.file, corpo: c.body };
};

// ── STATIC ────────────────────────────────────────────────────────────────────────────
test('#1978 static: a reivindicação exige comitê DO CICLO com can_interview', () => {
  assert.ok(mig, 'migration existe no timestamp canônico (o mesmo que a linha de tracking)');
  assert.match(mig, /FROM public\.selection_committee sc\s*\n\s*WHERE sc\.member_id = v_caller\.id\s*\n\s*AND sc\.cycle_id = v_app\.cycle_id\s*\n\s*AND sc\.can_interview/);
});

test('#1978 static: só atua com a lista VAZIA — designação existente não é sobrescrita', () => {
  assert.match(mig, /cardinality\(coalesce\(v_interview\.interviewer_ids, ARRAY\[\]::uuid\[\]\)\) = 0/);
  // o RAISE original continua no ramo ELSE: quem não é do comitê segue barrado
  assert.match(mig, /ELSE\s*\n\s*RAISE EXCEPTION 'Unauthorized: must be interviewer, committee lead, or platform admin';/);
});

test('#1978 static: a reivindicação é REGISTRADA e se distingue da do #1972', () => {
  assert.match(mig, /INSERT INTO public\.admin_audit_log[\s\S]{0,500}selection\.interview_self_assigned/);
  // 'via' separa esta porta da do #1972 no log: as duas escrevem a MESMA action
  assert.match(mig, /'via', 'mark_interview_status'/);
  assert.match(mig, /'issue', 1978/);
});

test('#1978 static: o portão original continua sendo a PRIMEIRA pergunta', () => {
  // a reivindicação vive DENTRO do ramo de recusa; quem já é designado nunca chega nela
  const idxPortao = mig.search(/IF NOT \(\s*\n\s*v_caller\.id = ANY\(v_interview\.interviewer_ids\)/);
  const idxClaim = mig.search(/interview_self_assigned/);
  assert.ok(idxPortao > 0, 'o portão original está no arquivo');
  assert.ok(idxClaim > idxPortao, 'a reivindicação é subordinada ao portão, não paralela a ele');
});

test('#1978 static: o ramo de role=lead NÃO foi removido — este conserto soma, não substitui', () => {
  // remover o lead seria tirar autoridade de quem a tem; o vão é a AUSÊNCIA de lead, não a presença
  assert.match(mig, /AND member_id = v_caller\.id AND role = 'lead'/);
});

test('#1978 static: os três status sem nota são a razão de existir do ramo', () => {
  // se um dia alguém restringir a RPC a 'completed', este ramo perde o motivo — que fique escrito
  assert.match(mig, /IF p_status NOT IN \('noshow', 'cancelled', 'rescheduled', 'completed'\)/);
  assert.match(mig, /noshow.*cancelled.*rescheduled|'noshow', 'cancelled' e 'rescheduled'/s);
});

// ── DB ────────────────────────────────────────────────────────────────────────────────
test('#1978 db: a migration É a captura — md5 do arquivo bate com o corpo VIVO',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Classe do #1932: arquivo que descreve corpo que produção não executa. Mesma normalização
    // que o helper usa (`regexp_replace(prosrc,'\s+',' ','g')`).
    const cap = capturaMaisNova('mark_interview_status');
    assert.ok(cap, 'alguma migration captura mark_interview_status');
    const md5Arquivo = createHash('md5').update(cap.corpo.replace(/\s+/g, ' ')).digest('hex');

    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    const vivas = (data ?? []).filter((f) => f.proname === 'mark_interview_status');
    assert.equal(vivas.length, 1, `esperava UMA mark_interview_status viva, achei ${vivas.length}`);
    assert.equal(vivas[0].body_md5, md5Arquivo,
      `o corpo vivo divergiu da captura mais nova (${cap.arquivo}): a migration deixou de ser a ` +
      'captura (classe do #1932)');
    assert.equal(vivas[0].is_secdef, true, 'continua SECURITY DEFINER');
  });

test('#1978: PARIDADE — as duas portas da entrevista fazem a MESMA pergunta', () => {
  // Esta é a asserção que mede o conserto. Se um dia o critério de UMA delas mudar sem a outra,
  // volta a existir alguém que lança nota e não marca no-show — o defeito do #1978.
  //
  // ⚠️ Lê a captura MAIS NOVA de cada função, não um arquivo fixo. Fixar no arquivo foi
  // exatamente o defeito do #1932: a migration seguinte vira a captura e o guard passa a afirmar
  // texto que produção não executa mais.
  for (const fn of ['mark_interview_status', 'submit_interview_scores']) {
    const cap = capturaMaisNova(fn);
    assert.ok(cap, `nenhuma migration captura ${fn}`);
    assert.match(cap.corpo, /cardinality\(coalesce\(v_interview\.interviewer_ids, ARRAY\[\]::uuid\[\]\)\) = 0/,
      `${fn} (captura ${cap.arquivo}) precisa reivindicar SÓ com a lista vazia`);
    assert.match(cap.corpo, /AND sc\.cycle_id = v_app\.cycle_id\s*\n\s*AND sc\.can_interview/,
      `${fn} (captura ${cap.arquivo}) precisa exigir can_interview no comitê DO CICLO`);
    assert.match(cap.corpo, /interview_self_assigned/,
      `${fn} (captura ${cap.arquivo}) precisa deixar rastro da reivindicação`);
  }
});

test('#1978 db: o portão não virou capacidade geral — a população segue ESTREITA',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Injetar o defeito de leitura: se "pode reivindicar" crescer para perto de "membro ativo",
    // o conserto virou ampliação de portão, que é exatamente o que o #1972 recusou fazer.
    const { data: podem, error: e1 } = await sb()
      .from('selection_committee').select('member_id').eq('can_interview', true);
    assert.ifError(e1);
    const { count: ativos, error: e2 } = await sb()
      .from('members').select('id', { count: 'exact', head: true })
      .eq('is_active', true).is('offboarded_at', null);
    assert.ifError(e2);
    assert.ok(podem.length > 0, 'há quem possa reivindicar — senão o conserto não desbloqueia ninguém');
    assert.ok(podem.length < ativos / 4,
      `a população habilitada (${podem.length}) precisa ser muito menor que a de ativos (${ativos}): ` +
      'marcar no-show é ato de comitê, não capacidade geral');
  });

// Decisao isolada numa funcao PURA para que o controle positivo nao dependa de mexer em producao:
// provar que um guard reprova exige injetar o defeito, e o defeito aqui seria "ciclo aberto sem
// lead", que eu nao vou criar no banco compartilhado so para ver o teste ficar vermelho.
export function ciclosAbertosSemLead(ciclos, comitePorCicloId) {
  return (ciclos ?? [])
    .filter((c) => !((comitePorCicloId[c.id] ?? []).some((r) => r.role === 'lead')))
    .map((c) => c.cycle_code ?? c.id);
}

test('#1978: o detector de ciclo-aberto-sem-lead acusa quando deve, e so quando deve', () => {
  // CONTROLE POSITIVO: com o defeito presente, tem que acusar.
  assert.deepEqual(
    ciclosAbertosSemLead(
      [{ id: 'a', cycle_code: 'sem-lead' }],
      { a: [{ role: 'evaluator' }, { role: 'observer' }] },
    ),
    ['sem-lead'],
    'um ciclo aberto so com evaluator/observer PRECISA ser acusado — foi exatamente o estado de 25/08',
  );
  // CONTROLE NEGATIVO: sem o defeito, tem que ficar quieto.
  assert.deepEqual(
    ciclosAbertosSemLead(
      [{ id: 'b', cycle_code: 'com-lead' }],
      { b: [{ role: 'lead' }, { role: 'evaluator' }] },
    ),
    [],
    'um ciclo com lead nao pode ser acusado, senao o guard vira ruido e alguem o desliga',
  );
  // Um lead em OUTRO ciclo nao vale para este.
  assert.deepEqual(
    ciclosAbertosSemLead(
      [{ id: 'c', cycle_code: 'orfao' }],
      { c: [{ role: 'evaluator' }], outro: [{ role: 'lead' }] },
    ),
    ['orfao'],
    'lead e por CICLO: um lead noutro ciclo nao cobre este',
  );
});

test('#1978 db: nenhum ciclo ABERTO pode ficar sem role=lead',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Em 25/08 isto era um `console.warn`, e um aviso que ninguem le nao e guard. Passa a REPROVAR.
    //
    // Por que vale reprovar: com zero leads, 12 RPCs de selecao caem para quem tem
    // manage_platform/manage_member (ou seja, so o GP opera o ciclo) e as 4 superficies de
    // notificacao de comite ficavam SEM DESTINATARIO. Essa metade CADUCOU: o #1978
    // (20260825153916) resolveu por ESTRUTURA, com `_selection_cycle_recipients()`, e o guard
    // segue valendo pelos 12 portoes.
    //
    // Designar lead e ato de governanca, entao o guard nao conserta: ele NOMEIA o ciclo e para a
    // fila ate alguem decidir. Foi a falta desse sinal que deixou o estado passar despercebido.
    const { data: ciclos, error: e1 } = await sb()
      .from('selection_cycles').select('id, cycle_code, status').eq('status', 'open');
    assert.ifError(e1);

    const comitePorCicloId = {};
    for (const c of ciclos ?? []) {
      const { data: com, error: e2 } = await sb()
        .from('selection_committee').select('member_id, role').eq('cycle_id', c.id);
      assert.ifError(e2);
      comitePorCicloId[c.id] = com ?? [];
    }

    const semLead = ciclosAbertosSemLead(ciclos, comitePorCicloId);
    assert.deepEqual(semLead, [],
      `ciclo(s) ABERTO(s) sem nenhum role='lead': ${semLead.join(', ')}. ` +
      'Enquanto durar, as RPCs de selecao presas a lead so respondem a quem tem manage_platform. ' +
      '(As notificacoes ja nao dependem disso desde o #1978: veja _selection_cycle_recipients.) ' +
      'Conserto e por DADO (designar um lead no comite do ciclo), nao por codigo. ' +
      'Atencao ao p253: o ciclo precisa manter >= 2 linhas evaluator+can_interview.');
  });

// ── #1978 fallback de destinatario ────────────────────────────────────────────────────
// A segunda metade da #1978: as 4 superficies de notificacao enderecavam `role='lead'`
// exclusivo, e `PERFORM create_notification(...) FROM ... WHERE role='lead'` com ZERO linhas
// nao chama nada -- nao falha, nao avisa, nao grava. Medido em 25/08/2026: `cycle4-2026`
// alcancava 1 destinatario (o lead corrigido por dado no mesmo dia) e `cycle2-2025`, ZERO.
//
// Mesma classe da #1813, e a decisao do PM e a mesma: fallback ESTRUTURAL. Designar lead
// resolve hoje e volta a falhar calado no proximo ciclo aberto sem lead.

const MIG_FB = resolve(DIR_MIG, '20260825153916_1978_fallback_de_destinatario_das_notificacoes_de_comite.sql');
const migFb = existsSync(MIG_FB) ? readFileSync(MIG_FB, 'utf8') : '';
// Prosa sai antes do assert: os comentarios CITAM o predicado antigo, e guard que le prosa
// acusa a propria documentacao (licao do #1801/#1805/#1809/#1813).
const semProsa = (sql) => sql
  .replace(/COMMENT ON [\s\S]*?';/g, '')
  .split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
const SQL_FB = semProsa(migFb);

test('#1978 fb static: a resolucao virou funcao propria, por ciclo', () => {
  assert.ok(migFb, 'a migration do fallback existe no timestamp canonico (o da linha de tracking)');
  assert.match(SQL_FB, /CREATE OR REPLACE FUNCTION public\._selection_cycle_recipients\(p_cycle_id uuid\)/);
  // `via` e o que deixa o teste distinguir "alertou o lead" de "caiu no fallback"; sem ela o
  // fallback fica indistinguivel do caminho normal, que e como este defeito passou despercebido
  assert.match(SQL_FB, /RETURNS TABLE\(member_id uuid, via text\)/);
});

test('#1978 fb static: a escada tem 3 degraus, e cada um so vale se o anterior for VAZIO', () => {
  // se dois degraus valessem juntos, um ciclo COM lead notificaria tambem o GP -- ruido que faz
  // alguem desligar o alerta, e o degrau 3 e amplo demais para ser paralelo a qualquer coisa
  assert.match(SQL_FB, /WHERE NOT EXISTS \(SELECT 1 FROM leads\)\s*\n\s*AND sc\.cycle_id = p_cycle_id/);
  assert.match(SQL_FB, /WHERE NOT EXISTS \(SELECT 1 FROM leads\)\s*\n\s*AND NOT EXISTS \(SELECT 1 FROM committee\)/);
  // autoridade por capacidade, nunca por rotulo de papel (o mesmo padrao do #1813)
  assert.match(SQL_FB, /m\.is_active\s*\n?\s*AND public\.can_by_member\(m\.id, 'manage_platform'\)/);
  assert.doesNotMatch(SQL_FB, /operational_role\s*=\s*'/, 'autoridade nao se decide por rotulo de papel');
});

test('#1978 fb static: a funcao nova nasce fechada (CREATE FUNCTION concede a PUBLIC)', () => {
  assert.match(SQL_FB, /REVOKE ALL ON FUNCTION public\._selection_cycle_recipients\(uuid\) FROM PUBLIC, anon, authenticated/i);
  assert.match(SQL_FB, /GRANT EXECUTE ON FUNCTION public\._selection_cycle_recipients\(uuid\) TO service_role/i);
});

test('#1978 fb static: as 4 superficies passaram a RESOLVER, e nao carregam mais o predicado cru', () => {
  // Le a captura MAIS NOVA de cada funcao, nunca um arquivo fixo (defeito do #1932).
  const esperado = { mark_interview_status: 2, submit_interview_scores: 1, _selection_status_recompute_cron: 1 };
  for (const [fn, n] of Object.entries(esperado)) {
    const cap = capturaMaisNova(fn);
    assert.ok(cap, `nenhuma migration captura ${fn}`);
    const corpo = semProsa(cap.corpo);
    const chamadas = (corpo.match(/_selection_cycle_recipients\(/g) ?? []).length;
    assert.equal(chamadas, n,
      `${fn} (captura ${cap.arquivo}): esperava ${n} chamada(s) a _selection_cycle_recipients, achei ${chamadas}`);
    assert.doesNotMatch(corpo, /FROM public\.selection_committee sc\s*\n\s*WHERE sc\.cycle_id = v_app\.cycle_id AND sc\.role = 'lead';/,
      `${fn} (captura ${cap.arquivo}) ainda resolve destinatario pelo predicado cru role='lead'`);
    assert.doesNotMatch(corpo, /FROM public\.selection_committee sc\s*\n\s*WHERE sc\.cycle_id = ANY\(v_affected_cycles\)/,
      `${fn} (captura ${cap.arquivo}) ainda resolve destinatario pelo predicado cru no laco do cron`);
  }
});

test('#1978 fb static: o PORTAO de mark_interview_status continua pedindo lead', () => {
  // Notificacao nao e portao. Se este conserto tivesse tirado o lead do portao, teria virado
  // ampliacao de autoridade -- exatamente o que o #1972 e o #1980 recusaram fazer.
  const cap = capturaMaisNova('mark_interview_status');
  assert.match(semProsa(cap.corpo), /WHERE cycle_id = v_app\.cycle_id AND member_id = v_caller\.id AND role = 'lead'/,
    'o portao perdeu o ramo de lead: isto seria mudanca de autoridade, nao de destinatario');
});

test('#1978 fb db: NENHUM ciclo pode resolver para conjunto vazio',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Esta e a assercao que mede o conserto. Zero destinatarios e como o defeito se escondia:
    // `PERFORM ... FROM <vazio>` retorna sem chamar nada, sem erro e sem linha em `notifications`.
    const cli = sb();
    const { data: ciclos, error: e1 } = await cli.from('selection_cycles').select('id, cycle_code, status');
    assert.ifError(e1);
    assert.ok((ciclos ?? []).length > 0, 'ha ciclos para medir');

    for (const c of ciclos) {
      const { data, error } = await cli.rpc('_selection_cycle_recipients', { p_cycle_id: c.id });
      assert.ifError(error);
      assert.ok(Array.isArray(data) && data.length > 0,
        `${c.cycle_code} (${c.status}) resolveu para NENHUM destinatario: as notificacoes de comite ` +
        'desse ciclo voltariam a ser engolidas em silencio');
    }
  });

test('#1978 fb db: ciclo inexistente ou NULL degrada para o GP, nunca para o VAZIO',
  { skip: dbGated ? false : skipMsg }, async () => {
    // O invariante e TOTAL, nao so sobre os ciclos que existem hoje. Se um chamador passar
    // `v_app.cycle_id` nulo (candidatura sem ciclo) a notificacao tem de ir para alguem: cair no
    // vazio seria reintroduzir o defeito por uma porta lateral, e do jeito mais silencioso.
    const cli = sb();
    for (const [rotulo, id] of [['inexistente', '00000000-0000-0000-0000-000000000000'], ['NULL', null]]) {
      const { data, error } = await cli.rpc('_selection_cycle_recipients', { p_cycle_id: id });
      assert.ifError(error);
      assert.ok(Array.isArray(data) && data.length > 0, `cycle_id ${rotulo} resolveu para o VAZIO`);
      assert.equal(data[0].via, 'manage_platform',
        `cycle_id ${rotulo} deveria cair no ultimo degrau, veio '${data[0].via}'`);
    }
  });

test('#1978 fb db: a resolucao escolhe UM degrau, nunca dois ao mesmo tempo',
  { skip: dbGated ? false : skipMsg }, async () => {
    const cli = sb();
    const { data: ciclos, error: e1 } = await cli.from('selection_cycles').select('id, cycle_code');
    assert.ifError(e1);
    for (const c of ciclos ?? []) {
      const { data, error } = await cli.rpc('_selection_cycle_recipients', { p_cycle_id: c.id });
      assert.ifError(error);
      const degraus = [...new Set(data.map((r) => r.via))];
      assert.equal(degraus.length, 1,
        `${c.cycle_code} misturou degraus (${degraus.join(' + ')}): havendo lead responsavel, a ` +
        'notificacao nao pode ir tambem para o comite inteiro nem para o GP');
      assert.ok(['lead', 'committee', 'manage_platform'].includes(degraus[0]), `degrau inesperado: ${degraus[0]}`);
    }
  });

test('#1978 fb db: o degrau escolhido e a CONSEQUENCIA do estado do ciclo, nao um numero fixo',
  { skip: dbGated ? false : skipMsg }, async () => {
    // Medido em 25/08/2026: cycle4-2026 -> lead(1), cycle3-2026 -> lead(2), cycle3-2026-b2 ->
    // lead(1), cycle2-2025 -> manage_platform(2), que e o unico sem lead E sem comite.
    // O teste NAO fixa esses numeros (a plataforma designa lead quando quiser); fixa a implicacao.
    const cli = sb();
    const { data: ciclos, error: e1 } = await cli.from('selection_cycles').select('id, cycle_code');
    assert.ifError(e1);
    for (const c of ciclos ?? []) {
      const [{ data: dest, error: e2 }, { data: com, error: e3 }] = await Promise.all([
        cli.rpc('_selection_cycle_recipients', { p_cycle_id: c.id }),
        cli.from('selection_committee').select('member_id, role').eq('cycle_id', c.id),
      ]);
      assert.ifError(e2);
      assert.ifError(e3);
      const membros = (com ?? []).filter((r) => r.member_id);
      const temLead = membros.some((r) => r.role === 'lead');
      const esperado = temLead ? 'lead' : (membros.length > 0 ? 'committee' : 'manage_platform');
      assert.equal(dest[0].via, esperado,
        `${c.cycle_code}: comite=${membros.length}, lead=${temLead} -> esperava degrau '${esperado}', ` +
        `veio '${dest[0].via}'`);
    }
  });

test('#1978 fb db: a resolucao nao e alcancavel por chamador anonimo',
  { skip: dbGated ? false : skipMsg }, async () => {
    const anon = createClient(
      SUPABASE_URL,
      process.env.PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY ?? 'sem-chave',
      { auth: { persistSession: false } },
    );
    const { error } = await anon.rpc('_selection_cycle_recipients', {
      p_cycle_id: '00000000-0000-0000-0000-000000000000',
    });
    assert.ok(error, 'a resolucao expoe ids de membro e nao pode responder a anonimo');
  });
