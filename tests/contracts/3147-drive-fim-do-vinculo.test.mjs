// tests/contracts/3147-drive-fim-do-vinculo.test.mjs
/**
 * #3147: o acesso ao Drive dado por iniciativa termina com o vínculo com a iniciativa.
 *
 * O CASO: o reconcile diário (ADR-0124) só concedia. Medido em 22/11/2026: 126 acessos ativos, 16 de pessoas fora do
 * roster da iniciativa, 7 delas membros ativos e 2 em iniciativa confidencial. A trilha de desligamento (ADR-0107) só
 * cobre quem sai do Núcleo.
 *
 * O que este guard afirma, com a condição amarrada ao resultado dentro do bloco que decide:
 *   G1 quem fica com acesso é decidido pelo MESMO predicado do roster (get_initiative_drive_roster): vínculo ativo
 *      naquela iniciativa e membro ativo. Uma segunda via de vínculo ativo na mesma iniciativa basta.
 *   G2 o INSERT da fila só pega concessão viva fora do roster e fora de quem tem manage_platform (exceção nomeada).
 *   G3 a chave nasce desligada e é lida fail-closed; aviso e aprovação automática só existem dentro do IF da chave.
 *   G4 o prazo: 7 dias, ou o próprio ciclo em iniciativa confidencial; a aprovação automática exige o aviso dado, o
 *      prazo vencido, o item não segurado, e confere de novo roster e exceção no próprio UPDATE.
 *   G5 o executor da ADR-0107 acha o item novo, só age no aprovado de concessão viva, e só o sucesso fecha a concessão.
 *   G6 o alinhamento com a trilha de desligamento compara a hora: o id da permissão do Drive se repete quando o acesso
 *      volta, então revogação antiga não fecha concessão nova.
 *   G7 o cancelamento do item que deixou de valer usa o mesmo predicado do roster.
 *   G8 a tela: manage_platform em todas as funções de gestão, a leitura aplica rls_can_see_initiative e põe a
 *      confidencial primeiro, e mostra também a fila de drive_offboarding_audit.
 *   G9 emulação do #785 sobre todas as funções da migration.
 *   M  cada predicado reprova a mutação do seu defeito, pela MESMA função.
 *
 * A camada viva (DB-gated) roda os mesmos predicados sobre o corpo em produção.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const MIG = readdirSync(MIG_DIR).filter((f) => /_3147_drive_fim_do_vinculo\.sql$/.test(f)).sort().pop();

/** Tira comentário de linha e colapsa espaço, para o predicado ler o código e não a prosa. */
export function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}
const body = (fn) => {
  const c = latestFunctionCapture(ROOT, fn);
  assert.ok(c, `${fn}: sem captura em supabase/migrations`);
  return c.body;
};
const slice = (s, from, to) => {
  const a = s.indexOf(from);
  if (a < 0) return '';
  const b = s.indexOf(to, a + from.length);
  return b < 0 ? s.slice(a) : s.slice(a, b + to.length);
};

/** O bloco IF ... END IF que começa em `start`, contando os IF aninhados. */
export function ifBlock(s, start) {
  const a = s.indexOf(start);
  if (a < 0) return '';
  const re = /\bEND IF\b|\bIF\b/g;
  re.lastIndex = a;
  let depth = 0, m;
  while ((m = re.exec(s))) {
    depth += m[0] === 'IF' ? 1 : -1;
    if (depth === 0) return s.slice(a, m.index + m[0].length);
  }
  return s.slice(a);
}

const ROSTER = /e\.initiative_id = p_initiative_id AND e\.status = 'active' AND m\.member_status = 'active'/;

