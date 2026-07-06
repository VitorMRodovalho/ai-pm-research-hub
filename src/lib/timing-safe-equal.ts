// #1050 — constant-time string comparison for secret / bearer-token checks.
// A plain `a === b` early-exits on the first differing byte, leaking how many
// leading bytes matched via response timing (a classic secret-recovery side channel).
// We HMAC both inputs with a per-call random key, then compare the fixed-length
// (32-byte) digests — so wall-clock time is independent of where/if the inputs
// diverge and of their lengths. Web Crypto is available in Workers/Deno/browsers.
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
