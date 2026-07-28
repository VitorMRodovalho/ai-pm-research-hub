// #1513 onda 4 — verificação de assinatura Svix no resend-webhook.
//
// Diferente dos outros guards do #1513, este NÃO é asserção estática: ele
// importa o helper e exercita o algoritmo, porque uma verificação de HMAC que
// "parece certa" e está errada aceita ou rejeita tudo em silêncio. Assinatura
// válida tem que passar; forjada, expirada e sem segredo têm que falhar.
//
// Por que importa mais que um webhook falso: esta EF insere em
// `email_webhook_events`, e é dessa tabela que `send-notification-email` deriva
// o DAILY_SEND_CAP (#1424). 90 eventos `email.sent` forjados zeram o orçamento
// diário e param toda a lane de e-mail transacional.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHmac, randomBytes } from "node:crypto";

const { verifySvixSignature } = await import("../../supabase/functions/_shared/svix.ts");

const SECRET_BYTES = randomBytes(24);
const SECRET = "whsec_" + SECRET_BYTES.toString("base64");
const NOW = 1785000000; // epoch fixo: Date.now() tornaria o teste dependente do relógio

function sign(id, ts, body, secretBytes = SECRET_BYTES) {
  const mac = createHmac("sha256", secretBytes).update(`${id}.${ts}.${body}`).digest("base64");
  return `v1,${mac}`;
}

function headersFor(id, ts, signature) {
  return new Headers({ "svix-id": id, "svix-timestamp": String(ts), "svix-signature": signature });
}

const BODY = JSON.stringify({ type: "email.sent", data: { email_id: "abc", to: ["x@y.z"] } });

test("#1513: assinatura válida passa", async () => {
  const h = headersFor("msg_1", NOW, sign("msg_1", NOW, BODY));
  assert.equal(await verifySvixSignature(BODY, h, SECRET, NOW), true);
});

test("#1513: segredo AUSENTE nunca autoriza (fail-closed, bug #618)", async () => {
  const h = headersFor("msg_1", NOW, sign("msg_1", NOW, BODY));
  assert.equal(await verifySvixSignature(BODY, h, undefined, NOW), false);
  assert.equal(await verifySvixSignature(BODY, h, "", NOW), false);
  assert.equal(await verifySvixSignature(BODY, h, "whsec_", NOW), false);
});

test("#1513: assinatura de OUTRO segredo é rejeitada", async () => {
  const outro = randomBytes(24);
  const h = headersFor("msg_1", NOW, sign("msg_1", NOW, BODY, outro));
  assert.equal(await verifySvixSignature(BODY, h, SECRET, NOW), false);
});

test("#1513: corpo alterado depois de assinado é rejeitado", async () => {
  // O ataque real: pegar um webhook legítimo e trocar o event_type.
  const h = headersFor("msg_1", NOW, sign("msg_1", NOW, BODY));
  const adulterado = BODY.replace("email.sent", "email.bounced");
  assert.equal(await verifySvixSignature(adulterado, h, SECRET, NOW), false);
});

test("#1513: replay fora da janela de 5 min é rejeitado nos dois sentidos", async () => {
  const velho = NOW - 6 * 60;
  const hv = headersFor("msg_1", velho, sign("msg_1", velho, BODY));
  assert.equal(await verifySvixSignature(BODY, hv, SECRET, NOW), false);

  const futuro = NOW + 6 * 60;
  const hf = headersFor("msg_1", futuro, sign("msg_1", futuro, BODY));
  assert.equal(await verifySvixSignature(BODY, hf, SECRET, NOW), false);

  // dentro da janela continua válido
  const dentro = NOW - 4 * 60;
  const hd = headersFor("msg_1", dentro, sign("msg_1", dentro, BODY));
  assert.equal(await verifySvixSignature(BODY, hd, SECRET, NOW), true);
});

test("#1513: o svix-id entra na assinatura (não dá para reusar a assinatura em outra mensagem)", async () => {
  const h = headersFor("msg_OUTRO", NOW, sign("msg_1", NOW, BODY));
  assert.equal(await verifySvixSignature(BODY, h, SECRET, NOW), false);
});

test("#1513: headers svix ausentes são rejeitados", async () => {
  const sig = sign("msg_1", NOW, BODY);
  assert.equal(await verifySvixSignature(BODY, new Headers({ "svix-id": "msg_1", "svix-timestamp": String(NOW) }), SECRET, NOW), false);
  assert.equal(await verifySvixSignature(BODY, new Headers({ "svix-id": "msg_1", "svix-signature": sig }), SECRET, NOW), false);
  assert.equal(await verifySvixSignature(BODY, new Headers({ "svix-timestamp": String(NOW), "svix-signature": sig }), SECRET, NOW), false);
  assert.equal(await verifySvixSignature(BODY, new Headers(), SECRET, NOW), false);
});

test("#1513: timestamp não-numérico é rejeitado em vez de virar NaN permissivo", async () => {
  // `Math.abs(now - NaN) > tol` é false — sem o guard de Number.isFinite, um
  // timestamp lixo PASSARIA pela checagem de janela. Mesma família do
  // reference-plpgsql-null-condition-skips-raise.
  const h = new Headers({ "svix-id": "msg_1", "svix-timestamp": "abc", "svix-signature": sign("msg_1", "abc", BODY) });
  assert.equal(await verifySvixSignature(BODY, h, SECRET, NOW), false);
});

test("#1513: múltiplas assinaturas (rotação de segredo) — basta uma casar", async () => {
  const outro = randomBytes(24);
  const header = `${sign("msg_1", NOW, BODY, outro)} ${sign("msg_1", NOW, BODY)}`;
  assert.equal(await verifySvixSignature(BODY, headersFor("msg_1", NOW, header), SECRET, NOW), true);
});

test("#1513: versão diferente de v1 é ignorada, não aceita", async () => {
  const mac = createHmac("sha256", SECRET_BYTES).update(`msg_1.${NOW}.${BODY}`).digest("base64");
  const h = headersFor("msg_1", NOW, `v0,${mac}`);
  assert.equal(await verifySvixSignature(BODY, h, SECRET, NOW), false);
});

// ── Fiação na EF ──
const ef = readFileSync("supabase/functions/resend-webhook/index.ts", "utf8");

test("#1513: resend-webhook verifica a assinatura ANTES de qualquer escrita", () => {
  assert.match(ef, /import \{ verifySvixSignature \} from '\.\.\/_shared\/svix\.ts'/);
  assert.match(ef, /await verifySvixSignature\(/);
  const gate = ef.indexOf("await verifySvixSignature(");
  const insert = ef.indexOf("from('email_webhook_events').insert(");
  assert.ok(gate !== -1 && insert !== -1 && gate < insert, "gate deve preceder o insert no log de eventos");
  assert.match(ef.slice(gate, gate + 500), /status|401|unauthorized/);
});

test("#1513: resend-webhook lê o corpo CRU (reserializar invalidaria a assinatura)", () => {
  // `req.json()` seguido de JSON.stringify muda espaçamento/ordem e o HMAC não
  // fecha. Tem de ser text() e o parse vem DEPOIS da verificação.
  assert.match(ef, /const rawBody = await req\.text\(\)/);
  assert.doesNotMatch(ef, /const payload = await req\.json\(\)/);
  const raw = ef.indexOf("const rawBody = await req.text()");
  const parse = ef.indexOf("JSON.parse(rawBody)");
  const gate = ef.indexOf("await verifySvixSignature(");
  assert.ok(raw < gate && gate < parse, "ordem: ler cru → verificar → parsear");
});
