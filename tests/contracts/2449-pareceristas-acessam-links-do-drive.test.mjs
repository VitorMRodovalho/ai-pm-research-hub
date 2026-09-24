// tests/contracts/2449-pareceristas-acessam-links-do-drive.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * O parecerista recebe acesso ao artefato que esta no card, e e avisado quando o acesso falha.
 *
 * O CASO (#2449): a concessao de acesso da curadoria lia so board_item_files, que so o MCP grava; os
 * artefatos reais ficam em board_items.attachments (21 links do Google Drive/Docs medidos em
 * 24/09/2026). Resultado: 0 linhas em drive_curation_grants na historia.
 *
 * Exercido em transacao desfeita (24/09/2026), com um card real de 2 links do Drive levado a
 * curation_pending: 2 designados, 4 concessoes reviewer_assignment + 2 committee_handoff (o
 * terceiro curador), 2 arquivos, ids batendo com os links; falha de concessao a designado = 1 aviso,
 * falha de concessao ao comite = nenhum aviso a mais.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

function sql(body) {
  return body.split('\n').map((l) => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; })
    .join('\n').replace(/\s+/g, ' ');
}

/** O helper le as DUAS fontes e extrai o id do Drive do link. */
export function duasFontes(body) {
  const c = sql(body);
  return {
    leArquivosDoCard: /FROM public\.board_item_files f WHERE f\.board_item_id = p_item_id AND f\.deleted_at IS NULL/.test(c),
    leLinksDoCard: /jsonb_array_elements\(coalesce\(bi\.attachments, '\[\]'::jsonb\)\) a WHERE bi\.id = p_item_id AND a->>'url' ~\* '\^https:\/\/\(drive\|docs\)\\\.google\\\.com\/'/.test(c),
    extraiId: /substring\(a->>'url' FROM '\/d\/\(\[A-Za-z0-9_-\]\{19,\}\)'\)/.test(c) && /substring\(a->>'url' FROM '\/folders\/\(\[A-Za-z0-9_-\]\{19,\}\)'\)/.test(c),
  };
}

/** A funcao de enfileirar le do helper (e nao so de board_item_files). */
export function enfileiraDoHelper(body) {
  const c = sql(body);
  return /FROM public\._card_drive_files\(p_item_id\) f/.test(c) && !/FROM public\.board_item_files f/.test(c);
}

/** O aviso: so na transicao pending_grant -> failed, e so para designado (nao comite). */
export function avisoDeFalha(body) {
  const c = sql(body);
  return /IF NEW\.status = 'failed' AND OLD\.status = 'pending_grant' AND NEW\.grant_reason IN \('reviewer_assignment', 'manual'\) THEN/.test(c)
    && /create_notification\( NEW\.grantee_member_id,/.test(c);
}

async function corpo(proname) {
  const { data, error } = await sb().rpc('_audit_function_source', { p_proname: proname });
  assert.equal(error, null, `_audit_function_source(${proname}) falhou: ${error?.message ?? ''}`);
  assert.ok(Array.isArray(data) && data.length === 1, `${proname}: esperava 1 sobrecarga, veio ${data?.length}`);
  return data[0].prosrc;
}

test(dbGated ? '#2449: a concessao da curadoria le os links do Drive do card e avisa a falha' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const h = duasFontes(await corpo('_card_drive_files'));
    assert.deepEqual(h, { leArquivosDoCard: true, leLinksDoCard: true, extraiId: true });
    assert.ok(enfileiraDoHelper(await corpo('enqueue_curation_drive_grants')), 'o comite voltou a ler so board_item_files');
    assert.ok(enfileiraDoHelper(await corpo('enqueue_curation_drive_grant_for_member')), 'o designado voltou a ler so board_item_files');
    assert.ok(avisoDeFalha(await corpo('trg_notify_curation_grant_failed')), 'o aviso de falha de acesso mudou de regra');
  });

test('#2449 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  const H = `SELECT f.drive_file_id::text FROM public.board_item_files f WHERE f.board_item_id = p_item_id AND f.deleted_at IS NULL
    UNION ALL SELECT coalesce(substring(a->>'url' FROM '/d/([A-Za-z0-9_-]{19,})'), substring(a->>'url' FROM '/folders/([A-Za-z0-9_-]{19,})')), a->>'url'
    FROM public.board_items bi, jsonb_array_elements(coalesce(bi.attachments, '[]'::jsonb)) a
    WHERE bi.id = p_item_id AND a->>'url' ~* '^https://(drive|docs)\\.google\\.com/'`;
  assert.deepEqual(duasFontes(H), { leArquivosDoCard: true, leLinksDoCard: true, extraiId: true });
  // 1: some a fonte dos links (o defeito original)
  assert.equal(duasFontes(m(H, "jsonb_array_elements(coalesce(bi.attachments, '[]'::jsonb)) a", 'x a')).leLinksDoCard, false);
  // 2: pastas deixam de ser reconhecidas
  assert.equal(duasFontes(m(H, "substring(a->>'url' FROM '/folders/([A-Za-z0-9_-]{19,})')", 'NULL')).extraiId, false);

  const E = 'SELECT v_org FROM public._card_drive_files(p_item_id) f CROSS JOIN curators c';
  assert.equal(enfileiraDoHelper(E), true);
  // 3: volta a ler so board_item_files
  assert.equal(enfileiraDoHelper(m(E, 'public._card_drive_files(p_item_id) f', 'public.board_item_files f')), false);

  const T = `IF NEW.status = 'failed' AND OLD.status = 'pending_grant' AND NEW.grant_reason IN ('reviewer_assignment', 'manual') THEN
    PERFORM public.create_notification( NEW.grantee_member_id, 'curation_review_assigned'`;
  assert.equal(avisoDeFalha(T), true);
  // 4: avisa tambem o comite inteiro (ruido para quem nao foi designado)
  assert.equal(avisoDeFalha(m(T, "NEW.grant_reason IN ('reviewer_assignment', 'manual')", 'true')), false);
  // 5: avisa em qualquer atualizacao, nao so na transicao (aviso repetido)
  assert.equal(avisoDeFalha(m(T, " AND OLD.status = 'pending_grant'", '')), false);
});
