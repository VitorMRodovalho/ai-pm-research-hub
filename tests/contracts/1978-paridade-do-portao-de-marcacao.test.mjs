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

const ROOT = process.cwd();
const MIG = resolve(ROOT, 'supabase/migrations/20260825034018_1978_paridade_do_portao_de_marcacao_de_entrevista.sql');
const mig = existsSync(MIG) ? readFileSync(MIG, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

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
    const corpo = mig.match(/AS \$function\$([\s\S]*?)\$function\$;/)?.[1];
    assert.ok(corpo, 'o arquivo carrega o corpo entre delimitadores $function$');
    const md5Arquivo = createHash('md5').update(corpo.replace(/\s+/g, ' ')).digest('hex');

    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    const vivas = (data ?? []).filter((f) => f.proname === 'mark_interview_status');
    assert.equal(vivas.length, 1, `esperava UMA mark_interview_status viva, achei ${vivas.length}`);
    assert.equal(vivas[0].body_md5, md5Arquivo,
      'o corpo vivo divergiu do arquivo: a migration deixou de ser a captura (classe do #1932)');
    assert.equal(vivas[0].is_secdef, true, 'continua SECURITY DEFINER');
  });

test('#1978: PARIDADE — as duas portas da entrevista fazem a MESMA pergunta', () => {
  // Esta é a asserção que mede o conserto. Se um dia o critério de UMA delas mudar sem a outra,
  // volta a existir alguém que lança nota e não marca no-show — o defeito do #1978.
  //
  // ⚠️ Lê a captura MAIS NOVA de cada função, não um arquivo fixo. Fixar no arquivo foi
  // exatamente o defeito do #1932: a migration seguinte vira a captura e o guard passa a afirmar
  // texto que produção não executa mais.
  const dir = resolve(ROOT, 'supabase/migrations');
  const capturaMaisNova = (fn) => {
    const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\b[\\s\\S]*?AS \\$function\\$([\\s\\S]*?)\\$function\\$;`);
    const arquivos = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
    for (let i = arquivos.length - 1; i >= 0; i--) {
      const m = readFileSync(resolve(dir, arquivos[i]), 'utf8').match(re);
      if (m) return { arquivo: arquivos[i], corpo: m[1] };
    }
    return null;
  };

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
    // notificacao de comite ficam SEM DESTINATARIO — `PERFORM create_notification(...) FROM
    // selection_committee WHERE role='lead'` com zero linhas nao chama nada, nao falha e nao avisa.
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
      'Enquanto durar, as RPCs de selecao presas a lead so respondem a quem tem manage_platform, ' +
      'e as notificacoes de comite nao tem a quem ser entregues. ' +
      'Conserto e por DADO (designar um lead no comite do ciclo), nao por codigo. ' +
      'Atencao ao p253: o ciclo precisa manter >= 2 linhas evaluator+can_interview.');
  });
