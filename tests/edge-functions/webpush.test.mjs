// #2806: _shared/webpush.ts contra as RFCs. Os valores de teste abaixo sao PUBLICOS, copiados da RFC 8291
// (secao 5 e apendice A); nenhuma chave aqui e usada em producao.
//
// Dois tipos de prova, de proposito:
//   1. o vetor da RFC, byte a byte, inclusive os valores intermediarios (PRK_key, IKM, PRK, CEK, NONCE);
//   2. um oraculo INDEPENDENTE (node:crypto, que nao passa pelo codigo testado) que decifra a mensagem com
//      sal e chave efemera aleatorios e confere a assinatura ES256 do VAPID.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createECDH, createDecipheriv, createHmac, createPublicKey, verify } from 'node:crypto';
import {
  b64urlDecode, b64urlEncode, deriveContentKeys, encryptPayload, importVapidKeys, rawPublicToJwk,
  vapidAuthorization, VapidSigner, VAPID_TOKEN_SECONDS, MAX_PLAINTEXT,
} from '../../supabase/functions/_shared/webpush.ts';

const V = {
  plaintext: 'V2hlbiBJIGdyb3cgdXAsIEkgd2FudCB0byBiZSBhIHdhdGVybWVsb24',
  asPublic: 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
  asPrivate: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw', // gitleaks:allow (RFC 8291 apendice A, valor publico)
  uaPublic: 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  salt: 'DGv6ra1nlYgDCS1FRnbzlw',
  auth: 'BTBZMqHH6r4Tts7J_aSIgg', // gitleaks:allow (RFC 8291 apendice A, valor publico)
  ecdh: 'kyrL1jIIOHEzg3sM2ZWRHDRB62YACZhhSlknJ672kSs',
  prkKey: 'Snr3JMxaHVDXHWJn5wdC52WjpCtd2EIEGBykDcZW32k', // gitleaks:allow (RFC 8291 apendice A, valor publico)
  ikm: 'S4lYMb_L0FxCeq0WhDx813KgSYqU26kOyzWUdsXYyrg',
  prk: '09_eUZGrsvxChDCGRCdkLiDXrReGOEVeSCdCcPBSJSc',
  cek: 'oIhVW04MRdy2XN9CiKLxTg',
  nonce: '4h_95klXJ5E_qnoN',
  message: 'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml'
    + 'mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT'
    + 'pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
};
const d = b64urlDecode;

async function rfcSenderPair() {
  const jwk = rawPublicToJwk(d(V.asPublic));
  const alg = { name: 'ECDH', namedCurve: 'P-256' };
  return {
    privateKey: await crypto.subtle.importKey('jwk', { ...jwk, d: V.asPrivate }, alg, false, ['deriveBits']),
    publicKey: await crypto.subtle.importKey('jwk', jwk, alg, true, []),
  };
}

test('#2806 RFC 8291 apendice A: valores intermediarios', async () => {
  const k = await deriveContentKeys(d(V.ecdh), d(V.auth), d(V.uaPublic), d(V.asPublic), d(V.salt));
  assert.equal(b64urlEncode(k.prkKey), V.prkKey);
  assert.equal(b64urlEncode(k.ikm), V.ikm);
  assert.equal(b64urlEncode(k.prk), V.prk);
  assert.equal(b64urlEncode(k.cek), V.cek);
  assert.equal(b64urlEncode(k.nonce), V.nonce);
});

test('#2806 RFC 8291 secao 5: a mensagem cifrada e identica, byte a byte', async () => {
  const out = await encryptPayload(d(V.plaintext), d(V.uaPublic), d(V.auth), { salt: d(V.salt), asKeyPair: await rfcSenderPair() });
  assert.equal(b64urlEncode(out), V.message);
});

// Oraculo independente: decifra com node:crypto (ECDH, HMAC e AES-128-GCM do OpenSSL), sem usar webpush.ts.
function oracleDecrypt(body, uaEcdh, authSecret) {
  const salt = body.subarray(0, 16);
  const rs = body.readUInt32BE(16);
  const idlen = body[20];
  const asPublic = body.subarray(21, 21 + idlen);
  const ct = body.subarray(21 + idlen);
  const h = (key, data) => createHmac('sha256', key).update(data).digest();
  const ecdh = uaEcdh.computeSecret(asPublic);
  const prkKey = h(authSecret, ecdh);
  const ikm = h(prkKey, Buffer.concat([Buffer.from('WebPush: info\x00'), uaEcdh.getPublicKey(), asPublic, Buffer.from([1])]));
  const prk = h(salt, ikm);
  const cek = h(prk, Buffer.from('Content-Encoding: aes128gcm\x00\x01')).subarray(0, 16);
  const nonce = h(prk, Buffer.from('Content-Encoding: nonce\x00\x01')).subarray(0, 12);
  const dec = createDecipheriv('aes-128-gcm', cek, nonce);
  dec.setAuthTag(ct.subarray(ct.length - 16));
  const padded = Buffer.concat([dec.update(ct.subarray(0, ct.length - 16)), dec.final()]);
  return { rs, idlen, delimiter: padded[padded.length - 1], plaintext: padded.subarray(0, padded.length - 1) };
}

