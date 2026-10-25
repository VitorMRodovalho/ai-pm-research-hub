/**
 * #2782: pedido de capítulo ou de organização pelo formulário da home vai para o CRM de parceiros.
 *
 * Medido em 24/10/2026: as portas "Para capítulos" e "Para organizações" mandavam o pedido para visitor_leads e
 * paravam ali, sem aviso nem tela, com a home prometendo resposta em até 5 dias úteis; e a promoção automática
 * não olhava o papel, então o pedido podia virar candidatura de pesquisador.
 *
 * Decisões do GP: o contato de quem pediu fica SÓ no histórico (partner_interactions.details, que só
 * get_partner_interactions lê, com manage_platform); o aviso vai a manage_platform; a retenção é a do lead, e só
 * alcança o que o formulário criou (marcador em admin_audit_log que só capture_visitor_lead grava).
 *
 * Os corpos SQL são lidos pela captura MAIS NOVA (#1932), com comentário mascarado. Cada asserção amarra a
 * condição ao resultado dentro do bloco que decide; a mutação de cada uma está no registro da PR.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { parseMigration } from '../helpers/rpc-body-drift-parser.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const fn = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);
const MARKER = 'visitor_lead.routed_to_partner_crm';
const migName = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('_2782_lead_capitulo_organizacao_crm.sql'));
const MIG = migName.length ? maskLineComments(read(`supabase/migrations/${migName[0]}`)) : '';

/** Divide uma lista SQL pelas vírgulas de nível zero (fora de parênteses e de literal). */
function splitTop(s) {
  const out = [];
  let depth = 0, inStr = false, cur = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      cur += c;
      if (c === "'" && s[i + 1] === "'") { cur += s[++i]; continue; }
      if (c === "'") inStr = false;
      continue;
    }
    if (c === "'") { inStr = true; cur += c; continue; }
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur.trim()); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

/** Texto entre o parêntese que abre em `openAt` e o que o fecha. */
function inside(s, openAt) {
  assert.equal(s[openAt], '(', 'esperava um parêntese de abertura');
  let depth = 0, inStr = false;
  for (let i = openAt; i < s.length; i++) {
    const c = s[i];
    if (inStr) { if (c === "'" && s[i + 1] === "'") { i++; continue; } if (c === "'") inStr = false; continue; }
    if (c === "'") { inStr = true; continue; }
    if (c === '(') depth++;
    if (c === ')') { depth--; if (depth === 0) return s.slice(openAt + 1, i); }
  }
  throw new Error('parêntese sem par');
}

/** Coluna -> expressão de cada INSERT INTO public.<tabela> (colunas) VALUES (valores). */
function insertMap(body, table) {
  return [...body.matchAll(new RegExp(`INSERT INTO public\\.${table} \\(`, 'g'))].map((h) => {
    const colsOpen = h.index + h[0].length - 1;
    const cols = splitTop(inside(body, colsOpen));
    const vals = splitTop(inside(body, body.indexOf('VALUES (', colsOpen) + 'VALUES '.length));
    assert.equal(cols.length, vals.length, `INSERT em ${table}: ${cols.length} colunas e ${vals.length} valores`);
    return { at: h.index, map: Object.fromEntries(cols.map((c, i) => [c, vals[i]])) };
  });
}

/** Valor atribuído a uma variável plpgsql (`v := ...;`). */
function assigned(body, v) {
  const m = body.match(new RegExp(`\\b${v} := ([\\s\\S]*?);`));
  assert.ok(m, `${v} não é atribuída`);
  return m[1];
}

const PII_VARS = /\b(v_name|v_email|v_message|v_phone|v_details|p_payload)\b/;

// ── as portas e os valores que elas mandam ───────────────────────────────────────────────────────────

