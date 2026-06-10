// _shared/ots.ts — zero-dependency OpenTimestamps client for Deno / Supabase Edge Functions.
//
// #569 Slice 2/3 (ADR-0101). Produces + upgrades `.ots` DetachedTimestampFile proofs over a
// SHA-256 digest. NO npm deps: SHA-256 via node:crypto (Deno-fully-supported built-in), calendar
// HTTP via native fetch. Mirrors the consensus-critical wire format of python-opentimestamps
// (core/serialize.py, timestamp.py, op.py, notary.py) byte-for-byte — see SPEC_569_S0_OTS_DENO_SPIKE.md.
//
// The work never leaves the Núcleo: only the digest is submitted to public calendars (digest-only, ADR-0101).

import { createHash } from "node:crypto";

export const DEFAULT_CALENDARS = [
  "https://alice.btc.calendar.opentimestamps.org",
  "https://bob.btc.calendar.opentimestamps.org",
  "https://finney.btc.calendar.opentimestamps.org",
  "https://btc.calendar.catallaxy.com",
];

// DetachedTimestampFile.HEADER_MAGIC (31 bytes) — "\x00OpenTimestamps\x00\x00Proof\x00" + bf89e2e884e89294
const HEADER_MAGIC = new Uint8Array([
  0x00, 0x4f, 0x70, 0x65, 0x6e, 0x54, 0x69, 0x6d, 0x65, 0x73, 0x74, 0x61, 0x6d, 0x70, 0x73,
  0x00, 0x00, 0x50, 0x72, 0x6f, 0x6f, 0x66, 0x00, 0xbf, 0x89, 0xe2, 0xe8, 0x84, 0xe8, 0x92, 0x94,
]);
const MAJOR_VERSION = 1;

// op tags (op.py)
const OP_APPEND = 0xf0, OP_PREPEND = 0xf1, OP_REVERSE = 0xf2, OP_HEXLIFY = 0xf3;
const OP_SHA1 = 0x02, OP_RIPEMD160 = 0x03, OP_SHA256 = 0x08, OP_KECCAK256 = 0x67;
const MAX_RESULT_LENGTH = 4096;
const CALENDAR_MAX_RESPONSE = 10000; // calendar.js ExceededSizeError threshold

// attestation tags (notary.py) — 8 bytes each
const TAG_PENDING = hexToBytes("83dfe30d2ef90c8e");
const TAG_BITCOIN = hexToBytes("0588960d73d71901");
const TAG_LITECOIN = hexToBytes("06869a0d73d71b45");
const ATT_MAX_PAYLOAD = 8192;
const URI_MAX = 1000;

// ============================================================================
// byte helpers
// ============================================================================
export function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error("odd-length hex");
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
export function bytesToHex(b: Uint8Array): string {
  let s = "";
  for (let i = 0; i < b.length; i++) s += b[i].toString(16).padStart(2, "0");
  return s;
}
function concat(...parts: Uint8Array[]): Uint8Array {
  let n = 0;
  for (const p of parts) n += p.length;
  const out = new Uint8Array(n);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}
function eqBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
function cmpBytes(a: Uint8Array, b: Uint8Array): number {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) { if (a[i] !== b[i]) return a[i] - b[i]; }
  return a.length - b.length;
}
function sha256(msg: Uint8Array): Uint8Array {
  return new Uint8Array(createHash("sha256").update(msg).digest());
}

// ============================================================================
// Writer / Reader (serialize.py: LEB128 varuint, varbytes = varuint(len)+bytes)
// ============================================================================
class Writer {
  private chunks: number[] = [];
  writeByte(b: number) { this.chunks.push(b & 0xff); }
  writeBytes(b: Uint8Array) { for (let i = 0; i < b.length; i++) this.chunks.push(b[i]); }
  writeVaruint(value: number) {
    if (value === 0) { this.chunks.push(0x00); return; }
    while (value !== 0) {
      let b = value & 0x7f;
      if (value > 0x7f) b |= 0x80;
      this.chunks.push(b);
      if (value <= 0x7f) break;
      value = Math.floor(value / 128);
    }
  }
  writeVarbytes(b: Uint8Array) { this.writeVaruint(b.length); this.writeBytes(b); }
  getBytes(): Uint8Array { return new Uint8Array(this.chunks); }
}

