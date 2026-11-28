/**
 * #3201 — a counter-signed EVENT guest certificate prints the member who counter-signed as its
 * second signatory, not the fixed Co-Gestor.
 *
 * Why it matters: the second signature IMAGE was already resolved from the real counter-signer
 * (hydrateCertData), while the NAME under it was hardcoded. A counter-signer with a signature on
 * file would have had their handwriting printed above someone else's name.
 *
 * Each assertion binds the condition to the result (.claude/rules/guards.md):
 *   A. the template picks the counter-signer only for type === 'event_participation' with a name,
 *      and the fallback stays the Co-Gestor for every other recognition cert
 *   B. the printed name and role are escaped (typed text reaches the PDF)
 *   C. the render route feeds name and role from content_snapshot, only when counter_signed_by exists
 *   D. the latest migration freezes counter_signed_by_role in content_snapshot, sanitized,
 *      and only inside the counter-signer branch
 * Behaviour is proven live, not here: node cannot import pdf.ts (extensionless imports), and a test
 * that skips on import failure would be green by absence. The re-rendered PDF is the evidence.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const ROOT = process.cwd();
const pdfTs = readFileSync(resolve(ROOT, 'src/lib/certificates/pdf.ts'), 'utf8');
const routeTs = readFileSync(resolve(ROOT, 'src/pages/api/internal/cert-pdf-render/[id].ts'), 'utf8');

function latestIssueBody() {
  const dir = resolve(ROOT, 'supabase/migrations');
  const files = readdirSync(dir).filter(f => f.endsWith('.sql')).sort();
  let body = null;
  for (const f of files) {
    const sql = readFileSync(join(dir, f), 'utf8');
    const re = /CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.issue_event_guest_certificate\s*\(p_data jsonb\)[\s\S]*?AS\s+\$(\w*)\$([\s\S]*?)\$\1\$/gi;
    let m;
    while ((m = re.exec(sql))) body = m[2];
  }
  return body;
}

test('A: counter-signer only for a counter-signed event cert; Co-Gestor otherwise', () => {
  assert.match(pdfTs, /const isEventCounterSigned = type === 'event_participation' && !!certData\.counter_signed_by_name;/);
  assert.match(pdfTs, /const secondName = isEventCounterSigned \? escHtml\(certData\.counter_signed_by_name!\) : 'Fabricio R\. C\. Costa';/);
  assert.match(pdfTs, /const secondRole = isEventCounterSigned\s*\?\s*escHtml\(certData\.counter_signed_by_role \|\| tpl\.roleCounterSigner\)\s*:\s*tpl\.roleCoGestor;/);
  assert.match(pdfTs, /<div class="rc-signame">\$\{secondName\}<\/div><div class="rc-sigrole">\$\{secondRole\}<\/div>/);
  assert.doesNotMatch(pdfTs, /<div class="rc-signame">Fabricio R\. C\. Costa<\/div>/, 'the fixed name must not be back in the markup');
});

test('B: escHtml escapes the characters that break markup', () => {
  const m = pdfTs.match(/function escHtml\(v: string\): string \{\n\s*return ([^\n]+);\n\}/);
  assert.ok(m, 'escHtml must exist');
  const escHtml = new Function('v', `return ${m[1]};`);
  assert.equal(escHtml('<b>"A&B"</b>'), '&lt;b&gt;&quot;A&amp;B&quot;&lt;/b&gt;');
});

test('C: the render route takes name and role from the snapshot, only with a counter-signer', () => {
  assert.match(routeTs, /counter_signed_by_name: guest\.counter_signed_by \? \(snap\.counter_signed_by_name \|\| undefined\) : undefined,/);
  assert.match(routeTs, /counter_signed_by_role: guest\.counter_signed_by \? \(snap\.counter_signed_by_role \|\| undefined\) : undefined,/);
});

test('D: issuance freezes a sanitized role, only inside the counter-signer branch', () => {
  const body = latestIssueBody();
  assert.ok(body, 'issue_event_guest_certificate must be captured in a migration');
  const branch = body.match(/IF v_counter IS NOT NULL THEN([\s\S]*?)END IF;\s*\n\s*SELECT p\.id INTO v_person/);
  assert.ok(branch, 'counter-signer branch must exist');
  assert.match(
    branch[1],
    /v_counter_role := NULLIF\(left\(btrim\(regexp_replace\(coalesce\(p_data->>'counter_signed_by_role', ''\), '\[\[:cntrl:\]\]', '', 'g'\)\), 80\), ''\);/,
  );
  assert.match(body, /'counter_signed_by_role', v_counter_role/);
});
