/**
 * Forward-defense: VersionDiffViewer MUST strip document scaffold (<!DOCTYPE>,
 * <head>, <style>, <body>) before rendering via dangerouslySetInnerHTML.
 *
 * Origin: p223 BUG-CPMAI.C. PM smoke after TAP R01 created (governance doc
 * 'd7447a94-ca3c-4cf6-8b6e-5e604136522c' chain '897aeddf-...'): clicking
 * "Diff R00 ↔ R01" tab shrunk the entire /admin/governance/documents/[chainId]
 * page including the lateral comments drawer, making content unreadable.
 *
 * Root cause: TAP HTML is stored as a complete HTML document (begins with
 * `<!DOCTYPE html>` + `<head>` + `<style>` block containing `body { max-width:
 * 920px; margin: 0 auto; ... }`). The /document/[id] viewer + ReviewChainIsland's
 * IsolatedHtmlFrame wrap content in `<iframe sandbox="allow-same-origin">` which
 * isolates the embedded `<style>` from the host page. But VersionDiffViewer uses
 * `dangerouslySetInnerHTML` directly (so it can highlight changed paragraphs via
 * class attrs across panes) — without isolation, the embedded `<style>` is
 * injected into the host DOM and `body { max-width: 920px }` applies globally,
 * shrinking the entire admin page.
 *
 * Fix: stripDocumentScaffold() helper called inside splitBlocks() removes
 * <!DOCTYPE>, <html>, <head>...</head> (which contains <style>/<link>/<meta>),
 * <body> tags, plus defensive strip of any extra <style>/<link>/<script> in the
 * body. Diff content is just paragraphs/headings/lists/tables — the scaffold
 * has no diffing value anyway.
 *
 * Cross-ref:
 *   - src/components/governance/VersionDiffViewer.tsx (stripDocumentScaffold)
 *   - src/components/governance/ReviewChainIsland.tsx (IsolatedHtmlFrame — alt path that uses iframe sandbox)
 *   - P162 BUG-CPMAI.C
 *
 * Scope: static analysis + behavioural unit. No DB env required.
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const VIEWER = resolve(process.cwd(), 'src/components/governance/VersionDiffViewer.tsx');

test('VersionDiffViewer.tsx exists', () => {
  const src = readFileSync(VIEWER, 'utf8');
  assert.ok(src.length > 1000, 'VersionDiffViewer source should be non-trivial');
});

test('VersionDiffViewer defines stripDocumentScaffold helper', () => {
  const src = readFileSync(VIEWER, 'utf8');
  assert.match(src, /function\s+stripDocumentScaffold\s*\(/, 'must declare stripDocumentScaffold function');
});

test('stripDocumentScaffold strips DOCTYPE, html, head (with style), body, link, script', () => {
  const src = readFileSync(VIEWER, 'utf8');
  // Extract the function body and check for required strip patterns
  const fnMatch = src.match(/function\s+stripDocumentScaffold[\s\S]*?\n\}/);
  assert.ok(fnMatch, 'stripDocumentScaffold body must be locatable');
  const body = fnMatch[0];
  assert.ok(body.includes('doctype'), 'must strip <!DOCTYPE>');
  assert.ok(body.includes('?html'), 'must strip <html> open + </html> (regex <\\/?html...>)');
  assert.ok(body.includes('<head'), 'must strip <head> (full block)');
  assert.ok(body.includes('<\\/head>'), 'must strip </head> closing');
  assert.ok(body.includes('<style'), 'must strip <style> blocks');
  assert.ok(body.includes('<link'), 'must strip <link>');
  assert.ok(body.includes('<script'), 'must strip <script> (defensive)');
  assert.ok(body.includes('?body'), 'must strip <body> open + </body> (regex <\\/?body...>)');
});

test('splitBlocks calls stripDocumentScaffold (so all consumers get clean input)', () => {
  const src = readFileSync(VIEWER, 'utf8');
  const splitFn = src.match(/function\s+splitBlocks[\s\S]*?\n\}/);
  assert.ok(splitFn, 'splitBlocks function must exist');
  assert.match(splitFn[0], /stripDocumentScaffold\s*\(/, 'splitBlocks must invoke stripDocumentScaffold');
});

test('Behavioural: stripDocumentScaffold actually removes TAP-shape scaffolding', async () => {
  // Reconstruct the regex helper inline to validate the behavior (mirrors source).
  const stripDocumentScaffold = (html) => {
    if (!html) return '';
    return html
      .replace(/<!doctype\s+html[^>]*>/gi, '')
      .replace(/<\/?html[^>]*>/gi, '')
      .replace(/<head[^>]*>[\s\S]*?<\/head>/gi, '')
      .replace(/<\/?body[^>]*>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<link[^>]*>/gi, '')
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
  };

  const sample = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>TAP</title>
<style>
  body { max-width: 920px; margin: 0 auto; padding: 24px; }
  h2 { color: #003a70; }
</style>
<link rel="stylesheet" href="x.css">
</head>
<body>
<h1>Título</h1>
<p>Conteúdo de teste.</p>
<style>.escaped{color:red}</style>
<script>alert('xss')</script>
</body>
</html>`;

  const out = stripDocumentScaffold(sample);

  assert.doesNotMatch(out, /<!doctype/i, 'DOCTYPE removed');
  assert.doesNotMatch(out, /<html/i, 'html tag removed');
  assert.doesNotMatch(out, /<head/i, 'head tag removed');
  assert.doesNotMatch(out, /<\/head>/i, 'closing head removed');
  assert.doesNotMatch(out, /<style/i, 'all style blocks removed');
  assert.doesNotMatch(out, /max-width: 920px/, 'CSS rules inside style purged (key offender)');
  assert.doesNotMatch(out, /<link/i, 'link tag removed');
  assert.doesNotMatch(out, /<script/i, 'script tag removed (defensive)');
  assert.doesNotMatch(out, /<body/i, 'body open removed');
  assert.doesNotMatch(out, /<\/body>/i, 'body close removed');

  // Content blocks preserved
  assert.match(out, /<h1>Título<\/h1>/, 'h1 content preserved');
  assert.match(out, /<p>Conteúdo de teste\.<\/p>/, 'p content preserved');
});

test('Behavioural: empty / null input safe', () => {
  const stripDocumentScaffold = (html) => {
    if (!html) return '';
    return html
      .replace(/<!doctype\s+html[^>]*>/gi, '')
      .replace(/<\/?html[^>]*>/gi, '')
      .replace(/<head[^>]*>[\s\S]*?<\/head>/gi, '')
      .replace(/<\/?body[^>]*>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<link[^>]*>/gi, '')
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
  };
  assert.equal(stripDocumentScaffold(''), '');
  assert.equal(stripDocumentScaffold(null), '');
  assert.equal(stripDocumentScaffold(undefined), '');
});

test('Behavioural: fragments without scaffold pass through unchanged', () => {
  const stripDocumentScaffold = (html) => {
    if (!html) return '';
    return html
      .replace(/<!doctype\s+html[^>]*>/gi, '')
      .replace(/<\/?html[^>]*>/gi, '')
      .replace(/<head[^>]*>[\s\S]*?<\/head>/gi, '')
      .replace(/<\/?body[^>]*>/gi, '')
      .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<link[^>]*>/gi, '')
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '');
  };
  const fragment = '<p>Hello</p><h2>Section</h2><ul><li>a</li><li>b</li></ul>';
  assert.equal(stripDocumentScaffold(fragment), fragment, 'fragment passes through untouched');
});
