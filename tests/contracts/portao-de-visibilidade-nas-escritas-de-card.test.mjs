/**
 * RPCs de escrita de card conferem a visibilidade da iniciativa antes de gravar (ADR-0105).
 *
 * SECURITY DEFINER contorna a RLS, e a autoridade de escrita (write_board de escopo organização, papel no quadro,
 * posse do card) não diz se quem chama enxerga a iniciativa. As leituras sobre card aplicam rls_can_see_* desde a
 * #785; estas escritas passam a aplicar também.
 *
 * O QUE ESTE GUARD AFIRMA:
 *   E. nas 23 funções, na captura VIGENTE de cada assinatura: o portão é uma instrução IF que nega o predicado do
 *      recurso CERTO (o card, o quadro, a origem e não só o destino) e termina na recusa que a função já usa
 *      (RAISE EXCEPTION ou RETURN jsonb de erro), ANTES da checagem de autoridade e ANTES da primeira escrita.
 *      Comentários mascarados.
 *   A. a migration revoga o EXECUTE de anon nas 11 que o tinham e devolve o EXECUTE a authenticated e service_role.
 *   V. no banco: o corpo vivo das 23 é a captura vigente; anon sem EXECUTE e authenticated com EXECUTE nas 23.
 *   R. recorrência, derivada do catálogo: toda função SECURITY DEFINER que escreve em board_items ou numa filha dele
 *      por FK, executável por authenticated, chama rls_can_see_* ou o predicado do checklist, ou está em EXCECOES com
 *      o motivo. A lista não apodrece: entrada que deixou de ser acusada reprova.
 *
 * O efeito vivo (quem é recusado e quem passa, como membros reais, nos dois sentidos) está na verificação do pacote,
 * desfeita por RAISE. Mutar este arquivo não exercita o banco.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { parseMigration, normalizeArgs } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const ARQUIVOS = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const CARD = "'Unauthorized: cannot access this card'";
const QUADRO = "'Unauthorized: cannot access this board'";

// predicados: cada um tem de aparecer NEGADO dentro do IF do portão. auth: a primeira checagem de autoridade.
const PORTOES = {
  update_board_item: { args: 'p_item_id uuid, p_fields jsonb', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /IF NOT public\._can_write_board_item\(v_caller\.id, p_item_id\)/ },
  create_board_item: { args: 'p_board_id uuid, p_title text, p_description text, p_assignee_id uuid, p_tags text[], p_due_date date, p_status text', forma: 'raise', msg: QUADRO,
    preds: [/rls_can_see_board\(p_board_id\)/], auth: /IF NOT public\._can_write_board\(v_caller\.id, p_board_id\)/ },
  move_board_item: { args: 'p_item_id uuid, p_new_status text, p_new_position integer, p_reason text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /IF p_new_status = 'done' AND NOT v_is_gp/ },
  create_card_comment: { args: 'p_board_item_id uuid, p_body text, p_parent_comment_id uuid, p_mentioned_member_ids uuid[]', forma: 'jsonb', msg: CARD,
    preds: [/rls_can_see_item\(p_board_item_id\)/], auth: /v_authorized := public\.rls_is_member\(\)/ },
  update_card_comment: { args: 'p_comment_id uuid, p_new_body text', forma: 'jsonb', msg: CARD,
    preds: [/rls_can_see_item\(v_comment\.board_item_id\)/], auth: /IF v_comment\.author_id != v_caller_id THEN/ },
  delete_card_comment: { args: 'p_comment_id uuid', forma: 'jsonb', msg: CARD,
    preds: [/rls_can_see_item\(v_comment\.board_item_id\)/], auth: /v_authorized := v_comment\.author_id = v_caller_id/ },
  assign_member_to_item: { args: 'p_item_id uuid, p_member_id uuid, p_role text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /IF NOT \(\s+public\.can_by_member\(v_caller\.id, 'participate_in_governance_review'\)/ },
  unassign_member_from_item: { args: 'p_item_id uuid, p_member_id uuid, p_role text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /IF NOT \(\s+public\.can_by_member\(v_caller\.id, 'participate_in_governance_review'\)/ },
  complete_checklist_item: { args: 'p_checklist_item_id uuid, p_completed boolean', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(v_item\.board_item_id\)/], auth: /IF NOT public\._can_write_board\(v_caller\.id, v_card\.board_id\)/ },
  convert_action_to_card: { args: 'p_action_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_due_date date', forma: 'raise', msg: QUADRO,
    // o quadro de destino E o evento do item de ação de origem, cujo texto vira o card
    preds: [/rls_can_see_board\(p_board_id\)/, /rls_can_see_initiative\(\(SELECT e\.initiative_id FROM public\.meeting_action_items a\s+JOIN public\.events e ON e\.id = a\.event_id\s+WHERE a\.id = p_action_item_id\)\)/],
    auth: /IF NOT public\._can_write_board\(v_caller_id, p_board_id\)/ },
  update_card_during_meeting: { args: 'p_card_id uuid, p_event_id uuid, p_new_status text, p_fields jsonb, p_note text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_card_id\)/], auth: /IF NOT public\._can_write_board_item\(v_caller_id, p_card_id\)/ },
  upsert_board_item: { args: 'p_item_id uuid, p_board_id uuid, p_title text, p_description text, p_status text, p_assignee_id uuid, p_due_date date, p_tags text[], p_labels jsonb, p_checklist jsonb, p_attachments jsonb', forma: 'raise', msg: QUADRO,
    preds: [/rls_can_see_board\(v_board_id\)/], auth: /v_allowed := \(/ },
  publish_board_item_from_curation: { args: 'p_item_id uuid', forma: 'raise', msg: "'Board item not found'",
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /IF NOT public\.can_by_member\(v_caller\.id, 'participate_in_governance_review'\)/ },
  admin_archive_board_item: { args: 'p_item_id uuid, p_reason text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /if v_caller is null\s+or not \(/ },
  admin_restore_board_item: { args: 'p_item_id uuid, p_restore_status text, p_reason text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /if v_caller is null\s+or not \(/ },
  admin_archive_project_board: { args: 'p_board_id uuid, p_reason text, p_archive_items boolean', forma: 'raise', msg: QUADRO,
    preds: [/rls_can_see_board\(p_board_id\)/], auth: /IF NOT public\.can_by_member\(v_caller_id, 'manage_board_admin'/ },
  admin_restore_project_board: { args: 'p_board_id uuid, p_reason text', forma: 'raise', msg: QUADRO,
    preds: [/rls_can_see_board\(p_board_id\)/], auth: /IF NOT public\.can_by_member\(v_caller_id, 'manage_board_admin'/ },
  move_item_to_board: { args: 'p_item_id uuid, p_target_board_id uuid', forma: 'raise', msg: "'Unauthorized: source card not visible'",
    // a ORIGEM: o portão do destino (rls_can_see_initiative(v_target.initiative_id)) já existia e não basta
    preds: [/rls_can_see_item\(p_item_id\)/], auth: /IF NOT public\.board_write_authority\(v_actor, p_target_board_id\)/ },
  create_action_item: { args: 'p_event_id uuid, p_description text, p_assignee_id uuid, p_due_date date, p_board_item_id uuid, p_checklist_item_id uuid, p_kind text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_board_item_id\)/, /rls_can_see_item\(\s+\(SELECT c\.board_item_id FROM public\.board_item_checklists c WHERE c\.id = p_checklist_item_id\)\)/],
    auth: /IF NOT public\.can_by_member\(v_caller_id, 'manage_event'\)/ },
  register_decision: { args: 'p_event_id uuid, p_title text, p_description text, p_related_card_ids uuid[]', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(rc\.id\)/], auth: /IF NOT public\.can_by_member\(v_caller_id, 'manage_event'\)/ },
  link_partner_to_card: { args: 'p_partner_entity_id uuid, p_board_item_id uuid, p_link_role text, p_notes text', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_board_item_id\)/], auth: /IF NOT public\.can_by_member\(v_member\.id, 'manage_partner'\)/ },
  unlink_partner_from_card: { args: 'p_partner_entity_id uuid, p_board_item_id uuid', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_board_item_id\)/], auth: /IF NOT public\.can_by_member\(v_member\.id, 'manage_partner'\)/ },
  upsert_publication_submission_event: { args: 'p_board_item_id uuid, p_channel text, p_submitted_at timestamp with time zone, p_outcome text, p_notes text, p_external_link text, p_published_at timestamp with time zone', forma: 'raise', msg: CARD,
    preds: [/rls_can_see_item\(p_board_item_id\)/], auth: /if not \(\s+coalesce\(v_member\.is_superadmin, false\)/ },
};

// As 11 que tinham EXECUTE para anon em 30/10/2026.
const SEM_ANON = ['assign_member_to_item', 'convert_action_to_card', 'create_action_item', 'create_board_item',
  'move_item_to_board', 'publish_board_item_from_curation', 'register_decision', 'unassign_member_from_item',
  'update_board_item', 'upsert_board_item', 'upsert_publication_submission_event'];

/** A captura vigente de public.<fn>(<args>): a última CREATE dessa assinatura em todas as migrations. */
function vigente(fn, args) {
  const alvo = normalizeArgs(args).replace(/\bpublic\./g, '');
  let hit = null;
  for (const f of ARQUIVOS) {
    const sql = readFileSync(join(MIG_DIR, f), 'utf8');
    if (!sql.includes(fn)) continue;
    for (const b of parseMigration(f, sql)) {
      if (b.name === fn && b.args.replace(/\bpublic\./g, '') === alvo) hit = b;
    }
  }
  assert.ok(hit, `nenhuma migration define public.${fn}(${args})`);
  return hit;
}

