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
 *   G10 (A1) o executor e o "aprovar já" reconferem quem fica: roster de volta ou manage_platform não sai.
 *   G11 (A2) o "aprovar já" avisa na hora quem ainda não foi avisado; a avulsa não avisa.
 *   G12 (A3) a pausa (quem não é active nem alumni) não é avisada nem aprovada pelo ciclo.
 *   G13 (A6) um aviso por pessoa e iniciativa, mesmo com dois e-mails.
 *   G14 (A8) a avulsa recusa o titular com manage_platform.
 *   G15 (A5) falha e "manter" deixam de bloquear quando a pessoa volta ao roster.
 *   G16 (A4) nenhuma pasta de trabalho é de duas iniciativas (vivo; o predicado tem controle nos dois sentidos).
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
    excecaoManagePlatform: /AND NOT public\.can_by_member\(g\.grantee_member_id, 'manage_platform'\)/.test(ins),
    // A7: concessão sem pessoa ou sem membro não entra (o predicado do roster não decide sobre NULL)
    exigeTitular: /AND g\.grantee_person_id IS NOT NULL AND g\.grantee_member_id IS NOT NULL/.test(ins),
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
    avisoDentro: /_drive_revocation_notify\(/.test(dentro) && !/_drive_revocation_notify\(|create_notification\(/.test(fora),
    aprovacaoDentro: /approval_mode = 'auto'/.test(dentro) && !/approval_mode = 'auto'/.test(fora),
  };
}

/** G4: prazo e aprovação automática. */
export function prazoEAprovacao(enqueueBody) {
  const s = sql(enqueueBody);
  const ap = slice(s, "SET status = 'approved', approval_mode = 'auto'", 'RETURNING x.id');
  const d = slice(s, 'FOR r IN', 'END LOOP;');
  return {
    seteDias: /c_notice constant interval := interval '7 days';/.test(s),
    confidencialNoCiclo: /due_at = CASE WHEN r\.conf_now THEN now\(\) ELSE now\(\) \+ c_notice END/.test(d),
    // A9: a confidencialidade do prazo é a da iniciativa agora, não a gravada na entrada
    confidencialLidaAgora: /SELECT x\.id, \(i\.visibility = 'confidential'\) AS conf_now FROM public\.drive_membership_revocations x JOIN public\.initiatives i ON i\.id = x\.initiative_id/.test(d)
      && !/is_confidential THEN/.test(d),
    seguradoNaoEAvisado: /x\.notified_at IS NULL AND x\.held_at IS NULL/.test(d),
    aprovaSoVencidoAvisadoSoltos: /x\.held_at IS NULL AND x\.notified_at IS NOT NULL AND \(x\.due_at <= now\(\) OR i\.visibility = 'confidential'\)/.test(ap),
    reconfereRoster: /AND NOT public\._drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id\)/.test(ap),
    reconfereExcecao: /AND NOT public\.can_by_member\(g\.grantee_member_id, 'manage_platform'\)/.test(ap),
    soConcessaoViva: /AND g\.status = 'granted'/.test(ap),
  };
}

/** G12 (A3): a pausa fica no manual. O aviso e a aprovação do ciclo exigem active ou alumni, no próprio WHERE. */
export function pausaNoManual(enqueueBody) {
  const s = sql(enqueueBody);
  const ap = slice(s, "SET status = 'approved', approval_mode = 'auto'", 'RETURNING x.id');
  const d = slice(s, 'FOR r IN', 'LOOP');
  return {
    avisoSoActiveOuAlumni: /JOIN public\.members m ON m\.id = x\.member_id WHERE .* AND m\.member_status IN \('active','alumni'\)/.test(d),
    aprovacaoSoActiveOuAlumni: /FROM public\.drive_membership_grants g, public\.members m, public\.initiatives i, public\.drive_membership_revocations o WHERE g\.id = x\.grant_id AND m\.id = g\.grantee_member_id AND i\.id = x\.initiative_id AND o\.id = x\.id .* AND m\.member_status IN \('active','alumni'\)/.test(ap),
  };
}

