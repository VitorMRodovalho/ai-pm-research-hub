/**
 * Contract: #1598 + #1599 — a cauda do arco #1594/#1595, no caminho de resgate.
 * Migration: supabase/migrations/20260805000511_1598_1599_rescues_checam_recusa_crons_gravam_erro.sql
 *
 * #1598 — os 2 rescues (`selection_rescue_stuck_interview`, `selection_rescue_unbooked_invite`)
 * chamavam `notify_selection_cutoff_approved` e NÃO checavam o retorno. Dependiam da exceção para
 * atomicidade; depois do #1594 a recusa de gate deixou de levantar, então o cancel/incremento
 * persistia SEM e-mail. `unbooked_invite` queimava o cap=1 em silêncio.
 *
 * #1599 — os dois crons de resgate descartavam o `SQLERRM` no `EXCEPTION WHEN OTHERS`. Seis
 * execuções consecutivas gravaram `error_count: 1` e nada mais, e a causa é hoje irrecuperável.
 *
 * ⚠️ SOBRE O RESÍDUO DESTE ARQUIVO. A metade (b) do #1594 exige que a recusa COMMITE, então uma
 * recusa exercida aqui deixa linha em `gate_attempts` — que é registro VERDADEIRO (uma tentativa
 * realmente aconteceu), não sujeira. Nenhum e-mail sai: é exatamente o que a metade (a) afirma. A
 * candidatura usada é REAL e do ciclo aberto (o rescue exige ciclo `open`, então o truque de ciclo
 * fechado do arquivo do #1594 não serve aqui). Por isso a escada de segurança: a recusa é PROVADA
 * por sonda no core ANTES de a porta ser exercida — sem essa prova o teste NÃO chama o rescue,
 * porque um fix quebrado queimaria o cap de um candidato real.
 */

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';

const ROOT = process.cwd();
const MIG_PATH = 'supabase/migrations/20260805000511_1598_1599_rescues_checam_recusa_crons_gravam_erro.sql';
const MIG = existsSync(resolve(ROOT, MIG_PATH)) ? readFileSync(resolve(ROOT, MIG_PATH), 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } }) : null;

const RESCUES = ['selection_rescue_stuck_interview', 'selection_rescue_unbooked_invite'];
const CRONS = ['_selection_stuck_scheduled_rescue_cron', '_selection_unbooked_rescue_cron'];