/** G1: o predicado de quem fica e o do roster são o mesmo. */
export function mesmoPredicadoDoRoster(keepsBody, rosterBody) {
  const k = sql(keepsBody), r = sql(rosterBody);
  return {
    keepsTemOPredicado: /JOIN public\.members m ON m\.person_id = e\.person_id WHERE e\.person_id = p_person_id AND e\.initiative_id = p_initiative_id AND e\.status = 'active' AND m\.member_status = 'active'/.test(k),
    // os dois ramos do roster (e-mail principal e secundário) usam a mesma condição
    rosterTemOPredicado: (r.match(/WHERE e\.initiative_id = p_initiative_id AND e\.status = 'active' AND m\.member_status = 'active'/g) || []).length === 2,
    keepsEExists: /SELECT EXISTS \( SELECT 1 FROM public\.engagements e/.test(k),
  };
}

/** G2: o INSERT da fila. */
export function insertDaFila(enqueueBody) {
  const ins = slice(sql(enqueueBody), 'INSERT INTO public.drive_membership_revocations', 'RETURNING id');
  return {
    soConcessaoViva: /WHERE g\.status = 'granted' AND g\.permission_id IS NOT NULL/.test(ins),
    foraDoRoster: /AND NOT public\._drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id\)/.test(ins),
    excecaoManagePlatform: /AND NOT coalesce\(public\.can_by_member\(g\.grantee_member_id, 'manage_platform'\), true\)/.test(ins),
    motivoFimDeVinculo: /'engagement_ended', \(i\.visibility = 'confidential'\)/.test(ins),
    naoDuplicaNemReabreMantido: /x\.status IN \('pending','approved','failed'\) OR x\.cancel_reason = 'management_kept'/.test(ins),
    cedeATrilhaDeDesligamento: /a\.status IN \('pending_revoke','approved'\)/.test(ins),
  };
}

