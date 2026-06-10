# SPEC #569 Slice 0 — OpenTimestamps-in-Deno feasibility spike

- **Issue:** #569 (OpenTimestamps / carimbo de tempo, Parecer 01/2026 rec k)
- **ADR:** ADR-0101 (digest-only asset registry) — closes its open item *"OTS-lib-in-Deno feasibility (Slice 0 spike)"*
- **Date:** 2026-06-09
- **Method:** source-grounded research (workflow `wf_dda4ebd6-078` — 4 research arms + 1 adversarial verifier, all WebFetch/WebSearch grounded against unpkg/GitHub raw/Deno docs/Supabase docs), then the chosen engine was **built + verified under Node 24** (the sandbox blocks Deno/`npm install`, but Node 24 type-strips the zero-dep TS directly and has `fetch`/`getRandomValues`/`AbortSignal.timeout`).
- **Status:** **DONE.** Decision = **HAND_ROLL** (PM, 2026-06-09). Engine `supabase/functions/_shared/ots.ts` built and **verified byte-exact** against 5 canonical `.ots` vectors + a live multi-calendar stamp. The lib-viability probe became unnecessary (we proved the hand-roll directly).

## Outcome (2026-06-09) — VERIFIED

PM chose **HAND_ROLL** (zero-dep). The engine is implemented at `supabase/functions/_shared/ots.ts` (`stamp` / `upgrade` / `describe`, pure Deno-std + `node:crypto` SHA-256 + native `fetch`; no npm). Verification (Node 24, `--experimental-strip-types`; tests at `_shared/ots_test.ts` for Deno CI + `/tmp/ots-node-test.ts` for the Node run):
- **Byte-exact round-trip (parse → re-serialize == canonical bytes) of 5 reference vectors** from `opentimestamps/javascript-opentimestamps/examples`: `incomplete` (175B pending), `two-calendars` (265B multi-op fork), `merkle2` (335B), `known-and-unknown-notary` (265B — UnknownAttestation preserved + cross-class attestation sort), `hello-world` (688B full Bitcoin-merkle attestation, block 358391). **10/10 pass.** This proves the serializer matches the consensus-critical wire format across every important shape.
- **Live stamp** against the public calendars: reached alice+bob+catallaxy, produced a 543B pending `.ots`, which **round-trips** and `describe`s as 3 pendings / 0 bitcoin; immediate `upgrade` is correctly a no-op (not yet anchored). Proof written to `/tmp/live.ots`.
- **Remaining gate (PM / time):** canonical `ots verify` accepting a stamped proof — needs Bitcoin anchoring (~hours) and the python `ots` client or opentimestamps.org drag-drop. This is the final independent acceptance gate.

**Still to build (Slice 2/3 proper):** the EF(s) that wire `ots.ts` to the `_ots_*` RPCs (`_ots_claim_unstamped_assets` → `stamp` → `_ots_mark_stamped`; cron `_ots_list_pending` → `upgrade` → `_ots_mark_confirmed`), the **bytea-over-PostgREST** encoding (pass the proof as `\x<hex>`; confirm at the deploy smoke), the block-height→UTC lookup for `attested_at`, and the health tool. EF deploy is PM-gated.

## Spike question
Can a Supabase Edge Function (Deno 2.1 line) produce/upgrade OpenTimestamps `.ots` proofs over a SHA-256 digest using `npm:opentimestamps@0.4.9`, or do we hand-roll a zero-dependency fetch-based client? This de-risks Slice 2 (stamp/verify EF) before any EF code is committed.

## Verdict

**Library `opentimestamps@0.4.9` under Deno EF = `likely_breaks` (medium confidence).** Two stacked, runtime-only failure modes that no doc-reading can settle:

