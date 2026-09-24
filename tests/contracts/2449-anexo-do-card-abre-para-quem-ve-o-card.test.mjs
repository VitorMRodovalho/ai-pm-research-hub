// tests/contracts/2449-anexo-do-card-abre-para-quem-ve-o-card.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * O anexo enviado pelo card abre para quem ve o card, e so para quem ve o card.
 *
 * O CASO (#2449): o bucket `board-attachments` e privado desde a criacao, e a tela gravava a URL de
 * getPublicUrl, que nao serve arquivo de bucket privado. Medido em 24/09/2026: o link de um anexo
 * real devolvia 400, igual ao controle com caminho inexistente; 39 anexos assim, 40 objetos. E a
 * policy de leitura liberava o bucket inteiro a qualquer `authenticated`, sem o gate do card.
 *
 * Duas metades, e as duas sao afirmadas: a tela abre por link ASSINADO; a policy do bucket le o
 * quadro do caminho e exige visibilidade dele (senao o link assinado vira vazamento).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const CARD = readFileSync('src/components/board/CardDetail.tsx', 'utf8');

/** A tela: link assinado do bucket, derivado do caminho; nunca a URL publica crua. */
export function tela(src) {
  const c = maskJsComments(src);
  return {
    assina: /sb\.storage\.from\(ATTACH_BUCKET\)\.createSignedUrls\(paths, 3600\)/.test(c),
    derivaCaminho: /\/\\\/storage\\\/v1\\\/object\\\/\(\?:public\|sign\)\\\/board-attachments\\\/\(\[\^\?#\]\+\)\//.test(c),
    abrePeloAssinado: /const href = attachmentHref\(att\);/.test(c) && /<a href=\{href \|\| undefined\}/.test(c),
    naoUsaUrlCrua: !/<a href=\{att\.url\}/.test(c) && !/<img src=\{att\.url\}/.test(c),
    gravaCaminho: /const newAttachment = \{ name: file\.name, url: urlData\?\.publicUrl \|\| storagePath, path: storagePath \};/.test(c),
  };
}

/** A regra de leitura: bucket E o helper que exige membro + visibilidade do quadro. */
export function policyDeLeitura(qual) {
  const q = (qual || '').replace(/\s+/g, ' ');
  return /bucket_id = 'board-attachments'::text/.test(q) && /_board_attachment_visible\(name\)/.test(q);
}

/** O helper: formato do caminho antes do cast, e os dois gates no ramo que decide. */
export function helper(body) {
  const b = (body || '').replace(/\s+/g, ' ');
  return /WHEN split_part\(p_name, '\/', 1\) ~\* '\^\[0-9a-f\]\{8\}[^']*' THEN public\.rls_is_authoritative_member\(\) AND public\.rls_can_see_board\(split_part\(p_name, '\/', 1\)::uuid\) ELSE false END/.test(b);
}

test('#2449: a tela abre o anexo por link assinado, nunca pela URL publica', () => {
  const t = tela(CARD);
  assert.deepEqual(t, Object.fromEntries(Object.keys(t).map((k) => [k, true])));
});

test(dbGated ? '#2449: a leitura do bucket exige quem ve o card' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data, error } = await sb().rpc('_audit_function_source', { p_proname: '_board_attachment_visible' });
    assert.equal(error, null, `_audit_function_source falhou: ${error?.message ?? ''}`);
    assert.ok(Array.isArray(data) && data.length === 1);
    assert.ok(helper(data[0].prosrc), 'o helper de visibilidade do anexo perdeu um dos gates');
    // o bucket continua privado: a metade da tela so faz sentido com ele privado
    const { data: b } = await sb().storage.getBucket('board-attachments');
    assert.equal(b?.public, false, 'board-attachments deixou de ser privado');
  });

test('#2449 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  // 1: volta a abrir pela URL crua (o defeito original)
  assert.equal(tela(m(CARD, '<a href={href || undefined}', '<a href={att.url}')).naoUsaUrlCrua, false);
  // 2: deixa de assinar
  assert.equal(tela(m(CARD, 'createSignedUrls(paths, 3600)', 'getPublicUrl(paths)')).assina, false);
  // 3: upload deixa de gravar o caminho
  assert.equal(tela(m(CARD, ', path: storagePath };', ' };')).gravaCaminho, false);

  const Q = "((bucket_id = 'board-attachments'::text) AND _board_attachment_visible(name))";
  assert.equal(policyDeLeitura(Q), true);
  // 4: a policy antiga (so o bucket)
  assert.equal(policyDeLeitura("(bucket_id = 'board-attachments'::text)"), false);

  const H = `SELECT CASE WHEN split_part(p_name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    THEN public.rls_is_authoritative_member() AND public.rls_can_see_board(split_part(p_name, '/', 1)::uuid) ELSE false END;`;
  assert.equal(helper(H), true);
  // 5: sem o gate do quadro (qualquer membro leria card confidencial)
  assert.equal(helper(m(H, ' AND public.rls_can_see_board(split_part(p_name, \'/\', 1)::uuid)', '')), false);
  // 6: caminho fora do formato passa a ser liberado
  assert.equal(helper(m(H, 'ELSE false END', 'ELSE true END')), false);
});

test(dbGated ? '#2449: as policies vivas do bucket exigem quem ve o card, na leitura e no envio' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data, error } = await sb().rpc('_audit_board_attachment_policies');
    assert.equal(error, null, `_audit_board_attachment_policies falhou: ${error?.message ?? ''}`);
    const sel = (data || []).find((p) => p.policyname === 'board_attach_select');
    const ins = (data || []).find((p) => p.policyname === 'board_attach_insert');
    assert.ok(sel, 'board_attach_select sumiu: sem ela ninguem le o bucket');
    assert.ok(policyDeLeitura(sel.qual), 'board_attach_select voltou a liberar o bucket sem o gate do card');
    assert.ok(ins && policyDeLeitura(ins.with_check), 'board_attach_insert voltou a aceitar envio sem o gate do card');
  });