// ── Offline: a migration existe e carrega a decisão ───────────────────────────
describe('#1598/#1599 — migration', () => {
  it('a migration existe no timestamp canônico', () => {
    assert.ok(MIG, `migration precisa existir em ${MIG_PATH}`);
  });

  it('redefine as 4 funções do caminho de resgate', () => {
    for (const fn of [...RESCUES, ...CRONS]) {
      assert.match(MIG, new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn}\\(`), `${fn} redefinida`);
    }
  });

  it('preserva o modelo de grant de cada função (rescues authenticated; crons service_role-only)', () => {
    for (const fn of RESCUES) {
      assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\(uuid\\) FROM PUBLIC, anon;`));
      assert.match(MIG, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\(uuid\\) TO authenticated, service_role;`));
    }
    for (const fn of CRONS) {
      assert.match(MIG, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\(\\) FROM PUBLIC, anon, authenticated;`));
      assert.match(MIG, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\(\\) TO service_role;`));
    }
  });
});

// ── DB: guard de CLASSE (aceite #1598, item 5) ────────────────────────────────
describe('#1598 — guard de classe: quem chama o notify checa o retorno', () => {
  it('nenhum chamador de notify_selection_cutoff_approved ignora o retorno', { skip: dbGated ? false : skipMsg }, async () => {
    // Guard de CLASSE, não lista de nomes: o quarto chamador nasce coberto. É o mesmo instrumento
    // que o #1595 usou para provar 3 -> 0 links crus, e foi ele que mediu este buraco.
    const { data: callers, error: e0 } = await sb.rpc('_audit_functions_matching', {
      p_pattern: 'notify_selection_cutoff_approved',
    });
    assert.ifError(e0);
    const { data: checkers, error: e1 } = await sb.rpc('_audit_functions_matching', {
      p_pattern: "->>\\s*'success'",
    });
    assert.ifError(e1);

    const checks = new Set((checkers ?? []).map((r) => r.proname));
    // a própria notify é a PRODUTORA do retorno, não consumidora.
    const consumers = (callers ?? []).map((r) => r.proname).filter((n) => n !== 'notify_selection_cutoff_approved');

    assert.ok(consumers.length >= 3, `esperava ao menos 3 consumidores, achei ${consumers.length}`);
    const blind = consumers.filter((n) => !checks.has(n));
    assert.deepEqual(blind, [], `estes chamam notify e não leem o retorno: ${blind.join(', ')}`);
  });

  it('nos 2 rescues, o despacho vem ANTES da mutação (é a inversão que fecha a #1598)', { skip: dbGated ? false : skipMsg }, async () => {
    // Invariante causal, não cosmética: se a mutação voltar a preceder o despacho, a recusa volta a
    // persistir estado sem e-mail — que é o defeito inteiro.
    const mutacao = {
      selection_rescue_stuck_interview: /SET status = 'cancelled'/,
      selection_rescue_unbooked_invite: /interview_auto_rescue_count = interview_auto_rescue_count \+ 1/,
    };

    for (const fn of RESCUES) {
      const { data, error } = await sb.rpc('_audit_function_source', { p_proname: fn });
      assert.ifError(error);
      assert.ok(data?.length > 0, `${fn} não existe no banco`);
      const src = data[0].prosrc;

      const iDispatch = src.indexOf('notify_selection_cutoff_approved(p_application_id)');
      assert.ok(iDispatch > -1, `${fn} precisa chamar o notify`);

      const m = src.match(mutacao[fn]);
      assert.ok(m, `${fn}: mutação de estado não encontrada — o padrão ficou obsoleto, corrigir o teste`);
      assert.ok(
        iDispatch < src.indexOf(m[0]),
        `${fn}: a mutação de estado acontece ANTES do despacho — regressão da #1598`,
      );

      // A recusa não pode voltar a ser exceção: a linha de gate_attempts precisa commitar (#1594).
      assert.match(src, /RETURN jsonb_build_object\(\s*'success', false/, `${fn}: a recusa tem de ser RETURN`);
    }
  });
});

