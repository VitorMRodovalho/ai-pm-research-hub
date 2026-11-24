// tests/contracts/3178-3179-drive-pasta-e-acesso-fora-do-ledger.test.mjs
/**
 * #3178: a revogação por iniciativa olha a pasta. Quem sai de uma iniciativa e segue no roster de outra que usa a
 * mesma pasta de trabalho fica com o acesso. Medido em 23/11/2026: 0 pastas de trabalho de duas iniciativas em 31
 * vínculos ativos; o caso passa a ser coberto antes de aparecer.
 * #3179: o acesso à pasta de trabalho que não veio do ledger vai para a revisão da gestão, sem revogação automática.
 *
 * O que este guard afirma, com a condição amarrada ao resultado dentro do bloco que decide:
 *   G21 o predicado de quem fica olha a pasta: o mesmo vínculo ativo e membro ativo, na iniciativa da concessão OU em
 *       iniciativa ativa com vínculo de trabalho vivo na pasta; e a versão de dois argumentos sai.
 *   G22 todo chamador passa a pasta da concessão (ciclo, executor, aprovar já), e nenhum chama com dois argumentos.
 *   G23 a tabela da revisão: RLS fechado, um item aberto por permissão da pasta, estados coerentes.
 *   G24 a classificação: só a pasta de trabalho viva; só usuário, sem dono, sem a conta de serviço; o veredito em ordem
 *       (concessão viva, trilha de desligamento aberta, o predicado da última conferência, herdado
 *       da pasta de cima pela #3186, achado); dry_run volta antes
 *       de qualquer escrita; fecha o que deixou de valer e abre só o achado.
 *   G25 o executor: acha o item da revisão, reconfere antes do Drive pela pessoa resolvida de novo pelo e-mail (nunca
 *       pelo id gravado) e pela trilha de desligamento, e só fecha o aprovado; o dreno drena as três filas.
 *   G26 a tela: manage_platform, rls_can_see_initiative e registro de PII na leitura; revogar recusa herdado, o e-mail
 *       que fica com o acesso (resolvido de novo, nunca pelo id gravado) e a trilha de desligamento aberta; manter e
 *       revogar pedem motivo.
 *   G29 a última conferência resolve a pessoa pelo e-mail: concessão viva no e-mail, ou TODO membro com o e-mail (em
 *       members e member_emails) no roster pela pasta ou com manage_platform.
 *   G30 a retenção (LGPD): o revogado perde o e-mail em 5 anos e o fechado em 90 dias, com o pseudônimo e o salt do
 *       #1054, no mesmo purge_expired_logs; nada é apagado.
 *   G27 emulação do #785 sobre as funções da migration.
 *   G28 o reconcile: lê a ACL mesmo com roster vazio, uma revisão por pasta, depois do ledger, sem a conta de serviço,
 *       pede o "herdado" ao Drive, e o dry_run da revisão não grava.
 *   M   cada predicado reprova a mutação do seu defeito, pela MESMA função.
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
const MIG = readdirSync(MIG_DIR).filter((f) => /_3178_3179_drive_pasta_e_acesso_fora_do_ledger\.sql$/.test(f)).sort().pop();
const EF_PATH = join(ROOT, 'supabase/functions/reconcile-initiative-drive-access/index.ts');

/** Tira comentário de linha e colapsa espaço, para o predicado ler o código e não a prosa. */
export function sql(b) {
  return b.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}