/** G5: o executor. */
export function executor(getBody, markBody) {
  const g = sql(getBody), m = sql(markBody);
  const ramo = slice(m, 'UPDATE public.drive_membership_revocations', 'END IF; SELECT * INTO v_rev');
  return {
    getAchaOItemNovo: /FROM public\.drive_membership_revocations r JOIN public\.drive_membership_grants g ON g\.id = r\.grant_id WHERE r\.id = p_audit_id/.test(g),
    getSoAprovadoDeConcessaoViva: /CASE WHEN g\.status IS DISTINCT FROM 'granted' THEN 'grant_' \|\| g\.status/.test(g),
    // A1: na última leitura antes do Drive, o item de fim de vínculo de quem fica devolve outro status
    getReconfereQuemFica: /WHEN r\.reason = 'engagement_ended' AND \( public\._drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id\) OR coalesce\(public\.can_by_member\(g\.grantee_member_id, 'manage_platform'\), false\) \) THEN 'stale_keeps_access' ELSE r\.status END AS status/.test(g),
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

/** G15 (A5): o bloqueio sai quando a pessoa volta ao roster. */
export function liberacao(enqueueBody) {
  const b2 = slice(sql(enqueueBody), 'WITH rel AS', 'RETURNING q.id');
  return {
    falhaOuManter: /\( \(q\.status = 'failed' AND q\.reason = 'engagement_ended'\) OR q\.cancel_reason = 'management_kept' \)/.test(b2),
    soQuandoVoltaAoRoster: /AND public\._drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id\)/.test(b2),
    fechaComoRestaurado: /SET status = 'cancelled', cancel_reason = 'engagement_restored'/.test(b2),
    antesDoInsert: sql(enqueueBody).indexOf('WITH rel AS') >= 0
      && sql(enqueueBody).indexOf('WITH rel AS') < sql(enqueueBody).indexOf('INSERT INTO public.drive_membership_revocations'),
  };
}

/** G10 + G11 (A1, A2): o "aprovar já". As recusas vêm antes do UPDATE; o aviso só para fim de vínculo não avisado. */
export function aprovarJa(b) {
  const s = sql(b);
  const up = s.indexOf("SET status = 'approved'");
  const antes = up >= 0 ? s.slice(0, up) : '';
  return {
    recusaManagePlatform: /IF coalesce\(public\.can_by_member\(v_g\.grantee_member_id, 'manage_platform'\), false\) THEN RAISE EXCEPTION/.test(antes),
    recusaRosterDeVolta: /IF v_rev\.reason = 'engagement_ended' AND public\._drive_grant_keeps_access\(v_g\.grantee_person_id, v_g\.initiative_id\) THEN RAISE EXCEPTION/.test(antes),
    recusaConcessaoFechada: /IF v_g\.status IS DISTINCT FROM 'granted' THEN RAISE EXCEPTION/.test(antes),
    avisaSoFimDeVinculoNaoAvisado: /v_notify_now := v_rev\.reason = 'engagement_ended' AND v_rev\.notified_at IS NULL;/.test(s)
      && /IF v_notify_now THEN v_sent := public\._drive_revocation_notify\(v_rev\.id, true\); END IF;/.test(s),
    prazoNaHora: /notified_at = CASE WHEN v_notify_now THEN now\(\) ELSE notified_at END, due_at = CASE WHEN v_notify_now THEN now\(\) ELSE due_at END/.test(s),
  };
}

