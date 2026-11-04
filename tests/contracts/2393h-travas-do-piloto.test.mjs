/**
 * Contract: #2393, fatia A1 (ADR-0134) — a candidatura de vaga piloto da linha não entra no fluxo geral.
 *
 * Três camadas, e cada uma tem asserção própria:
 *   1. um trigger BEFORE UPDATE OF status em selection_applications SUPRIME e registra a mudança de status da
 *      candidatura line_pilot para fora da lista permitida (padrão da #1613: sem exceção, por causa dos
 *      escritores em laço). Ele é o que segura finalize_decisions e admin_decide_dual_track: com o status
 *      mantido, approve_selection_application recusa, porque só aprova candidatura approved ou converted;
 *   2. admin_update_application recusa, com mensagem, toda mudança de status que não seja desistência ou
 *      cancelamento, ANTES do UPDATE e da aprovação canônica;
 *   3. schedule_interview e _issue_interview_booking_token_core recusam (P0030, LINE_PILOT_NOT_GENERAL_FLOW)
 *      antes de criar entrevista ou token.
 * Na tela, a ficha da gestão troca decisão, avaliação e entrevista pelo estado do piloto, com o mesmo par de
 * status permitidos da RPC.
 *
 * Camada S (estática). O efeito (a aprovação suprimida, a recusa com mensagem, a candidatura geral intacta) é a
 * verificação do pacote, num DO desfeito pela sentinela.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const TRG_FN = '_trg_piloto_trava_status';
const TRG = 'trg_zy_piloto_trava_status';
const PERMITIDOS_RPC = ['withdrawn', 'cancelled'];

function captura(nome) {
  const cap = latestFunctionCapture(ROOT, nome);
  assert.ok(cap, `${nome}: nenhuma migration cria esta função`);
  return { file: cap.file, corpo: maskLineComments(cap.block).replace(/\s+/g, ' ') };
}

function antes(corpo, a, b, msg) {
  const ia = corpo.indexOf(a);
  const ib = corpo.indexOf(b);
  assert.ok(ia >= 0, `${msg}: trava não encontrada`);
  assert.ok(ib >= 0, `${msg}: âncora "${b.slice(0, 50)}" não encontrada`);
  assert.ok(ia < ib, `${msg}: a trava tem de vir antes de "${b.slice(0, 50)}"`);
}

test('#2393h S: o trigger mantém o status da candidatura piloto fora da lista permitida e registra', () => {
  const { corpo } = captura(TRG_FN);
  assert.match(corpo,
    /BEGIN IF NEW\.status IS NOT DISTINCT FROM OLD\.status OR NEW\.status IN \('submitted', 'screening', 'objective_eval', 'rejected', 'withdrawn', 'cancelled'\) OR NOT EXISTS \( SELECT 1 FROM public\.vep_opportunities vo WHERE vo\.opportunity_id = NEW\.vep_opportunity_id AND vo\.evaluation_track = 'line_pilot' \) THEN RETURN NEW; END IF; v_tentado := NEW\.status; NEW\.status := OLD\.status;/,
    'a condição ou o resultado da trava mudou');
  assert.match(corpo, /INSERT INTO public\.admin_audit_log \(actor_id, action, target_type, target_id, changes, metadata\) VALUES \( v_actor, 'selection\.pilot_status_blocked',/,
    'a supressão deixou de ser registrada');
  assert.doesNotMatch(corpo.replace(/EXCEPTION WHEN OTHERS THEN RAISE WARNING/g, ''), /RAISE EXCEPTION/,
    'a trava não pode levantar exceção: há escritores em laço (#1613)');
});

test('#2393h S: a lista permitida da RPC está dentro da lista permitida do trigger', () => {
  const { corpo } = captura(TRG_FN);
  const lista = corpo.match(/NEW\.status IN \(([^)]*)\)/)[1].split(',').map((x) => x.trim().replace(/'/g, ''));
  for (const s of PERMITIDOS_RPC) assert.ok(lista.includes(s), `o trigger suprimiria ${s}, que a RPC permite`);
  for (const s of ['approved', 'converted', 'interview_pending', 'interview_scheduled', 'objective_cutoff', 'waitlist', 'final_eval'])
    assert.ok(!lista.includes(s), `o trigger deixaria passar ${s} na candidatura piloto`);
});

test('#2393h S: o trigger existe no estado final das migrations, antes de gravar o status', () => {
  let ultimo = null;
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql')).sort()) {
    const s = maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')).replace(/\s+/g, ' ');
    const eventos = [];
    for (const m of s.matchAll(new RegExp(`CREATE (?:OR REPLACE )?TRIGGER ${TRG} ([^;]*);`, 'g'))) eventos.push({ i: m.index, def: m[1] });
    for (const m of s.matchAll(new RegExp(`DROP TRIGGER (?:IF EXISTS )?${TRG} ON public\\.selection_applications;`, 'g'))) eventos.push({ i: m.index, def: null });
    for (const e of eventos.sort((a, b) => a.i - b.i)) ultimo = e.def;
  }
  assert.equal(ultimo, `BEFORE UPDATE OF status ON public.selection_applications FOR EACH ROW EXECUTE FUNCTION public.${TRG_FN}()`,
    'o trigger não existe no estado final ou mudou de momento, de evento ou de função');
});

test('#2393h S: a aprovação canônica só aprova candidatura já approved ou converted (a 2ª camada da trava)', () => {
  const { corpo } = captura('approve_selection_application');
  assert.match(corpo, /IF v_app\.status NOT IN \('approved', 'converted'\) THEN RETURN jsonb_build_object\( 'success', false,/,
    'approve_selection_application deixou de recusar status fora de approved e converted: a trava de status não segura mais finalize_decisions');
});

test('#2393h S: admin_update_application recusa a mudança de status do piloto antes do UPDATE e da aprovação', () => {
  const { corpo } = captura('admin_update_application');
  const trava = `IF NOT public._na_avaliacao_geral(p_application_id) AND v_requested_status IS DISTINCT FROM v_old_status AND v_requested_status NOT IN ('${PERMITIDOS_RPC.join("', '")}') THEN RETURN json_build_object( 'error',`;
  assert.ok(corpo.includes(trava), 'a condição da recusa mudou');
  assert.match(corpo, /'code', 'line_pilot_status_locked' \); END IF;/, 'a recusa perdeu o código ou deixou de retornar');
  antes(corpo, trava, 'UPDATE public.selection_applications SET', 'admin_update_application');
  antes(corpo, trava, 'public.approve_selection_application(', 'admin_update_application');
});

for (const [nome, ancora] of [
  ['schedule_interview', 'INSERT INTO public.selection_interviews'],
  ['_issue_interview_booking_token_core', 'INSERT INTO public.onboarding_tokens'],
]) {
  test(`#2393h S: ${nome} recusa a candidatura piloto antes de gravar`, () => {
    const { corpo } = captura(nome);
    const trava = "IF NOT public._na_avaliacao_geral(p_application_id) THEN PERFORM public._log_gate_attempt(";
    assert.ok(corpo.includes(trava), 'a recusa do piloto sumiu');
    const bloco = corpo.slice(corpo.indexOf(trava), corpo.indexOf('END IF;', corpo.indexOf(trava)));
    assert.match(bloco, /'P0030', 'LINE_PILOT_NOT_GENERAL_FLOW'.*RETURN jsonb_build_object\( 'success', false,.*'gate_failed_reason', 'LINE_PILOT_NOT_GENERAL_FLOW'/,
      'a recusa deixou de registrar ou de retornar');
    antes(corpo, trava, ancora, nome);
  });
}

test('#2393h S: nenhum cliente executa a função do trigger', () => {
  const { file } = captura(TRG_FN);
  const sql = maskLineComments(readFileSync(join(MIGRATIONS, file), 'utf8')).replace(/\s+/g, ' ');
  assert.match(sql, new RegExp(`REVOKE ALL ON FUNCTION public\\.${TRG_FN}\\(\\) FROM PUBLIC, anon, authenticated;`), 'a função não é revogada dos clientes');
  const re = new RegExp(`GRANT[^;]*ON FUNCTION public\\.${TRG_FN}\\b[^;]*\\b(anon|PUBLIC|authenticated)\\b`, 'i');
  for (const f of readdirSync(MIGRATIONS).filter((x) => x.endsWith('.sql') && x >= file))
    assert.doesNotMatch(maskLineComments(readFileSync(join(MIGRATIONS, f), 'utf8')), re, `${f}: devolve a função a um cliente`);
});

const tela = () => maskJsComments(readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8')).replace(/\s+/g, ' ');

test('#2393h S: a ficha aplica o estado do piloto só na candidatura piloto, com o par de status da RPC', () => {
  const s = tela();
  assert.match(s, /function isPilotRow\(r: any\): boolean \{ return r\?\.evaluation_track === 'line_pilot'; \}/, 'a trilha deixou de vir do painel');
  assert.match(s, new RegExp(`const PILOT_STATUS_OPTIONS = \\['${PERMITIDOS_RPC.join("', '")}'\\];`), 'o menu do piloto divergiu da RPC');
  assert.match(s,
    /function aplicarEstadoDoPiloto\(body: HTMLElement, r: any\): void \{ if \(!isPilotRow\(r\)\) return; const sel = [^;]*; if \(sel\) \{ Array\.from\(sel\.options\)\.forEach\(\(o\) => \{ if \(o\.value !== r\.status && !PILOT_STATUS_OPTIONS\.includes\(o\.value\)\) o\.remove\(\); \}\);/,
    'a ficha deixou de restringir o menu de status do piloto');
  assert.match(s, /body\.querySelector\('#modal-early-acceptance-block'\)\?\.remove\(\);/, 'o aceite antecipado continua na ficha do piloto');
  assert.match(s, /if \(evalBox\) evalBox\.innerHTML = pilotNotice\(T\.modal\.pilotEvaluate\);/, 'a aba Avaliar do piloto voltou ao formulário');
  assert.match(s, /if \(interview\) interview\.innerHTML = pilotNotice\(T\.modal\.pilotInterview\);/, 'a aba Entrevista do piloto voltou ao formulário');
});

test('#2393h S: a ficha chama o estado do piloto e as abas não carregam formulário do fluxo geral para ele', () => {
  const s = tela();
  antes(s, 'aplicarEstadoDoPiloto(body, row);', "body.querySelectorAll('.modal-tab-btn').forEach(btn => {", 'a ficha');
  assert.match(s, /if \(tab === 'evaluate' && !isPilotRow\(row\)\) loadEvaluationForm\(row\.id\);/, 'a aba Avaliar carrega o formulário geral para o piloto');
  assert.match(s, /if \(tab === 'interview' && !isPilotRow\(row\)\) loadInterviewForm\(row\);/, 'a aba Entrevista carrega o formulário geral para o piloto');
  assert.match(s, /if \(tab === 'videos'\) loadVideoScreenings\(row\.id, isPilotRow\(row\)\);/, 'a aba Vídeos não sabe a trilha');
  assert.match(s, /esc\(pilot \? T\.modal\.pilotVideos : T\.modal\.videosEmpty\)/, 'a aba Vídeos do piloto mostra o texto do fluxo geral');
});

test('#2393h S: as 4 chaves do estado do piloto existem nas 3 línguas e chegam à tela', () => {
  const s = readFileSync(resolve(ROOT, 'src/pages/admin/selection.astro'), 'utf8');
  for (const k of ['pilotDecision', 'pilotEvaluate', 'pilotInterview', 'pilotVideos']) {
    assert.ok(s.includes(`    ${k}: t('admin.selection.modal.${k}', lang),`), `${k} não chega à tela`);
    for (const lang of ['pt-BR', 'en-US', 'es-LATAM']) {
      const i18n = readFileSync(resolve(ROOT, `src/i18n/${lang}.ts`), 'utf8');
      assert.match(i18n, new RegExp(`\\n  'admin\\.selection\\.modal\\.${k}': '[^'\\n]{40,}`), `${lang}: falta ${k}`);
    }
  }
});