/** G3: a chave. */
export function chave(enqueueBody) {
  const s = sql(enqueueBody);
  const dentro = ifBlock(s, 'IF v_on THEN');
  const fora = s.replace(dentro, '');
  return {
    failClosed: /v_on := coalesce\(v_cfg, 'false'::jsonb\) IS NOT DISTINCT FROM 'true'::jsonb;/.test(s),
    leAChaveCerta: /WHERE key = 'drive_membership_revoke_enabled'/.test(s),
    avisoDentro: /create_notification\(/.test(dentro) && !/create_notification\(/.test(fora),
    aprovacaoDentro: /approval_mode = 'auto'/.test(dentro) && !/approval_mode = 'auto'/.test(fora),
  };
}

/** G4: prazo e aprovação automática. */
export function prazoEAprovacao(enqueueBody) {
  const s = sql(enqueueBody);
  const ap = slice(s, "SET status = 'approved', approval_mode = 'auto'", 'RETURNING x.id');
  return {
    seteDias: /c_notice constant interval := interval '7 days';/.test(s),
    confidencialNoCiclo: /due_at = CASE WHEN r\.is_confidential THEN now\(\) ELSE now\(\) \+ c_notice END/.test(s),
    seguradoNaoEAvisado: /x\.notified_at IS NULL AND x\.held_at IS NULL/.test(s),
    aprovaSoVencidoAvisadoSoltos: /x\.held_at IS NULL AND x\.notified_at IS NOT NULL AND x\.due_at <= now\(\)/.test(ap),
    reconfereRoster: /AND NOT public\._drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id\)/.test(ap),
    reconfereExcecao: /AND NOT coalesce\(public\.can_by_member\(g\.grantee_member_id, 'manage_platform'\), true\)/.test(ap),
    soConcessaoViva: /AND g\.status = 'granted'/.test(ap),
  };
}

/** G5: o executor. */
export function executor(getBody, markBody) {
  const g = sql(getBody), m = sql(markBody);
  const ramo = slice(m, 'UPDATE public.drive_membership_revocations', 'END IF; SELECT * INTO v_rev');
  return {
    getAchaOItemNovo: /FROM public\.drive_membership_revocations r JOIN public\.drive_membership_grants g ON g\.id = r\.grant_id WHERE r\.id = p_audit_id/.test(g),
    getSoAprovadoDeConcessaoViva: /CASE WHEN g\.status = 'granted' THEN r\.status ELSE 'grant_' \|\| g\.status END AS status/.test(g),
    markSoDoAprovado: /WHERE id = p_audit_id AND status = 'approved' RETURNING \* INTO v_rev;/.test(ramo),
    markFechaConcessaoSoNoSucesso: /IF p_status IN \('revoked','already_absent'\) THEN UPDATE public\.drive_membership_grants SET status = 'revoked', revoked_at = now\(\), revoked_by = v_rev\.approved_by, revoked_via = 'membership_queue', updated_at = now\(\) WHERE id = v_rev\.grant_id AND status = 'granted';/.test(ramo),
    // o portão de serviço vem antes de qualquer leitura, nas duas funções
    portaoServiceRoleNoTopo: [g, m].every((s) => {
      const i = s.indexOf("BEGIN IF public.current_caller_role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service-role only'; END IF;");
      const j = s.search(/\b(SELECT|UPDATE) /);
      return i >= 0 && j > i;
    }),
  };
}

/** G6: alinhamento com a trilha de desligamento. */
export function alinhamento(enqueueBody) {
  const a = slice(sql(enqueueBody), 'WITH done AS', 'RETURNING g.id');
  return {
    mesmaPermissao: /a\.drive_file_id = g\.drive_folder_id AND a\.permission_id = g\.permission_id/.test(a),
    soRevogacaoConcluida: /a\.status IN \('revoked','already_absent'\) AND a\.revoked_at IS NOT NULL/.test(a),
    depoisDoUltimoEnvio: /AND a\.revoked_at > coalesce\(g\.last_dispatched_at, g\.granted_at\)/.test(a),
    soConcessaoViva: /WHERE g\.status = 'granted'/.test(a),
  };
}

/** G7: o cancelamento do que deixou de valer. */
export function cancelamento(enqueueBody) {
  const c = slice(sql(enqueueBody), 'WITH c AS', 'RETURNING q.id');
  return {
    vinculoDeVolta: /q\.reason = 'engagement_ended' AND \( public\._drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id\)/.test(c),
    soAberto: /q\.status IN \('pending','approved'\)/.test(c),
    concessaoFechada: /WHEN g\.status IS DISTINCT FROM 'granted' THEN 'grant_closed'/.test(c),
  };
}

const GESTAO = ['admin_list_drive_revocation_queue', 'admin_hold_drive_revocation', 'admin_cancel_drive_revocation',
  'admin_approve_drive_membership_revocation', 'admin_request_drive_revocation'];

/** G8: portão de gestão (condição e efeito no mesmo IF). */
export function portaoGestao(b) {
  return /v_caller_id := \(SELECT id FROM public\.members WHERE auth_id = auth\.uid\(\)\); IF v_caller_id IS NULL OR NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN RAISE EXCEPTION/.test(sql(b));
}
export function leituraDaTela(b) {
  const s = sql(b);
  return {
    portaoConfidencial: /AND public\.rls_can_see_initiative\(r\.initiative_id\)/.test(s),
    confidencialPrimeiro: /ORDER BY q\.is_confidential DESC/.test(s),
    mostraADesligamento: /FROM public\.drive_offboarding_audit a JOIN public\.members m ON m\.id = a\.member_id WHERE a\.status IN \('pending_revoke','approved','failed'\)/.test(s),
    registraLeituraDePii: /PERFORM public\.log_pii_access_batch\(v_ids/.test(s),
  };
}

/** G9: o critério de _audit_secdef_initiative_reader_gates, aplicado ao corpo (a parte de privilégio vem do .sql). */
export function leitoraSemPortao(prosrc, executavelPorAuthenticated) {
  const tocaTabela = /(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)/.test(prosrc)
    || /\bevents\b/.test(prosrc) || /\binitiatives\b/.test(prosrc);
  const escreve = /(INSERT |UPDATE |DELETE )/.test(prosrc.toUpperCase());
  const portao = /rls_can_see_(initiative|board|item)|confidential/.test(prosrc);
  return tocaTabela && !escreve && executavelPorAuthenticated && !portao;
}

const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));
const ok = (o, msg) => assert.deepEqual(o, allTrue(o), msg);