class Reader {
  pos = 0;
  private buf: Uint8Array;
  constructor(buf: Uint8Array) { this.buf = buf; }
  private need(n: number) { if (this.pos + n > this.buf.length) throw new Error("TruncationError"); }
  readByte(): number { this.need(1); return this.buf[this.pos++]; }
  readBytes(n: number): Uint8Array { this.need(n); const r = this.buf.slice(this.pos, this.pos + n); this.pos += n; return r; }
  readVaruint(): number {
    let value = 0, shift = 0;
    for (;;) {
      const b = this.readByte();
      value += (b & 0x7f) * Math.pow(2, shift);
      if (!(b & 0x80)) break;
      shift += 7;
    }
    return value;
  }
  readVarbytes(maxLen: number, minLen = 0): Uint8Array {
    const l = this.readVaruint();
    if (l > maxLen) throw new Error(`varbytes max length exceeded: ${l} > ${maxLen}`);
    if (l < minLen) throw new Error(`varbytes min length not met: ${l} < ${minLen}`);
    return this.readBytes(l);
  }
  assertMagic(magic: Uint8Array) {
    const got = this.readBytes(magic.length);
    if (!eqBytes(got, magic)) throw new Error("BadMagicError");
  }
  assertEof() { if (this.pos !== this.buf.length) throw new Error("TrailingGarbageError"); }
  eof(): boolean { return this.pos >= this.buf.length; }
}

// ============================================================================
// Op (op.py)
// ============================================================================
type Op =
  | { tag: number; arg: Uint8Array } // binary: append/prepend
  | { tag: number };                  // unary: sha256/sha1/ripemd160/keccak256/reverse/hexlify

function isBinary(tag: number) { return tag === OP_APPEND || tag === OP_PREPEND; }

function opApply(op: Op, msg: Uint8Array): Uint8Array {
  switch (op.tag) {
    case OP_APPEND: return concat(msg, (op as any).arg);
    case OP_PREPEND: return concat((op as any).arg, msg);
    case OP_SHA256: return sha256(msg);
    case OP_REVERSE: { const r = msg.slice(); r.reverse(); return r; }
    case OP_HEXLIFY: return new TextEncoder().encode(bytesToHex(msg));
    // sha1/ripemd160/keccak256 are not produced by Bitcoin OTS paths; supported on read only if needed.
    case OP_SHA1: return new Uint8Array(createHash("sha1").update(msg).digest());
    case OP_RIPEMD160: return new Uint8Array(createHash("ripemd160").update(msg).digest());
    default: throw new Error(`opApply: unsupported op tag 0x${op.tag.toString(16)}`);
  }
}

function opSerialize(w: Writer, op: Op) {
  w.writeByte(op.tag);
  if (isBinary(op.tag)) w.writeVarbytes((op as any).arg);
}

function opDeserialize(r: Reader, tag: number): Op {
  switch (tag) {
    case OP_APPEND: case OP_PREPEND:
      return { tag, arg: r.readVarbytes(MAX_RESULT_LENGTH, 1) };
    case OP_SHA1: case OP_RIPEMD160: case OP_SHA256: case OP_KECCAK256:
    case OP_REVERSE: case OP_HEXLIFY:
      return { tag };
    default:
      throw new Error(`Unknown operation tag 0x${tag.toString(16)}`);
  }
}

// Op ordering (Op.__lt__): by TAG byte, then by tuple(self) = (arg,) for binary, () for unary.
function opCompare(a: Op, b: Op): number {
  if (a.tag !== b.tag) return a.tag - b.tag;
  const aa = (a as any).arg as Uint8Array | undefined;
  const bb = (b as any).arg as Uint8Array | undefined;
  if (aa && bb) return cmpBytes(aa, bb);
  return 0;
}
function opEqual(a: Op, b: Op): boolean { return opCompare(a, b) === 0; }

// ============================================================================
// Attestation (notary.py)
// ============================================================================
type Attestation =
  | { kind: "pending"; uri: string }
  | { kind: "bitcoin"; height: number }
  | { kind: "litecoin"; height: number }
  | { kind: "unknown"; tag: Uint8Array; payload: Uint8Array };

