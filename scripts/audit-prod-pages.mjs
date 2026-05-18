/**
 * Prod page audit script — paste into Chrome DevTools console while logged in.
 *
 * What it does:
 *   1. Walks a predefined list of ~80 static routes (PT-BR + EN + ES).
 *   2. For each route, opens it in a hidden iframe + waits for load + scrapes:
 *      - HTTP status (via fetch HEAD)
 *      - any console.error captured during iframe load
 *      - final URL (detects redirects)
 *      - presence of common error markers (404 text, "Sorry, this page", etc.)
 *   3. Compiles results into a structured JSON object.
 *   4. Writes JSON to `window.__auditResults__` AND console.log + copies to clipboard.
 *
 * Usage:
 *   1. Log into https://nucleoia.vitormr.dev in Chrome.
 *   2. Open DevTools Console.
 *   3. Paste this entire script + press Enter.
 *   4. Wait ~2-3 minutes for the crawl to complete.
 *   5. Paste the resulting JSON back to me for analysis.
 *
 * Limitations:
 *   - iframe-based crawl misses errors thrown after iframe DOMContentLoaded
 *     (deferred async errors). Capture window is 3s post-load.
 *   - Dynamic routes (/admin/member/[id], etc.) require manual seed IDs;
 *     this script does NOT crawl them (would need a separate pass with real IDs).
 *   - Some pages may have CSP blocking iframe embedding (X-Frame-Options DENY).
 *     Those will show as 'iframe_blocked' in the results.
 *   - Auth-gated pages assume the session is active in the parent tab; iframes
 *     inherit the parent's cookies/storage (same-origin).
 */
