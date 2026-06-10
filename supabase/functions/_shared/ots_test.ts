// ots_test.ts — #569 Slice 2/3 correctness gate. Run: deno test -A supabase/functions/_shared/ots_test.ts
//
// The decisive check is BYTE-EXACT round-trip (parse -> re-serialize == canonical bytes) of real `.ots`
// vectors from opentimestamps/javascript-opentimestamps/examples. If these pass, the serializer matches
// the consensus-critical wire format across pending / multi-calendar-fork / Bitcoin-merkle / unknown-attestation.
// The live stamp test (OTS_LIVE=1) additionally proves a freshly-produced proof round-trips; the FINAL legal
// gate (a canonical `ots verify` accepting our proof) is run by the PM.

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { _internal, bytesToHex, hexToBytes, describe, stamp, upgrade } from "./ots.ts";

// --- canonical vectors (javascript-opentimestamps/examples/*.ots) ---
const VECTORS: Record<string, string> = {
  // single pending calendar (alice)
  incomplete:
    "004f70656e54696d657374616d7073000050726f6f6600bf89e2e884e89294010805c4f616a8e5310d19d938cfd769864d7f4ccdc2ca8b479b10af83564b097af9f0010e754bf93806a7ebaa680ef7bd0114bf408f010b573e8850cfd9e63d1f043fbb6fc250e08f10457cfa5c4f0086fb1ac8d4e4eb0e70083dfe30d2ef90c8e2e2d68747470733a2f2f616c6963652e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f7267",
  // fork into two calendars (alice + bob) — exercises multi-op fork + op sort
  twoCalendars:
    "004f70656e54696d657374616d7073000050726f6f6600bf89e2e884e892940108efaa174f68e59705757460f4f7d204bd2b535cfd194d9d945418732129404ddbf010839037eef449dec6dac322ca97347c4508fff0106b4023b6edd3a0eeeb09e5d718723b9e08f10457d46515f008eadd66b1688d55740083dfe30d2ef90c8e2e2d68747470733a2f2f616c6963652e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f7267f010a3ad701ef9f10535a84968b5a99d858008f10457d46516f008647b90ea1b270a970083dfe30d2ef90c8e2c2b68747470733a2f2f626f622e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f7267",
  // full Bitcoin attestation via a tx merkle path — exercises the long op chain + BitcoinBlockHeaderAttestation
  helloWorld:
    "004f70656e54696d657374616d7073000050726f6f6600bf89e2e884e89294010803ba204e50d126e4674c005e04d82e84c21366780af1f43bd54a37816b6ab34003f1c8010100000001e482f9d32ecc3ba657b69d898010857b54457a90497982ff56f97c4ec58e6f98010000006b483045022100b253add1d1cf90844338a475a04ff13fc9e7bd242b07762dea07f5608b2de367022000b268ca9c3342b3769cdd062891317cdcef87aac310b6855e9d93898ebbe8ec0121020d8e4d107d2b339b0050efdd4b4a09245aa056048f125396374ea6a2ab0709c6ffffffff026533e605000000001976a9140bf057d40fbba6744862515f5b55a2310de5772f88aca0860100000000001976a914f00688ac000000000808f120a987f716c533913c314c78e35d35884cac943fa42cac49d2b2c69f4003f85f880808f120dec55b3487e1e3f722a49b55a7783215862785f4a3acb392846019f71dc64a9d0808f120b2ca18f485e080478e025dab3d464b416c0e1ecb6629c9aefce8c8214d0424320808f02011b0e90661196ff4b0813c3eda141bab5e91604837bdf7a0c9df37db0e3a11980808f020c34bc1a4a1093ffd148c016b1e664742914e939efabe4d3d356515914b26d9e20808f020c3e6e7c38c69f6af24c2be34ebac48257ede61ec0a21b9535e4443277be306460808f1200798bf8606e00024e5d5d54bf0c960f629dfb9dad69157455b6f2652c0e8de810808f0203f9ada6d60baa244006bb0aad51448ad2fafb9d4b6487a0999cff26b91f0f5360808f120c703019e959a8dd3faef7489bb328ba485574758e7091f01464eb65872c975c80808f020cbfefff513ff84b915e3fed6f9d799676630f8364ea2a6c7557fad94a5b5d7880808f1200be23709859913babd4460bbddf8ed213e7c8773a4b1face30f8acfdf093b7050808000588960d73d7190103f7ef15",
  // known (bob pending) + an UnknownAttestation (tag 0001020304050607) — exercises preservation + cross-class sort
  knownUnknown:
    "004f70656e54696d657374616d7073000050726f6f6600bf89e2e884e892940108d288b2ee212b01e3e5f6d333df3a4d53f292cc3f07b09013c0b40c8e7dcb9c03f01046d842bd5d8377e0f42041bec9bda66708fff010332c572f9c4b8d5db9d99758d48fff3408f10457e89f38f00873c6dc4d0cbc29f00083dfe30d2ef90c8e2c2b68747470733a2f2f626f622e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f7267f010e7ad29076f188033d20767602ca3a8e008f10457e89f37f00862df56371ae23d8d0001020304050607082e78787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878",
  // two calendars under a deeper merkle path
  merkle2:
    "004f70656e54696d657374616d7073000050726f6f6600bf89e2e884e8929401088bd5a5f07b4451c29756df5eb51d194fb5b20c7e89812d877bbad30d871c582ff010b63d8f213d047298b8ab4595acd8e5d008f120ae59d2c0d2f5efa97df8f3cca7e85845880c102237f1a6a1b0b4c6a5ab77f49408f020026356e7972f023930ec84c213adedc4050460973935bbd2f4df3d7bd5dec55f08fff0102e12050afd7a10ea4f591ed717d35de608f10457d982dff008b1f26e2e555904770083dfe30d2ef90c8e2e2d68747470733a2f2f616c6963652e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f7267f0104aaade9c2ffb853ccff9c07681d019fd08f10457d982e0f0086644ef713071762a0083dfe30d2ef90c8e2c2b68747470733a2f2f626f622e6274632e63616c656e6461722e6f70656e74696d657374616d70732e6f7267",
};