function attTag(a: Attestation): Uint8Array {
  switch (a.kind) {
    case "pending": return TAG_PENDING;
    case "bitcoin": return TAG_BITCOIN;
    case "litecoin": return TAG_LITECOIN;
    case "unknown": return a.tag;
  }
}

function attSerialize(w: Writer, a: Attestation) {
  w.writeBytes(attTag(a));
  const pw = new Writer();
  switch (a.kind) {
    case "pending": pw.writeVarbytes(new TextEncoder().encode(a.uri)); break;
    case "bitcoin": case "litecoin": pw.writeVaruint(a.height); break;
    case "unknown": pw.writeBytes(a.payload); break;
  }
  w.writeVarbytes(pw.getBytes());
}

function attDeserialize(r: Reader): Attestation {
  const tag = r.readBytes(8);
  const payload = r.readVarbytes(ATT_MAX_PAYLOAD);
  const pr = new Reader(payload);
  if (eqBytes(tag, TAG_PENDING)) {
    const uri = new TextDecoder().decode(pr.readVarbytes(URI_MAX));
    pr.assertEof();
    return { kind: "pending", uri };
  } else if (eqBytes(tag, TAG_BITCOIN)) {
    const height = pr.readVaruint(); pr.assertEof();
    return { kind: "bitcoin", height };
  } else if (eqBytes(tag, TAG_LITECOIN)) {
    const height = pr.readVaruint(); pr.assertEof();
    return { kind: "litecoin", height };
  }
  return { kind: "unknown", tag, payload };
}

// TimeAttestation.__lt__: cross-class by TAG; same-class by uri (pending) / height (bitcoin/litecoin) / (tag,payload) (unknown).
function attCompare(a: Attestation, b: Attestation): number {
  const t = cmpBytes(attTag(a), attTag(b));
  if (t !== 0) return t;
  if (a.kind === "pending" && b.kind === "pending") return a.uri < b.uri ? -1 : a.uri > b.uri ? 1 : 0;
  if ((a.kind === "bitcoin" || a.kind === "litecoin") && (b.kind === "bitcoin" || b.kind === "litecoin")) return a.height - b.height;
  if (a.kind === "unknown" && b.kind === "unknown") return cmpBytes(a.payload, b.payload);
  return 0;
}
function attEqual(a: Attestation, b: Attestation): boolean { return attCompare(a, b) === 0; }

// ============================================================================
// Timestamp (timestamp.py)
// ============================================================================
class Timestamp {
  msg: Uint8Array;
  attestations: Attestation[] = [];
  ops: { op: Op; child: Timestamp }[] = [];
  constructor(msg: Uint8Array) { this.msg = msg; }

  // Timestamp.serialize — replicates the 0xff/0x00 fork layout exactly (timestamp.py:101-128).
  serialize(w: Writer) {
    if (this.attestations.length === 0 && this.ops.length === 0) throw new Error("empty timestamp");
    const atts = [...this.attestations].sort(attCompare);
    if (atts.length > 1) {
      for (let i = 0; i < atts.length - 1; i++) { w.writeBytes(new Uint8Array([0xff, 0x00])); attSerialize(w, atts[i]); }
    }
    if (this.ops.length === 0) {
      w.writeByte(0x00); attSerialize(w, atts[atts.length - 1]);
    } else {
      if (atts.length > 0) { w.writeBytes(new Uint8Array([0xff, 0x00])); attSerialize(w, atts[atts.length - 1]); }
      const ops = [...this.ops].sort((x, y) => opCompare(x.op, y.op));
      for (let i = 0; i < ops.length - 1; i++) { w.writeByte(0xff); opSerialize(w, ops[i].op); ops[i].child.serialize(w); }
      const last = ops[ops.length - 1];
      opSerialize(w, last.op); last.child.serialize(w);
    }
  }

  static deserialize(r: Reader, initialMsg: Uint8Array, recursion = 256): Timestamp {
    if (recursion <= 0) throw new Error("RecursionLimitError");
    const self = new Timestamp(initialMsg);
    const handle = (tag: number) => {
      if (tag === 0x00) {
        self.attestations.push(attDeserialize(r));
      } else {
        const op = opDeserialize(r, tag);
        const result = opApply(op, initialMsg);
        const child = Timestamp.deserialize(r, result, recursion - 1);
        self.ops.push({ op, child });
      }
    };
    let tag = r.readByte();
    while (tag === 0xff) { handle(r.readByte()); tag = r.readByte(); }
    handle(tag);
    return self;
  }