const ESCRITA = /\b(INSERT\s+INTO|UPDATE\s+[a-z_.]+(\s+[a-z_]+)?\s+SET|DELETE\s+FROM|PERFORM\s+public\.(move_board_item|update_board_item))\b/i;

/** O IF do portão: uma instrução só (sem ';' até o THEN), com cada predicado negado, terminando na recusa. */
function portao(corpo, spec) {
  const recusa = spec.forma === 'jsonb'
    ? `RETURN\\s+jsonb_build_object\\(\\s*'error',\\s*${spec.msg}\\s*\\)`
    : `RAISE\\s+EXCEPTION\\s+${spec.msg}`;
  const re = new RegExp(`\\bIF\\s[^;]*?THEN\\s+${recusa}`, 'gi');
  let m;
  while ((m = re.exec(corpo)) !== null) {
    const cond = m[0];
    if (spec.preds.every((p) => new RegExp(`NOT\\s+public\\.${p.source}`, 'i').test(cond))) return m.index;
  }
  return -1;
}

for (const [fn, spec] of Object.entries(PORTOES)) {
  test(`E. ${fn}: o portão nega o predicado do recurso e recusa, antes da autoridade e da 1ª escrita`, () => {
    const corpo = maskLineComments(vigente(fn, spec.args).body);
    const iPortao = portao(corpo, spec);
    assert.ok(iPortao >= 0, `${fn}: sem IF NOT ${spec.preds.map((p) => p.source).join(' + ')} THEN ${spec.forma} ${spec.msg}`);
    const iAuth = corpo.search(spec.auth);
    assert.ok(iAuth >= 0, `${fn}: a checagem de autoridade esperada não está no corpo (${spec.auth.source})`);
    const iEscrita = corpo.search(ESCRITA);
    assert.ok(iEscrita >= 0, `${fn}: nenhuma escrita achada no corpo`);
    assert.ok(iPortao < iAuth, `${fn}: o portão (${iPortao}) vem depois da autoridade (${iAuth})`);
    assert.ok(iPortao < iEscrita, `${fn}: o portão (${iPortao}) vem depois da primeira escrita (${iEscrita})`);
  });
}