test('#2782 A: as portas mandam exatamente os papéis que a RPC roteia ao CRM', () => {
  const join = maskJsComments(read('src/components/sections/JoinSection.astro'));
  const chapterDoor = join.match(/data-door="chapter">([\s\S]*?)<\/article>/);
  const partnerDoor = join.match(/data-door="partner">([\s\S]*?)<\/article>/);
  assert.ok(chapterDoor && partnerDoor, 'as portas de capítulo e de organização sumiram da home');
  assert.match(chapterDoor[1], /<ApplyInterest client:visible roleInterest="chapter" source="home-join"/);
  assert.match(partnerDoor[1], /<ApplyInterest client:visible roleInterest="partner" source="home-join"/);
  const payload = maskJsComments(read('src/lib/interestPayload.ts'));
  assert.match(payload, /export type InterestRole = 'researcher' \| 'leader' \| 'chapter' \| 'partner';/);
  assert.match(payload, /role_interest: opts\.roleInterest,/);

  const f = fn('capture_visitor_lead');
  assert.match(f, /v_role := NULLIF\(TRIM\(p_payload->>'role_interest'\), ''\);/);
  const route = f.match(/v_partner_route := COALESCE\(v_role IN \(([^)]*)\), false\);/);
  assert.ok(route, 'a decisão de rota ao CRM sumiu');
  assert.deepEqual(splitTop(route[1]).sort(), ["'chapter'", "'partner'"]);
});

// ── a captura ────────────────────────────────────────────────────────────────────────────────────────

test('#2782 B1: o lead de parceria nasce e passa a ficar fora da promoção automática', () => {
  const f = fn('capture_visitor_lead');
  const ins = insertMap(f, 'visitor_leads');
  assert.equal(ins.length, 1, 'esperava um INSERT em visitor_leads');
  assert.equal(ins[0].map.auto_promote_eligible, 'NOT v_partner_route');
  const upd = f.match(/UPDATE public\.visitor_leads SET([\s\S]*?)WHERE id = v_existing_id;/);
  assert.ok(upd, 'o caminho do lead existente sumiu');
  assert.match(upd[1], /auto_promote_eligible = CASE WHEN v_partner_route THEN false ELSE auto_promote_eligible END/);
});

test('#2782 B2: a entidade nasce prospect, com o tipo da porta e SEM contato nem nome de pessoa', () => {
  const f = fn('capture_visitor_lead');
  const ents = insertMap(f, 'partner_entities');
  assert.equal(ents.length, 1, 'esperava um único INSERT em partner_entities');
  const m = ents[0].map;
  assert.equal(m.status, "'prospect'");
  assert.equal(m.entity_type, "CASE v_role WHEN 'chapter' THEN 'pmi_chapter' ELSE 'outro' END");
  // partner_entities é lida por todo membro ativo (partners_read_members): o contato não entra nela
  assert.ok(!('contact_name' in m) && !('contact_email' in m), 'a entidade voltou a guardar o contato de quem pediu');
  for (const [col, val] of Object.entries(m)) assert.doesNotMatch(val, PII_VARS, `partner_entities.${col} leva dado de quem pediu`);
  assert.match(m.notes, /v_lead_id::text/);
  // e nada na captura volta a casar entidade por contato (o que juntava a mensagem a uma entidade alheia)
  assert.doesNotMatch(f, /contact_(email|name)/);
});

test('#2782 B3: a entidade do mesmo lead é reaproveitada pelo vínculo de auditoria, não por e-mail', () => {
  const f = fn('capture_visitor_lead');
  const look = f.match(/SELECT pe\.id INTO v_partner_id([\s\S]*?)LIMIT 1;/);
  assert.ok(look, 'a busca da entidade do lead sumiu');
  assert.match(look[1], /FROM public\.admin_audit_log a\s+JOIN public\.partner_entities pe ON pe\.id::text = a\.changes->>'partner_entity_id'/);
  assert.match(look[1], new RegExp(`WHERE a\\.action = '${MARKER.replace('.', '\\.')}'\\s+AND a\\.target_type = 'visitor_lead' AND a\\.target_id = v_lead_id`));
  const branch = f.match(/IF v_partner_id IS NULL THEN([\s\S]*?)END IF;/);
  assert.ok(branch, 'a criação não está condicionada a não haver entidade do lead');
  const at = insertMap(f, 'partner_entities')[0].at;
  assert.ok(branch.index < at && at < branch.index + branch[0].length, 'o INSERT em partner_entities está fora do ramo');
  assert.ok(look.index < branch.index, 'a busca tem de vir antes do ramo');
});

