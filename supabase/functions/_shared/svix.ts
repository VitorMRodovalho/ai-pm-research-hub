/**
 * Verificação de assinatura Svix — #1513 onda 4.
 *
 * Por que este arquivo existe: `resend-webhook` era a única das 8 EFs abertas
 * encontradas no #1513 que NÃO pode ser fechada com service-role. Quem a chama é
 * a Resend, de fora, e ela não tem credencial nossa — ela assina o corpo com um
 * segredo compartilhado, no formato Svix. Sem verificar essa assinatura, qualquer
 * um que soubesse a URL inseria eventos forjados em `email_webhook_events`, que é
 * a tabela de onde `send-notification-email` deriva o `DAILY_SEND_CAP` (#1424):
 * 90 eventos `email.sent` falsos zeram o orçamento do dia e param toda a lane de
 * e-mail transacional, parecendo problema de cota em vez de ataque.
 *
 * Formato (https://docs.svix.com/receiving/verifying-payloads/how-manual):
 *   svix-id         identificador único da mensagem
 *   svix-timestamp  epoch em segundos
 *   svix-signature  lista separada por espaço de `v1,<base64>` (pode haver várias
 *                   durante rotação de segredo — basta UMA casar)
 *   conteúdo assinado = `${id}.${timestamp}.${corpo cru}`
 *   segredo = `whsec_<base64>`; o prefixo é descartado e o resto é a CHAVE em
 *   base64 (bytes crus), não texto — decodificar antes do HMAC é obrigatório.
 *
 * Decisões deliberadas:
 *  - FAIL-CLOSED em tudo: segredo ausente/vazio, header ausente, timestamp fora
 *    da janela ou assinatura que não casa ⇒ false. Um segredo não configurado
 *    NUNCA autoriza (é o bug #618 do backup-to-r2, e o motivo de `tokenMatches`
 *    das EFs OTS rejeitar segredo vazio).
 *  - Janela de tolerância de 5 min nos dois sentidos, para conter replay de uma
 *    requisição legítima capturada. Sem isso a assinatura é válida para sempre.
 *  - Comparação em tempo constante, para não vazar o segredo por timing.
 */

const TOLERANCE_SECONDS = 5 * 60;

/** Comparação em tempo constante. Comprimentos diferentes saem imediatamente — o
 *  comprimento de uma assinatura não é segredo, o conteúdo é. */
function timingSafeEqualStr(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToBase64(bytes: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)));
}

/**
 * Verifica a assinatura Svix de um webhook.
 *
 * @param rawBody  o corpo CRU, byte a byte como chegou. Reserializar o JSON
 *                 (JSON.stringify de um objeto já parseado) muda espaços e ordem
 *                 e invalida a assinatura — leia com `req.text()` e parseie DEPOIS.
 * @param headers  os headers da requisição
 * @param secret   `RESEND_WEBHOOK_SECRET`, no formato `whsec_...`
 * @param nowSeconds  injetável para teste; default = relógio real
 */
export async function verifySvixSignature(
  rawBody: string,
  headers: Headers,
  secret: string | null | undefined,
  nowSeconds: number = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  if (!secret) return false;

  const id = headers.get("svix-id");
  const timestamp = headers.get("svix-timestamp");
  const signatureHeader = headers.get("svix-signature");
  if (!id || !timestamp || !signatureHeader) return false;

  const ts = Number(timestamp);
  if (!Number.isFinite(ts)) return false;
  if (Math.abs(nowSeconds - ts) > TOLERANCE_SECONDS) return false;

  // `whsec_` é só um rótulo humano; o material da chave é o base64 depois dele.
  const rawSecret = secret.startsWith("whsec_") ? secret.slice(6) : secret;
  if (!rawSecret) return false;

  let keyBytes: Uint8Array;
  try {
    keyBytes = base64ToBytes(rawSecret);
  } catch {
    return false;
  }
  if (keyBytes.length === 0) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes as unknown as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = `${id}.${timestamp}.${rawBody}`;
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signed));
  const expected = bytesToBase64(mac);

  // O header traz uma ou mais assinaturas `v<versão>,<base64>`. Durante rotação de
  // segredo a Resend manda as duas; basta uma casar.
  for (const part of signatureHeader.split(" ")) {
    const comma = part.indexOf(",");
    if (comma === -1) continue;
    const version = part.slice(0, comma);
    const value = part.slice(comma + 1);
    if (version !== "v1") continue;
    if (timingSafeEqualStr(value, expected)) return true;
  }
  return false;
}