// ───────────────────────── estático: a captura mais nova ─────────────────────────
test('#3147 G0: a migration existe e cria a fila com RLS fechado e o estado revoked na concessão', () => {
  assert.ok(MIG, 'migration *_3147_drive_fim_do_vinculo.sql ausente');
  const m = readFileSync(join(MIG_DIR, MIG), 'utf8');
  assert.match(m, /CHECK \(status IN \('pending_grant','granted','failed','already_present','skipped','revoked'\)\)/);
  assert.match(m, /CHECK \(\(status = 'revoked'\) = \(revoked_at IS NOT NULL AND revoked_via IS NOT NULL\)\)/);
  assert.match(m, /CREATE POLICY drive_membership_revocations_deny_all[\s\S]*?USING \(false\) WITH CHECK \(false\)/);
  assert.match(m, /REVOKE ALL ON public\.drive_membership_revocations FROM PUBLIC, anon, authenticated;/);
  assert.match(m, /drive_membership_revocations_open_uidx\s+ON public\.drive_membership_revocations \(grant_id\) WHERE status IN \('pending','approved'\)/);
  // a chave nasce desligada e não sobrescreve quem já ligou
  assert.match(m, /VALUES \('drive_membership_revoke_enabled', 'false'::jsonb\)\s+ON CONFLICT \(key\) DO NOTHING;/);
  // o índice de concessão viva NÃO muda: revoked fica fora dele, e o reconcile pode conceder de novo
  assert.doesNotMatch(m, /drive_membership_grants_active_uidx/);
  // as funções de serviço não são executáveis por usuário
  for (const fn of ['enqueue_membership_drive_revocations\\(\\)', '_drive_grant_keeps_access\\(uuid, uuid\\)']) {
    assert.match(m, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn} FROM PUBLIC, anon, authenticated;`));
  }
  // os dois crons: o ciclo e o dreno de sempre, agora com as duas filas
  assert.match(m, /cron\.schedule\('membership-drive-revocation-queue-hourly', '50 \* \* \* \*',\s*\$cron\$ SELECT public\.enqueue_membership_drive_revocations\(\); \$cron\$\)/);
  const dreno = slice(m, "cron.schedule('revoke-drive-drain-hourly'", '$drain$;');
  assert.match(dreno, /FROM public\.drive_offboarding_audit\s+WHERE status = 'approved' AND approved_at < now\(\) - interval '5 minutes'\s+UNION ALL\s+SELECT id, approved_at FROM public\.drive_membership_revocations\s+WHERE status = 'approved' AND approved_at < now\(\) - interval '5 minutes'/);
  assert.match(dreno, /functions\/v1\/revoke-drive-permission/);
});

test('#3147 G1: quem fica com acesso é o mesmo predicado do roster', () => {
  ok(mesmoPredicadoDoRoster(body('_drive_grant_keeps_access'), body('get_initiative_drive_roster')), 'o predicado divergiu do roster');
});
test('#3147 G2: o INSERT da fila', () => ok(insertDaFila(body('enqueue_membership_drive_revocations')), 'o INSERT da fila mudou'));
test('#3147 G3: a chave', () => ok(chave(body('enqueue_membership_drive_revocations')), 'a chave deixou de mandar no aviso ou na aprovação'));
test('#3147 G4: prazo e aprovação automática', () => ok(prazoEAprovacao(body('enqueue_membership_drive_revocations')), 'prazo ou aprovação mudou'));
test('#3147 G5: o executor da ADR-0107 acha o item novo', () => {
  ok(executor(body('get_drive_revocation_row'), body('mark_drive_revocation_done')), 'o executor mudou');
});
test('#3147 G6: o alinhamento com a trilha de desligamento compara a hora', () => ok(alinhamento(body('enqueue_membership_drive_revocations'))));
test('#3147 G7: o cancelamento usa o predicado do roster', () => ok(cancelamento(body('enqueue_membership_drive_revocations'))));
test('#3147 G8: a tela', () => {
  for (const fn of GESTAO) assert.ok(portaoGestao(body(fn)), `${fn}: sem o portão manage_platform`);
  ok(leituraDaTela(body('admin_list_drive_revocation_queue')), 'a leitura da tela mudou');
});

test('#3147 G9: emulação do #785 sobre as funções da migration', () => {
  const m = readFileSync(join(MIG_DIR, MIG), 'utf8');
  const fns = [...m.matchAll(/CREATE OR REPLACE FUNCTION public\.([a-z_0-9]+)\(/g)].map((x) => x[1]);
  assert.ok(fns.length >= 10, `esperava as funções da migration, vieram ${fns.length}`);
  const resultado = {};
  for (const fn of new Set(fns)) {
    const authed = new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\([^)]*\\) TO [^;]*authenticated`).test(m);
    resultado[fn] = leitoraSemPortao(body(fn), authed);
  }
  assert.deepEqual(Object.entries(resultado).filter(([, v]) => v).map(([k]) => k), [], 'leitora SECDEF sem portão confidencial');
  // controle positivo: uma leitora de initiatives sem portão é pega; a mesma com o portão passa; escritora passa
  assert.equal(leitoraSemPortao('SELECT i.title FROM public.initiatives i WHERE i.id = p_id', true), true, 'a emulação não pega a leitora sem portão');
  assert.equal(leitoraSemPortao('SELECT i.title FROM public.initiatives i WHERE public.rls_can_see_initiative(i.id)', true), false);
  assert.equal(leitoraSemPortao('UPDATE public.initiatives SET title = p_t', true), false);
  // nota: o critério vivo também aceita a palavra 'confidential' como portão, e a leitura da tela tem as duas
  // coisas (rls_can_see_initiative e is_confidential). Quem afirma o portão real é o G8 (portaoConfidencial).
});