test('#2806: sal e chave efemera aleatorios, e o oraculo independente decifra', async () => {
  const ua = createECDH('prime256v1');
  ua.generateKeys();
  const auth = Buffer.from(crypto.getRandomValues(new Uint8Array(16)));
  const text = JSON.stringify({ title: 'Nova notificação', url: '/notifications' });
  const a = Buffer.from(await encryptPayload(new TextEncoder().encode(text), new Uint8Array(ua.getPublicKey()), new Uint8Array(auth)));
  const b = Buffer.from(await encryptPayload(new TextEncoder().encode(text), new Uint8Array(ua.getPublicKey()), new Uint8Array(auth)));
  assert.notDeepEqual(a.subarray(0, 16), b.subarray(0, 16), 'o sal tem de mudar a cada mensagem');
  const r = oracleDecrypt(a, ua, auth);
  assert.equal(r.rs, 4096);
  assert.equal(r.idlen, 65);
  assert.equal(r.delimiter, 2);
  assert.equal(r.plaintext.toString('utf8'), text);
});

test('#2806: recusa mensagem acima do limite e auth secret de tamanho errado', async () => {
  const ua = createECDH('prime256v1');
  ua.generateKeys();
  const pub = new Uint8Array(ua.getPublicKey());
  await assert.rejects(encryptPayload(new Uint8Array(MAX_PLAINTEXT + 1), pub, new Uint8Array(16)), /3993/);
  await assert.doesNotReject(encryptPayload(new Uint8Array(MAX_PLAINTEXT), pub, new Uint8Array(16)));
  await assert.rejects(encryptPayload(new Uint8Array(10), pub, new Uint8Array(15)), /16 octetos/);
});

async function freshVapid() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey);
  const pub = new Uint8Array([4, ...d(jwk.x), ...d(jwk.y)]);
  return { keys: await importVapidKeys(b64urlEncode(pub), jwk.d), jwk };
}

test('#2806 RFC 8292: cabecalho vapid com JWT ES256 que o node:crypto verifica', async () => {
  const { keys, jwk } = await freshVapid();
  const now = 1_800_000_000;
  const h = await vapidAuthorization('https://fcm.googleapis.com', 'mailto:contato@example.org', keys, now);
  const m = h.match(/^vapid t=([^.]+)\.([^.]+)\.([^,]+), k=(.+)$/);
  assert.ok(m, `formato inesperado: ${h.slice(0, 40)}`);
  assert.equal(m[4], keys.publicKeyB64);
  assert.deepEqual(JSON.parse(Buffer.from(m[1], 'base64url')), { typ: 'JWT', alg: 'ES256' });
  assert.deepEqual(JSON.parse(Buffer.from(m[2], 'base64url')), {
    aud: 'https://fcm.googleapis.com', exp: now + VAPID_TOKEN_SECONDS, sub: 'mailto:contato@example.org',
  });
  assert.ok(VAPID_TOKEN_SECONDS <= 24 * 3600, 'a RFC 8292 limita o exp a 24 h');
  const pubKey = createPublicKey({ key: { kty: 'EC', crv: 'P-256', x: jwk.x, y: jwk.y }, format: 'jwk' });
  const sig = Buffer.from(m[3], 'base64url');
  assert.equal(sig.length, 64);
  assert.ok(verify('sha256', Buffer.from(`${m[1]}.${m[2]}`), { key: pubKey, dsaEncoding: 'ieee-p1363' }, sig));
  // controle: a mesma verificacao recusa um claim alterado
  const forged = Buffer.from(JSON.stringify({ aud: 'https://evil.example', exp: now + 60, sub: 'mailto:x@y.z' })).toString('base64url');
  assert.equal(verify('sha256', Buffer.from(`${m[1]}.${forged}`), { key: pubKey, dsaEncoding: 'ieee-p1363' }, sig), false);
});

test('#2806: subject fora de mailto/https e chave privada de tamanho errado sao recusados', async () => {
  const { keys, jwk } = await freshVapid();
  await assert.rejects(vapidAuthorization('https://fcm.googleapis.com', 'http://example.org', keys, 1), /mailto/);
  await assert.rejects(importVapidKeys(keys.publicKeyB64, jwk.d.slice(0, 20)), /32 octetos/);
});

test('#2806: o assinador reaproveita o cabecalho por origem e so renova perto de vencer', async () => {
  const { keys } = await freshVapid();
  const s = new VapidSigner(keys, 'mailto:contato@example.org');
  const t0 = 1_800_000_000;
  const a = await s.authorizationFor('https://fcm.googleapis.com/fcm/send/abc', t0);
  assert.equal(await s.authorizationFor('https://fcm.googleapis.com/fcm/send/def', t0 + 3600), a, 'mesma origem, dentro da janela');
  assert.notEqual(await s.authorizationFor('https://web.push.apple.com/xyz', t0), a, 'outra origem tem outro aud');
  assert.notEqual(await s.authorizationFor('https://fcm.googleapis.com/fcm/send/abc', t0 + VAPID_TOKEN_SECONDS - 3600), a, 'renova com menos de 1 h');
});