/** G11 + G14 (A2, A8): a avulsa recusa manage_platform antes de escrever e não avisa ninguém. */
export function avulsa(b) {
  const s = sql(b);
  const up = s.indexOf('UPDATE public.drive_membership_revocations');
  return {
    recusaManagePlatform: up > 0 && /IF coalesce\(public\.can_by_member\(v_g\.grantee_member_id, 'manage_platform'\), false\) THEN RAISE EXCEPTION/.test(s.slice(0, up)),
    semAviso: !/_drive_revocation_notify\(|create_notification\(/.test(s),
    viraPedidoManual: /SET status = 'approved', reason = 'manual'/.test(s),
  };
}

/** G13 (A6): um aviso por pessoa e iniciativa. A condição e o retorno no mesmo IF, antes da notificação. */
export function avisoUmPorPar(b) {
  const s = sql(b);
  const dedup = ifBlock(s, 'IF EXISTS (SELECT 1 FROM public.drive_membership_revocations o');
  return {
    mesmoPar: /WHERE o\.id <> v\.id AND o\.member_id = v\.member_id AND o\.initiative_id = v\.initiative_id AND o\.notified_at IS NOT NULL/.test(dedup),
    retornaSemAvisar: /THEN RETURN false; END IF/.test(dedup),
    antesDaNotificacao: dedup !== '' && s.indexOf(dedup) < s.indexOf('PERFORM public.create_notification('),
    // a pausa não recebe o texto que diz que o vínculo terminou
    pausaTextoNeutro: /WHEN p_closing_now AND v\.member_status IN \('active','alumni'\) THEN 'Seu vínculo com '/.test(s)
      && /WHEN p_closing_now THEN 'A gestão do Núcleo encerrou seu acesso/.test(s),
  };
}

/** G17 (#3147 fatia 2, achado 5): o aviso só é calado por outro do MESMO episódio, e o "foi encerrado" só por outro
 * "foi encerrado". Tudo dentro do IF que retorna sem avisar. */
export function avisoNoMesmoEpisodio(b) {
  const s = sql(b);
  const dedup = ifBlock(s, 'IF EXISTS (SELECT 1 FROM public.drive_membership_revocations o');
  return {
    janelaDoEpisodio: /c_episode constant interval := interval '7 days';/.test(s)
      && /AND o\.detected_at BETWEEN v\.detected_at - c_episode AND v\.detected_at \+ c_episode/.test(dedup)
      && /SELECT x\.id, x\.member_id, x\.initiative_id, x\.due_at, x\.detected_at,/.test(s),
    soItemAberto: /AND o\.status IN \('pending','approved'\)/.test(dedup) && !/o\.status <> 'cancelled'/.test(dedup),
    encerradoSoPorEncerrado: /AND \(NOT p_closing_now OR o\.due_at <= o\.notified_at\)\) THEN RETURN false; END IF/.test(dedup),
    semJanelaPeloRelogio: !/o\.notified_at > now\(\)/.test(dedup),
  };
}

/** G18 (fatia 2): cada item liberado no b2 deixa linha de auditoria com o estado de ANTES. */
export function liberacaoAuditada(enqueueBody) {
  const b2 = slice(sql(enqueueBody), 'WITH rel AS', 'SELECT count(*) INTO v_released FROM rel;');
  return {
    leOEstadoDeAntes: /FROM public\.drive_membership_grants g, public\.drive_membership_revocations o WHERE g\.id = q\.grant_id AND o\.id = q\.id/.test(b2)
      && /RETURNING q\.id, q\.grant_id, o\.status AS status_before, o\.cancel_reason AS cancel_reason_before/.test(b2),
    gravaPorItemLiberado: /INSERT INTO public\.admin_audit_log \(actor_id, action, target_type, target_id, changes, metadata\) SELECT NULL, 'drive_membership_revocation_released', 'drive_membership_revocations', rel\.id, jsonb_build_object\('status_before', rel\.status_before, 'cancel_reason_before', rel\.cancel_reason_before,.* FROM rel RETURNING 1/.test(b2),
  };
}

/** G19 (fatia 2): o passo e relê a visibilidade da iniciativa e grava o que valeu. */
export function aprovacaoReleVisibilidade(enqueueBody) {
  const ap = slice(sql(enqueueBody), "SET status = 'approved', approval_mode = 'auto'", 'RETURNING x.id');
  return {
    juntaAIniciativaDoItem: /public\.initiatives i, public\.drive_membership_revocations o WHERE .*AND i\.id = x\.initiative_id AND o\.id = x\.id/.test(ap),
    confidencialAgoraSai: /AND \(x\.due_at <= now\(\) OR i\.visibility = 'confidential'\)/.test(ap),
    gravaOQueValeu: /is_confidential = \(i\.visibility = 'confidential'\), due_at = LEAST\(x\.due_at, now\(\)\)/.test(ap),
  };
}

/** G20 (fatia 2, decisão do GP de 23/11/2026): quem sai antes do prazo avisado recebe o "foi encerrado". O prazo de
 * antes vem de o; o aviso sai só para esses ids, dentro da chave, com a hora gravada antes de avisar. */
export function encerradoNaAntecipacao(enqueueBody) {
  const s = sql(enqueueBody);
  const dentro = ifBlock(s, 'IF v_on THEN');
  const laco = slice(dentro, 'FOREACH v_id IN ARRAY', 'END LOOP;');
  return {
    prazoDeAntes: /RETURNING x\.id, \(o\.due_at > now\(\)\) AS closing_early \)/.test(dentro)
      && /SELECT array_agg\(id ORDER BY id\), array_agg\(id ORDER BY id\) FILTER \(WHERE closing_early\) INTO v_ids, v_early FROM ap;/.test(dentro),
    avisaEncerradoSoAosAntecipados: /^FOREACH v_id IN ARRAY coalesce\(v_early, ARRAY\[\]::uuid\[\]\) LOOP/.test(laco)
      && /IF public\._drive_revocation_notify\(v_id, true\) THEN v_sent := v_sent \+ 1; END IF;/.test(laco),
    horaAntesDoAviso: /LOOP UPDATE public\.drive_membership_revocations SET notified_at = now\(\), updated_at = now\(\) WHERE id = v_id; IF public\._drive_revocation_notify\(v_id, true\)/.test(laco),
  };
}

/** G16 (A4): pastas de trabalho de mais de uma iniciativa, a partir das linhas de initiative_drive_links. */
export function pastasDeMaisDeUmaIniciativa(rows) {
  const porPasta = new Map();
  for (const r of rows) {
    if (r.unlinked_at || r.link_purpose !== 'workspace' || !r.drive_folder_id) continue;
    if (!porPasta.has(r.drive_folder_id)) porPasta.set(r.drive_folder_id, new Set());
    porPasta.get(r.drive_folder_id).add(r.initiative_id);
  }
  return [...porPasta].filter(([, s]) => s.size > 1).map(([k]) => k);
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

test('#3147 G10-G15: executor, aprovar já, pausa, aviso por par, avulsa e liberação', () => {
  ok(aprovarJa(body('admin_approve_drive_membership_revocation')), 'o aprovar já mudou');
  ok(avulsa(body('admin_request_drive_revocation')), 'a avulsa mudou');
  ok(pausaNoManual(body('enqueue_membership_drive_revocations')), 'a pausa saiu do manual');
  ok(avisoUmPorPar(body('_drive_revocation_notify')), 'o aviso por par mudou');
  ok(liberacao(body('enqueue_membership_drive_revocations')), 'a liberação do bloqueio mudou');
});

test('#3147 G17-G20 (fatia 2): aviso por episódio, liberação auditada, visibilidade relida e encerrado antecipado', () => {
  ok(avisoNoMesmoEpisodio(body('_drive_revocation_notify')), 'o aviso deixou de ser por episódio');
  ok(liberacaoAuditada(body('enqueue_membership_drive_revocations')), 'a liberação deixou de ser auditada');
  ok(aprovacaoReleVisibilidade(body('enqueue_membership_drive_revocations')), 'o passo e deixou de reler a visibilidade');
  ok(encerradoNaAntecipacao(body('enqueue_membership_drive_revocations')), 'quem sai antes do prazo deixou de receber o encerrado');
});

test('#3147 G16: o predicado de pasta compartilhada diz sim e diz não', () => {
  const a = { link_purpose: 'workspace', unlinked_at: null };
  assert.deepEqual(pastasDeMaisDeUmaIniciativa([{ ...a, drive_folder_id: 'F1', initiative_id: 'I1' }, { ...a, drive_folder_id: 'F1', initiative_id: 'I2' }]), ['F1']);
  // a mesma iniciativa duas vezes, um vínculo desfeito ou outro propósito não contam
  assert.deepEqual(pastasDeMaisDeUmaIniciativa([{ ...a, drive_folder_id: 'F1', initiative_id: 'I1' }, { ...a, drive_folder_id: 'F1', initiative_id: 'I1' }]), []);
  assert.deepEqual(pastasDeMaisDeUmaIniciativa([{ ...a, drive_folder_id: 'F1', initiative_id: 'I1' }, { ...a, drive_folder_id: 'F1', initiative_id: 'I2', unlinked_at: '2026-01-01' }]), []);
  assert.deepEqual(pastasDeMaisDeUmaIniciativa([{ ...a, drive_folder_id: 'F1', initiative_id: 'I1' }, { ...a, link_purpose: 'other', drive_folder_id: 'F1', initiative_id: 'I2' }]), []);
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
  assert.equal(insertDaFila(mut(E, "AND NOT public.can_by_member(g.grantee_member_id, 'manage_platform')\n       -- já tem", "-- já tem")).excecaoManagePlatform, false);
  // M2b (A7) a concessão sem titular entra
  assert.equal(insertDaFila(mut(E, '       AND g.grantee_person_id IS NOT NULL AND g.grantee_member_id IS NOT NULL\n', '')).exigeTitular, false);
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
  assert.equal(prazoEAprovacao(mut(E, 'CASE WHEN r.conf_now THEN now() ELSE', 'CASE WHEN false THEN now() ELSE')).confidencialNoCiclo, false);
  // M7b (A9) o prazo volta a ler a confidencialidade gravada na entrada
  assert.equal(prazoEAprovacao(mut(E, "SELECT x.id, (i.visibility = 'confidential') AS conf_now", 'SELECT x.id, x.is_confidential AS conf_now')).confidencialLidaAgora, false);
  // M8 aprova sem o aviso dado
  assert.equal(prazoEAprovacao(mut(E, 'AND x.held_at IS NULL AND x.notified_at IS NOT NULL\n', 'AND x.held_at IS NULL\n')).aprovaSoVencidoAvisadoSoltos, false);
  // M9 aprova o segurado
  assert.equal(prazoEAprovacao(mut(E, '         AND x.held_at IS NULL AND x.notified_at IS NOT NULL', '         AND x.notified_at IS NOT NULL')).aprovaSoVencidoAvisadoSoltos, false);
  // M10 a aprovação não reconfere o roster (corrida entre o aviso e o prazo)
  const ap = "AND NOT public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)\n         AND NOT public.can_by_member";
  assert.equal(prazoEAprovacao(mut(E, ap, 'AND NOT public.can_by_member')).reconfereRoster, false);
  // M11 o executor age na concessão já fechada
  assert.equal(executor(mut(G, "CASE WHEN g.status IS DISTINCT FROM 'granted' THEN 'grant_' || g.status", 'CASE WHEN false THEN NULL'), MK).getSoAprovadoDeConcessaoViva, false);
  // M11b (A1) o executor deixa de reconferir quem fica: o vínculo de volta entre a aprovação e o dreno é revogado
  assert.equal(executor(mut(G, "THEN 'stale_keeps_access'", "THEN r.status"), MK).getReconfereQuemFica, false);
  assert.equal(executor(mut(G, "              OR coalesce(public.can_by_member(g.grantee_member_id, 'manage_platform'), false) )", '              OR false )'), MK).getReconfereQuemFica, false);
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

  const AP = body('admin_approve_drive_membership_revocation');
  const AV = body('admin_request_drive_revocation');
  const N = body('_drive_revocation_notify');
  // M19 (A1) o aprovar já aceita quem voltou ao roster
  assert.equal(aprovarJa(mut(AP, "IF v_rev.reason = 'engagement_ended' AND public._drive_grant_keeps_access(v_g.grantee_person_id, v_g.initiative_id) THEN", 'IF false THEN')).recusaRosterDeVolta, false);
  // M20 (A1) o aprovar já aceita o titular com manage_platform
  assert.equal(aprovarJa(mut(AP, "  IF coalesce(public.can_by_member(v_g.grantee_member_id, 'manage_platform'), false) THEN", '  IF false THEN')).recusaManagePlatform, false);
  // M21 (A1) a recusa vai para depois do UPDATE (o item já foi aprovado quando a recusa chega)
  const rec = "  IF v_rev.reason = 'engagement_ended' AND public._drive_grant_keeps_access(v_g.grantee_person_id, v_g.initiative_id) THEN\n    RAISE EXCEPTION 'A pessoa voltou ao roster da iniciativa; o item será cancelado no próximo ciclo';\n  END IF;\n";
  assert.equal(aprovarJa(mut(mut(AP, rec, ''), '  IF v_notify_now THEN\n', rec + '  IF v_notify_now THEN\n')).recusaRosterDeVolta, false);
  // M22 (A2) o aprovar já deixa de avisar
  assert.equal(aprovarJa(mut(AP, '    v_sent := public._drive_revocation_notify(v_rev.id, true);\n', '')).avisaSoFimDeVinculoNaoAvisado, false);
  // M23 (A2) o aprovar já avisa de novo quem já foi avisado
  assert.equal(aprovarJa(mut(AP, " AND v_rev.notified_at IS NULL;", ';')).avisaSoFimDeVinculoNaoAvisado, false);
  // M24 (A2) a avulsa passa a avisar
  assert.equal(avulsa(mut(AV, '  RETURN jsonb_build_object(', '  PERFORM public._drive_revocation_notify(v_rev.id, true);\n  RETURN jsonb_build_object(')).semAviso, false);
  // M25 (A8) a avulsa aceita o titular com manage_platform
  assert.equal(avulsa(mut(AV, "  IF coalesce(public.can_by_member(v_g.grantee_member_id, 'manage_platform'), false) THEN", '  IF false THEN')).recusaManagePlatform, false);
  // M26 (A3) o ciclo avisa a pausa
  assert.equal(pausaNoManual(mut(E, "         AND m.member_status IN ('active','alumni')\n       ORDER BY", '       ORDER BY')).avisoSoActiveOuAlumni, false);
  // M27 (A3) o ciclo aprova a pausa
  assert.equal(pausaNoManual(mut(E, "         AND m.member_status IN ('active','alumni')\n         AND NOT public._drive_grant_keeps_access", '         AND NOT public._drive_grant_keeps_access')).aprovacaoSoActiveOuAlumni, false);
  // M28 (A6) o aviso deixa de olhar o par: dois e-mails, dois avisos
  assert.equal(avisoUmPorPar(mut(N, ' AND o.initiative_id = v.initiative_id', '')).mesmoPar, false);
  // M29 (A6) a conferência do par não impede o aviso
  assert.equal(avisoUmPorPar(mut(N, '    RETURN false;\n  END IF;\n  PERFORM', '    NULL;\n  END IF;\n  PERFORM')).retornaSemAvisar, false);
  // M30 (A3) a pausa recebe o texto de vínculo encerrado
  assert.equal(avisoUmPorPar(mut(N, "WHEN p_closing_now AND v.member_status IN ('active','alumni')", 'WHEN p_closing_now')).pausaTextoNeutro, false);
  // M31 (A5) a falha volta a bloquear para sempre
  assert.equal(liberacao(mut(E, "(q.status = 'failed' AND q.reason = 'engagement_ended') OR ", '')).falhaOuManter, false);
  // M32 (A5) libera sem a pessoa ter voltado ao roster
  assert.equal(liberacao(mut(E, "       AND public._drive_grant_keeps_access(g.grantee_person_id, g.initiative_id)\n    RETURNING q.id, q.grant_id,", "    RETURNING q.id, q.grant_id,")).soQuandoVoltaAoRoster, false);

  // fatia 2
  // M33 o aviso volta a ser calado por item fechado de outro episódio
  assert.equal(avisoNoMesmoEpisodio(mut(N, "AND o.status IN ('pending','approved')", "AND o.status <> 'cancelled'")).soItemAberto, false);
  // M34 o aviso perde a janela do episódio
  assert.equal(avisoNoMesmoEpisodio(mut(N, '                AND o.detected_at BETWEEN v.detected_at - c_episode AND v.detected_at + c_episode\n', '')).janelaDoEpisodio, false);
  // M35 o "foi encerrado" volta a ser calado pelo "termina em 7 dias"
  assert.equal(avisoNoMesmoEpisodio(mut(N, '\n                AND (NOT p_closing_now OR o.due_at <= o.notified_at)) THEN', ') THEN')).encerradoSoPorEncerrado, false);
  // M36 o "foi encerrado" é calado por qualquer aviso (a condição invertida)
  assert.equal(avisoNoMesmoEpisodio(mut(N, 'NOT p_closing_now OR o.due_at <= o.notified_at', 'p_closing_now OR o.due_at <= o.notified_at')).encerradoSoPorEncerrado, false);
  // M37 a liberação deixa de gravar auditoria
  const aud = slice(E, '  ), rel_audit AS (', '    RETURNING 1\n');
  assert.equal(liberacaoAuditada(mut(E, aud, '')).gravaPorItemLiberado, false);
  // M38 a auditoria grava o estado de DEPOIS (q, e não o)
  assert.equal(liberacaoAuditada(mut(E, 'o.status AS status_before', 'q.status AS status_before')).leOEstadoDeAntes, false);
  // M39 o passo e esquece a visibilidade
  assert.equal(aprovacaoReleVisibilidade(mut(E, "AND (x.due_at <= now() OR i.visibility = 'confidential')", 'AND x.due_at <= now()')).confidencialAgoraSai, false);
  // M40 o passo e lê a confidencialidade gravada na entrada
  assert.equal(aprovacaoReleVisibilidade(mut(E, "OR i.visibility = 'confidential')", 'OR x.is_confidential)')).confidencialAgoraSai, false);
  // M41 o passo e não grava o que valeu
  assert.equal(aprovacaoReleVisibilidade(mut(E, "             is_confidential = (i.visibility = 'confidential'),\n", '')).gravaOQueValeu, false);
  // M42 quem sai antes do prazo recebe o texto de "termina em 7 dias"
  assert.equal(encerradoNaAntecipacao(mut(E, '_drive_revocation_notify(v_id, true)', '_drive_revocation_notify(v_id, false)')).avisaEncerradoSoAosAntecipados, false);
  // M43 a hora do aviso não é gravada antes de avisar: o par recebe dois "foi encerrado"
  assert.equal(encerradoNaAntecipacao(mut(E, '      UPDATE public.drive_membership_revocations SET notified_at = now(), updated_at = now() WHERE id = v_id;\n', '')).horaAntesDoAviso, false);
  // M44 o prazo de antes lido da linha nova (sempre falso: ninguém recebe o encerrado)
  assert.equal(encerradoNaAntecipacao(mut(E, '(o.due_at > now()) AS closing_early', '(x.due_at > now()) AS closing_early')).prazoDeAntes, false);
  // M45 o laço avisa todo aprovado, e não só quem saiu antes do prazo
  assert.equal(encerradoNaAntecipacao(mut(E, 'FOREACH v_id IN ARRAY coalesce(v_early,', 'FOREACH v_id IN ARRAY coalesce(v_ids,')).avisaEncerradoSoAosAntecipados, false);
  // M46 o filtro some: v_early vira todo aprovado
  assert.equal(encerradoNaAntecipacao(mut(E, ' FILTER (WHERE closing_early)', '')).prazoDeAntes, false);
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
  ok(pausaNoManual(E)); ok(liberacao(E));
  ok(aprovarJa(await vivo('admin_approve_drive_membership_revocation')));
  ok(avulsa(await vivo('admin_request_drive_revocation')));
  ok(avisoUmPorPar(await vivo('_drive_revocation_notify')));
  ok(avisoNoMesmoEpisodio(await vivo('_drive_revocation_notify')));
  ok(liberacaoAuditada(E)); ok(aprovacaoReleVisibilidade(E)); ok(encerradoNaAntecipacao(E));
});

test(dbGated ? '#3147 G16 vivo: nenhuma pasta de trabalho é de duas iniciativas' : `SKIP: ${skipMsg}`, { skip: !dbGated }, async () => {
  // #3178: a revogação por iniciativa supõe uma pasta, uma
  // iniciativa. Se aparecer uma pasta de duas, quem sai de uma perde a pasta que a outra ainda dá.
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.from('initiative_drive_links')
    .select('initiative_id, drive_folder_id, link_purpose, unlinked_at')
    .eq('link_purpose', 'workspace').is('unlinked_at', null).limit(2000);
  assert.equal(error, null, `initiative_drive_links: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length > 0, 'nenhum vínculo de pasta de trabalho lido: o instrumento não mediu');
  assert.ok(data.length < 2000, 'a leitura bateu no limite: o resultado pode estar cortado');
  assert.deepEqual(pastasDeMaisDeUmaIniciativa(data), [], 'pasta de trabalho de mais de uma iniciativa');
});