  // Timestamp.merge — same msg required; union attestations; merge ops recursively (timestamp.py:84-99).
  merge(other: Timestamp) {
    if (!eqBytes(this.msg, other.msg)) throw new Error("merge: different messages");
    for (const oa of other.attestations) {
      if (!this.attestations.some((a) => attEqual(a, oa))) this.attestations.push(oa);
    }
    for (const oe of other.ops) {
      const mine = this.ops.find((e) => opEqual(e.op, oe.op));
      if (mine) mine.child.merge(oe.child);
      else this.ops.push({ op: oe.op, child: oe.child });
    }
  }

  // walk every (nodeMsg, attestation)
  *allAttestations(): Generator<{ msg: Uint8Array; att: Attestation }> {
    for (const a of this.attestations) yield { msg: this.msg, att: a };
    for (const e of this.ops) yield* e.child.allAttestations();
  }

  // find the node with the given msg (first match, DFS)
  findNode(msg: Uint8Array): Timestamp | null {
    if (eqBytes(this.msg, msg)) return this;
    for (const e of this.ops) { const n = e.child.findNode(msg); if (n) return n; }
    return null;
  }
}

// ============================================================================
// DetachedTimestampFile (.ots)
// ============================================================================
export interface DetachedTimestamp { fileHashOpTag: number; timestamp: Timestamp; }

function serializeDetached(fileHashOpTag: number, timestamp: Timestamp): Uint8Array {
  const w = new Writer();
  w.writeBytes(HEADER_MAGIC);
  w.writeByte(MAJOR_VERSION);
  w.writeByte(fileHashOpTag);          // CryptOp.serialize = 1 tag byte
  w.writeBytes(timestamp.msg);          // the file digest
  timestamp.serialize(w);
  return w.getBytes();
}

function deserializeDetached(bytes: Uint8Array): DetachedTimestamp {
  const r = new Reader(bytes);
  r.assertMagic(HEADER_MAGIC);
  const major = r.readByte();
  if (major !== MAJOR_VERSION) throw new Error(`Unsupported major version ${major}`);
  const fileHashOpTag = r.readByte();
  const digestLen = fileHashOpTag === OP_SHA256 ? 32 : fileHashOpTag === OP_SHA1 || fileHashOpTag === OP_RIPEMD160 ? 20 : fileHashOpTag === OP_KECCAK256 ? 32 : -1;
  if (digestLen < 0) throw new Error(`unexpected file_hash_op tag 0x${fileHashOpTag.toString(16)}`);
  const fileDigest = r.readBytes(digestLen);
  const timestamp = Timestamp.deserialize(r, fileDigest);
  r.assertEof();
  return { fileHashOpTag, timestamp };
}

// ============================================================================
// Public API: stamp + upgrade
// ============================================================================

export interface StampResult { otsBytes: Uint8Array; calendarsOk: string[]; submittedDigest: string; }

/**
 * Stamp a 32-byte SHA-256 file digest: nonce-append + SHA-256 → submit to calendars → build the .ots.
 * Returns the serialized `.ots` (pending, not yet Bitcoin-anchored) + which calendars responded.
 */