(async function auditProdPages() {
  console.log('🔍 Iniciando audit prod...');

  // Routes to crawl — static only (no dynamic IDs)
  const ROUTES = [
    // Public PT-BR
    '/', '/about', '/blog', '/changelog', '/cpmai', '/docs/mcp', '/gamification',
    '/governance', '/governance/glossario', '/governance/ip-agreement',
    '/help', '/library', '/privacy', '/projects', '/publications', '/ranks', '/rank',
    '/teams',
    // Auth-required PT-BR (assuming logged in)
    '/admin', '/admin/adoption', '/admin/ai-calibration', '/admin/analytics',
    '/admin/audit-log', '/admin/blog', '/admin/campaigns', '/admin/certificates',
    '/admin/chapter', '/admin/chapter-report', '/admin/comms', '/admin/comms-ops',
    '/admin/curatorship', '/admin/cycle-report', '/admin/data-health',
    '/admin/gamification', '/admin/governance/charters',
    '/admin/governance/documents', '/admin/governance/ip-ratification',
    '/admin/governance-v2', '/admin/help', '/admin/initiative-kinds',
    '/admin/initiatives', '/admin/knowledge', '/admin/members',
    '/admin/members/inactive-candidates', '/admin/organization',
    '/admin/partnerships', '/admin/pilots', '/admin/portfolio',
    '/admin/publications', '/admin/report', '/admin/selection', '/admin/settings',
    '/admin/sustainability', '/admin/tags', '/admin/tribes',
    '/admin/vep-reconciliation', '/admin/webinars',
    '/artifacts', '/attendance', '/boards', '/certificates', '/initiatives',
    '/meetings', '/minha-candidatura', '/notifications', '/onboarding',
    '/presentations', '/profile', '/profile/me', '/profile/verify-secondary',
    '/publications/submissions', '/report', '/settings/notifications',
    '/stakeholder', '/volunteer-agreement', '/webinars', '/workspace',
    // EN mirrors (sampling)
    '/en/', '/en/about', '/en/blog', '/en/admin', '/en/workspace',
    // ES mirrors (sampling)
    '/es/', '/es/about', '/es/blog', '/es/admin', '/es/workspace',
  ];

  const results = {
    started_at: new Date().toISOString(),
    base_origin: location.origin,
    total_routes: ROUTES.length,
    routes: [],
  };

  // Phase 1: HEAD/GET fetch each route, capture status + redirect chain
  console.log(`📡 Phase 1/2: fetch HEAD para ${ROUTES.length} rotas...`);
  for (let i = 0; i < ROUTES.length; i++) {
    const path = ROUTES[i];
    const entry = { path, phase1: {}, phase2: {} };
    try {
      const r = await fetch(path, {
        method: 'GET',
        credentials: 'include',
        redirect: 'follow',
      });
      entry.phase1 = {
        status: r.status,
        final_url: r.url,
        redirected: r.redirected,
        content_type: r.headers.get('content-type'),
        x_frame_options: r.headers.get('x-frame-options'),
      };
      // Sniff the response body for error markers
      const ct = (r.headers.get('content-type') || '').toLowerCase();
      if (ct.includes('text/html') && r.status === 200) {
        const text = await r.text();
        const markers = [];
        if (/404/.test(text) && /page not found|página não encontrada|p[áa]gina/i.test(text)) markers.push('404_text');
        if (/<title>404/i.test(text)) markers.push('404_title');
        if (/RangeError|TypeError|SyntaxError|ReferenceError/i.test(text)) markers.push('js_error_in_html');
        if (/Cannot read prop|undefined is not/i.test(text)) markers.push('runtime_error_text');
        if (/oops|sorry, something went wrong|tente novamente/i.test(text)) markers.push('error_page_copy');
        if (text.length < 500) markers.push('suspiciously_short_response');
        entry.phase1.error_markers = markers;
        entry.phase1.body_length = text.length;
      }
    } catch (err) {
      entry.phase1.error = String(err);
    }
    results.routes.push(entry);
    if ((i + 1) % 10 === 0) console.log(`  ${i + 1}/${ROUTES.length} done`);
  }

  // Phase 2: iframe load each non-redirected, status-200 route, capture console errors
  console.log(`🖼  Phase 2/2: iframe load para rotas 200 OK...`);
  const consoleErrors = [];
  const origConsoleError = console.error;
  console.error = function (...args) {
    consoleErrors.push({ ts: Date.now(), args: args.map(a => String(a)).join(' ') });
    origConsoleError.apply(console, args);
  };

  for (const entry of results.routes) {
    if (entry.phase1.status !== 200) continue;
    if (entry.phase1.x_frame_options && /deny|sameorigin/i.test(entry.phase1.x_frame_options)) {
      entry.phase2.skipped = 'x_frame_options_deny_or_sameorigin';
      continue;
    }
    consoleErrors.length = 0;
    const iframe = document.createElement('iframe');
    iframe.style.cssText = 'position:absolute;left:-9999px;width:1024px;height:768px;border:0';
    iframe.src = entry.path;
    document.body.appendChild(iframe);
    await new Promise(resolve => {
      let resolved = false;
      const done = () => { if (!resolved) { resolved = true; resolve(); } };
      iframe.addEventListener('load', () => setTimeout(done, 3000));
      iframe.addEventListener('error', done);
      setTimeout(done, 8000); // hard timeout
    });
    entry.phase2 = {
      console_errors_count: consoleErrors.length,
      console_errors: consoleErrors.slice(0, 5), // cap to 5 per page
      final_iframe_url: (() => {
        try { return iframe.contentWindow.location.href; } catch { return 'cross_origin_or_blocked'; }
      })(),
    };
    iframe.remove();
  }

  console.error = origConsoleError;

  // Aggregate summary
  const summary = {
    total: results.routes.length,
    ok: results.routes.filter(r => r.phase1.status === 200 && !(r.phase1.error_markers || []).length && !(r.phase2.console_errors_count || 0)).length,
    redirected: results.routes.filter(r => r.phase1.redirected).length,
    non_200: results.routes.filter(r => r.phase1.status && r.phase1.status !== 200).length,
    with_error_markers: results.routes.filter(r => (r.phase1.error_markers || []).length).length,
    with_console_errors: results.routes.filter(r => (r.phase2.console_errors_count || 0) > 0).length,
    iframe_blocked: results.routes.filter(r => r.phase2.skipped).length,
    fetch_errors: results.routes.filter(r => r.phase1.error).length,
  };
  results.summary = summary;
  results.finished_at = new Date().toISOString();

  // Output
  window.__auditResults__ = results;
  const json = JSON.stringify(results, null, 2);
  console.log('✅ Audit completo. Summary:', summary);
  console.log('📋 Resultado em window.__auditResults__');
  console.log('--- JSON COMPLETO (copie e cole de volta no chat) ---');
  console.log(json);

  // Try to copy to clipboard
  try {
    await navigator.clipboard.writeText(json);
    console.log('📎 JSON copiado para clipboard. Cole no chat.');
  } catch (e) {
    console.log('⚠️  Clipboard bloqueado — copie o JSON do console manualmente.');
  }

  return results;
})();
