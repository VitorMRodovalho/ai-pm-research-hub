import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

/**
 * #315 Wave 2 (#310) — Admin intake wizard contract
 *
 * Locks the contract between the React wizard and the Wave 1a M3 RPC
 * `create_governance_document_intake(p_payload jsonb)`. Forward-defense
 * locks the regression class where wizard payload drifts from RPC contract
 * or where required Tier-1 fields are silently dropped.
 *
 * Pattern: static file assertions (offline) — no DB env required.
 */

const COMPONENT_PATH = 'src/components/governance/DocumentIntakeWizard.tsx';
const PAGE_PATH = 'src/pages/admin/governance/documents.astro';
const PT_BR_DICT = 'src/i18n/pt-BR.ts';
const EN_US_DICT = 'src/i18n/en-US.ts';
const ES_LATAM_DICT = 'src/i18n/es-LATAM.ts';

const COMPONENT_SRC = existsSync(COMPONENT_PATH) ? readFileSync(COMPONENT_PATH, 'utf8') : '';
const PAGE_SRC = existsSync(PAGE_PATH) ? readFileSync(PAGE_PATH, 'utf8') : '';
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
const VIS_CLASSES = ['public', 'active_members', 'legal_scoped', 'admin_only', 'audit_restricted'];
const ACK_MODES = ['informational', 'binding', 'legal_signature'];

