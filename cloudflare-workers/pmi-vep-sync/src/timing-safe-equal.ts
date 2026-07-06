// #1050 — constant-time string comparison for the /ingest shared-secret check.
// A plain `a === b` early-exits on the first differing byte, leaking how many leading
// bytes matched via timing. We HMAC both inputs with a per-call random key and compare
// the fixed-length digests, so timing is independent of where the inputs diverge.
// (Local copy — this Worker builds separately from the main app's src/lib.)
export async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const key = crypto.getRandomValues(new Uint8Array(32));
  const ck = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const [ha, hb] = await Promise.all([
    crypto.subtle.sign('HMAC', ck, enc.encode(a)),
    crypto.subtle.sign('HMAC', ck, enc.encode(b)),
  ]);
  const va = new Uint8Array(ha);
  const vb = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i];
  return diff === 0;
}
