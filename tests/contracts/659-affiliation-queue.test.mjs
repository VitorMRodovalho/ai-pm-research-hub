/**
 * #659 — get_affiliation_verification_queue (Pasta Diretoria de Filiação, epic #660 step 2)
 *
 * Reescrito na #3105. A versão anterior fixava a migration original (20260805000155) e afirmava o predicado de
 * coorte "pré-onboarding OU pmi_id_verified=false OU nunca verificado". A função foi redefinida 9 vezes depois disso,
 * e a #3105 trocou o critério: a fila é quem a regra NÃO validou, ou seja, quem tem vínculo ativo que exige termo e o
 * portão de filiação (affiliation_gate) fechado. Este guard lê a CAPTURA VIGENTE de cada função.
 *
 * Trava:
 *   A. o critério de "precisa de verificação humana" mora numa função só (affiliation_needs_review), que liga o
 *      vínculo que exige termo ao portão fechado;
 *   B. a fila (escopo padrão) e o rollup leem essa função, e nenhum dos dois volta a copiar o predicado antigo;
 *   C. cada linha da fila traz o resultado do portão;
 *   D. o resto do contrato de #659: audiência de leitura = de escrita, fail-closed sem sessão, pmi_memberships e
 *      pré-onboarding expostos, trilha do Art. 37;
 *   E. a função nova é interna (não executável por anon/authenticated); grants da fila na assinatura (text);
 *   F. (banco) sem sessão, a fila recusa.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const MIGRATIONS = resolve(ROOT, 'supabase/migrations');
const body = (fn) => maskLineComments(latestFunctionCapture(ROOT, fn).body);
const block = (fn) => maskLineComments(latestFunctionCapture(ROOT, fn).block);

const QUEUE = body('get_affiliation_verification_queue');
const ROLLUP = body('get_affiliation_chapter_rollup');
const NEEDS = body('affiliation_needs_review');

const MIG_3105 = (() => {
  const f = readdirSync(MIGRATIONS).filter((n) => /^\d{14}_3105_fila_de_filiacao_le_o_portao\.sql$/.test(n));
  assert.equal(f.length, 1, 'a migration da #3105 existe uma vez');
  return maskLineComments(readFileSync(resolve(MIGRATIONS, f[0]), 'utf8'));
})();

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const canRun = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required';

async function rpc(fn, args) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`rpc ${fn} HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// O bloco que decide a coorte da fila: do WHERE do CTE até o fim do CTE.
function cohortWhere(q) {
  const i = q.indexOf("WHERE m.member_status = 'active'");
  assert.ok(i > 0, 'a fila tem o WHERE de membros ativos');
  const j = q.indexOf('SELECT', i);
  assert.ok(j > i, 'o WHERE termina antes do SELECT final');
  return q.slice(i, j);
}

// ── A. uma regra só ─────────────────────────────────────────────────────────
test('A. affiliation_needs_review: vinculo ativo que exige termo E portao fechado', () => {
  assert.match(
    NEEDS,
    /JOIN public\.engagements e ON e\.person_id = m\.person_id AND e\.status = 'active'\s+JOIN public\.engagement_kinds ek ON ek\.slug = e\.kind AND ek\.requires_agreement IS TRUE\s+WHERE m\.id = p_member_id/,
    'a pessoa precisa ter vínculo ativo de tipo que exige termo',
  );
  assert.match(
    NEEDS,
    /\)\s+AND NOT COALESCE\(\(public\.affiliation_gate\(p_member_id\) ->> 'open'\)::boolean, false\)/,
    'e o portão cru precisa estar fechado (nulo conta como fechado)',
  );
  assert.doesNotMatch(NEEDS, /affiliation_gate_first_term/, 'o portão cru, não o do primeiro termo');
});

// ── B. fila e rollup leem a regra ───────────────────────────────────────────
test('B1. a fila: escopo all OU affiliation_needs_review, e nada do predicado antigo', () => {
  const w = cohortWhere(QUEUE);
  assert.match(w, /AND \(\s+p_scope = 'all'\s+OR public\.affiliation_needs_review\(m\.id\)\s+\)/, 'coorte = all OU precisa de verificação');
  assert.doesNotMatch(w, /pmi_id_verified/, 'o cache pmi_id_verified não decide a coorte');
  assert.doesNotMatch(w, /member_affiliation_verifications/, '"nunca verificado" não decide a coorte');
  assert.doesNotMatch(w, /pre\.flag/, 'pré-onboarding sozinho não decide a coorte');
});

test('B2. o rollup conta in_queue pela mesma funcao', () => {
  assert.match(ROLLUP, /count\(\*\) FILTER \(WHERE public\.affiliation_needs_review\(m\.id\)\) AS in_queue/);
  assert.doesNotMatch(ROLLUP, /pmi_id_verified|member_affiliation_verifications|member_is_pre_onboarding/,
    'o rollup não copia o predicado antigo');
});

// ── C. o motivo em cada linha ───────────────────────────────────────────────
test('C. cada linha da fila traz o resultado do portao', () => {
  assert.match(QUEUE, /'affiliation_gate', public\.affiliation_gate\(c\.member_id\),/);
});

// ── D. o contrato de #659 que continua ──────────────────────────────────────
test('D1. audiência de leitura = de escrita (filiacao_director OU manage_member), fail-closed', () => {
  assert.match(QUEUE, /IF v_caller_id IS NULL THEN\s+RAISE EXCEPTION 'Forbidden: authentication required'/);
  assert.match(
    QUEUE,
    /IF NOT \('filiacao_director' = ANY\(COALESCE\(v_caller_designations, '\{\}'::text\[\]\)\)\)\s+AND NOT public\.can_by_member\(v_caller_id, 'manage_member'\) THEN\s+RAISE EXCEPTION 'Forbidden: requires filiacao_director/,
  );
  assert.doesNotMatch(QUEUE, /view_internal_analytics/, 'a leitura em lote não é mais larga que a escrita');
});

test('D2. expõe pmi_memberships e a bandeira de pré-onboarding', () => {
  assert.match(QUEUE, /'pmi_memberships', COALESCE\(c\.pmi_memberships, '\[\]'::jsonb\)/);
  assert.match(QUEUE, /'is_pre_onboarding', c\.is_pre_onboarding/);
  assert.match(QUEUE, /ek\.requires_agreement IS NOT TRUE OR e\.agreement_certificate_id IS NOT NULL/);
});

test('D3. trilha do Art. 37 pela leitura em lote', () => {
  assert.match(QUEUE, /PERFORM public\.log_pii_access_batch\(\s+v_member_ids,[\s\S]*?'affiliation_verification_queue'/);
});

// ── E. grants ───────────────────────────────────────────────────────────────
test('E. affiliation_needs_review é interna; a fila segue com o grant da assinatura (text)', () => {
  assert.match(MIG_3105, /REVOKE ALL ON FUNCTION public\.affiliation_needs_review\(uuid\) FROM public, anon, authenticated;/);
  assert.match(MIG_3105, /GRANT EXECUTE ON FUNCTION public\.affiliation_needs_review\(uuid\) TO service_role;/);
  assert.doesNotMatch(block('affiliation_needs_review'), /SECURITY DEFINER/, 'função auxiliar sem SECURITY DEFINER próprio');
  const scope = readFileSync(resolve(MIGRATIONS, '20260805000437_1364b_affiliation_queue_scope_all.sql'), 'utf8');
  assert.match(scope, /REVOKE ALL ON FUNCTION public\.get_affiliation_verification_queue\(text\) FROM public, anon;/);
  assert.match(scope, /GRANT EXECUTE ON FUNCTION public\.get_affiliation_verification_queue\(text\) TO authenticated, service_role;/);
});

// ── G. tela ─────────────────────────────────────────────────────────────────
test('G. a tela mostra o motivo só com o portão fechado, nas 3 línguas', () => {
  const island = maskJsComments(readFileSync(resolve(ROOT, 'src/components/admin/AffiliationQueueIsland.tsx'), 'utf8'));
  assert.match(
    island,
    /\{r\.affiliation_gate && !r\.affiliation_gate\.open && \(\s+<span data-testid="aq-gate-reason"[^>]*>\s+\{t\(`comp\.affiliationQueue\.gateReason_\$\{r\.affiliation_gate\.reason \?\? 'unknown'\}`/,
  );
  for (const d of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = readFileSync(resolve(ROOT, `src/i18n/${d}.ts`), 'utf8');
    for (const k of ['not_affiliated', 'unknown', 'entry_chapter_required']) {
      assert.match(dict, new RegExp(`'comp\\.affiliationQueue\\.gateReason_${k}': '`), `${d}: gateReason_${k}`);
    }
  }
});

// ── F. banco ────────────────────────────────────────────────────────────────
test(canRun ? 'F. sem sessão (auth.uid NULL), a fila recusa' : skipMsg, { skip: !canRun }, async () => {
  await assert.rejects(
    () => rpc('get_affiliation_verification_queue', {}),
    /Forbidden: authentication required/,
    'service-role call has auth.uid()=NULL → must fail-closed (and proves the function exists + gate fires)',
  );
});
