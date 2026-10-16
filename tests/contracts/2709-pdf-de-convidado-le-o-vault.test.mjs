// tests/contracts/2709-pdf-de-convidado-le-o-vault.test.mjs
/**
 * #2709 — o certificado de convidado nunca gerava PDF: o gatilho lia o GUC
 * `app.cert_pdf_internal_secret`, que o Postgres gerenciado não deixa definir (SEDIMENT-225.B).
 * O gatilho dos membros já lia do vault desde 20260805000006; o de convidado nasceu no mesmo dia
 * copiando a versão anterior.
 *
 * O que este arquivo prova:
 *   (A) o gatilho de convidado lê o segredo do vault e decide pelo valor lido, com `vault` no
 *       search_path;
 *   (B) nenhuma captura mais nova de função volta a ler o GUC (a classe, não só esta função);
 *   (C) as asserções mordem;
 *   (D) camada VIVA: corpo vivo == captura.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, buildNewestDefinitions, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { functionBlock } from '../helpers/rpc-body-error-scan.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const FN = '_trg_event_guest_cert_pdf_autogen';
const GUC_RE = /current_setting\s*\(\s*'app\.cert_pdf_internal_secret'/i;

function violacoes(block, body) {
  const v = [];
  const sql = maskLineComments(body);
  if (GUC_RE.test(sql)) v.push('o gatilho voltou a ler o GUC app.cert_pdf_internal_secret');
  // A leitura do vault tem de ir para v_secret E ser ela que decide se o render é pedido.
  if (!/SELECT decrypted_secret INTO v_secret\s+FROM vault\.decrypted_secrets\s+WHERE name = 'cert_pdf_internal_secret'\s+LIMIT 1;\s+IF v_secret IS NULL OR v_secret = '' THEN\s+RAISE WARNING '[^']*'[^;]*;\s+RETURN NEW;\s+END IF;/.test(sql)) {
    v.push('o segredo não vem do vault, ou não é ele que decide o pulo');
  }
  if (!/PERFORM net\.http_post\([\s\S]{0,200}'Bearer ' \|\| v_secret/.test(sql)) v.push('o pedido de render não usa o segredo lido');
  if (!/SET search_path TO 'public', 'extensions', 'vault'/.test(block)) v.push('vault fora do search_path');
  return v;
}

test('#2709 static: o gatilho de convidado lê o segredo do vault', () => {
  const c = latestFunctionCapture(ROOT, FN);
  assert.deepEqual(violacoes(c.block, c.body), []);
});

test('#2709 static: nenhuma função vigente lê o GUC app.cert_pdf_internal_secret', () => {
  const dir = join(ROOT, 'supabase/migrations');
  const { newest } = buildNewestDefinitions(dir);
  assert.ok(newest.size > 500, `só ${newest.size} funções lidas: o parser parou de ver as migrations`);
  const cache = new Map();
  const leem = [];
  for (const [name, { file }] of newest) {
    if (!cache.has(file)) cache.set(file, maskLineComments(readFileSync(join(dir, file), 'utf8')));
    const blk = functionBlock(cache.get(file), name);
    if (blk && GUC_RE.test(blk.body)) leem.push(`${name} (${file})`);
  }
  assert.deepEqual(leem, [], 'o GUC não pode ser definido no Postgres gerenciado; leia do vault');
});

test('#2709 static: reprova — leitura volta ao GUC', () => {
  const c = latestFunctionCapture(ROOT, FN);
  const adulterado = c.body.replace(
    "SELECT decrypted_secret INTO v_secret\n  FROM vault.decrypted_secrets\n  WHERE name = 'cert_pdf_internal_secret'\n  LIMIT 1;",
    "v_secret := COALESCE(current_setting('app.cert_pdf_internal_secret', true), '');",
  );
  assert.notEqual(adulterado, c.body);
  assert.ok(violacoes(c.block, adulterado).length > 0);
});

test('#2709 static: reprova — o pulo deixa de olhar o segredo', () => {
  const c = latestFunctionCapture(ROOT, FN);
  const adulterado = c.body.replace("IF v_secret IS NULL OR v_secret = '' THEN", 'IF true THEN');
  assert.notEqual(adulterado, c.body);
  assert.ok(violacoes(c.block, adulterado).length > 0);
});

test('#2709 static: reprova — vault fora do search_path', () => {
  const c = latestFunctionCapture(ROOT, FN);
  const bloco = c.block.replace("SET search_path TO 'public', 'extensions', 'vault'", "SET search_path TO 'public', 'extensions'");
  assert.notEqual(bloco, c.block);
  assert.ok(violacoes(bloco, c.body).length > 0);
});

test('#2709 db: corpo VIVO bate com a captura', { skip: dbGated ? false : skipMsg }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
  assert.ifError(error);
  const c = latestFunctionCapture(ROOT, FN);
  const md5 = createHash('md5').update(c.body.replace(/\s+/g, ' ')).digest('hex');
  const vivas = (data ?? []).filter((f) => f.proname === FN);
  assert.equal(vivas.length, 1, `esperava 1 viva, achei ${vivas.length}`);
  assert.equal(vivas[0].body_md5, md5, `corpo vivo divergiu de ${c.file}`);
});
