/**
 * #1000 — VEP reconciliation quick-chips no pipeline de seleção (/admin/selection).
 *
 * 5 chips mutuamente exclusivos derivados de `status` + `vep_recon.status_raw` (ambos já
 * em cada linha de get_selection_dashboard) — FRONTEND-ONLY, sem novo RPC e sem escrever
 * estado VEP. Mesma taxonomia dos buckets da /admin/vep-reconciliation (#1001), para as
 * duas telas não divergirem.
 *
 * Offline-only (static source + i18n parity). Sem DB gating. O `lint:i18n` NÃO cobre
 * selection.astro, então a paridade das chaves destes chips precisa deste guard.
 *
 * Register in BOTH the "test" and "test:contracts" whitelists in package.json (#1109).
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();
const PAGE = resolve(ROOT, 'src/pages/admin/selection.astro');
const DICTS = ['pt-BR', 'en-US', 'es-LATAM'].map((l) => resolve(ROOT, `src/i18n/${l}.ts`));

const CHIP_KEYS = [
  'vepApprovedNeedsExtend',
  'vepRejectedNeedsDeny',
  'vepOfferWaiting',
  'vepOfferAccepted',
  'vepOfferExpired',
];

test('#1000 i18n parity: 5 chip labels + 5 hints exist in all 3 dicts', () => {
  for (const d of DICTS) {
    const src = readFileSync(d, 'utf8');
    for (const k of CHIP_KEYS) {
      assert.match(src, new RegExp(`'admin\\.selection\\.${k}'`), `${d}: label admin.selection.${k}`);
      assert.match(src, new RegExp(`'admin\\.selection\\.${k}Hint'`), `${d}: hint admin.selection.${k}Hint`);
    }
  }
});

test('#1000 static: the 5 filter-vep-chip buttons are wired with the expected data-vep values', () => {
  const src = readFileSync(PAGE, 'utf8');
  for (const v of ['approved_needs_extend', 'rejected_needs_deny', 'offer_waiting', 'offer_accepted', 'offer_expired']) {
    assert.match(src, new RegExp(`filter-vep-chip[\\s\\S]{0,240}?data-vep="${v}"`), `chip data-vep="${v}" present`);
  }
});

test('#1000 static: applyFilters derives chips from status + vep_recon.status_raw (correct predicates)', () => {
  const src = readFileSync(PAGE, 'utf8');
  assert.match(src, /let filterVep/, 'filterVep state var declared');
  assert.match(src, /const vs = r\.vep_recon\?\.status_raw/, 'reads vep_recon.status_raw');
  assert.match(src, /approved_needs_extend'\)\s*vepMatch = st === 'approved' && vs === 'Submitted'/,
    'approved_needs_extend = approved + Submitted');
  assert.match(src, /rejected_needs_deny'\)\s*vepMatch = st === 'rejected' && \['Submitted', 'Active', 'OfferExtended'\]\.includes\(vs\)/,
    'rejected_needs_deny = rejected + VEP-open set');
  assert.match(src, /offer_waiting'\)\s*vepMatch = vs === 'OfferExtended'/, 'offer_waiting = OfferExtended');
  assert.match(src, /offer_accepted'\)\s*vepMatch = st === 'approved' && vs === 'Active'/, 'offer_accepted = approved + Active');
  assert.match(src, /offer_expired'\)\s*vepMatch = \['OfferExpired', 'Expired'\]\.includes\(vs\)/, 'offer_expired = OfferExpired/Expired');
});

test('#1000 static: chips are read-only — no VEP-state RPC invoked from the chip handler', () => {
  const src = readFileSync(PAGE, 'utf8');
  // The chip block must not call mark_vep_reconciled or any VEP write from its handler.
  const chipHandler = src.slice(src.indexOf("filter-vep-chip'"));
  const handlerSlice = chipHandler.slice(0, 1200);
  assert.doesNotMatch(handlerSlice, /mark_vep_reconciled|\.rpc\(/, 'chip handler performs no RPC/VEP write');
});