// ── DB: comportamento — as três metades do aceite (#1598, item 4) ─────────────
describe('#1598 — na recusa: sem e-mail, sem mutação, COM linha em gate_attempts', () => {
  let alvo = null;
  let recusaProvada = false;
  let antes = null;

  before(async () => {
    if (!dbGated) return;

    // Alvo escolhido por PREDICADO, nunca por id fixo: candidatura do ciclo aberto que o
    // `unbooked_invite` aceitaria (open + interview_pending + cap 0) e que o core RECUSA em modo
    // `full` (sem linha de entrevista → modo full).
    //
    // ⚠️ #1640 — a âncora MUDOU. Ela era "sem análise de IA → P0001", e esse gate saiu. Manter o
    // predicado antigo faria esta sonda EMITIR um token real para um candidato de ciclo ABERTO e,
    // pior, destravaria a chamada de rescue logo abaixo. A recusa agora tem de vir de um gate que
    // sobreviveu: peer-review incompleto (P0002) ou nota não calculada (P0003).
    const { data: cycles } = await sb.from('selection_cycles').select('id').eq('status', 'open');
    const openIds = (cycles ?? []).map((c) => c.id);
    if (!openIds.length) return;

    const { data: apps } = await sb
      .from('selection_applications')
      .select('id, status, interview_auto_rescue_count, cutoff_approved_email_sent_at, updated_at, objective_score_avg')
      .in('cycle_id', openIds)
      .eq('status', 'interview_pending')
      .eq('interview_auto_rescue_count', 0);

    for (const a of apps ?? []) {
      const { count } = await sb
        .from('selection_interviews')
        .select('id', { count: 'exact', head: true })
        .eq('application_id', a.id);
      if ((count ?? 0) > 0) continue; // linha de entrevista → reuse_prior, não recusa
      const { count: evals } = await sb
        .from('selection_evaluations')
        .select('id', { count: 'exact', head: true })
        .eq('application_id', a.id);
      const codigo = (evals ?? 0) < 2 ? 'P0002' : (a.objective_score_avg === null ? 'P0003' : null);
      if (!codigo) continue;          // passaria no gate — emitir aqui seria convite real por teste
      // preferir quem TEM carimbo: só assim o restore do carimbo é observável.
      if (!alvo || (a.cutoff_approved_email_sent_at && !alvo.cutoff_approved_email_sent_at)) {
        alvo = { ...a, codigo };
      }
    }
    if (alvo) antes = { ...alvo };
  });

  it('sonda: o core RECUSA esta candidatura em modo full', { skip: dbGated ? false : skipMsg }, async () => {
    if (!alvo) {
      // Dizer alto: skip lê como verde, e uma asserção não exercida não é uma asserção.
      // Medido em 07/08/2026, logo após a #1640: NENHUMA candidatura `interview_pending` do ciclo
      // aberto recusa mais — as 11 têm 2 avaliações e nota. A população que tornava esta asserção
      // exercível era, em boa parte, a que o gate de IA barrava indevidamente.
      console.log('[1598] nenhuma candidatura do ciclo aberto recusa em modo full — asserção não exercida');
      return;
    }
    const { data, error } = await sb.rpc('_issue_interview_booking_token_core', {
      p_application_id: alvo.id,
      p_bypass_granted: false,
      p_caller_id: null,
      p_bypass_requested: false,
    });
    assert.ifError(error);
    assert.equal(data?.success, false, 'o core tinha de recusar');
    assert.equal(data?.gate_failed_code, alvo.codigo);
    assert.equal(data?.gate_mode, 'full');
    recusaProvada = true;
  });

  it('o rescue devolve {success:false} e NÃO queima o cap, NÃO manda e-mail, e DEIXA a linha de auditoria', { skip: dbGated ? false : skipMsg }, async () => {
    if (!alvo || !recusaProvada) {
      // Trava deliberada: sem a prova acima, chamar o rescue arriscaria queimar o cap de um
      // candidato real e mandar convite indevido.
      console.log('[1598] porta não exercida: a recusa do core não foi provada nesta corrida');
      return;
    }

    const refusalsAntes = (
      await sb.from('gate_attempts').select('id', { count: 'exact', head: true })
        .eq('application_id', alvo.id).eq('gate_passed', false)
    ).count ?? 0;

    const dispatchAntes = (
      await sb.from('admin_audit_log').select('id', { count: 'exact', head: true })
        .eq('action', 'selection.cutoff_approved_email_dispatched').eq('target_id', alvo.id)
    ).count ?? 0;

    const rescuedAntes = (
      await sb.from('admin_audit_log').select('id', { count: 'exact', head: true })
        .eq('action', 'selection.unbooked_invite_rescued').eq('target_id', alvo.id)
    ).count ?? 0;

    const { data, error } = await sb.rpc('selection_rescue_unbooked_invite', { p_application_id: alvo.id });

    // Metade zero: a recusa NÃO pode chegar como exceção (isso desfaria a linha de gate_attempts).
    assert.ifError(error);
    assert.equal(data?.success, false, 'o rescue tinha de recusar');
    assert.equal(data?.reason, 'gate_refused');
    assert.equal(data?.cap_consumed, false);
    assert.equal(data?.gate_failed_code, alvo.codigo);   // #1640: era P0001 fixo

    // Metade (a): nenhum e-mail — nem despacho de cutoff, nem audit de resgate.
    const dispatchDepois = (
      await sb.from('admin_audit_log').select('id', { count: 'exact', head: true })
        .eq('action', 'selection.cutoff_approved_email_dispatched').eq('target_id', alvo.id)
    ).count ?? 0;
    assert.equal(dispatchDepois, dispatchAntes, 'saiu e-mail numa recusa de gate');

    const rescuedDepois = (
      await sb.from('admin_audit_log').select('id', { count: 'exact', head: true })
        .eq('action', 'selection.unbooked_invite_rescued').eq('target_id', alvo.id)
    ).count ?? 0;
    assert.equal(rescuedDepois, rescuedAntes, 'gravou audit de resgate numa recusa');

    // Metade (b): a candidatura ficou INTACTA — o cap não foi queimado e o carimbo voltou.
    const { data: depois, error: e2 } = await sb
      .from('selection_applications')
      .select('interview_auto_rescue_count, cutoff_approved_email_sent_at, status, updated_at')
      .eq('id', alvo.id)
      .single();
    assert.ifError(e2);
    assert.equal(depois.interview_auto_rescue_count, 0, 'o cap=1 foi queimado numa recusa — é o defeito da #1598');
    assert.equal(
      depois.cutoff_approved_email_sent_at,
      antes.cutoff_approved_email_sent_at,
      'o carimbo de idempotência não foi restaurado — a candidatura sairia da fila do cron',
    );
    assert.equal(depois.status, 'interview_pending');
    assert.equal(depois.updated_at, antes.updated_at, 'updated_at foi bumpado numa recusa (muda a ordem da fila)');

    // Metade (c): a tentativa recusada EXISTE na auditoria (é o #1594 valendo aqui dentro).
    const refusalsDepois = (
      await sb.from('gate_attempts').select('id', { count: 'exact', head: true })
        .eq('application_id', alvo.id).eq('gate_passed', false)
    ).count ?? 0;
    assert.ok(
      refusalsDepois > refusalsAntes,
      'a recusa não deixou linha em gate_attempts — auditoria decorativa de novo',
    );
  });
});