// ───────────────────────── mutações: cada predicado reprova o seu defeito ─────────────────────────
test('#3147 M: cada predicado reprova a mutação do seu defeito', () => {
  const mut = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutação não aplicou: ${a}`); return out; };
  const E = body('enqueue_membership_drive_revocations');
  const K = body('_drive_grant_keeps_access');
  const R = body('get_initiative_drive_roster');
  const G = body('get_drive_revocation_row');
  const MK = body('mark_drive_revocation_done');
  const L = body('admin_list_drive_revocation_queue');

  // M1 o vínculo encerrado deixa de entrar: a fila esquece o roster
  assert.equal(insertDaFila(mut(E, "AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)\n       -- exceção", "-- exceção")).foraDoRoster, false);
  // M2 quem tem manage_platform entra
  assert.equal(insertDaFila(mut(E, "AND NOT coalesce(public.can_by_member(g.grantee_member_id, 'manage_platform'), true)\n       -- já tem", "-- já tem")).excecaoManagePlatform, false);
  // M3 o predicado de quem fica aceita vínculo de qualquer iniciativa (a segunda via vira qualquer via)
  assert.equal(mesmoPredicadoDoRoster(mut(K, 'AND e.initiative_id = p_initiative_id ', ''), R).keepsTemOPredicado, false);
  // M4 o predicado aceita membro não ativo
  assert.equal(mesmoPredicadoDoRoster(mut(K, "AND m.member_status = 'active'", ''), R).keepsTemOPredicado, false);
  // M5 a chave lida fail-open
  assert.equal(chave(mut(E, "coalesce(v_cfg, 'false'::jsonb)", "coalesce(v_cfg, 'true'::jsonb)")).failClosed, false);
  // M6 a aprovação automática sai de dentro da chave
  assert.equal(chave(mut(E, '    END LOOP;\n\n    -- e.', '    END LOOP;\n  END IF;\n  IF true THEN\n    -- e.')).aprovacaoDentro, false);
  // M6b o aviso sai de dentro da chave
  assert.equal(chave(mut(E, '  IF v_on THEN\n', '  IF true THEN\n')).avisoDentro, false);
  // M7 a confidencial ganha prazo de 7 dias
  assert.equal(prazoEAprovacao(mut(E, 'CASE WHEN r.is_confidential THEN now() ELSE', 'CASE WHEN false THEN now() ELSE')).confidencialNoCiclo, false);
  // M8 aprova sem o aviso dado
  assert.equal(prazoEAprovacao(mut(E, 'AND x.notified_at IS NOT NULL AND x.due_at <= now()', 'AND x.due_at <= now()')).aprovaSoVencidoAvisadoSoltos, false);
  // M9 aprova o segurado
  assert.equal(prazoEAprovacao(mut(E, '         AND x.held_at IS NULL AND x.notified_at IS NOT NULL', '         AND x.notified_at IS NOT NULL')).aprovaSoVencidoAvisadoSoltos, false);
  // M10 a aprovação não reconfere o roster (corrida entre o aviso e o prazo)
  const ap = "AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)\n         AND NOT coalesce";
  assert.equal(prazoEAprovacao(mut(E, ap, 'AND NOT coalesce')).reconfereRoster, false);
  // M11 o executor age na concessão já fechada
  assert.equal(executor(mut(G, "CASE WHEN g.status = 'granted' THEN r.status ELSE 'grant_' || g.status END", 'r.status'), MK).getSoAprovadoDeConcessaoViva, false);
  // M12 a falha fecha a concessão
  assert.equal(executor(G, mut(MK, "IF p_status IN ('revoked','already_absent') THEN\n        UPDATE public.drive_membership_grants", "IF p_status IN ('revoked','already_absent','failed') THEN\n        UPDATE public.drive_membership_grants")).markFechaConcessaoSoNoSucesso, false);
  // M13 a revogação antiga fecha a concessão nova (sem a hora)
  assert.equal(alinhamento(mut(E, '       AND a.revoked_at > coalesce(g.last_dispatched_at, g.granted_at)\n', '')).depoisDoUltimoEnvio, false);
  // M14 o vínculo de volta não cancela o item
  assert.equal(cancelamento(mut(E, "AND ( public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)\n                  OR", 'AND ( false\n                  OR')).vinculoDeVolta, false);
  // M15 a tela perde o portão confidencial
  assert.equal(leituraDaTela(mut(L, 'AND public.rls_can_see_initiative(r.initiative_id)', '')).portaoConfidencial, false);
  // M16 a tela deixa de mostrar a fila de desligamento
  assert.equal(leituraDaTela(mut(L, "WHERE a.status IN ('pending_revoke','approved','failed')", "WHERE a.status IN ('approved')")).mostraADesligamento, false);
  // M17 uma função de gestão sem o portão
  assert.equal(portaoGestao(mut(body('admin_request_drive_revocation'), "NOT public.can_by_member(v_caller_id, 'manage_platform')", 'false')), false);
  // M18 a fila reabre o que a gestão decidiu manter
  assert.equal(insertDaFila(mut(E, " OR x.cancel_reason = 'management_kept'", '')).naoDuplicaNemReabreMantido, false);
});

// ───────────────────────── vivo: os mesmos predicados sobre o corpo em produção ─────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

async function vivo(proname) {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#3147 vivo: o corpo em produção passa nos mesmos predicados' : `SKIP: ${skipMsg}`, { skip: !dbGated }, async () => {
  const E = await vivo('enqueue_membership_drive_revocations');
  ok(mesmoPredicadoDoRoster(await vivo('_drive_grant_keeps_access'), await vivo('get_initiative_drive_roster')));
  ok(insertDaFila(E)); ok(chave(E)); ok(prazoEAprovacao(E)); ok(alinhamento(E)); ok(cancelamento(E));
  ok(executor(await vivo('get_drive_revocation_row'), await vivo('mark_drive_revocation_done')));
  for (const fn of GESTAO) assert.ok(portaoGestao(await vivo(fn)), `${fn} vivo: sem o portão`);
  ok(leituraDaTela(await vivo('admin_list_drive_revocation_queue')));
});
