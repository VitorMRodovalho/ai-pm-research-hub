/**
 * #2699 — o Termo contra-assinado não baixava PDF.
 *
 * CAUSA, medida em 14/10/2026: #2022 faz a contra-assinatura zerar `pdf_url` (o congelado dizia
 * "pendente"), mas o único gerador do PDF era AFTER INSERT. Os 15 termos contra-assinados de 02/09
 * a 14/10 ficaram sem PDF, e o download caía numa aba com print() que, bloqueada, saía em silêncio.
 *
 * Os guards amarram CONDIÇÃO a RESULTADO dentro do bloco que decide (CLAUDE.md, 17/09): uma
 * string solta num corpo longo sobrevive à remoção do mecanismo.
 *
 * Cross-ref: #2022 (invalidação do congelado), #648 (o congelado é o artefato autoritativo).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, 'supabase/migrations');
const MIG_FILE = readdirSync(MIG_DIR).find((f) => /_2699_contra_assinatura_regera_o_pdf_congelado\.sql$/.test(f));
const MIG = MIG_FILE ? maskLineComments(readFileSync(join(MIG_DIR, MIG_FILE), 'utf8')) : '';
const SWEEP = latestFunctionCapture(ROOT, '_certificate_pdf_regen_sweep_cron');
const SWEEP_BODY = SWEEP ? maskLineComments(SWEEP.body) : '';
const PDF = maskJsComments(readFileSync(join(ROOT, 'src/lib/certificates/pdf.ts'), 'utf8'));

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);

function triggerStatement() {
  const m = MIG.match(/CREATE TRIGGER trg_certificate_pdf_regen_on_invalidate[\s\S]*?;/);
  return m ? m[0] : '';
}

test('#2699 a migration existe', () => {
  assert.ok(MIG_FILE, 'migration *_2699_contra_assinatura_regera_o_pdf_congelado.sql não encontrada');
});

test('#2699 gatilho: invalidar o congelado de um certificado emitido chama o render', () => {
  const trg = triggerStatement();
  assert.ok(trg, 'CREATE TRIGGER trg_certificate_pdf_regen_on_invalidate ausente');
  // UPDATE, não INSERT: o defeito era exatamente o gerador só existir no INSERT.
  assert.match(trg, /AFTER UPDATE OF pdf_url, counter_signed_at ON public\.certificates/,
    'o gatilho tem de vigiar o UPDATE que a contra-assinatura faz');
  // A condição e o resultado no MESMO comando: WHEN (... NEW.pdf_url IS NULL ...) EXECUTE render.
  assert.match(trg,
    /WHEN \(NEW\.pdf_url IS NULL\s+AND NEW\.status = 'issued'\s+AND \(OLD\.pdf_url IS NOT NULL OR OLD\.counter_signed_at IS DISTINCT FROM NEW\.counter_signed_at\)\)\s+EXECUTE FUNCTION public\._trg_certificate_pdf_autogen\(\)/,
    'o WHEN tem de disparar o render quando o congelado some de um certificado emitido');
});

test('#2699 varredura: cada certificado selecionado sem PDF recebe um pedido de render E conta tentativa', () => {
  assert.ok(SWEEP, '_certificate_pdf_regen_sweep_cron não capturada');
  const loop = SWEEP_BODY.match(/FOR v_rec IN([\s\S]*?)END LOOP;/);
  assert.ok(loop, 'laço da varredura ausente');
  const [, block] = loop;
  // seleção: sem PDF, emitido, abaixo do teto de tentativas
  assert.match(block, /WHERE c\.pdf_url IS NULL\s+AND c\.status = 'issued'/,
    'a varredura tem de escolher os emitidos SEM pdf_url');
  assert.match(block, /l\.action = 'certificate\.pdf_regen_requested' AND l\.target_id = c\.id\) < 3\b/,
    'sem teto, um certificado que nunca renderiza ocupa as vagas para sempre');
  // resultado: pedido ao endpoint de render + registro da tentativa, no mesmo laço
  assert.match(block, /LOOP\s+PERFORM net\.http_post\(\s+url := 'https:\/\/nucleoia\.vitormr\.dev\/api\/internal\/cert-pdf-render\/' \|\| v_rec\.id::text/,
    'o laço tem de pedir o render de cada certificado selecionado');
  assert.match(block, /INSERT INTO public\.admin_audit_log[\s\S]*?'certificate\.pdf_regen_requested', 'certificate', v_rec\.id/,
    'sem o registro, a tentativa não conta e o teto nunca chega');
});

test('#2699 varredura: certificado esgotado faz o cron FALHAR, não sumir', () => {
  assert.match(SWEEP_BODY,
    /IF v_enviados = 0 AND v_esgotados > 0 THEN\s+RAISE EXCEPTION/,
    'esgotar em silêncio repetiria o defeito: a falha de cron é o que o _alert_sweep_cron lê');
  assert.match(SWEEP_BODY, /IF v_secret IS NULL OR v_secret = '' THEN\s+RAISE EXCEPTION/,
    'sem segredo a varredura não pode devolver verde');
});

test('#2699 varredura: agendada e fechada para anon/authenticated', () => {
  assert.match(MIG, /cron\.schedule\(\s+'certificate-pdf-regen-sweep',\s+'\*\/10 \* \* \* \*',\s+\$cron\$SELECT public\._certificate_pdf_regen_sweep_cron\(5\);\$cron\$/,
    'a varredura não está agendada');
  assert.match(MIG, /REVOKE ALL ON FUNCTION public\._certificate_pdf_regen_sweep_cron\(integer\) FROM PUBLIC, anon, authenticated;/,
    'função que dispara render não pode ficar exposta à API');
});

test('#2699 front: aba bloqueada mostra aviso, nas duas funções de download', () => {
  const blocked = PDF.match(/if \(!w\) \{ showBlockedTabNotice\(url\); return; \}/g) || [];
  assert.equal(blocked.length, 2, 'individual e lote têm de avisar quando window.open devolve null');
  assert.doesNotMatch(PDF, /if \(!w\) \{ URL\.revokeObjectURL\(url\); return; \}/,
    'a saída silenciosa voltou');
  // o aviso tem de oferecer o link (gesto novo), não só texto
  const fn = PDF.match(/function showBlockedTabNotice\([\s\S]*?\n\}/);
  assert.ok(fn, 'showBlockedTabNotice ausente');
  assert.match(fn[0], /link\.href = url;[\s\S]*box\.append\(msg, link, close\);[\s\S]*document\.body\.appendChild\(box\);/,
    'o aviso tem de levar um link para o mesmo documento e ir para a página');
});

test('#2699 front: o congelado é BAIXADO e a falha dele é dita', () => {
  assert.match(PDF, /\.download\(row\.pdf_url\);\s+if \(!dlErr && blob\) \{\s+saveBlob\(blob,/,
    'o congelado tem de virar arquivo baixado, sem aba');
  assert.match(PDF, /if \(frozenFailed\) notify\(t\('certificates\.frozenUnavailable'/,
    'quando o congelado existe e não vem, quem clicou tem de saber que recebeu a reconstrução');
});

test('#2699 front: o lote diz quantos ficaram de fora', () => {
  assert.match(PDF, /catch \(e\) \{ console\.warn\('\[pdf\] skipping cert in bulk render'[^}]*skipped\+\+; return ''; \}/,
    'o documento pulado tem de ser contado');
  assert.match(PDF, /if \(skipped > 0\) \{\s+notify\(t\('certificates\.bulkSkipped'/,
    'a contagem de pulados tem de chegar a quem pediu o lote');
});

test('#2699 vivo: nenhum certificado emitido e contra-assinado há mais de 2h está sem PDF',
  { skip: dbGated ? false : 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required' }, async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
  const corte = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
  const { data, error } = await sb
    .from('certificates')
    .select('verification_code, type, counter_signed_at')
    .eq('status', 'issued')
    .is('pdf_url', null)
    .not('counter_signed_at', 'is', null)
    .lt('counter_signed_at', corte);
  assert.ok(!error, error?.message);
  // controle positivo: a consulta enxerga contra-assinados (senão o zero acima é vacuidade)
  const { count, error: e2 } = await sb
    .from('certificates')
    .select('id', { count: 'exact', head: true })
    .not('counter_signed_at', 'is', null);
  assert.ok(!e2, e2?.message);
  assert.ok((count ?? 0) > 0, 'nenhum contra-assinado visível: o guard passaria por vacuidade');
  assert.deepEqual(data, [],
    `contra-assinados sem PDF há mais de 2h (a varredura não recuperou): ${JSON.stringify(data)}`);
});