1. **Entrypoint resolution (newly found in the adversarial pass).** `package.json` declares `"main": "open-timestamps.js"`, but **there is no `open-timestamps.js` at the package root** — the file that attaches the sub-modules (`OTS.DetachedTimestampFile`, `.Ops`, `.Context`, `.Timestamp`, `.Calendar`) onto the export is `index.js`. The lib works only if Deno's npm CJS resolver honours Node's `LOAD_AS_DIRECTORY → LOAD_INDEX` fallback for a missing named `main` (likely, **not docs-guaranteed**). If Deno instead lands on `src/open-timestamps.js` (which exports only the 11 public *functions* and none of the classes), `OTS.DetachedTimestampFile` is `undefined` → `TypeError` on the first line.
2. **`request`/`request-promise` transport.** This deprecated (since 2020) node:http-based stack is the **sole** calendar client in `src/calendar.js` (`POST /digest`, `GET /timestamp/<hex>`). Deno node-compat marks `node:http/https/net/tls` "partially supported"; `denoland/deno#27757` corrupts npm:request response decoding on Deno **2.1.5+** (Supabase EF is on **2.1.4**, one minor below — not biting *yet*, but fragile and a future EF Deno bump activates it). Also `this.timeout` is never initialised → stamp() has **no per-call timeout** → a hung calendar can approach the 150s wall/idle limit → 504.
3. **Lower-tier (real):** `Buffer` is **not** a Deno default global, but the lib uses bare `Buffer.from` / `stream instanceof Buffer` → must `globalThis.Buffer = (await import('node:buffer')).Buffer` **before** importing the lib.

**Crucially, even the "use the lib" path bypasses its transport** (both research arms converge on: do the calendar HTTP with native `fetch`, use the lib only for `fromHash` + `serializeToBytes` + `Context.StreamDeserialization`). So the lib's only safe contribution is **`.ots` serialization** — while still dragging `bitcore-lib@8.14.4` + `request` + `request-promise` + `moment-timezone` (large tz DB) into a 20 MB-capped EF bundle and gambling on the entrypoint resolution + Buffer shim.

**Hand-rolled zero-dependency fetch client = realistic and cleaner.** The wire protocol is trivial; the `.ots` format is well-specified; SHA-256 is native (`crypto.subtle`). MVP ~150–250 LoC (one calendar response per `.ots`, no merge — a legitimate, `ots verify`-acceptable proof); full multi-calendar merge ~400–600 LoC. It removes **every** Deno unknown (entrypoint, request stack, Buffer global, bitcore-lib bloat).

**EF constraints (all green, measured):** outbound HTTPS to the calendars works (443 open, no egress allowlist; only ports 25/587 blocked); `npm:` supported; Deno 2.1 line (2.5 upgrade closed not-planned Oct-2025); wall-clock 150s free / 400s paid; CPU 2s (excludes I/O); memory 256 MB; bundle 20 MB. A stamp = 3–4 fast network calls → fits comfortably. Set explicit per-calendar `AbortSignal.timeout` and fire in parallel.

## Recommendation (PL/CTO)