describe('p258 #310 — Wave 2 admin intake wizard contract', () => {
  describe('file presence + header cross-refs', () => {
    it('component file exists', () => {
      assert.ok(existsSync(COMPONENT_PATH), `expected ${COMPONENT_PATH}`);
      assert.ok(COMPONENT_SRC.length > 0, 'component file must not be empty');
    });

    it('admin documents page imports the wizard', () => {
      assert.ok(existsSync(PAGE_PATH), `expected ${PAGE_PATH}`);
      assert.match(PAGE_SRC, /import DocumentIntakeWizard from '\.\.\/\.\.\/\.\.\/components\/governance\/DocumentIntakeWizard'/);
    });

    it('component header references #315 Wave 2 (#310) + the RPC contract', () => {
      assert.match(COMPONENT_SRC, /#315/);
      assert.match(COMPONENT_SRC, /#310/);
      assert.match(COMPONENT_SRC, /create_governance_document_intake/);
    });
  });

  describe('RPC contract — Tier-1 5 fields + 2 optional', () => {
    it('payload includes all 5 Tier-1 required fields per P1-Q6', () => {
      assert.match(COMPONENT_SRC, /title:\s*v_title/);
      assert.match(COMPONENT_SRC, /doc_type:\s*docType/);
      assert.match(COMPONENT_SRC, /author_label:\s*v_author/);
      assert.match(COMPONENT_SRC, /visibility_class:\s*visibilityClass/);
      assert.match(COMPONENT_SRC, /description:\s*v_description/);
    });

    it('payload includes proposer_ack_offline boolean (A2)', () => {
      assert.match(COMPONENT_SRC, /proposer_ack_offline:\s*proposerAckOffline/);
    });

    it('payload conditionally includes proposer_member_id when provided', () => {
      assert.match(COMPONENT_SRC, /if \(v_proposer\) payload\.proposer_member_id = v_proposer/);
    });

    it('RPC call uses canonical name + p_payload wrapper', () => {
      assert.match(COMPONENT_SRC, /sb\.rpc\('create_governance_document_intake',\s*\{\s*p_payload:\s*payload\s*\}\)/);
    });

    it('success redirect targets the existing editor de versão route', () => {
      assert.match(
        COMPONENT_SRC,
        /window\.location\.href = `\$\{langPrefix\}\/admin\/governance\/documents\/\$\{docId\}\/versions\/new`/,
      );
    });

    it('extracts document_id from RPC return envelope', () => {
      assert.match(COMPONENT_SRC, /res\.data\?\.document_id/);
    });
  });

  describe('select dropdowns — full CHECK constraint enumeration', () => {
    it('11 doc_type options match governance_documents_doc_type_check', () => {
      const docTypeArrayMatch = COMPONENT_SRC.match(/const DOC_TYPES:[^=]*=\s*\[([\s\S]*?)\];/);
      assert.ok(docTypeArrayMatch, 'DOC_TYPES array must be declared');
      for (const dt of DOC_TYPES) {
        assert.match(docTypeArrayMatch[1], new RegExp(`'${dt}'`), `doc_type '${dt}' must be in DOC_TYPES`);
      }
    });

    it('5 visibility_class options match governance_documents_visibility_class_check', () => {
      const visArrayMatch = COMPONENT_SRC.match(/const VISIBILITY_CLASSES:[^=]*=\s*\[([\s\S]*?)\];/);
      assert.ok(visArrayMatch, 'VISIBILITY_CLASSES array must be declared');
      for (const vc of VIS_CLASSES) {
        assert.match(visArrayMatch[1], new RegExp(`'${vc}'`), `visibility_class '${vc}' must be in VISIBILITY_CLASSES`);
      }
    });

    it('default doc_type is editorial_guide (Frontiers anchor case)', () => {
      assert.match(COMPONENT_SRC, /useState<DocType>\('editorial_guide'\)/);
    });

    it('default visibility_class is active_members (corpus baseline)', () => {
      assert.match(COMPONENT_SRC, /useState<VisibilityClass>\('active_members'\)/);
    });
  });

  describe('A1 acknowledgement_mode preview mirrors RPC default', () => {
    it('declares ACK_DEFAULTS mapping covering all 11 doc_types', () => {
      const ackMatch = COMPONENT_SRC.match(/const ACK_DEFAULTS:[^=]*=\s*\{([\s\S]*?)\};/);
      assert.ok(ackMatch, 'ACK_DEFAULTS must be declared');
      for (const dt of DOC_TYPES) {
        assert.match(ackMatch[1], new RegExp(`${dt}:`), `ACK_DEFAULTS missing key ${dt}`);
      }
    });

    it('uses the 3 canonical acknowledgement_mode values only', () => {
      const ackMatch = COMPONENT_SRC.match(/const ACK_DEFAULTS:[^=]*=\s*\{([\s\S]*?)\};/)[1];
      const usedModes = [...ackMatch.matchAll(/'(informational|binding|legal_signature)'/g)].map((m) => m[1]);
      assert.ok(usedModes.length === DOC_TYPES.length, 'all 11 doc_types map to a mode');
      for (const m of usedModes) {
        assert.ok(ACK_MODES.includes(m), `unexpected acknowledgement_mode '${m}'`);
      }
    });

    it('Mirrors the RPC defaults per A1: editorial_guide=informational, cooperation_agreement=legal_signature, volunteer_term_template=binding', () => {
      assert.match(COMPONENT_SRC, /editorial_guide:\s*'informational'/);
      assert.match(COMPONENT_SRC, /cooperation_agreement:\s*'legal_signature'/);
      assert.match(COMPONENT_SRC, /volunteer_term_template:\s*'binding'/);
    });
  });

  describe('UX guards', () => {
    it('validates required fields client-side before RPC call', () => {
      assert.match(COMPONENT_SRC, /if \(!v_title \|\| !v_author \|\| !v_description\)/);
    });

    it('rejects malformed proposer_member_id before sending to RPC', () => {
      assert.match(COMPONENT_SRC, /v_proposer && !isUuid\(v_proposer\)/);
    });

    it('renders error inline (does not throw)', () => {
      assert.match(COMPONENT_SRC, /data-testid="intake-error"/);
    });

    it('disables submit + cancel during in-flight request', () => {
      assert.match(COMPONENT_SRC, /disabled=\{submitting\}/);
    });

    it('proposer_member_id input is collapsed behind Advanced toggle', () => {
      assert.match(COMPONENT_SRC, /advancedOpen \?\s*'▼'/);
      assert.match(COMPONENT_SRC, /\{advancedOpen && \(/);
    });
  });

  describe('forward-defense regressions (lock regression class)', () => {
    it('F1: payload MUST NOT send acknowledgement_mode from client (Wave 2 scope — RPC computes it per A1)', () => {
      assert.doesNotMatch(
        COMPONENT_SRC,
        /payload\[?['"]?acknowledgement_mode/,
        'Wave 2 wizard must not let the client override acknowledgement_mode — RPC computes default per A1; override path ships post-intake.',
      );
      // narrower form: never appears as object literal property either
      assert.doesNotMatch(
        COMPONENT_SRC,
        /acknowledgement_mode:\s*[a-zA-Z]/,
        'no acknowledgement_mode property in any payload literal',
      );
    });

    it('F2: payload MUST NOT include status (RPC computes from proposer_ack_offline per A2)', () => {
      assert.doesNotMatch(COMPONENT_SRC, /payload\[?['"]?status/);
      // Wizard surfaces initialStatus to the GP as PREVIEW only; never as payload key
      const payloadMatch = COMPONENT_SRC.match(/const payload:[^=]*=\s*\{([\s\S]*?)\};/);
      assert.ok(payloadMatch, 'payload literal must exist');
      assert.doesNotMatch(payloadMatch[1], /status:/, 'payload must not carry status — RPC owns A2 logic');
    });

    it('F3: doc_type values MUST come from the typed enum (no free-text doc_type submission)', () => {
      // The select binds to setDocType(e.target.value as DocType) — types narrowed.
      assert.match(COMPONENT_SRC, /setDocType\(e\.target\.value as DocType\)/);
      // No <input type="text"> for doc_type
      assert.doesNotMatch(COMPONENT_SRC, /id="intake-doc-type"[^>]*type="text"/);
    });

    it('F4: visibility_class values MUST come from the typed enum (no free-text visibility submission)', () => {
      assert.match(COMPONENT_SRC, /setVisibilityClass\(e\.target\.value as VisibilityClass\)/);
      assert.doesNotMatch(COMPONENT_SRC, /id="intake-visibility"[^>]*type="text"/);
    });

    it('F5: success path MUST redirect to /admin/governance/documents/{docId}/versions/new (Wave 2 gate)', () => {
      // Critical: the entire point of Wave 2 is that intake leads directly to the editor.
      // If this regresses (e.g., a session navigation), the wizard is broken.
      const successBranch = COMPONENT_SRC.match(/if \(!docId\)[\s\S]*?window\.location\.href[^;]+;/);
      assert.ok(successBranch, 'success branch must redirect after docId is extracted');
      assert.match(
        successBranch[0],
        /\/admin\/governance\/documents\/\$\{docId\}\/versions\/new/,
        'redirect must target the editor de versão route',
      );
    });
  });

  describe('admin page integration', () => {
    it('admin page mounts <DocumentIntakeWizard client:load /> with langPrefix + strings', () => {
      assert.match(PAGE_SRC, /<DocumentIntakeWizard\s+client:load\s+langPrefix=\{langPrefix\}\s+strings=\{intakeStrings\}\s*\/>/);
    });

    it('admin page declares intakeStrings bundle with all required entries', () => {
      // Sanity sample (the i18n parity test covers the full set)
      assert.match(PAGE_SRC, /ctaOpen:\s*t\('governance\.docs\.intake\.ctaOpen'/);
      assert.match(PAGE_SRC, /modalTitle:\s*t\('governance\.docs\.intake\.modalTitle'/);
      assert.match(PAGE_SRC, /docTypes:\s*\{/);
      assert.match(PAGE_SRC, /visibilityClasses:\s*\{/);
    });
  });

  describe('i18n parity — pt-BR canonical × en-US × es-LATAM', () => {
    function extractKeys(src) {
      return new Set([...src.matchAll(/'governance\.docs\.intake\.[^']+'/g)].map((m) => m[0]));
    }
    const ptKeys = extractKeys(PT);
    const enKeys = extractKeys(EN);
    const esKeys = extractKeys(ES);

    it('all 3 dictionaries have the same governance.docs.intake.* key set', () => {
      assert.deepEqual([...ptKeys].sort(), [...enKeys].sort(), 'pt-BR vs en-US drift');
      assert.deepEqual([...ptKeys].sort(), [...esKeys].sort(), 'pt-BR vs es-LATAM drift');
    });

    it('each dict declares all 11 doc_type localized labels', () => {
      for (const dt of DOC_TYPES) {
        assert.ok(ptKeys.has(`'governance.docs.intake.docType.${dt}'`), `pt-BR missing docType.${dt}`);
        assert.ok(enKeys.has(`'governance.docs.intake.docType.${dt}'`), `en-US missing docType.${dt}`);
        assert.ok(esKeys.has(`'governance.docs.intake.docType.${dt}'`), `es-LATAM missing docType.${dt}`);
      }
    });

    it('each dict declares all 5 visibility_class label + hint pairs', () => {
      for (const vc of VIS_CLASSES) {
        for (const dict of [{ name: 'pt-BR', set: ptKeys }, { name: 'en-US', set: enKeys }, { name: 'es-LATAM', set: esKeys }]) {
          assert.ok(
            dict.set.has(`'governance.docs.intake.visibility.${vc}'`),
            `${dict.name} missing visibility.${vc}`,
          );
          assert.ok(
            dict.set.has(`'governance.docs.intake.visibility.${vc}Hint'`),
            `${dict.name} missing visibility.${vc}Hint`,
          );
        }
      }
    });

    it('ackInformational / ackBinding / ackLegalSignature exist in all 3 langs', () => {
      for (const dict of [{ name: 'pt-BR', set: ptKeys }, { name: 'en-US', set: enKeys }, { name: 'es-LATAM', set: esKeys }]) {
        assert.ok(dict.set.has(`'governance.docs.intake.ackInformational'`), `${dict.name} missing ackInformational`);
        assert.ok(dict.set.has(`'governance.docs.intake.ackBinding'`), `${dict.name} missing ackBinding`);
        assert.ok(dict.set.has(`'governance.docs.intake.ackLegalSignature'`), `${dict.name} missing ackLegalSignature`);
      }
    });
  });
});