test('#2782 B4: o contato e a mensagem vão SÓ para details da nota; summary não leva dado de quem pediu', () => {
  const f = fn('capture_visitor_lead');
  const det = assigned(f, 'v_details');
  for (const v of ['v_name', 'v_email', 'v_phone', 'v_message']) assert.match(det, new RegExp(`\\b${v}\\b`), `details sem ${v}`);
  // get_audit_log e export_audit_log_csv expõem summary: nele não pode haver dado de quem pediu
  assert.doesNotMatch(assigned(f, 'v_summary'), PII_VARS);
  const ix = insertMap(f, 'partner_interactions');
  assert.equal(ix.length, 1);
  assert.equal(ix[0].map.interaction_type, "'note'");
  assert.equal(ix[0].map.summary, 'v_summary');
  assert.equal(ix[0].map.details, 'v_details');
  assert.equal(ix[0].map.actor_member_id, 'NULL');
  const gate = f.match(/IF v_partner_created OR NOT EXISTS \(([\s\S]*?)\) THEN([\s\S]*?)END IF;/);
  assert.ok(gate, 'a nota não está condicionada');
  assert.ok(gate.index < ix[0].at && ix[0].at < gate.index + gate[0].length, 'a nota está fora do portão de repetição');
  assert.match(gate[1], /pi\.summary = v_summary/);
  assert.match(gate[1], /pi\.details IS NOT DISTINCT FROM v_details/);
  assert.match(gate[2], /RETURNING id INTO v_interaction_id;/);
});

test('#2782 B5: avisa quem tem manage_platform, sem dado de quem pediu, e só quando entrou nota nova', () => {
  const f = fn('capture_visitor_lead');
  const block = f.match(/IF v_interaction_id IS NOT NULL THEN([\s\S]*?)END LOOP;/);
  assert.ok(block, 'o aviso não está condicionado a uma nota nova');
  const loop = block[1].match(/FOR v_recipient IN([\s\S]*?)LOOP/);
  assert.ok(loop, 'o laço de destinatários sumiu');
  assert.match(loop[1], /m\.member_status = 'active' AND m\.auth_id IS NOT NULL/);
  assert.match(loop[1], /AND public\.can_by_member\(m\.id, 'manage_platform'\)/);
  assert.doesNotMatch(loop[1], /manage_partner/);
  assert.match(loop[1], /AND NOT EXISTS \([\s\S]*?n\.type = 'partner_lead_received'[\s\S]*?n\.source_id = v_partner_id AND n\.is_read IS NOT TRUE\)/);
  const call = block[1].indexOf('PERFORM public.create_notification(');
  assert.ok(call > 0, 'o aviso não usa create_notification');
  const args = splitTop(inside(block[1], call + 'PERFORM public.create_notification'.length));
  assert.equal(args.length, 7, 'create_notification(recipient, type, title, body, link, source_type, source_id)');
  assert.equal(args[0], 'v_recipient.id');
  assert.equal(args[1], "'partner_lead_received'");
  assert.doesNotMatch(args[2], PII_VARS, 'o título leva dado de quem pediu');
  assert.doesNotMatch(args[3], PII_VARS, 'o corpo leva dado de quem pediu (e vai por e-mail)');
  assert.equal(args[4], "'/admin/partnerships'");
  assert.equal(args[6], 'v_partner_id');
});