test('E. as 23 do inventário, nenhuma a menos', () => {
  assert.equal(Object.keys(PORTOES).length, 23);
});

// ── A. EXECUTE de anon ──────────────────────────────────────────────────────────────────────────────

/** Achada pelo conteúdo (a versão no nome é a que o apply carimba): a recusa da origem e o REVOKE do update. */
function migracaoDoPortao() {
  const hit = ARQUIVOS.filter((f) => {
    const sql = maskLineComments(readFileSync(join(MIG_DIR, f), 'utf8'));
    return sql.includes("'Unauthorized: source card not visible'")
      && sql.includes('REVOKE ALL ON FUNCTION public.update_board_item(p_item_id uuid, p_fields jsonb) FROM PUBLIC, anon;');
  });
  assert.equal(hit.length, 1, `esperada 1 migration do portão, achadas ${hit.length}`);
  return maskLineComments(readFileSync(join(MIG_DIR, hit[0]), 'utf8'));
}

test('A. a migration tira o EXECUTE de anon nas 11 e devolve a authenticated e service_role', () => {
  const mig = migracaoDoPortao();
  for (const fn of SEM_ANON) {
    const args = reEsc(PORTOES[fn].args);
    assert.match(mig, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn}\\(${args}\\) FROM PUBLIC, anon;\\s+GRANT EXECUTE ON FUNCTION public\\.${fn}\\(${args}\\) TO authenticated, service_role;`),
      `${fn}: REVOKE de anon seguido do GRANT a authenticated e service_role`);
  }
  assert.equal((mig.match(/REVOKE ALL ON FUNCTION/g) || []).length, SEM_ANON.length, 'só as 11 perdem o grant');
});

// ── V e R. banco ────────────────────────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const skip = SUPABASE_URL && SUPABASE_KEY ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(name, body = {}) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  assert.equal(r.status, 200, `${name}: HTTP ${r.status}`);
  return r.json();
}

test('V. o corpo vivo das 23 é a captura vigente', { skip }, async () => {
  const vivos = await rpc('_audit_list_public_function_bodies');
  for (const [fn, spec] of Object.entries(PORTOES)) {
    const linhas = vivos.filter((x) => x.proname === fn);
    assert.equal(linhas.length, 1, `${fn}: ${linhas.length} assinaturas vivas`);
    assert.equal(linhas[0].identity_args, spec.args, `${fn}: assinatura viva diferente`);
    assert.equal(linhas[0].body_md5, vigente(fn, spec.args).bodyHash, `${fn}: corpo vivo diferente da captura vigente`);
  }
});

test('V. anon sem EXECUTE e authenticated com EXECUTE nas 23', { skip }, async () => {
  const acl = await rpc('_audit_function_execute_acl', { p_names: Object.keys(PORTOES) });
  assert.equal(acl.length, 23, `esperadas 23 linhas de ACL, vieram ${acl.length}`);
  const comAnon = acl.filter((x) => x.anon_exec).map((x) => x.proname);
  assert.deepEqual(comAnon, [], `ainda com EXECUTE para anon: ${comAnon.join(', ')}`);
  const semAuth = acl.filter((x) => !x.authenticated_exec).map((x) => x.proname);
  assert.deepEqual(semAuth, [], `sem EXECUTE para authenticated: ${semAuth.join(', ')}`);
});

// Escritoras sem o portão no corpo, cada uma com o motivo. Fora daqui, toda escritora acusada reprova.
const EXCECOES = {
  admin_detect_data_anomalies: 'só manage_platform, que vê toda iniciativa (ADR-0105)',
  admin_map_notion_item_to_board: 'só manage_platform, que vê toda iniciativa (ADR-0105)',
  place_responsibility_handoff: 'só manage_platform ou service, que vê toda iniciativa (ADR-0105)',
  admin_offboard_member: 'ciclo de vida do membro (manage_member): reatribui os cards de quem sai',
  create_external_speaker_engagement: 'escreve só no quadro que a própria chamada cria',
  auto_comms_card_on_publish: 'gatilho: roda dentro da escrita que o disparou',
  clear_board_assignee_on_junction_delete: 'gatilho: roda dentro da escrita que o disparou',
  ensure_assignee_in_board_junction: 'gatilho: roda dentro da escrita que o disparou',
  log_forecast_change: 'gatilho: roda dentro da escrita que o disparou',
  recalculate_card_dates: 'gatilho: roda dentro da escrita que o disparou',
  trg_auto_submit_curation_on_reviewer_assign: 'gatilho: roda dentro da escrita que o disparou',
  admin_manage_publication: 'publicação pública, sem card no argumento',
  convert_proposal_to_webinar: 'webinar, sem card no argumento',
  increment_publication_view: 'contador de publicação pública, sem card no argumento',
  link_webinar_event: 'webinar e evento, sem card no argumento',
  manage_action_items: 'itens de ação de evento, sem card no argumento',
  register_event_showcase: 'vitrine de evento, sem card no argumento',
  remove_event_showcase: 'vitrine de evento, sem card no argumento',
  resolve_action_item: 'item de ação de evento, sem card no argumento',
  update_publication_submission: 'submissão de publicação, sem card no argumento',
  update_publication_submission_status: 'submissão de publicação, sem card no argumento',
  update_webinar_comms_assets: 'webinar, sem card no argumento',
  upsert_webinar: 'webinar, sem card no argumento',
};
// Predicado que já carrega o portão: quem o chama está coberto. Afirmado no corpo vivo abaixo.
const PREDICADOS = ['can_manage_card_checklist'];

test('R. toda escritora de card SECURITY DEFINER, executável por authenticated, passa pelo portão', { skip }, async () => {
  const cobertura = await rpc('_audit_confidential_write_gate_coverage');
  const filhas = [...new Set(cobertura.filter((r) => r.aponta_para === 'board_items').map((r) => r.tabela))];
  assert.ok(filhas.includes('board_item_comments') && filhas.includes('board_item_assignments'),
    `as filhas de board_items por FK vieram sem comentários ou atribuições: ${filhas.join(', ')}`);
  const tabelas = ['board_items', ...filhas].join('|');
  const escritoras = (await rpc('_audit_functions_matching', {
    p_pattern: `(?i)(insert\\s+into|update|delete\\s+from|merge\\s+into)\\s+(only\\s+)?(public\\.)?"?(${tabelas})\\M`,
  })).filter((x) => x.is_secdef);
  const nomes = new Set(escritoras.map((x) => x.proname));
  // controle positivo da busca
  for (const fn of ['update_board_item', 'create_card_comment', 'move_item_to_board']) assert.ok(nomes.has(fn), `a busca não achou ${fn}`);

  const exec = new Map((await rpc('_audit_secdef_initiative_reader_gates')).map((x) => [`${x.proname}|${x.identity_args}`, x.exec_authenticated]));
  const comPortao = new Set((await rpc('_audit_functions_matching', { p_pattern: 'rls_can_see_(item|board|initiative)\\s*\\(' })).map((x) => x.proname));
  const viaPredicado = new Set();
  for (const p of PREDICADOS) for (const x of await rpc('_audit_functions_matching', { p_pattern: `\\m${p}\\s*\\(` })) viaPredicado.add(x.proname);

  const acusadas = [...new Set(escritoras
    .filter((x) => exec.get(`${x.proname}|${x.identity_args}`))
    .filter((x) => !comPortao.has(x.proname) && !viaPredicado.has(x.proname))
    .map((x) => x.proname))].sort();
  const fora = acusadas.filter((n) => !(n in EXCECOES));
  assert.deepEqual(fora, [], `escrevem em card sem o portão (ponha rls_can_see_* antes da escrita, ou justifique em EXCECOES): ${fora.join(', ')}`);
  const podres = Object.keys(EXCECOES).filter((n) => !acusadas.includes(n));
  assert.deepEqual(podres, [], `EXCECOES que deixaram de ser acusadas (tire da lista): ${podres.join(', ')}`);
});

test('R. o predicado do checklist carrega o portão no corpo vivo', { skip }, async () => {
  const [linha] = await rpc('_audit_function_source', { p_proname: 'can_manage_card_checklist' });
  assert.ok(linha, 'can_manage_card_checklist não existe no banco');
  assert.match(maskLineComments(linha.prosrc), /p_card_id IS NOT NULL\s+AND public\.rls_can_see_item\(p_card_id\)\s+AND \(/,
    'o portão do predicado tem de estar na conjunção, antes dos ramos de autoridade');
});
