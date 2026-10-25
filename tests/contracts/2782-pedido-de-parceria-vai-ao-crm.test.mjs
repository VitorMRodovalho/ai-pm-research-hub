/**
 * #2782: pedido de capítulo ou de organização pelo formulário da home vai para o CRM de parceiros.
 *
 * Medido em 24/10/2026: as portas "Para capítulos" e "Para organizações" mandavam o pedido para visitor_leads e
 * paravam ali, sem aviso nem tela, com a home prometendo resposta em até 5 dias úteis; e a promoção automática
 * não olhava o papel, então o pedido podia virar candidatura de pesquisador.
 *
 * Os corpos SQL são lidos pela captura MAIS NOVA (#1932), com comentário mascarado. Cada asserção amarra a
 * condição ao resultado dentro do bloco que decide; a mutação de cada uma está no registro da PR.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const fn = (name) => maskLineComments(latestFunctionCapture(ROOT, name).body);

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

/** Coluna -> expressão de um INSERT INTO <tabela> (colunas) VALUES (valores). */
function insertMap(body, table) {
  const re = new RegExp(`INSERT INTO public\\.${table} \\(`, 'g');
  const hits = [...body.matchAll(re)];
  return hits.map((h) => {
    const colsOpen = h.index + h[0].length - 1;
    const cols = splitTop(inside(body, colsOpen));
    const v = body.indexOf('VALUES (', colsOpen);
    const vals = splitTop(inside(body, v + 'VALUES '.length));
    assert.equal(cols.length, vals.length, `INSERT em ${table}: ${cols.length} colunas e ${vals.length} valores`);
    return { at: h.index, map: Object.fromEntries(cols.map((c, i) => [c, vals[i]])) };
  });
}

const PII_VARS = /\b(v_name|v_email|v_message|p_payload)\b|phone/;

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

test('#2782 B2: uma entidade prospect por e-mail de contato, com o tipo da porta e nome sem dado da pessoa', () => {
  const f = fn('capture_visitor_lead');
  const route = f.slice(f.indexOf('IF v_partner_route THEN'));
  assert.ok(f.includes('IF v_partner_route THEN'), 'o bloco de rota ao CRM sumiu');
  assert.match(route, /SELECT pe\.id INTO v_partner_id\s+FROM public\.partner_entities pe\s+WHERE LOWER\(TRIM\(pe\.contact_email\)\) = v_email/);

  const ents = insertMap(f, 'partner_entities');
  assert.equal(ents.length, 1, 'esperava um único INSERT em partner_entities');
  const branch = f.match(/IF v_partner_id IS NULL THEN([\s\S]*?)END IF;/);
  assert.ok(branch, 'a criação não está condicionada a não haver entidade');
  assert.ok(branch.index < ents[0].at && ents[0].at < branch.index + branch[0].length,
    'o INSERT em partner_entities está fora do ramo "não existe entidade com este e-mail"');
  assert.ok(f.indexOf('SELECT pe.id INTO v_partner_id') < branch.index, 'a busca por e-mail tem de vir antes do ramo');

  const m = ents[0].map;
  assert.equal(m.status, "'prospect'");
  assert.equal(m.entity_type, "CASE v_role WHEN 'chapter' THEN 'pmi_chapter' ELSE 'outro' END");
  assert.equal(m.contact_name, 'v_name');
  assert.equal(m.contact_email, 'v_email');
  // capítulo ativo tem o nome publicado (get_public_impact_data.chapters_summary): o nome não leva dado da pessoa
  assert.doesNotMatch(m.name, PII_VARS);
  assert.match(m.notes, /v_lead_id::text/);
  assert.doesNotMatch(m.notes, PII_VARS);
});

test('#2782 B3: a mensagem vira uma nota no CRM, sem duplicar no envio repetido', () => {
  const f = fn('capture_visitor_lead');
  const ix = insertMap(f, 'partner_interactions');
  assert.equal(ix.length, 1);
  assert.equal(ix[0].map.interaction_type, "'note'");
  assert.equal(ix[0].map.details, 'v_message');
  assert.equal(ix[0].map.partner_id, 'v_partner_id');
  const gate = f.match(/IF v_partner_created OR NOT EXISTS \(([\s\S]*?)\) THEN([\s\S]*?)END IF;/);
  assert.ok(gate, 'a nota não está condicionada');
  assert.ok(gate.index < ix[0].at && ix[0].at < gate.index + gate[0].length, 'a nota está fora do portão de repetição');
  assert.match(gate[1], /pi\.summary = v_summary/);
  assert.match(gate[1], /pi\.details IS NOT DISTINCT FROM v_message/);
  assert.match(gate[2], /v_logged := true;/);
});

test('#2782 B4: avisa quem tem manage_partner, sem dado de quem pediu, e só quando algo novo chegou', () => {
  const f = fn('capture_visitor_lead');
  const block = f.match(/IF v_logged THEN([\s\S]*?)END LOOP;/);
  assert.ok(block, 'o aviso não está condicionado a uma nota nova');
  const loop = block[1].match(/FOR v_recipient IN([\s\S]*?)LOOP/);
  assert.ok(loop, 'o laço de destinatários sumiu');
  assert.match(loop[1], /m\.member_status = 'active' AND m\.auth_id IS NOT NULL/);
  assert.match(loop[1], /AND public\.can_by_member\(m\.id, 'manage_partner'\)/);
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

test('#2782 B5: a resposta ao anônimo tem uma forma só, e a rota ao CRM não devolve nada antes dela', () => {
  const f = fn('capture_visitor_lead');
  const ok = [...f.matchAll(/RETURN jsonb_build_object\('success'[^;]*;/g)].map((m) => m[0]);
  assert.deepEqual(ok, ["RETURN jsonb_build_object('success', true, 'lead_id', v_lead_id);"]);
  const route = f.slice(f.indexOf('IF v_partner_route THEN'), f.lastIndexOf('RETURN jsonb_build_object'));
  assert.doesNotMatch(route, /\bRETURN\b/, 'um RETURN dentro da rota faria a resposta dizer se o e-mail é de parceiro');
  // a trava por IP continua sendo a primeira coisa que a função faz
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

test('#2782 F: a tela de parcerias escapa o que interpola e mostra a mensagem', () => {
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