test('#2782 B6: o vínculo lead -> entidade -> nota fica em admin_audit_log, sem dado de quem pediu', () => {
  const f = fn('capture_visitor_lead');
  const after = f.slice(f.indexOf('IF v_interaction_id IS NOT NULL THEN'));
  const aud = insertMap(after, 'admin_audit_log');
  assert.equal(aud.length, 1, 'esperava um INSERT em admin_audit_log dentro do ramo da nota nova');
  assert.equal(aud[0].map.action, `'${MARKER}'`);
  assert.equal(aud[0].map.target_type, "'visitor_lead'");
  assert.equal(aud[0].map.target_id, 'v_lead_id');
  const changes = aud[0].map.changes;
  for (const [k, v] of [['partner_entity_id', 'v_partner_id'], ['partner_created', 'v_partner_created'], ['partner_interaction_id', 'v_interaction_id']]) {
    assert.match(changes, new RegExp(`'${k}', ${v}\\b`), `changes sem ${k}`);
  }
  assert.doesNotMatch(changes, PII_VARS, 'o registro de auditoria é append-only e não pode levar dado de quem pediu');
});

test('#2782 B7: a resposta ao anônimo tem uma forma só, e a rota ao CRM não devolve nada antes dela', () => {
  const f = fn('capture_visitor_lead');
  const ok = [...f.matchAll(/RETURN jsonb_build_object\('success'[^;]*;/g)].map((m) => m[0]);
  assert.deepEqual(ok, ["RETURN jsonb_build_object('success', true, 'lead_id', v_lead_id);"]);
  const route = f.slice(f.indexOf('IF v_partner_route THEN'), f.lastIndexOf('RETURN jsonb_build_object'));
  assert.doesNotMatch(route, /\bRETURN\b/, 'um RETURN dentro da rota faria a resposta variar');
  assert.match(f, /^\s*DECLARE[\s\S]*?BEGIN\s+IF NOT public\.rl_check_and_bump\('capture_visitor_lead', 10, 60\) THEN/);
});

// ── a promoção automática ───────────────────────────────────────────────────────────────────────────

test('#2782 C: a promoção automática pula capítulo e organização mesmo com a flag true', () => {
  const f = fn('auto_promote_eligible_leads_for_cycle');
  const sel = f.match(/FOR v_lead IN\s+SELECT vl\.\*\s+FROM public\.visitor_leads vl\s+WHERE([\s\S]*?)ORDER BY vl\.created_at ASC\s+LOOP/);
  assert.ok(sel, 'a seleção da promoção mudou de forma');
  assert.match(sel[1], /vl\.auto_promote_eligible = true/);
  const skip = sel[1].match(/AND COALESCE\(vl\.role_interest, ''\) NOT IN \(([^)]*)\)/);
  assert.ok(skip, 'a promoção voltou a ignorar o papel');
  assert.deepEqual(splitTop(skip[1]).sort(), ["'chapter'", "'partner'"]);
});

// ── o catálogo de entrega ───────────────────────────────────────────────────────────────────────────

test('#2782 D: o aviso é catalogado como imediato no SQL e no ADR-0022', () => {
  assert.match(fn('_delivery_mode_for'), /WHEN 'partner_lead_received'\s+THEN 'transactional_immediate'/,
    'sem esta linha o aviso cai no ELSE (digest_weekly) e chega no sábado');
  const cat = JSON.parse(read('docs/adr/ADR-0022-notification-types-catalog.json'));
  assert.equal(cat.types?.partner_lead_received?.delivery_mode, 'transactional_immediate');
});

// ── prospect nunca chega a superfície pública ───────────────────────────────────────────────────────

/** Cada leitura de partner_entities: do FROM até o fim do subselect (parêntese que fecha) ou do comando. */
function partnerReads(body) {
  const out = [];
  for (const m of body.matchAll(/\bFROM\s+(?:public\.)?partner_entities\b/g)) {
    let depth = 0, inStr = false, end = body.length;
    for (let i = m.index; i < body.length; i++) {
      const c = body[i];
      if (inStr) { if (c === "'") inStr = false; continue; }
      if (c === "'") { inStr = true; continue; }
      if (c === '(') depth++;
      if (c === ')') { if (depth === 0) { end = i; break; } depth--; }
      if (c === ';' && depth === 0) { end = i; break; }
    }
    out.push(body.slice(m.index, end));
  }
  return out;
}

