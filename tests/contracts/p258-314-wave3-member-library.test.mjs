import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

/**
 * #315 Wave 3 (#314) — Member-facing biblioteca contract
 *
 * Pins the contract between the React library component and the Wave 1a M3 RPC
 * `list_governance_library(p_filters jsonb)`. Forward-defense regressions lock:
 * - PII leak (file_id / drive_url / content / pdf_url MUST NOT render);
 * - retired `documents` tab in GovernancePage MUST NOT reappear;
 * - legacy `get_governance_documents` RPC MUST NOT be called;
 * - DocumentsList.tsx MUST stay deleted (single canonical surface).
 *
 * Pattern: static file assertions only (offline) — no DB env required.
 */

const COMPONENT_PATH = 'src/components/governance/GovernanceLibrary.tsx';
const PAGE_PATH = 'src/pages/governance/documents/index.astro';
const PAGE_EN_REDIRECT = 'src/pages/en/governance/documents/index.astro';
const PAGE_ES_REDIRECT = 'src/pages/es/governance/documents/index.astro';
const ALIAS_PT = 'src/pages/documents.astro';
const ALIAS_EN = 'src/pages/en/documents.astro';
const ALIAS_ES = 'src/pages/es/documents.astro';
const GOV_PAGE_TSX = 'src/components/governance/GovernancePage.tsx';
const LEGACY_LIST_TSX = 'src/components/governance/DocumentsList.tsx';
const PT_BR_DICT = 'src/i18n/pt-BR.ts';
const EN_US_DICT = 'src/i18n/en-US.ts';
const ES_LATAM_DICT = 'src/i18n/es-LATAM.ts';

const COMPONENT_SRC = existsSync(COMPONENT_PATH) ? readFileSync(COMPONENT_PATH, 'utf8') : '';
// Strip block + line comments so PII-leak forward-defense doesn't false-positive
// on the docstring listing forbidden keywords as a reminder.
const COMPONENT_CODE = COMPONENT_SRC
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .split('\n')
  .map((l) => l.replace(/(^|[^:])\/\/.*$/, '$1'))
  .join('\n');
const PAGE_SRC = existsSync(PAGE_PATH) ? readFileSync(PAGE_PATH, 'utf8') : '';
const GOV_PAGE_SRC = existsSync(GOV_PAGE_TSX) ? readFileSync(GOV_PAGE_TSX, 'utf8') : '';
const PT = existsSync(PT_BR_DICT) ? readFileSync(PT_BR_DICT, 'utf8') : '';
const EN = existsSync(EN_US_DICT) ? readFileSync(EN_US_DICT, 'utf8') : '';
const ES = existsSync(ES_LATAM_DICT) ? readFileSync(ES_LATAM_DICT, 'utf8') : '';

const DOC_TYPES = [
  'manual',
  'editorial_guide',
  'governance_guideline',
  'policy',
  'volunteer_term_template',
  'volunteer_addendum',
  'cooperation_agreement',
  'cooperation_addendum',
  'project_charter',
  'executive_summary',
  'framework_reference',
];
const STATUSES = ['draft', 'pending_proposer_consent', 'under_review', 'approved', 'active', 'superseded', 'withdrawn', 'revoked'];
const VIS_CLASSES = ['public', 'active_members', 'legal_scoped', 'admin_only', 'audit_restricted'];
const ACK_MODES = ['informational', 'binding', 'legal_signature'];