/** Tira comentário de TS (linha e bloco) e colapsa espaço. */
export function ts(b) {
  return b.replace(/\/\*[\s\S]*?\*\//g, ' ').split('\n')
    .map((l) => { const i = l.search(/(^|[^:"'])\/\//); return i >= 0 ? l.slice(0, i + (l[i] === '/' ? 0 : 1)) : l; })
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
const allTrue = (o) => Object.fromEntries(Object.keys(o).map((k) => [k, true]));
const ok = (o, msg) => assert.deepEqual(o, allTrue(o), msg);

/** G21: quem fica olha a pasta. */
export function olhaAPasta(keepsBody, migText) {
  const k = sql(keepsBody);
  const m = migText == null ? null : sql(migText);
  const r = {
    mesmoVinculoEMembro: /WHERE e\.person_id = p_person_id AND e\.status = 'active' AND m\.member_status = 'active' AND \(/.test(k),
    iniciativaOuPasta: /AND \( e\.initiative_id = p_initiative_id OR EXISTS \(SELECT 1 FROM public\.initiative_drive_links l JOIN public\.initiatives i ON i\.id = l\.initiative_id WHERE l\.initiative_id = e\.initiative_id AND l\.drive_folder_id = p_drive_folder_id AND l\.link_purpose = 'workspace' AND l\.unlinked_at IS NULL AND i\.status = 'active'\) \)/.test(k),
  };
  if (m != null) {
    // a versão de dois argumentos sai DEPOIS de os chamadores passarem a pasta
    const drop = m.indexOf('DROP FUNCTION IF EXISTS public._drive_grant_keeps_access(uuid, uuid);');
    const ultimoChamador = m.lastIndexOf('CREATE OR REPLACE FUNCTION public.admin_approve_drive_membership_revocation(');
    r.doisArgumentosSai = drop > 0 && drop > ultimoChamador && ultimoChamador > 0;
    r.servicoSo = /REVOKE ALL ON FUNCTION public\._drive_grant_keeps_access\(uuid, uuid, text\) FROM PUBLIC, anon, authenticated;/.test(m);
  }
  return r;
}

const DOIS_ARGS = /_drive_grant_keeps_access\(\s*[^,()]+,\s*[^,()]+\s*\)/g;
const count = (s, re) => (s.match(re) || []).length;

/** G22: todo chamador passa a pasta da concessão. */
export function chamadoresPassamAPasta(enqueueBody, getBody, approveBody) {
  const e = sql(enqueueBody), g = sql(getBody), a = sql(approveBody);
  return {
    cicloQuatroComPasta: count(e, /_drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id, g\.drive_folder_id\)/g) === 4,
    executorComPasta: /WHEN r\.reason = 'engagement_ended' AND \( public\._drive_grant_keeps_access\(g\.grantee_person_id, g\.initiative_id, g\.drive_folder_id\)/.test(g),
    aprovarJaComPasta: /IF v_rev\.reason = 'engagement_ended' AND public\._drive_grant_keeps_access\(v_g\.grantee_person_id, v_g\.initiative_id, v_g\.drive_folder_id\) THEN RAISE EXCEPTION/.test(a),
    nenhumComDois: count(e, DOIS_ARGS) + count(g, DOIS_ARGS) + count(a, DOIS_ARGS) === 0,
  };
}

/** G23: a tabela da revisão. */
export function tabela(migText) {
  const m = migText;
  return {
    rlsFechado: /CREATE POLICY drive_folder_access_findings_deny_all ON public\.drive_folder_access_findings\s+AS PERMISSIVE FOR ALL TO public USING \(false\) WITH CHECK \(false\);/.test(m),
    semAcessoDeCliente: /REVOKE ALL ON public\.drive_folder_access_findings FROM PUBLIC, anon, authenticated;/.test(m),
    umAbertoPorPermissao: /drive_folder_access_findings_open_uidx\s+ON public\.drive_folder_access_findings \(drive_folder_id, permission_id\) WHERE status IN \('open','kept','approved','failed'\);/.test(m),
    aprovadoTemQuem: /CONSTRAINT dfaf_approved_has_person\s+CHECK \(status NOT IN \('approved','revoked','already_absent','failed'\)\s+OR \(approved_by IS NOT NULL AND approved_at IS NOT NULL\)\)/.test(m),
    mantidoTemMotivo: /CONSTRAINT dfaf_kept_has_review\s+CHECK \(status <> 'kept' OR \(reviewed_at IS NOT NULL AND review_note IS NOT NULL\)\)/.test(m),
    motivoDaTrilha: /close_reason\s+text CHECK \(close_reason IN \('permission_gone','covered_by_grant','offboarding_lane','on_roster',\s+'manage_platform_exception'\)\)/.test(m),
    fechadoTemMotivo: /CONSTRAINT dfaf_closed_has_reason\s+CHECK \(\(status = 'closed'\) = \(close_reason IS NOT NULL AND closed_at IS NOT NULL\)\)/.test(m),
  };
}

/** G29: a última conferência resolve a pessoa pelo e-mail. */
export function pessoaPeloEmail(helperBody, migText) {
  const h = sql(helperBody);
  const r = {
    concessaoNoEmail: /SELECT EXISTS \(SELECT 1 FROM public\.drive_membership_grants g WHERE g\.drive_folder_id = p_drive_folder_id AND g\.permission_email = lower\(btrim\(p_email\)\)::citext AND g\.status = 'granted'\)/.test(h),
    todoMembroDoEmail: /OR EXISTS \(SELECT 1 FROM public\.members m WHERE \( lower\(m\.email\) = lower\(btrim\(p_email\)\) OR EXISTS \(SELECT 1 FROM public\.member_emails me WHERE me\.member_id = m\.id AND me\.email = lower\(btrim\(p_email\)\)::citext\) \) AND \( \(m\.person_id IS NOT NULL AND public\._drive_grant_keeps_access\(m\.person_id, NULL, p_drive_folder_id\)\) OR coalesce\(public\.can_by_member\(m\.id, 'manage_platform'\), false\) \)\)/.test(h),
    semLimite: !/\bLIMIT\b/.test(h),
  };
  if (migText != null) r.servicoSo = /REVOKE ALL ON FUNCTION public\._drive_finding_keeps_access\(text, text\) FROM PUBLIC, anon, authenticated;/.test(migText);
  return r;
}

/** G30: a retenção do e-mail da revisão. */
export function retencao(purgeBody) {
  const p = sql(purgeBody);
  const CRIT = /permission_email NOT LIKE 'sha256:%' AND \( \(status IN \('revoked','already_absent'\) AND created_at < now\(\) - \(v_dfaf_terminal_anonymize_days \|\| ' days'\)::interval\) OR \(status = 'closed' AND closed_at < now\(\) - \(v_dfaf_closed_anonymize_days \|\| ' days'\)::interval\) \)/g;
  return {
    prazoRevogado5Anos: /v_dfaf_terminal_anonymize_days constant integer := 1825;/.test(p),
    prazoFechado90Dias: /v_dfaf_closed_anonymize_days constant integer := 90;/.test(p),
    criterioNasDuasPontas: count(p, CRIT) === 2,
    pseudonimoDoMesmoSalt: /UPDATE public\.drive_folder_access_findings SET permission_email = 'sha256:' \|\| encode\(extensions\.digest\(permission_email::text \|\| v_drive_audit_salt, 'sha256'\), 'hex'\)/.test(p),
    saltDo1054: /v_drive_audit_salt constant text := 'nucleoia-drive-offboarding-audit-anon-v1';/.test(p),
    devolveALinha: /RETURN QUERY SELECT 'drive_folder_access_findings'::text, 'anonymize'::text, v_count, v_oldest;/.test(p),
    naoApaga: !/DELETE FROM public\.drive_folder_access_findings/.test(p),
  };
}

/** G24: a classificação da ACL. */
export function classificacao(recordBody) {
  const s = sql(recordBody);
  const corpo = s.slice(s.indexOf('BEGIN'));
  const dry = corpo.indexOf('IF p_dry_run THEN RETURN');
  const primeiraEscrita = corpo.search(/\b(UPDATE public\.|INSERT INTO public\.)/);
  return {
    soServico: /^ ?BEGIN IF public\.current_caller_role\(\) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION/.test(corpo),
    soPastaDeTrabalhoViva: /IF NOT EXISTS \(SELECT 1 FROM public\.initiative_drive_links l WHERE l\.drive_folder_id = p_drive_folder_id AND l\.link_purpose = 'workspace' AND l\.unlinked_at IS NULL\) THEN RAISE EXCEPTION/.test(s),
    soUsuarioSemDonoNemServico: /WHERE x\.type = 'user' AND coalesce\(x\.deleted, false\) = false AND x\.id IS NOT NULL AND nullif\(btrim\(x\."emailAddress"\), ''\) IS NOT NULL AND x\.role IS DISTINCT FROM 'owner' AND lower\(btrim\(x\."emailAddress"\)\) NOT IN \(SELECT lower\(btrim\(e\)\) FROM unnest\(coalesce\(p_ignore_emails/.test(s),
    vereditoEmOrdem: /'verdict', CASE WHEN EXISTS \(SELECT 1 FROM public\.drive_membership_grants g WHERE g\.drive_folder_id = p_drive_folder_id AND g\.permission_email = w\.email::citext AND g\.status = 'granted'\) THEN 'covered_by_grant' WHEN EXISTS \(SELECT 1 FROM public\.drive_offboarding_audit a WHERE a\.drive_file_id = p_drive_folder_id AND a\.permission_id = w\.permission_id AND a\.status IN \('pending_revoke','approved'\)\) THEN 'offboarding_lane' WHEN public\._drive_finding_keeps_access\(p_drive_folder_id, w\.email\) THEN CASE WHEN w\.member_id IS NOT NULL AND coalesce\(public\.can_by_member\(w\.member_id, 'manage_platform'\), false\) THEN 'manage_platform_exception' ELSE 'on_roster' END WHEN w\.inherited IS TRUE THEN 'inherited' ELSE 'finding' END/.test(s),
    dryRunAntesDeEscrever: dry > 0 && primeiraEscrita > dry,
    fechaOQueDeixouDeValer: /UPDATE public\.drive_folder_access_findings f SET status = 'closed', closed_at = now\(\), updated_at = now\(\), close_reason = coalesce\(\(SELECT cur\.verdict FROM cur WHERE cur\.permission_id = f\.permission_id AND cur\.verdict <> 'finding'\), 'permission_gone'\) WHERE f\.drive_folder_id = p_drive_folder_id AND f\.status IN \('open','kept','approved','failed'\) AND NOT EXISTS \(SELECT 1 FROM cur WHERE cur\.permission_id = f\.permission_id AND cur\.verdict = 'finding'\)/.test(s),
    abreSoOAchado: /INSERT INTO public\.drive_folder_access_findings \(drive_folder_id, permission_id, permission_email, permission_role, inherited, person_id, member_id\) SELECT [^;]*? WHERE c\.verdict = 'finding' AND NOT EXISTS \(SELECT 1 FROM public\.drive_folder_access_findings f WHERE f\.drive_folder_id = p_drive_folder_id AND f\.permission_id = c\.permission_id AND f\.status IN \('open','kept','approved','failed'\)\)/.test(s),
    registraPii: /INSERT INTO public\.pii_access_log \(accessor_id, target_member_id, fields_accessed, context, reason, actor_kind\) SELECT NULL, mid, ARRAY\['email'\], 'record_drive_folder_acl'/.test(s),
  };
}

/** G25: o executor e o dreno. */
export function executorDaRevisao(getBody, markBody, migText) {
  const g = sql(getBody), mk = sql(markBody);
  const ramo = slice(g, 'FROM public.drive_membership_revocations r', "'queue', 'folder_acl'");
  const dreno = migText == null ? '' : slice(migText, "cron.schedule('revoke-drive-drain-hourly'", '$drain$;');
  const r = {
    reconfereAntesDoDrive: /CASE WHEN f\.status = 'approved' AND public\._drive_finding_keeps_access\(f\.drive_folder_id, f\.permission_email::text\) THEN 'stale_keeps_access' WHEN f\.status = 'approved' AND EXISTS \(SELECT 1 FROM public\.drive_offboarding_audit a WHERE a\.drive_file_id = f\.drive_folder_id AND a\.permission_id = f\.permission_id AND a\.status IN \('pending_revoke','approved'\)\) THEN 'offboarding_lane' ELSE f\.status END AS status/.test(ramo),
    naoConfiaNoIdGravado: ramo !== '' && !/\bf\.(person_id|member_id)\b/.test(ramo),
    achaPeloId: /FROM public\.drive_folder_access_findings f WHERE f\.id = p_audit_id/.test(ramo),
    soFechaOAprovado: /UPDATE public\.drive_folder_access_findings SET status = p_status, google_error = p_google_error, revoked_at = CASE WHEN p_status IN \('revoked','already_absent'\) THEN now\(\) ELSE revoked_at END, updated_at = now\(\) WHERE id = p_audit_id AND status = 'approved' RETURNING \* INTO v_f;/.test(mk),
    auditaORevogado: /IF v_f\.id IS NOT NULL THEN IF p_status IN \('revoked','already_absent'\) THEN INSERT INTO public\.admin_audit_log [^;]*'drive_folder_access_revoked'/.test(mk),
  };
  if (migText != null) {
    r.drenoTresFilas = /UNION ALL\s+SELECT id, approved_at FROM public\.drive_folder_access_findings\s+WHERE status = 'approved' AND approved_at < now\(\) - interval '5 minutes'/.test(dreno)
      && /FROM public\.drive_membership_revocations\s+WHERE status = 'approved'/.test(dreno)
      && /FROM public\.drive_offboarding_audit\s+WHERE status = 'approved'/.test(dreno);
  }
  return r;
}

const PORTAO = /v_caller_id := \(SELECT id FROM public\.members WHERE auth_id = auth\.uid\(\)\); IF v_caller_id IS NULL OR NOT public\.can_by_member\(v_caller_id, 'manage_platform'\) THEN RAISE EXCEPTION/;

/** G26: a tela da revisão. */
export function telaDaRevisao(listBody, reviewBody) {
  const l = sql(listBody), v = sql(reviewBody);
  const revogar = v.slice(v.indexOf('ELSE IF v_f.status NOT IN'));
  return {
    leituraPortao: PORTAO.test(l),
    leituraConfidencial: /WHERE l\.drive_folder_id = f\.drive_folder_id AND l\.link_purpose = 'workspace' AND public\.rls_can_see_initiative\(l\.initiative_id\) \) ini ON ini\.initiatives IS NOT NULL/.test(l),
    confidencialPrimeiro: /ORDER BY q\.is_confidential DESC/.test(l),
    leituraRegistraPii: /PERFORM public\.log_pii_access_batch\(v_ids, ARRAY\['email'\], 'admin_list_drive_folder_access_findings'/.test(l),
    acaoPortao: PORTAO.test(v),
    motivoObrigatorio: /IF p_action IN \('keep','revoke'\) AND v_note IS NULL THEN RAISE EXCEPTION/.test(v),
    revogarRecusaHerdado: /IF v_f\.inherited IS TRUE THEN RAISE EXCEPTION/.test(revogar),
    revogarRecusaQuemFica: /IF public\._drive_finding_keeps_access\(v_f\.drive_folder_id, v_f\.permission_email::text\) THEN RAISE EXCEPTION/.test(revogar),
    revogarRecusaTrilha: /IF EXISTS \(SELECT 1 FROM public\.drive_offboarding_audit a WHERE a\.drive_file_id = v_f\.drive_folder_id AND a\.permission_id = v_f\.permission_id AND a\.status IN \('pending_revoke','approved'\)\) THEN RAISE EXCEPTION/.test(revogar),
    revogarNaoConfiaNoIdGravado: revogar !== '' && !/\bv_f\.(person_id|member_id)\b/.test(revogar),
    revogarAprova: /UPDATE public\.drive_folder_access_findings SET status = 'approved', approved_by = v_caller_id, approved_at = now\(\)/.test(revogar),
  };
}

/** G27: o critério de _audit_secdef_initiative_reader_gates, aplicado ao corpo (a parte de privilégio vem do .sql). */
export function leitoraSemPortao(prosrc, executavelPorAuthenticated) {
  const tocaTabela = /(board_items|project_boards|board_members|board_lifecycle_events|board_item_|board_drive_links|meeting_action_items)/.test(prosrc)
    || /\bevents\b/.test(prosrc) || /\binitiatives\b/.test(prosrc);
  const escreve = /(INSERT |UPDATE |DELETE )/.test(prosrc.toUpperCase());
  const portao = /rls_can_see_(initiative|board|item)|confidential/.test(prosrc);
  return tocaTabela && !escreve && executavelPorAuthenticated && !portao;
}

/** G28: o reconcile. */
export function reconcileRevisa(efText) {
  const e = ts(efText);
  const loop = slice(e, 'for (const t of targets) {', 'if (dryRun) {');
  const upsert = e.indexOf('sb.rpc("upsert_membership_drive_grants"');
  const revisaoReal = e.indexOf('aclReview ? await reviewFolders(false) : null');
  const revisao = slice(e, 'const reviewFolders = async (dry: boolean) => {', 'return { folders:');
  return {
    pedeOHerdado: /url\.searchParams\.set\("fields", "nextPageToken, permissions\(id,type,role,emailAddress,deleted,permissionDetails\(inherited\)\)"\)/.test(e),
    leComRosterVazio: /if \(roster\.length === 0 && !aclReview\) continue;/.test(loop) && !/if \(roster\.length === 0\) continue;/.test(loop),
    umaPorPasta: /if \(aclReview && !aclByFolder\.has\(t\.drive_folder_id\)\) aclByFolder\.set\(t\.drive_folder_id, perms\);/.test(loop),
    chamaAClassificacao: /for \(const \[folderId, perms\] of aclByFolder\) \{[\s\S]*?sb\.rpc\("record_drive_folder_acl", \{ p_drive_folder_id: folderId, p_permissions: acl, p_ignore_emails: \[String\(sa\.key\?\.client_email \?\? ""\)\]\.filter\(\(e\) => e !== ""\), p_dry_run: dry, \}\)/.test(revisao),
    depoisDoLedger: upsert > 0 && revisaoReal > upsert,
    dryRunNaoGrava: /if \(dryRun\) \{ const aclReviewResult = aclReview \? await reviewFolders\(true\) : null;/.test(e),
    forceEmailNaoRevisa: /const aclReview = !forceEmail && body\.skip_acl_review !== true;/.test(e),
  };
}

// ───────────────────────── estático: a captura mais nova ─────────────────────────
test('#3178 G21: quem fica com o acesso olha a pasta, e a versão de dois argumentos sai', () => {
  assert.ok(MIG, 'migration *_3178_3179_drive_pasta_e_acesso_fora_do_ledger.sql ausente');
  ok(olhaAPasta(body('_drive_grant_keeps_access'), readFileSync(join(MIG_DIR, MIG), 'utf8')), 'o predicado deixou de olhar a pasta');
});
test('#3178 G22: todo chamador passa a pasta da concessão', () => {
  ok(chamadoresPassamAPasta(body('enqueue_membership_drive_revocations'), body('get_drive_revocation_row'),
    body('admin_approve_drive_membership_revocation')), 'um chamador deixou de passar a pasta');
});
test('#3179 G23: a tabela da revisão', () => ok(tabela(readFileSync(join(MIG_DIR, MIG), 'utf8')), 'a tabela da revisão mudou'));
test('#3179 G24: a classificação da ACL', () => ok(classificacao(body('record_drive_folder_acl')), 'a classificação mudou'));
test('#3179 G25: o executor acha o item da revisão e o dreno drena as três filas', () => {
  ok(executorDaRevisao(body('get_drive_revocation_row'), body('mark_drive_revocation_done'), readFileSync(join(MIG_DIR, MIG), 'utf8')), 'o executor mudou');
});
test('#3179 G26: a tela da revisão', () => {
  ok(telaDaRevisao(body('admin_list_drive_folder_access_findings'), body('admin_review_drive_folder_access')), 'a tela da revisão mudou');
});
test('#3179 G29: a última conferência resolve a pessoa pelo e-mail', () => {
  ok(pessoaPeloEmail(body('_drive_finding_keeps_access'), readFileSync(join(MIG_DIR, MIG), 'utf8')), 'a conferência deixou de resolver pelo e-mail');
});
test('#3179 G30: a retenção do e-mail da revisão', () => ok(retencao(body('purge_expired_logs')), 'a retenção mudou'));
test('#3178-#3179 G27: emulação do #785 sobre as funções da migration', () => {
  const m = readFileSync(join(MIG_DIR, MIG), 'utf8');
  const fns = [...new Set([...m.matchAll(/CREATE OR REPLACE FUNCTION public\.([a-z_0-9]+)\(/g)].map((x) => x[1]))];
  assert.ok(fns.length >= 8, `esperava as funções da migration, vieram ${fns.length}`);
  const resultado = {};
  for (const fn of fns) {
    const authed = new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn}\\([^)]*\\) TO [^;]*authenticated`).test(m);
    resultado[fn] = leitoraSemPortao(body(fn), authed);
  }
  assert.deepEqual(Object.entries(resultado).filter(([, v]) => v).map(([k]) => k), [], 'leitora SECDEF sem portão confidencial');
  // a leitora nova está entre as que a emulação olhou, e é executável por authenticated: o portão é que a livra
  assert.ok(fns.includes('admin_list_drive_folder_access_findings'));
  assert.equal(leitoraSemPortao(body('admin_list_drive_folder_access_findings').replace(/public\.rls_can_see_initiative\(l\.initiative_id\)/g, 'true').replace(/confidential/g, 'x'), true),
    true, 'sem o portão, a leitora nova é pega');
  // controle positivo: uma leitora de initiatives sem portão é pega; com o portão passa; escritora passa
  assert.equal(leitoraSemPortao('SELECT i.title FROM public.initiatives i WHERE i.id = p_id', true), true);
  assert.equal(leitoraSemPortao('SELECT i.title FROM public.initiatives i WHERE public.rls_can_see_initiative(i.id)', true), false);
  assert.equal(leitoraSemPortao('UPDATE public.initiatives SET title = p_t', true), false);
});
test('#3179 G28: o reconcile revisa a ACL de cada pasta', () => ok(reconcileRevisa(readFileSync(EF_PATH, 'utf8')), 'o reconcile mudou'));

// ───────────────────────── mutações: cada predicado reprova o seu defeito ─────────────────────────
test('#3178-#3179 M: cada predicado reprova a mutação do seu defeito', () => {
  const mut = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutação não aplicou: ${a}`); return out; };
  const M = readFileSync(join(MIG_DIR, MIG), 'utf8');
  const K = body('_drive_grant_keeps_access');
  const E = body('enqueue_membership_drive_revocations');
  const G = body('get_drive_revocation_row');
  const AP = body('admin_approve_drive_membership_revocation');
  const R = body('record_drive_folder_acl');
  const MK = body('mark_drive_revocation_done');
  const L = body('admin_list_drive_folder_access_findings');
  const V = body('admin_review_drive_folder_access');
  const EF = readFileSync(EF_PATH, 'utf8');
  const H = body('_drive_finding_keeps_access');
  const P = body('purge_expired_logs');

  // G21
  assert.equal(olhaAPasta(mut(K, 'l.drive_folder_id = p_drive_folder_id', 'true'), null).iniciativaOuPasta, false);
  assert.equal(olhaAPasta(mut(K, " AND i.status = 'active'", ''), null).iniciativaOuPasta, false);
  assert.equal(olhaAPasta(mut(K, 'l.unlinked_at IS NULL', 'true'), null).iniciativaOuPasta, false);
  assert.equal(olhaAPasta(mut(K, "e.status = 'active' AND m.member_status = 'active'", "e.status = 'active'"), null).mesmoVinculoEMembro, false);
  assert.equal(olhaAPasta(K, mut(M, 'DROP FUNCTION IF EXISTS public._drive_grant_keeps_access(uuid, uuid);', '')).doisArgumentosSai, false);
  // G22
  assert.equal(chamadoresPassamAPasta(mut(E, 'g.initiative_id, g.drive_folder_id)', 'g.initiative_id)'), G, AP).cicloQuatroComPasta, false);
  assert.equal(chamadoresPassamAPasta(mut(E, 'g.initiative_id, g.drive_folder_id)', 'g.initiative_id)'), G, AP).nenhumComDois, false);
  assert.equal(chamadoresPassamAPasta(E, mut(G, 'g.initiative_id, g.drive_folder_id)', 'g.initiative_id)'), AP).executorComPasta, false);
  assert.equal(chamadoresPassamAPasta(E, G, mut(AP, 'v_g.initiative_id, v_g.drive_folder_id)', 'v_g.initiative_id)')).aprovarJaComPasta, false);
  // G23
  assert.equal(tabela(mut(M, 'USING (false) WITH CHECK (false);\nREVOKE ALL ON public.drive_folder_access_findings', 'USING (true) WITH CHECK (false);\nREVOKE ALL ON public.drive_folder_access_findings')).rlsFechado, false);
  assert.equal(tabela(mut(M, "(drive_folder_id, permission_id) WHERE status IN ('open','kept','approved','failed');", "(drive_folder_id, permission_id) WHERE status IN ('open');")).umAbertoPorPermissao, false);
  // G24
  assert.equal(classificacao(mut(R, "AND x.role IS DISTINCT FROM 'owner'\n", '')).soUsuarioSemDonoNemServico, false);
  assert.equal(classificacao(mut(R, "WHERE x.type = 'user'", "WHERE x.type IS NOT NULL")).soUsuarioSemDonoNemServico, false);
  assert.equal(classificacao(mut(R, "AND g.status = 'granted') THEN 'covered_by_grant'", "AND g.status IS NOT NULL) THEN 'covered_by_grant'")).vereditoEmOrdem, false);
  assert.equal(classificacao(mut(R, 'public._drive_finding_keeps_access(p_drive_folder_id, w.email)', 'false')).vereditoEmOrdem, false);
  assert.equal(classificacao(mut(R, "AND a.status IN ('pending_revoke','approved')) THEN 'offboarding_lane'", "AND false) THEN 'offboarding_lane'")).vereditoEmOrdem, false);
  assert.equal(classificacao(mut(R, "ELSE 'finding' END", "ELSE 'on_roster' END")).vereditoEmOrdem, false);
  const dry = slice(R, '  IF p_dry_run THEN\n', '  END IF;\n');
  assert.equal(classificacao(mut(R, dry, '')).dryRunAntesDeEscrever, false);
  assert.equal(classificacao(mut(R, "AND NOT EXISTS (SELECT 1 FROM cur WHERE cur.permission_id = f.permission_id AND cur.verdict = 'finding')", '')).fechaOQueDeixouDeValer, false);
  assert.equal(classificacao(mut(R, "     WHERE c.verdict = 'finding'\n       AND NOT EXISTS", '     WHERE true\n       AND NOT EXISTS')).abreSoOAchado, false);
  assert.equal(classificacao(mut(R, "IF NOT EXISTS (SELECT 1 FROM public.initiative_drive_links l\n                  WHERE l.drive_folder_id = p_drive_folder_id AND l.link_purpose = 'workspace' AND l.unlinked_at IS NULL) THEN", 'IF false THEN')).soPastaDeTrabalhoViva, false);
  // G25
  assert.equal(executorDaRevisao(mut(G, "THEN 'offboarding_lane'\n              ELSE f.status END", "THEN f.status\n              ELSE f.status END"), MK, null).reconfereAntesDoDrive, false);
  // M1: a conferência volta a confiar no id gravado no item
  const viaId = mut(G, 'public._drive_finding_keeps_access(f.drive_folder_id, f.permission_email::text)',
    '(f.person_id IS NOT NULL AND public._drive_grant_keeps_access(f.person_id, NULL, f.drive_folder_id))');
  assert.equal(executorDaRevisao(viaId, MK, null).reconfereAntesDoDrive, false);
  assert.equal(executorDaRevisao(viaId, MK, null).naoConfiaNoIdGravado, false);
  assert.equal(executorDaRevisao(G, mut(MK, "WHERE id = p_audit_id AND status = 'approved'\n     RETURNING * INTO v_f;", "WHERE id = p_audit_id\n     RETURNING * INTO v_f;"), null).soFechaOAprovado, false);
  const linhaDreno = "        UNION ALL\n        SELECT id, approved_at FROM public.drive_folder_access_findings\n         WHERE status = 'approved' AND approved_at < now() - interval '5 minutes'\n";
  assert.equal(executorDaRevisao(G, MK, mut(M, linhaDreno, '')).drenoTresFilas, false);
  // G26
  assert.equal(telaDaRevisao(mut(L, 'AND public.rls_can_see_initiative(l.initiative_id)', ''), V).leituraConfidencial, false);
  assert.equal(telaDaRevisao(L, mut(V, '    IF v_f.inherited IS TRUE THEN\n', '    IF false THEN\n')).revogarRecusaHerdado, false);
  assert.equal(telaDaRevisao(L, mut(V, 'IF public._drive_finding_keeps_access(v_f.drive_folder_id, v_f.permission_email::text) THEN', 'IF false THEN')).revogarRecusaQuemFica, false);
  const viaIdV = mut(V, 'IF public._drive_finding_keeps_access(v_f.drive_folder_id, v_f.permission_email::text) THEN',
    'IF v_f.person_id IS NOT NULL AND public._drive_grant_keeps_access(v_f.person_id, NULL, v_f.drive_folder_id) THEN');
  assert.equal(telaDaRevisao(L, viaIdV).revogarNaoConfiaNoIdGravado, false);
  assert.equal(telaDaRevisao(L, mut(V, "                  AND a.status IN ('pending_revoke','approved')) THEN\n      RAISE EXCEPTION 'A trilha", "                  AND false) THEN\n      RAISE EXCEPTION 'A trilha")).revogarRecusaTrilha, false);
  // G29
  assert.equal(pessoaPeloEmail(mut(H, "OR EXISTS (SELECT 1 FROM public.member_emails me\n", "OR false AND EXISTS (SELECT 1 FROM public.member_emails me\n"), null).todoMembroDoEmail, false);
  assert.equal(pessoaPeloEmail(mut(H, "OR coalesce(public.can_by_member(m.id, 'manage_platform'), false) ))", ')))'), null).todoMembroDoEmail, false);
  assert.equal(pessoaPeloEmail(mut(H, "AND g.status = 'granted')", "AND g.status IS NOT NULL)"), null).concessaoNoEmail, false);
  assert.equal(pessoaPeloEmail(mut(H, "OR coalesce(public.can_by_member(m.id, 'manage_platform'), false) ));", "OR coalesce(public.can_by_member(m.id, 'manage_platform'), false) ) LIMIT 1);"), null).semLimite, false);
  // G30
  assert.equal(retencao(mut(P, 'v_dfaf_closed_anonymize_days  constant integer := 90;', 'v_dfaf_closed_anonymize_days  constant integer := 3650;')).prazoFechado90Dias, false);
  assert.equal(retencao(mut(P, 'v_dfaf_terminal_anonymize_days constant integer := 1825;', 'v_dfaf_terminal_anonymize_days constant integer := 99999;')).prazoRevogado5Anos, false);
  assert.equal(retencao(mut(P, "           OR (status = 'closed' AND closed_at < now() - (v_dfaf_closed_anonymize_days || ' days')::interval) );", ' );')).criterioNasDuasPontas, false);
  assert.equal(retencao(mut(P, "SET permission_email = 'sha256:' || encode(extensions.digest(permission_email::text || v_drive_audit_salt, 'sha256'), 'hex'),\n            updated_at", "SET permission_email = 'sha256:' || encode(extensions.digest(permission_email::text, 'sha256'), 'hex'),\n            updated_at")).pseudonimoDoMesmoSalt, false);
  assert.equal(retencao(mut(P, "RETURN QUERY SELECT 'drive_folder_access_findings'::text, 'anonymize'::text, v_count, v_oldest;", "RETURN QUERY SELECT 'drive_folder_access_findings'::text, 'anonymize'::text, 0::bigint, v_oldest;")).devolveALinha, false);
  assert.equal(tabela(mut(M, "'covered_by_grant','offboarding_lane','on_roster',", "'covered_by_grant','on_roster',")).motivoDaTrilha, false);
  assert.equal(telaDaRevisao(L, mut(V, "IF p_action IN ('keep','revoke') AND v_note IS NULL", "IF p_action IN ('keep') AND v_note IS NULL")).motivoObrigatorio, false);
  assert.equal(telaDaRevisao(L, mut(V, "IF v_caller_id IS NULL OR NOT public.can_by_member(v_caller_id, 'manage_platform')", 'IF v_caller_id IS NULL')).acaoPortao, false);
  // G28
  assert.equal(reconcileRevisa(mut(EF, 'if (roster.length === 0 && !aclReview) continue;', 'if (roster.length === 0) continue;')).leComRosterVazio, false);
  assert.equal(reconcileRevisa(mut(EF, 'p_ignore_emails: [String(sa.key?.client_email ?? "")].filter((e) => e !== ""), ', '')).chamaAClassificacao, false);
  assert.equal(reconcileRevisa(mut(EF, 'const aclReviewResult = aclReview ? await reviewFolders(true) : null;', 'const aclReviewResult = aclReview ? await reviewFolders(false) : null;')).dryRunNaoGrava, false);
  assert.equal(reconcileRevisa(mut(EF, ',permissionDetails(inherited)', '')).pedeOHerdado, false);
  // a revisão real antes do ledger: um achado de quem acabou de ganhar concessão nesta rodada
  const real = '  const aclReviewResult = aclReview ? await reviewFolders(false) : null;\n';
  const antes = mut(EF, real, '');
  assert.equal(reconcileRevisa(mut(antes, '  // 4. idempotent ledger upsert\n', '  // 4. idempotent ledger upsert\n' + real)).depoisDoLedger, false);
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

test(dbGated ? '#3178-#3179 vivo: o corpo em produção passa nos mesmos predicados' : `SKIP: ${skipMsg}`, { skip: !dbGated }, async () => {
  ok(olhaAPasta(await vivo('_drive_grant_keeps_access'), null));
  ok(chamadoresPassamAPasta(await vivo('enqueue_membership_drive_revocations'), await vivo('get_drive_revocation_row'),
    await vivo('admin_approve_drive_membership_revocation')));
  ok(classificacao(await vivo('record_drive_folder_acl')));
  ok(executorDaRevisao(await vivo('get_drive_revocation_row'), await vivo('mark_drive_revocation_done'), null));
  ok(telaDaRevisao(await vivo('admin_list_drive_folder_access_findings'), await vivo('admin_review_drive_folder_access')));
  ok(pessoaPeloEmail(await vivo('_drive_finding_keeps_access'), null));
  ok(retencao(await vivo('purge_expired_logs')));
});