export async function stamp(
  fileDigest: Uint8Array,
  opts: { calendars?: string[]; m?: number; timeoutMs?: number } = {},
): Promise<StampResult> {
  if (fileDigest.length !== 32) throw new Error("stamp: expected a 32-byte SHA-256 digest");
  const calendars = opts.calendars ?? DEFAULT_CALENDARS;
  const m = opts.m ?? Math.min(2, calendars.length);
  const timeoutMs = opts.timeoutMs ?? 20000;

  // tree: fileDigest --OpAppend(nonce16)--> (fileDigest‖nonce) --OpSHA256--> S
  const nonce = crypto.getRandomValues(new Uint8Array(16));
  const appended = concat(fileDigest, nonce);
  const S = sha256(appended);

  const root = new Timestamp(fileDigest);
  const t1 = new Timestamp(appended);
  root.ops.push({ op: { tag: OP_APPEND, arg: nonce }, child: t1 });
  const tS = new Timestamp(S);
  t1.ops.push({ op: { tag: OP_SHA256 }, child: tS });

  const calendarsOk: string[] = [];
  await Promise.all(calendars.map(async (cal) => {
    try {
      const resp = await fetch(`${cal.replace(/\/$/, "")}/digest`, {
        method: "POST",
        headers: { "Accept": "application/vnd.opentimestamps.v1", "Content-Type": "application/x-www-form-urlencoded" },
        body: S,
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const buf = new Uint8Array(await resp.arrayBuffer());
      if (buf.length > CALENDAR_MAX_RESPONSE) throw new Error("calendar response too large");
      const calTs = Timestamp.deserialize(new Reader(buf), S); // rooted at S
      tS.merge(calTs);
      calendarsOk.push(cal);
    } catch (_e) { /* tolerate per-calendar failure; require m successes below */ }
  }));

  if (calendarsOk.length < m) throw new Error(`stamp: only ${calendarsOk.length}/${m} calendars responded`);
  return { otsBytes: serializeDetached(OP_SHA256, root), calendarsOk, submittedDigest: bytesToHex(S) };
}

export interface UpgradeResult {
  otsBytes: Uint8Array;
  changed: boolean;
  confirmed: boolean;
  bitcoinBlockHeight: number | null; // attested UTC requires a block-height→time lookup (Slice 3 cron)
}

/**
 * Upgrade a pending `.ots`: for each PendingAttestation, GET the calendar's /timestamp/<commitment>.
 * 200 → merge the Bitcoin attestation; 404 → still pending. Returns the (possibly) upgraded `.ots`.
 */
export async function upgrade(
  otsBytes: Uint8Array,
  opts: { timeoutMs?: number; calendarAllowlist?: string[] } = {},
): Promise<UpgradeResult> {
  const timeoutMs = opts.timeoutMs ?? 20000;
  const allow = opts.calendarAllowlist ?? DEFAULT_CALENDARS;
  const { fileHashOpTag, timestamp } = deserializeDetached(otsBytes);

  // collect pending (nodeMsg, uri) before mutating
  const pendings: { msg: Uint8Array; uri: string }[] = [];
  for (const { msg, att } of timestamp.allAttestations()) {
    if (att.kind === "pending") pendings.push({ msg, uri: att.uri });
  }

  let changed = false;
  for (const p of pendings) {
    const base = p.uri.replace(/\/$/, "");
    // only follow calendars we trust (the pending URI is attacker-influenceable in general; here it is our own submit set)
    if (!allow.some((c) => base === c.replace(/\/$/, ""))) continue;
    try {
      const resp = await fetch(`${base}/timestamp/${bytesToHex(p.msg)}`, {
        headers: { "Accept": "application/vnd.opentimestamps.v1" },
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (resp.status === 404) continue; // not yet anchored
      if (!resp.ok) continue;
      const buf = new Uint8Array(await resp.arrayBuffer());
      if (buf.length > CALENDAR_MAX_RESPONSE) continue;
      const upg = Timestamp.deserialize(new Reader(buf), p.msg); // rooted at the commitment
      const node = timestamp.findNode(p.msg);
      if (node) { node.merge(upg); changed = true; }
    } catch (_e) { /* leave pending; retry next pass */ }
  }

  let height: number | null = null;
  for (const { att } of timestamp.allAttestations()) {
    if (att.kind === "bitcoin") height = height === null ? att.height : Math.min(height, att.height);
  }

  return {
    otsBytes: changed ? serializeDetached(fileHashOpTag, timestamp) : otsBytes,
    changed,
    confirmed: height !== null,
    bitcoinBlockHeight: height,
  };
}

// info-ish: list attestations in a stored proof (for health/debug, no network)
export function describe(otsBytes: Uint8Array): { fileDigest: string; pending: string[]; bitcoinHeights: number[] } {
  const { timestamp } = deserializeDetached(otsBytes);
  const pending: string[] = [];
  const bitcoinHeights: number[] = [];
  for (const { att } of timestamp.allAttestations()) {
    if (att.kind === "pending") pending.push(att.uri);
    else if (att.kind === "bitcoin") bitcoinHeights.push(att.height);
  }
  return { fileDigest: bytesToHex(timestamp.msg), pending, bitcoinHeights };
}

export const _internal = { Writer, Reader, Timestamp, serializeDetached, deserializeDetached, sha256, HEADER_MAGIC };