describe('p258 #314 — Wave 3 member library contract', () => {
  describe('file presence + headers', () => {
    it('GovernanceLibrary.tsx exists', () => {
      assert.ok(existsSync(COMPONENT_PATH), `expected ${COMPONENT_PATH}`);
      assert.ok(COMPONENT_SRC.length > 0, 'component must not be empty');
    });

    it('canonical page /governance/documents/index.astro exists and mounts the component', () => {
      assert.ok(existsSync(PAGE_PATH), `expected ${PAGE_PATH}`);
      assert.match(PAGE_SRC, /import GovernanceLibrary from '\.\.\/\.\.\/\.\.\/components\/governance\/GovernanceLibrary'/);
      assert.match(PAGE_SRC, /<GovernanceLibrary\s+client:load/);
    });

    it('EN locale redirect page exists', () => {
      assert.ok(existsSync(PAGE_EN_REDIRECT), `expected ${PAGE_EN_REDIRECT}`);
      const src = readFileSync(PAGE_EN_REDIRECT, 'utf8');
      assert.match(src, /Astro\.redirect\('\/governance\/documents'/);
      assert.match(src, /lang=en-US/);
    });

    it('ES locale redirect page exists', () => {
      assert.ok(existsSync(PAGE_ES_REDIRECT), `expected ${PAGE_ES_REDIRECT}`);
      const src = readFileSync(PAGE_ES_REDIRECT, 'utf8');
      assert.match(src, /Astro\.redirect\('\/governance\/documents'/);
      assert.match(src, /lang=es-LATAM/);
    });

    it('component header references #315 Wave 3 (#314) + the RPC contract', () => {
      assert.match(COMPONENT_SRC, /#315/);
      assert.match(COMPONENT_SRC, /#314/);
      assert.match(COMPONENT_SRC, /list_governance_library/);
    });
  });

  describe('/documents alias (P2-Q3 ratified Wave 3)', () => {
    it('PT canonical alias exists and 301-redirects to /governance/documents', () => {
      assert.ok(existsSync(ALIAS_PT), `expected ${ALIAS_PT}`);
      const src = readFileSync(ALIAS_PT, 'utf8');
      assert.match(src, /Astro\.redirect\('\/governance\/documents'/);
      assert.match(src, /,\s*301\s*\)/);
    });

    it('EN alias exists and 301-redirects to /en/governance/documents', () => {
      assert.ok(existsSync(ALIAS_EN), `expected ${ALIAS_EN}`);
      const src = readFileSync(ALIAS_EN, 'utf8');
      assert.match(src, /Astro\.redirect\('\/en\/governance\/documents'/);
      assert.match(src, /,\s*301\s*\)/);
    });

    it('ES alias exists and 301-redirects to /es/governance/documents', () => {
      assert.ok(existsSync(ALIAS_ES), `expected ${ALIAS_ES}`);
      const src = readFileSync(ALIAS_ES, 'utf8');
      assert.match(src, /Astro\.redirect\('\/es\/governance\/documents'/);
      assert.match(src, /,\s*301\s*\)/);
    });
  });

  describe('RPC contract — list_governance_library(p_filters jsonb)', () => {
    it('calls list_governance_library with p_filters object', () => {
      assert.match(COMPONENT_SRC, /sb\.rpc\('list_governance_library',\s*\{\s*p_filters:\s*filters\s*\}\)/);
    });

    it('reads documents from res.data.documents array', () => {
      assert.match(COMPONENT_SRC, /Array\.isArray\(res\.data\?\.documents\)/);
      assert.match(COMPONENT_SRC, /res\.data\.documents/);
    });

    it('filters payload only includes doc_type and status keys', () => {
      assert.match(COMPONENT_SRC, /if \(docType\) filters\.doc_type = docType/);
      assert.match(COMPONENT_SRC, /if \(status\) filters\.status = status/);
      // No other keys (visibility/legal scoping is server-side).
    });
  });

  describe('select dropdowns + LibraryDoc payload shape', () => {
    it('11 doc_type filter options match governance_documents_doc_type_check', () => {
      const m = COMPONENT_SRC.match(/const DOC_TYPE_FILTER_OPTIONS:[^=]*=\s*\[([\s\S]*?)\];/);
      assert.ok(m, 'DOC_TYPE_FILTER_OPTIONS must be declared');
      for (const dt of DOC_TYPES) {
        assert.match(m[1], new RegExp(`'${dt}'`), `missing ${dt}`);
      }
    });

    it('LibraryDoc type lists exactly the 12 RPC payload fields per Wave 1a M3', () => {
      const t = COMPONENT_SRC.match(/type LibraryDoc = \{([\s\S]*?)\};/);
      assert.ok(t, 'LibraryDoc type must be declared');
      const expected = [
        'id',
        'title',
        'description',
        'doc_type',
        'status',
        'visibility_class',
        'acknowledgement_mode',
        'effective_from',
        'effective_until',
        'approved_at',
        'current_ratified_version_id',
        'current_version_id',
      ];
      for (const f of expected) {
        assert.match(t[1], new RegExp(`${f}:`), `LibraryDoc missing field ${f}`);
      }
    });
  });

  describe('forward-defense — no PII leak (P0-Q8)', () => {
    // Tests run on COMPONENT_CODE (comments stripped) so that header docstring
    // listing the forbidden keywords as a reminder does not false-positive.
    it('component code MUST NOT reference file_id', () => {
      assert.doesNotMatch(COMPONENT_CODE, /\bfile_id\b/);
    });

    it('component code MUST NOT reference drive_url', () => {
      assert.doesNotMatch(COMPONENT_CODE, /\bdrive_url\b/);
    });

    it('component code MUST NOT reference content_html (reader page handles that — biblioteca only)', () => {
      assert.doesNotMatch(COMPONENT_CODE, /\bcontent_html\b/);
    });

    it('component code MUST NOT reference pdf_url', () => {
      assert.doesNotMatch(COMPONENT_CODE, /\bpdf_url\b/);
    });

    it('component MUST NOT do direct table SELECT on governance_documents (RPC-only)', () => {
      assert.doesNotMatch(COMPONENT_CODE, /\.from\(['"`]governance_documents['"`]\)/);
      assert.doesNotMatch(COMPONENT_CODE, /\.from\(['"`]document_versions['"`]\)/);
    });
  });

  describe('forward-defense — retired legacy surfaces (single-source guarantee)', () => {
    it('DocumentsList.tsx MUST be deleted (no other consumer; biblioteca is the canonical surface)', () => {
      assert.ok(!existsSync(LEGACY_LIST_TSX), `DocumentsList.tsx should NOT exist at ${LEGACY_LIST_TSX} — Wave 3 retired it`);
    });

    it('GovernancePage.tsx MUST NOT import DocumentsList', () => {
      assert.doesNotMatch(GOV_PAGE_SRC, /import DocumentsList from/);
      assert.doesNotMatch(GOV_PAGE_SRC, /<DocumentsList\b/);
    });

    it('GovernancePage.tsx MUST NOT call the legacy get_governance_documents RPC (replaced by list_governance_library)', () => {
      assert.doesNotMatch(GOV_PAGE_SRC, /sb\.rpc\(['"`]get_governance_documents['"`]/);
    });

    it('GovernancePage.tsx View type MUST NOT include "documents" (tab retired)', () => {
      const viewType = GOV_PAGE_SRC.match(/type View = ([^;]+);/);
      assert.ok(viewType, 'View type declaration must exist');
      assert.doesNotMatch(viewType[1], /'documents'/);
    });

    it('GovernancePage.tsx redirects ?view=documents to /governance/documents (preserves bookmarks)', () => {
      assert.match(GOV_PAGE_SRC, /params\.get\('view'\) === 'documents'/);
      assert.match(GOV_PAGE_SRC, /\/governance\/documents/);
      assert.match(GOV_PAGE_SRC, /window\.location\.replace/);
    });

    it('GovernancePage.tsx surfaces a cross-link to /governance/documents from the manual view', () => {
      assert.match(GOV_PAGE_SRC, /data-testid="governance-library-crosslink"/);
      assert.match(GOV_PAGE_SRC, /href=\{`\$\{lp\}\/governance\/documents`\}/);
    });
  });

  describe('UX guards', () => {
    it('renders explicit loading state', () => {
      assert.match(COMPONENT_SRC, /data-testid="lib-loading"/);
    });

    it('renders explicit error state', () => {
      assert.match(COMPONENT_SRC, /data-testid="lib-error"/);
    });

    it('renders explicit empty state', () => {
      assert.match(COMPONENT_SRC, /data-testid="lib-empty"/);
    });

    it('cards link to existing /governance/document/{id} reader', () => {
      assert.match(COMPONENT_SRC, /href=\{`\$\{langPrefix\}\/governance\/document\/\$\{d\.id\}`\}/);
    });

    it('persists filters in URL (?type, ?status) for shareable links', () => {
      assert.match(COMPONENT_SRC, /url\.searchParams\.set\('type'/);
      assert.match(COMPONENT_SRC, /url\.searchParams\.set\('status'/);
      assert.match(COMPONENT_SRC, /url\.searchParams\.delete\('type'/);
      assert.match(COMPONENT_SRC, /url\.searchParams\.delete\('status'/);
    });
  });

  describe('i18n parity — pt-BR canonical × en-US × es-LATAM', () => {
    function extractKeys(src) {
      return new Set([...src.matchAll(/'governance\.library\.[^']+'/g)].map((m) => m[0]));
    }
    const ptKeys = extractKeys(PT);
    const enKeys = extractKeys(EN);
    const esKeys = extractKeys(ES);

    it('all 3 dictionaries share the same governance.library.* key set', () => {
      assert.deepEqual([...ptKeys].sort(), [...enKeys].sort(), 'pt-BR vs en-US drift');
      assert.deepEqual([...ptKeys].sort(), [...esKeys].sort(), 'pt-BR vs es-LATAM drift');
    });

    it('each dict declares 11 doc_type labels', () => {
      for (const dt of DOC_TYPES) {
        const key = `'governance.library.docType.${dt}'`;
        assert.ok(ptKeys.has(key), `pt-BR missing ${key}`);
        assert.ok(enKeys.has(key), `en-US missing ${key}`);
        assert.ok(esKeys.has(key), `es-LATAM missing ${key}`);
      }
    });

    it('each dict declares 8 status labels (matches CHECK)', () => {
      for (const s of STATUSES) {
        const key = `'governance.library.status.${s}'`;
        assert.ok(ptKeys.has(key), `pt-BR missing ${key}`);
        assert.ok(enKeys.has(key), `en-US missing ${key}`);
        assert.ok(esKeys.has(key), `es-LATAM missing ${key}`);
      }
    });

    it('each dict declares 5 visibility labels (matches CHECK)', () => {
      for (const v of VIS_CLASSES) {
        const key = `'governance.library.visibility.${v}'`;
        assert.ok(ptKeys.has(key), `pt-BR missing ${key}`);
        assert.ok(enKeys.has(key), `en-US missing ${key}`);
        assert.ok(esKeys.has(key), `es-LATAM missing ${key}`);
      }
    });

    it('each dict declares 3 acknowledgement_mode labels (matches CHECK)', () => {
      for (const a of ACK_MODES) {
        const key = `'governance.library.ack.${a}'`;
        assert.ok(ptKeys.has(key), `pt-BR missing ${key}`);
        assert.ok(enKeys.has(key), `en-US missing ${key}`);
        assert.ok(esKeys.has(key), `es-LATAM missing ${key}`);
      }
    });
  });
});