**Primary: HAND_ROLL the fetch-based stamp/upgrade + a minimal `.ots` serializer; do NOT ship `opentimestamps@0.4.9`.** Use the canonical `ots` CLI (or the lib in a local Deno scratch, if the probe shows it loads) **as a correctness oracle during development only.** Rationale:
- The lib's only safe contribution (serialization) is the *one* part the hand-roll must write anyway; everything else (its transport) is bypassed regardless.
- Removes all Deno-compat unknowns + every deprecated/heavy dep from legal-evidence infra (dependency hygiene matters more here — a `.ots` that `ots verify` rejects defeats rec k's probative purpose).
- Full control + unit-testable byte-fidelity against known-good vectors.

**Mandatory correctness gate for the hand-roll:** round-trip known-good `.ots` vectors (parse → re-serialize → byte-identical) **and** prove a freshly-stamped proof is accepted by the canonical `ots verify` (or opentimestamps.org drag-drop). A self-rolled cryptographic-proof serializer is not trusted until an independent verifier accepts its output.

**Alternative (if PM prefers): USE_LIB_WITH_SHIMS** — `globalThis.Buffer` shim + import + native-`fetch` calendar transport (lib only for `fromHash`/serialize). Cheaper to write *if* the probe passes, but carries the bundle/dep/entrypoint risk.

## Decisive empirical probe (settles both top failure modes, ~30s, offline, no deploy)

Run locally with a Deno on the **2.1.x** line (to match the EF). *Kept for reference only — the HAND_ROLL decision made this unnecessary; the engine was verified directly (see Outcome above).*

```ts
// otsprobe.ts  —  deno run -A otsprobe.ts
import { Buffer } from "node:buffer";
(globalThis as any).Buffer = Buffer;                 // required: lib uses bare Buffer
import OTS from "npm:opentimestamps@0.4.9";

// PROBE 1 — entrypoint/import shape (the newly-found killer):
const keys = Object.keys(OTS as any);
const hasClasses = !!(OTS as any).DetachedTimestampFile && !!(OTS as any).Ops && !!(OTS as any).Context;
console.log("KEYS:", keys.join(","));
console.log("PROBE1 import-shape:", hasClasses ? "PASS (resolved index.js)" : "FAIL (resolved bare main; classes missing)");

// PROBE 2 — module graph (incl. require('request-promise')) loads + build+serialize works offline:
try {
  const { DetachedTimestampFile, Ops } = OTS as any;
  const fdHash = new Uint8Array(32).fill(7);          // fake 32-byte sha256 digest
  const det = DetachedTimestampFile.fromHash(new Ops.OpSHA256(), fdHash);
  const bytes = det.serializeToBytes();               // pure, no network
  console.log("PROBE2 build+serialize:", bytes?.length, "bytes -> PASS");
} catch (e) {
  console.log("PROBE2 build+serialize: FAIL ->", (e as Error).message);
}
```

- **PASS** (lib viable as oracle / as Alternative): `KEYS` includes `DetachedTimestampFile,Ops,Context,Timestamp,Calendar`; PROBE1 PASS; PROBE2 prints a byte length + PASS.
- **PROBE1 FAIL** → import the subpath explicitly: `import OTS from "npm:opentimestamps@0.4.9/index.js"` and re-run.
- **PROBE2 FAIL** (`Buffer is not defined` / request-promise load error) → lib graph doesn't load under Deno node-compat → go straight to HAND_ROLL.
- Only if both pass: a 10-line throwaway EF doing `await OTS.stamp(det,{calendars:["https://alice.btc.calendar.opentimestamps.org"],m:1})` on the **deployed** runtime (local CLI Deno ≠ prod, per supabase/cli#504) settles whether `request` survives Deno 2.1.4 over the network.

## Slice 2 design (stamp EF) — engine-agnostic

Pipeline (single-consumer until `FOR UPDATE SKIP LOCKED` lands — ADR-0101 open item):
1. `service_role` calls `_ots_claim_unstamped_assets(limit)` → `[{id, sha256}]`.
2. Per asset: `fileDigest = hexToBytes(sha256)` (32 B). Build the OTS commitment exactly as the protocol requires: **`nonce = crypto.getRandomValues(new Uint8Array(16))`; `S = SHA256(fileDigest ‖ nonce)`** (the lib does `OpAppend(nonce)` then `OpSHA256`). Submit **`S`** (raw bytes) — never the bare file digest.
3. For each calendar (alice/bob/finney + catallaxy): `fetch(POST {cal}/digest, { body: S, headers: { Accept: "application/vnd.opentimestamps.v1" }, signal: AbortSignal.timeout(20_000) })`. 200 → `arrayBuffer()` is a bare serialized `Timestamp` (msg == S, no `.ots` magic). Tolerate partial calendar failures; require `m` ≥ 1–2 successes. Fire in parallel.
4. Build the full `.ots`: header magic (31 B) + `0x01` + fileHashOp tag `0x08` + fileDigest + the timestamp tree (`fileDigest --OpAppend(nonce)--> --OpSHA256--> S`, with each calendar's returned subtree under `S`). **MVP shortcut:** store **one calendar response per `.ots`** (no merge) — independently upgradeable/verifiable; merge is robustness, not correctness.
5. `_ots_mark_stamped(asset_id, ots_proof::bytea)` → flips to `pending`. **bytea-over-PostgREST edge:** supabase-js sends a JSON string; pass the proof as a `\\x<hex>` escaped string (Postgres `bytea` hex input) so it round-trips byte-exact. Validate by reading back via `_ots_list_pending` (which `encode(...,'base64')`s it) and comparing.
6. On hard failure: `_ots_mark_error(asset_id, error)` (status → `error` on the 5th attempt).

## Slice 3 design (upgrade cron) + the `attested_at` gap

1. `pg_cron` → `pg_net` → EF `upgrade`; EF calls `_ots_list_pending(limit)` → `[{id, sha256, ots_proof_b64}]`.
2. Per asset: decode base64 → parse `.ots` → for each `PendingAttestation`, `GET {cal}/timestamp/<hex(commitment)>` (commitment = the msg at the pending node). **200** → bare `Timestamp` ending in a `BitcoinBlockHeaderAttestation(blockHeight)`; merge into the tree, re-serialize. **404** → still pending (Bitcoin not yet mined, ~min–hours) → leave, retry next cron.
3. ⚠️ **`attested_at` is NOT in the proof.** `BitcoinBlockHeaderAttestation` commits only the **block height** (the merkle root in block N) — *not* a UTC. `_ots_mark_confirmed(id, proof, bitcoin_block, attested_at)` requires both. Getting the UTC needs a block-height→time source. The lib's `verify()` does this via bitcore-lib + esplora (**heavy — keep out of the EF**). **Use a lightweight HTTP lookup instead:** `blockstream.info/api/block-height/{N}` → block hash → `/block/{hash}` → `.timestamp` (or a maintained block-time table). This keeps bitcore-lib entirely out of the bundle. Treat the explorer as untrusted-but-non-probative (the *proof* is the Bitcoin attestation; the UTC is a convenience field for display/ordering — document that the attestation, not our stored UTC, is the legal anchor).
4. `_ots_mark_confirmed(id, upgradedProof, blockHeight, attestedUtc)` (CHECK PI1: confirmed ⇒ block+attested).
5. Health tool in the `get_lgpd_cron_health` mould (Slice 3).

## `.ots` wire format (hand-roll reference — verified vs python/js-opentimestamps source)
- **HEADER_MAGIC** (31 bytes, raw): `00 4f 70 65 6e 54 69 6d 65 73 74 61 6d 70 73 00 00 50 72 6f 6f 66 00 bf 89 e2 e8 84 e8 92 94` = `"\x00OpenTimestamps\x00\x00Proof\x00"` + `bf89e2e884e89294`.
- **MAJOR_VERSION** `0x01` (varuint). **fileHashOp** = 1 tag byte: SHA256 `0x08` (32 B digest), SHA1 `0x02`, RIPEMD160 `0x03`, KECCAK256 `0x67`. Then the **fileDigest** bytes raw.
- **Timestamp** = recursive `msg + ops-map + attestations-set`. On the wire: read a tag; `0xff` = fork (read next as real tag); `0x00` = an attestation follows; else it's an op (`f0` append [+varbytes arg], `f1` prepend [+varbytes], `f2` reverse, `f3` hexlify, `02/03/08/67` crypt [no arg]) then recurse. Linear chains write the op tag directly (no `0xff`); multiple branches fork with `0xff`, last edge no `0xff`.
- **Attestation** (after `0x00`): 8-byte TAG + `varbytes(payload)`. `PendingAttestation` TAG `83dfe30d2ef90c8e`, payload = `varbytes(uri_utf8)`. `BitcoinBlockHeaderAttestation` TAG `0588960d73d71901`, payload = `varuint(blockHeight)`. Unknown tags preserved as raw varbytes.
- **varuint** = LEB128 (low 7 bits + `0x80` continuation). **varbytes** = `varuint(len) + bytes`. Calendar responses cap at 10000 bytes; submit digest cap 64 bytes.

## Open decisions (PM)
1. **Slice 2 engine:** HAND_ROLL (rec) vs USE_LIB_WITH_SHIMS.
2. **Execution:** this session's sandbox blocks local `npm install` / Deno install → building+**verifying** Slice 2 needs either the PM running the probe (+ later EF deploy) via `!`, or a local-toolchain permission, or me drafting code the PM runs/deploys.

## Sources
Workflow `wf_dda4ebd6-078` arms cite: unpkg/GitHub-raw `opentimestamps@0.4.9` + `python-opentimestamps` source; Deno node-compat docs; Supabase EF limits/changelog; `denoland/deno#27757`, `supabase/cli#504`, `bitpay/bitcore#1454`. Full structured output archived with the run.