const PUBLIC_READERS = { get_public_impact_data: 2, get_chapter_metrics: 3, exec_portfolio_health: 1 };

test('#2782 E: toda leitura anônima de partner_entities filtra status sem admitir prospect', () => {
  for (const [name, floor] of Object.entries(PUBLIC_READERS)) {
    const reads = partnerReads(fn(name));
    assert.ok(reads.length >= floor, `${name}: esperava ao menos ${floor} leitura(s) de partner_entities, achei ${reads.length}`);
    for (const r of reads) {
      assert.doesNotMatch(r, /\bstatus\s*(?:<>|!=|NOT\s+IN)/i, `${name}: filtro negativo de status admite prospect`);
      const lits = [];
      for (const s of r.matchAll(/\b(?:\w+\.)?status\s*(?:=\s*('[^']*')|IN\s*\(([^)]*)\))/g)) {
        lits.push(...(s[1] ? [s[1]] : splitTop(s[2])));
      }
      assert.ok(lits.length > 0, `${name}: leitura de partner_entities sem filtro de status: ${r.slice(0, 120)}`);
      for (const l of lits) {
        assert.ok(["'active'", "'negotiation'"].includes(l), `${name}: status ${l} chega a superfície pública`);
      }
    }
  }
});

// ── a tela do CRM recebe dado do formulário público ─────────────────────────────────────────────────

test('#2782 F: a tela de parcerias escapa o que interpola e mostra a nota', () => {
  const page = maskJsComments(read('src/pages/admin/partnerships.astro'));
  assert.match(page, /import \{ escapeHtml as E \} from '\.\.\/\.\.\/lib\/escape-html';/);
  const grid = page.match(/grid\.innerHTML = filtered\.map\(\(p: any\) => \{([\s\S]*?)\}\)\.join\(''\);/);
  const timeline = page.match(/timeline\.innerHTML = interactions\.map\(\(ix: any\) => \{([\s\S]*?)\}\)\.join\(''\);/);
  assert.ok(grid && timeline, 'os dois templates da tela mudaram de forma');
  const FIELDS = /\b(p|ix)\.(id|name|description|contact_name|contact_email|summary|details|outcome|next_action|actor_name)\b/g;
  let seen = 0;
  for (const tpl of [grid[1], timeline[1]]) {
    for (const m of tpl.matchAll(FIELDS)) {
      seen++;
      const before = tpl.slice(Math.max(0, m.index - 2), m.index);
      const after = tpl.slice(m.index + m[0].length);
      const wrapped = before === 'E(' && after.startsWith(')');
      const condition = /^\s*\?/.test(after);
      assert.ok(wrapped || condition, `${m[0]} vai ao innerHTML sem escapeHtml`);
    }
  }
  assert.ok(seen >= 12, `o varredor viu só ${seen} interpolação(ões); esperava ao menos 12`);
  assert.match(timeline[1], /\$\{ix\.details \? `<p[^`]*>\$\{E\(ix\.details\)\}<\/p>` : ''\}/);

  const island = maskJsComments(read('src/components/islands/PartnerPipelineIsland.tsx'));
  assert.match(island, /\{ix\.details && <p className="[^"]*">\{ix\.details\}<\/p>\}/);
  assert.doesNotMatch(island, /dangerouslySetInnerHTML/);
});

// ── retenção: a do lead, e só sobre o que o formulário criou ────────────────────────────────────────

/** Bloco de um ramo da varredura: do ELSIF da política até o v_handled que o fecha. */
function sweepBranch(type, table) {
  const s = fn('_data_retention_sweep');
  const head = `ELSIF v_policy.cleanup_type = '${type}' AND v_policy.table_name = '${table}' THEN`;
  const at = s.indexOf(head);
  assert.ok(at > 0, `a varredura não tem ramo para ${table}/${type}`);
  return s.slice(at, s.indexOf('v_handled := true;', at));
}

const ENTITY_MARKER = new RegExp(
  `EXISTS \\(SELECT 1 FROM public\\.admin_audit_log a\\s+WHERE a\\.action = '${MARKER.replace('.', '\\.')}'\\s+` +
  `AND a\\.changes->>'partner_created' = 'true'\\s+AND a\\.changes->>'partner_entity_id' = pe\\.id::text\\)`);
const NOTE_MARKER = (alias) => new RegExp(
  `EXISTS \\(SELECT 1 FROM public\\.admin_audit_log a\\s+WHERE a\\.action = '${MARKER.replace('.', '\\.')}'\\s+` +
  `AND a\\.changes->>'partner_interaction_id' = ${alias}\\.id::text\\)`);

/** O conjunto é calculado uma vez; a contagem seca e a corrida real só usam v_ids. */
function oneSet(branch) {
  const sel = branch.match(/SELECT COALESCE\(array_agg\((pi|pe)\.id\), '\{\}'\) INTO v_ids([\s\S]*?);\s+IF p_dry_run THEN\s+v_affected := cardinality\(v_ids\);\s+ELSE([\s\S]*?)END IF;/);
  assert.ok(sel, 'o ramo não calcula o conjunto uma vez antes de contar ou agir');
  assert.doesNotMatch(sel[3], /(?<!DELETE )\bFROM public\.partner_|\bWHERE (?!id = ANY \(v_ids\))/, 'a corrida real usa outro predicado que a contagem seca');
  return { where: sel[2], act: sel[3] };
}

const CANDIDATE = [
  /pe\.status = 'prospect'/,
  /COALESCE\(pe\.updated_at, pe\.created_at\) < v_cutoff/,
  /NOT EXISTS \(SELECT 1 FROM public\.partner_interactions i\s+WHERE i\.partner_id = pe\.id AND i\.created_at >= v_cutoff\)/,
];

test('#2782 G1: a nota do formulário perde o dado de quem pediu no prazo, só em entidade criada pelo formulário', () => {
  const { where, act } = oneSet(sweepBranch('anonymize', 'partner_interactions'));
  assert.match(where, ENTITY_MARKER, 'sem o marcador de origem a anonimização alcança entidade criada à mão');
  assert.match(where, NOTE_MARKER('pi'), 'sem o marcador da nota a anonimização alcança interação de outro caminho');
  assert.match(where, /pi\.details IS NOT NULL/);
  for (const c of CANDIDATE) assert.match(where, c);
  assert.match(act, /UPDATE public\.partner_interactions\s+SET details = NULL,/);
  assert.match(act, /WHERE id = ANY \(v_ids\);\s+GET DIAGNOSTICS v_affected = ROW_COUNT;/);
  assert.doesNotMatch(act, /DELETE/);
});

test('#2782 G2: só a entidade do formulário que virou casca é apagada, e nada que outra tabela aponte', () => {
  const { where, act } = oneSet(sweepBranch('delete', 'partner_entities'));
  assert.match(where, ENTITY_MARKER, 'sem o marcador de origem o apagamento alcança entidade criada à mão');
  for (const c of CANDIDATE) assert.match(where, c);
  // casca: toda interação dela é nota do formulário JÁ anonimizada
  assert.match(where, new RegExp(`NOT EXISTS \\(SELECT 1 FROM public\\.partner_interactions i\\s+WHERE i\\.partner_id = pe\\.id\\s+` +
    `AND \\(i\\.details IS NOT NULL\\s+OR NOT ${NOTE_MARKER('i').source}\\)\\)`));
  // toda tabela com chave para partner_entities (medido em 24/10/2026), além de partner_interactions
  for (const [t, c] of [['partner_attachments', 'partner_entity_id'], ['partner_cards', 'partner_entity_id'],
    ['board_items', 'source_partner_id'], ['initiatives', 'origin_partner_entity_id'], ['governance_documents', 'partner_entity_id']]) {
    assert.match(where, new RegExp(`NOT EXISTS \\(SELECT 1 FROM public\\.${t} x WHERE x\\.${c} = pe\\.id\\)`), `casca com vínculo em ${t}`);
  }
  assert.match(act, /DELETE FROM public\.partner_entities WHERE id = ANY \(v_ids\);\s+GET DIAGNOSTICS v_affected = ROW_COUNT;/);
});

test('#2782 G3: o marcador de origem só é gravado pela captura do formulário', () => {
  // toda captura vigente de função, de todas as migrations
  const dir = resolve(ROOT, 'supabase/migrations');
  const latest = new Map();
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
    for (const b of parseMigration(f, read(`supabase/migrations/${f}`))) latest.set(`${b.name}@${b.args}`, b);
  }
  assert.ok(latest.size > 500, `o varredor viu só ${latest.size} funções`);
  const writers = [], readers = [];
  for (const [key, b] of latest) {
    const body = maskLineComments(b.body);
    if (!body.includes(`'${MARKER}'`)) continue;
    readers.push(b.name);
    for (const ins of insertMap(body, 'admin_audit_log')) {
      if (Object.values(ins.map).includes(`'${MARKER}'`)) writers.push(key.split('@')[0]);
    }
  }
  assert.deepEqual(writers, ['capture_visitor_lead'], 'outro caminho grava o marcador que a retenção usa');
  assert.deepEqual([...new Set(readers)].sort(), ['_data_retention_sweep', 'capture_visitor_lead']);
});

test('#2782 G4: as duas políticas entram com o prazo do lead e o executor da varredura', () => {
  const ins = MIG.match(/INSERT INTO public\.data_retention_policy \(table_name, retention_days, cleanup_type, description, is_active, executor\)([\s\S]*?);/);
  assert.ok(ins, 'a migration não declara as políticas');
  assert.match(ins[1], /SELECT v\.t, lead\.retention_days, v\.c, v\.d, true, 'data-retention-sweep-daily'/);
  assert.match(ins[1], /\('partner_interactions', 'anonymize',/);
  assert.match(ins[1], /\('partner_entities', 'delete',/);
  assert.match(ins[1], /WHERE r\.table_name = 'visitor_leads' AND r\.cleanup_type = 'delete' AND r\.is_active\) AS lead/);
  assert.match(ins[1], /WHERE NOT EXISTS \(SELECT 1 FROM public\.data_retention_policy p WHERE p\.table_name = v\.t AND p\.cleanup_type = v\.c\)/);
});

// ── vivo ────────────────────────────────────────────────────────────────────────────────────────────

const dbGated = Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = () => createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });

test(dbGated ? '#2782 vivo: o aviso sai na hora, não no digest semanal' : `SKIP: ${skipMsg}`, { skip: !dbGated }, async () => {
  const { data, error } = await sb().rpc('_delivery_mode_for', { p_type: 'partner_lead_received' });
  assert.equal(error, null, `_delivery_mode_for indisponível: ${error?.message ?? ''}`);
  assert.equal(data, 'transactional_immediate');
  // controle: o ELSE continua digest_weekly, então o teste sabe dizer não
  const { data: outro } = await sb().rpc('_delivery_mode_for', { p_type: 'tipo_que_nao_existe_2782' });
  assert.equal(outro, 'digest_weekly');
});

test(dbGated ? '#2782 vivo: a varredura seca executa as duas políticas novas' : `SKIP: ${skipMsg}`, { skip: !dbGated }, async () => {
  const { data, error } = await sb().rpc('_data_retention_sweep', { p_dry_run: true });
  assert.ifError(error);
  assert.equal(data.dry_run, true);
  const pol = Object.fromEntries(data.policies.map((p) => [`${p.table}/${p.type}`, p]));
  for (const p of ['partner_interactions/anonymize', 'partner_entities/delete']) {
    assert.equal(pol[p]?.handled, true, `${p} não foi executada pela varredura`);
    assert.equal(typeof pol[p].affected, 'number', p);
    assert.equal(pol[p].days, pol['visitor_leads/delete'].days, `${p} não tem o prazo do lead`);
  }
});
