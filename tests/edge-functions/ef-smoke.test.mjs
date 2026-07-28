import test from 'node:test';
import assert from 'node:assert/strict';

/**
 * Integration smoke tests for deployed Edge Functions.
 * Requires: SUPABASE_URL + SUPABASE_ANON_KEY env vars.
 * Safe operations only — no side effects.
 *
 * Skip in CI: these require network access to deployed EFs.
 */

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || process.env.PUBLIC_SUPABASE_ANON_KEY;

const canRun = !!(SUPABASE_URL && SUPABASE_ANON_KEY);
const skipMsg = 'Skipped: SUPABASE_URL and SUPABASE_ANON_KEY required for smoke tests';

// Em CI, "sem credencial" NAO pode significar verde. Este arquivo rodou meses
// pulando em silencio porque o step nao exportava SUPABASE_ANON_KEY (#1513), e
// um skip silencioso e indistinguivel de um pass na leitura do log. Localmente o
// skip continua valendo: nem todo dev tem .env.
const IS_CI = process.env.CI === 'true' || process.env.GITHUB_ACTIONS === 'true';

test('smoke: em CI as credenciais precisam estar no env (nao pode pular calado)', () => {
  if (!IS_CI) return;
  assert.ok(
    canRun,
    'SUPABASE_URL + SUPABASE_ANON_KEY ausentes no env do CI: os smokes de EF deployada ' +
      'pulariam em silencio. Exporte ambos no step `Run Unit Tests` de .github/workflows/ci.yml.',
  );
});

async function efPost(slug, body = {}) {
  const url = `${SUPABASE_URL}/functions/v1/${slug}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = null; }
  return { status: res.status, json, text };
}

test('smoke: sync-credly-all rejects anon token', { skip: !canRun && skipMsg }, async () => {
  const { status } = await efPost('sync-credly-all', {});
  // Anon key should be rejected (401 or 403)
  assert.ok([401, 403].includes(status), `Expected 401/403, got ${status}`);
});

test('smoke: verify-credly rejects the anon key (#1513 onda 3)', { skip: !canRun && skipMsg }, async () => {
  // Antes do #1513 esta EF não verificava chamador nenhum, e este teste media o
  // comportamento DEPOIS do gate inexistente: a anon key entrava e o erro vinha
  // da validação de member_id (400/500). Agora a anon key não é usuário nem
  // service-role, então para no gate. Ela escreve em gamification_points,
  // course_progress e members — deixar a anon key passar era o buraco.
  const { status, json } = await efPost('verify-credly', { member_id: '00000000-0000-0000-0000-000000000000' });
  assert.ok(status === 401, `Expected 401, got ${status}`);
  assert.ok(json !== null, 'Response should be valid JSON');
});

test('smoke: resend-webhook rejects an unsigned request (#1513 onda 4)', { skip: !canRun && skipMsg }, async () => {
  // Este teste afirmava que a EF aceitava (200) qualquer evento — o que era
  // exatamente o buraco: sem verificar a assinatura Svix, qualquer um inseria em
  // email_webhook_events, tabela de onde send-notification-email deriva o
  // DAILY_SEND_CAP. 90 eventos `email.sent` forjados paravam a lane de e-mail.
  const { status, json } = await efPost('resend-webhook', { type: 'test.ping', data: {} });
  assert.ok(status === 401, `Expected 401, got ${status}`);
  assert.ok(json !== null, 'Response should be valid JSON');
});

test('smoke: send-campaign rejects anon token', { skip: !canRun && skipMsg }, async () => {
  const { status } = await efPost('send-campaign', {});
  assert.ok([401, 403].includes(status), `Expected 401/403, got ${status}`);
});

test('smoke: get-comms-metrics rejects the anon key (#1513 fase 2)', { skip: !canRun && skipMsg }, async () => {
  // Este teste afirmava "JWT-verified: anon key should work for read-only", que
  // era precisamente a premissa errada do #1513: verify_jwt=true aceita QUALQUER
  // JWT do projeto, e a anon key é pública. Ela devolvia 200 com métricas da
  // organização lidas em service role. Agora tem gate de service-role.
  const { status } = await efPost('get-comms-metrics', {});
  assert.ok(status === 401, `Expected 401, got ${status}`);
});

// ⚠️ NOTA DE MANUTENÇÃO (#1513, 2026-07-28). Este arquivo bate em PRODUÇÃO, então
// o resultado depende do que está DEPLOYADO, não do que está na branch. O gate do
// get-comms-metrics passou verde no CI do PR que o introduziu — porque o deploy
// ainda não tinha acontecido — e só ficou vermelho depois. Ao mudar auth de EF,
// espere estes smokes virarem no momento do deploy, não no do merge.
// (Classe "invariante de CI sobre dado vivo", #1487 classe B.)