// ── Consumidores: a metade que o #1594 esqueceu, virada em asserção ───────────
describe('#1598 — os consumidores do rescue tratam success:false', () => {
  // A mudança de exceção para retorno estruturado NÃO termina no banco: quem lê só `error` passa a
  // ler RECUSA como SUCESSO. Foi assim que a #1598 nasceu. Aqui isso é guard, não memória.
  const ASTRO = readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8');
  const MCP = readFileSync(resolve(ROOT, 'supabase/functions/nucleo-mcp/index.ts'), 'utf8');

  // Fatia entre ÂNCORAS REAIS, nunca por N bytes: uma janela de tamanho fixo reprova (ou aprova)
  // por contagem de caracteres, que foi exatamente o defeito do guard `p280-411-w1c` corrigido no
  // #1594. E `indexOf` devolve -1 quando não acha, o que faria uma comparação de ordem passar por
  // acidente — por isso cada posição é afirmada como ENCONTRADA antes de ser comparada.
  const blocoEntre = (src, inicio, fim) => {
    const i = src.indexOf(inicio);
    assert.ok(i > -1, `âncora inicial não encontrada: ${inicio}`);
    const j = src.indexOf(fim, i + inicio.length);
    assert.ok(j > i, `âncora final não encontrada depois de: ${inicio}`);
    return src.slice(i, j);
  };

  const ordem = (bloco, antes, depois, msg) => {
    const a = bloco.indexOf(antes);
    const d = bloco.indexOf(depois);
    assert.ok(a > -1, `não encontrei "${antes}" no bloco`);
    assert.ok(d > -1, `não encontrei "${depois}" no bloco`);
    assert.ok(a < d, msg);
  };

  it('admin/selection.astro — o botão de resgate não mostra sucesso numa recusa', () => {
    const bloco = blocoEntre(ASTRO, "sb.rpc('selection_rescue_stuck_interview'", '} catch (e: any)');
    assert.match(bloco, /data\?\.success === false/, 'o handler precisa tratar a recusa');
    ordem(bloco, 'data?.success === false', 'T.modal.rescueStuckToast',
      'o toast de sucesso aparece antes da checagem de recusa');
  });

  it('nucleo-mcp lane RAW — a tool não devolve envelope de sucesso numa recusa', () => {
    const bloco = blocoEntre(MCP, 'sb.rpc("selection_rescue_stuck_interview"', 'return ok(data);');
    assert.match(bloco, /data\?\.success === false/, 'o lane RAW precisa tratar a recusa');
    // O bloco TERMINA no ok(data), então achar a checagem dentro dele já prova que ela vem antes.
    ordem(bloco, 'data?.error', 'data?.success === false',
      'a checagem de recusa precisa vir depois do erro estruturado, como no lane semântico');
  });

  it('a descrição da tool não promete mais a atomicidade que o #1594 removeu', () => {
    const desc = blocoEntre(MCP, 'mcp.tool("selection_rescue_stuck_interview"', 'async (params:');
    assert.doesNotMatch(
      desc,
      /One transaction — a re-dispatch failure rolls the cancel back/,
      'a descrição ainda promete rollback do cancel numa recusa — o modelo lê isto',
    );
    assert.match(desc, /#1598/, 'a descrição precisa dizer o que a recusa faz');
  });
});

// ── DB: #1599 — os crons param de engolir a mensagem ──────────────────────────
describe('#1599 — os crons de resgate gravam o erro e separam recusa de resgate', () => {
  it('ambos capturam SQLERRM + SQLSTATE + application_id, e não só o contador', { skip: dbGated ? false : skipMsg }, async () => {
    for (const fn of CRONS) {
      const { data, error } = await sb.rpc('_audit_function_source', { p_proname: fn });
      assert.ifError(error);
      assert.ok(data?.length > 0, `${fn} não existe no banco`);
      const src = data[0].prosrc;

      assert.match(src, /EXCEPTION WHEN OTHERS THEN/, `${fn}: o laço precisa isolar a linha`);
      assert.match(src, /SQLERRM/, `${fn}: a mensagem tem de ser guardada`);
      assert.match(src, /SQLSTATE/, `${fn}: o código tem de ser guardado`);
      assert.match(src, /'errors', v_error_rows/, `${fn}: o audit tem de gravar o array de erros`);
    }
  });

  it('ambos contam RECUSA separado de RESGATE (senão o #1594 se repete um andar acima)', { skip: dbGated ? false : skipMsg }, async () => {
    for (const fn of CRONS) {
      const { data } = await sb.rpc('_audit_function_source', { p_proname: fn });
      const src = data[0].prosrc;

      // O defeito seria voltar ao PERFORM cego: sem ler o retorno, recusa vira resgate.
      assert.doesNotMatch(
        src,
        /PERFORM public\.selection_rescue_(stuck_interview|unbooked_invite)\(/,
        `${fn}: PERFORM cego — o retorno do rescue precisa ser lido`,
      );
      assert.match(src, /v_result->>'success'/, `${fn}: tem de checar o retorno do rescue`);
      assert.match(src, /v_refused := v_refused \+ 1/, `${fn}: recusa precisa de contador próprio`);
      assert.match(src, /'refused_count', v_refused/, `${fn}: refused_count tem de chegar ao audit`);
    }
  });

  it('erro recorrente deixa de ser invisível: vira linha em data_anomaly_log', { skip: dbGated ? false : skipMsg }, async () => {
    for (const fn of CRONS) {
      const { data } = await sb.rpc('_audit_function_source', { p_proname: fn });
      const src = data[0].prosrc;
      assert.match(src, /IF v_errors > 0 THEN/, `${fn}: precisa reagir a erro, não só contá-lo`);
      assert.match(src, /INSERT INTO public\.data_anomaly_log/, `${fn}: o erro tem de sair do audit`);
      assert.match(src, /'selection_rescue_cron_error'/, `${fn}: tipo de anomalia estável`);
    }
  });
});