Deno.test("sha256 NIST vector (abc)", () => {
  const h = _internal.sha256(new TextEncoder().encode("abc"));
  assertEquals(bytesToHex(h), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
});

Deno.test("varuint round-trip (LEB128)", () => {
  for (const v of [0, 1, 127, 128, 255, 256, 16383, 16384, 65535, 1234567]) {
    const w = new _internal.Writer();
    w.writeVaruint(v);
    const r = new _internal.Reader(w.getBytes());
    assertEquals(r.readVaruint(), v, `varuint ${v}`);
    assert(r.eof(), `varuint ${v} consumed exactly`);
  }
});

Deno.test("varbytes round-trip", () => {
  const payload = hexToBytes("deadbeef0001ff");
  const w = new _internal.Writer();
  w.writeVarbytes(payload);
  const r = new _internal.Reader(w.getBytes());
  assertEquals(bytesToHex(r.readVarbytes(100)), "deadbeef0001ff");
});

// THE decisive correctness gate: byte-exact round-trip of canonical vectors.
for (const [name, hex] of Object.entries(VECTORS)) {
  Deno.test(`round-trip byte-exact: ${name}`, () => {
    const bytes = hexToBytes(hex);
    const { fileHashOpTag, timestamp } = _internal.deserializeDetached(bytes);
    const out = _internal.serializeDetached(fileHashOpTag, timestamp);
    assertEquals(bytesToHex(out), hex, `${name} did not round-trip byte-exact`);
  });
}

Deno.test("describe: incomplete has one alice pending, no bitcoin", () => {
  const d = describe(hexToBytes(VECTORS.incomplete));
  assertEquals(d.pending, ["https://alice.btc.calendar.opentimestamps.org"]);
  assertEquals(d.bitcoinHeights, []);
});

Deno.test("describe: helloWorld is Bitcoin-confirmed", () => {
  const d = describe(hexToBytes(VECTORS.helloWorld));
  assertEquals(d.pending, []);
  assert(d.bitcoinHeights.length === 1 && d.bitcoinHeights[0] > 0, "expected one bitcoin attestation");
});

Deno.test("describe: knownUnknown keeps bob pending alongside the unknown attestation", () => {
  const d = describe(hexToBytes(VECTORS.knownUnknown));
  assertEquals(d.pending, ["https://bob.btc.calendar.opentimestamps.org"]);
});

// --- live (network) — opt-in: OTS_LIVE=1 deno test -A ---
Deno.test({
  name: "LIVE: stamp a digest -> pending .ots round-trips + >=1 calendar",
  ignore: Deno.env.get("OTS_LIVE") !== "1",
  fn: async () => {
    const digest = _internal.sha256(new TextEncoder().encode("nucleo-ia-ots-spike-2026-06-09"));
    const res = await stamp(digest, { m: 1, timeoutMs: 25000 });
    assert(res.calendarsOk.length >= 1, "at least one calendar should respond");
    // round-trip our freshly produced proof
    const { fileHashOpTag, timestamp } = _internal.deserializeDetached(res.otsBytes);
    const out = _internal.serializeDetached(fileHashOpTag, timestamp);
    assertEquals(bytesToHex(out), bytesToHex(res.otsBytes), "live proof must round-trip");
    const d = describe(res.otsBytes);
    assert(d.pending.length >= 1, "fresh proof is pending");
    assertEquals(d.bitcoinHeights, [], "fresh proof not yet Bitcoin-anchored");
    // upgrade immediately should be a no-op (not yet mined) but must not corrupt the proof
    const up = await upgrade(res.otsBytes, { timeoutMs: 25000 });
    assert(!up.confirmed, "fresh proof should still be pending right after stamp");
  },
});
