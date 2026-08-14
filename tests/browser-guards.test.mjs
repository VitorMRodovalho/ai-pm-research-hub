import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { chromium } from 'playwright';

const START_TIMEOUT_MS = 45_000;

let devServer;
let port = Number(process.env.BROWSER_TEST_PORT || 0);
let base = '';

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resolveAvailablePort(preferredPort) {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.on('error', reject);
    server.listen(preferredPort, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close(() => reject(new Error('Could not resolve browser test port')));
        return;
      }
      const nextPort = address.port;
      server.close((error) => {
        if (error) reject(error);
        else resolve(nextPort);
      });
    });
  });
}

async function waitForServer() {
  const startedAt = Date.now();
  while (Date.now() - startedAt < START_TIMEOUT_MS) {
    try {
      const res = await fetch(`${base}/`, { redirect: 'manual' });
      if (res.status >= 200 && res.status < 500) return;
    } catch {
      // retry until server becomes available
    }
    await sleep(500);
  }
  throw new Error(`Server did not start within ${START_TIMEOUT_MS}ms`);
}

async function run() {
  port = await resolveAvailablePort(port || 0);
  base = `http://127.0.0.1:${port}`;
  devServer = spawn(
    'npm',
    ['run', 'dev', '--', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
    { stdio: 'inherit', shell: false }
  );
  await waitForServer();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ locale: 'pt-BR' });
    await page.goto(`${base}/admin/selection`, { waitUntil: 'networkidle' });
    const denied = page.locator('#sel-denied');
    await denied.waitFor({ state: 'visible' });
    assert.match(await denied.textContent() || '', /Acesso (restrito a administradores|negado ao módulo de seleção)/);
    assert.equal(await page.locator('#sel-panel').isVisible(), false);

    // #1590 — o stub virou parametrizado por MEMBRO. Antes só existia o caso `manager`, e era
    // exatamente por isso que o gate podia recusar todo o comitê sem nenhum teste ficar vermelho.
    const installSelectionStubs = (targetPage, member, capabilities) => targetPage.evaluate(([fakeMember, caps]) => {
      window.__nucleoCapabilities = caps;
      const fakeSb = {
        auth: {
          getSession() {
            return Promise.resolve({ data: { session: null } });
          },
        },
        rpc(name) {
          if (name === 'volunteer_funnel_summary') {
            return Promise.resolve({
              data: {
                source: 'selection_applications',
                by_cycle: [{ cycle_code: 'cycle3-2026', cycle_title: 'Ciclo 3', cycle_status: 'closed', total_applications: 10, unique_applicants: 8, matched_members: 4, active_applications: 7, converted: 1, approved: 4 }],
                by_status: [{ status: 'approved', cnt: 4 }],
                certifications: [],
                geography: [],
              },
              error: null,
            });
          }
          if (name === 'get_member_by_auth') return Promise.resolve({ data: fakeMember, error: null });
          if (name === 'get_selection_cycles') {
            return Promise.resolve({ data: [{ id: 'cycle-uuid-teste', title: 'Ciclo de teste', status: 'open' }], error: null });
          }
          // #1590 onda C — o painel de roteamento. O payload imita a FORMA que a RPC devolve
          // (incluindo `is_self` e `caller.can_manage`, que é quem decide o que a linha oferece).
          if (name === 'get_selection_routing_overview') {
            return Promise.resolve({
              data: {
                cycle: { id: 'cycle-uuid-teste', cycle_code: 'cycle-teste', status: 'open', has_fallback_url: true, fallback_url: null },
                caller: { member_id: 'eu', committee_role: 'evaluator', can_manage: !!(caps?.org_actions || []).includes('manage_member') },
                local_date: '2026-08-13',
                routable_now: 1,
                blocked_now: 1,
                members: [
                  {
                    member_id: 'eu', name: 'Committee Evaluator', operational_role: 'tribe_leader',
                    role: 'evaluator', can_interview: true, is_self: true,
                    url_source: 'committee_override', has_url: true,
                    booking_url: 'https://calendar.app.google/eu', committee_url: 'https://calendar.app.google/eu',
                    routable_now: true, not_routable_reasons: [], blocked_now: false, blocks: [],
                    dispatch_count: 4, last_dispatched_at: '2026-08-07T17:00:11.676908+00:00',
                  },
                  {
                    member_id: 'outra', name: 'Outra Pessoa', operational_role: 'chapter_liaison',
                    role: 'observer', can_interview: true, is_self: false,
                    url_source: null, has_url: false, booking_url: null, committee_url: null,
                    routable_now: false, not_routable_reasons: ['role_not_routable', 'no_booking_url'],
                    blocked_now: false, blocks: [],
                    dispatch_count: 0, last_dispatched_at: null,
                  },
                  {
                    member_id: 'pausada', name: 'Pessoa Pausada', operational_role: 'manager',
                    role: 'evaluator', can_interview: true, is_self: false,
                    url_source: 'member_global', has_url: true, booking_url: null, committee_url: null,
                    routable_now: false, not_routable_reasons: ['blocked_window'], blocked_now: true,
                    blocks: [{ id: 'bloco-1', starts_on: '2026-08-10', ends_on: '2026-08-20', reason: 'ferias', created_by_name: 'Ela', created_by_self: true, active: true }],
                    dispatch_count: 8, last_dispatched_at: '2026-08-08T00:57:35.982524+00:00',
                  },
                ],
              },
              error: null,
            });
          }
          return Promise.resolve({ data: [], error: null });
        },
        from(table) {
          if (table === 'cycles') {
            return {
              select() { return this; },
              order() { return Promise.resolve({ data: [{ cycle_code: 'cycle_3', cycle_label: 'Ciclo 3', is_current: true, sort_order: 3 }], error: null }); },
            };
          }
          return {
            select() { return this; },
            order() { return Promise.resolve({ data: [], error: null }); },
          };
        },
      };
      window.navGetMember = () => fakeMember;
      window.navGetSb = () => fakeSb;
      window.dispatchEvent(new CustomEvent('nav:member', { detail: fakeMember }));
    }, [member, capabilities ?? null]);

    const GP = {
      auth_id: 'selection-admin-test',
      operational_role: 'manager',
      designations: [],
      is_superadmin: false,
      name: 'Selection Admin',
      selection_committee_role: null,
    };
    // Perfil medido em 12/08/2026: o avaliador real do ciclo aberto. tribe_leader, sem designação,
    // sem superadmin — recusado pelo gate antigo, autorizado pela RPC.
    const AVALIADOR_DE_COMITE = {
      auth_id: 'selection-committee-test',
      operational_role: 'tribe_leader',
      designations: [],
      is_superadmin: false,
      name: 'Committee Evaluator',
      selection_committee_role: 'evaluator',
    };
    const PESQUISADOR = {
      auth_id: 'selection-outsider-test',
      operational_role: 'researcher',
      designations: [],
      is_superadmin: false,
      name: 'Plain Researcher',
      selection_committee_role: null,
    };

    const selectionPage = await browser.newPage({ locale: 'pt-BR' });
    await selectionPage.goto(`${base}/admin/selection`, { waitUntil: 'networkidle' });
    await installSelectionStubs(selectionPage, GP, {
      caller_id: null, person_id: null, is_superadmin: false,
      org_actions: ['manage_platform', 'manage_member'], initiative_actions: {}, tribe_actions: {},
    });
    await selectionPage.locator('#sel-panel').waitFor({ state: 'visible' });
    await selectionPage.waitForFunction(() => document.querySelectorAll('#sel-tbody tr').length > 0);
    assert.equal(await selectionPage.locator('#sel-tbody tr').count() > 0, true);
    // O GP escreve: os controles aparecem e o aviso de leitura NÃO.
    assert.equal(await selectionPage.locator('#recalc-rankings-btn').isVisible(), true);
    assert.equal(await selectionPage.locator('#sel-readonly-note').isVisible(), false);
    await selectionPage.close();

    // #1590 — o avaliador de comitê ENTRA, e entra em modo de leitura.
    const committeePage = await browser.newPage({ locale: 'pt-BR' });
    await committeePage.goto(`${base}/admin/selection`, { waitUntil: 'networkidle' });
    await installSelectionStubs(committeePage, AVALIADOR_DE_COMITE, {
      caller_id: null, person_id: null, is_superadmin: false,
      org_actions: [], initiative_actions: {}, tribe_actions: {},
    });
    await committeePage.locator('#sel-panel').waitFor({ state: 'visible' });
    assert.equal(await committeePage.locator('#sel-denied').isVisible(), false,
      'o avaliador de comitê era recusado pelo gate de tier — este é o defeito do #1590');
    assert.equal(await committeePage.locator('#sel-readonly-note').isVisible(), true);
    for (const seletor of ['#recalc-rankings-btn', '#start-screening-btn', '[data-sel-tab="import"]']) {
      assert.equal(await committeePage.locator(seletor).isVisible(), false,
        `${seletor} chama RPC que o servidor recusa para ele; tem de ficar fora da tela`);
    }

    // #1590 onda C — a aba de comitê PASSA a aparecer para o avaliador: ela virou a superfície do
    // roteamento, e o roteamento tem autosserviço. Antes desta onda ele não tinha porta nenhuma
    // para cadastrar a própria agenda de entrevista, que é o campo que decide para quem o
    // candidato é mandado.
    assert.equal(await committeePage.locator('[data-sel-tab="committee"]').isVisible(), true,
      'sem a aba, o avaliador continua sem porta para a própria agenda — é o defeito da onda C');

    await committeePage.locator('[data-sel-tab="committee"]').click();
    await committeePage.locator('[data-routing-row="eu"]').waitFor({ state: 'visible' });

    // A PRÓPRIA linha oferece escrita; a de outra pessoa, não. É a decisão por RECURSO que a RPC
    // também aplica — a tela só evita oferecer o botão que seria recusado.
    assert.equal(await committeePage.locator('[data-routing-row="eu"] [data-action="routing-url-toggle"]').isVisible(), true,
      'o avaliador precisa alcançar a PRÓPRIA agenda');
    assert.equal(await committeePage.locator('[data-routing-row="eu"] [data-action="routing-pause-toggle"]').isVisible(), true,
      'pausar a si mesmo é autosserviço (decisão do PM)');
    assert.equal(await committeePage.locator('[data-routing-row="outra"] [data-action="routing-url-toggle"]').count(), 0,
      'a linha de OUTRA pessoa não pode oferecer escrita a quem não tem manage_member');
    assert.equal(await committeePage.locator('[data-routing-row="pausada"] [data-action="routing-resume"]').count(), 0,
      'reativar bloqueio alheio também é manage_member');

    // Os controles de COMITÊ (o que continua sendo escrita de GP) seguem escondidos dentro da aba.
    assert.equal(await committeePage.locator('#committee-add-card').isVisible(), false,
      'abrir a ABA não pode abrir a escrita de comitê');
    assert.equal(await committeePage.locator('[data-action="remove-committee"]').first().isVisible(), false,
      'remover do comitê continua exigindo manage_member');

    // O motivo de não-roteável chega traduzido, e o resumo publica FATO, não posição de fila.
    const painel = await committeePage.locator('#committee-list').innerText();
    assert.ok(/papel não entrevista/i.test(painel), 'o motivo tem de chegar traduzido, não como chave crua');
    assert.ok(!/próximo da fila/i.test(painel), 'o painel não pode publicar ordem de fila');
    assert.match(await committeePage.locator('#routing-summary').innerText(), /1 de 3/,
      'o resumo tem de contar quem pode ser escolhido HOJE');

    await committeePage.close();

    // A INVERSA: sem comitê e sem tier, continua recusado. Sem esta, remover o gate passa.
    const outsiderPage = await browser.newPage({ locale: 'pt-BR' });
    await outsiderPage.goto(`${base}/admin/selection`, { waitUntil: 'networkidle' });
    await installSelectionStubs(outsiderPage, PESQUISADOR, {
      caller_id: null, person_id: null, is_superadmin: false,
      org_actions: [], initiative_actions: {}, tribe_actions: {},
    });
    await outsiderPage.locator('#sel-denied').waitFor({ state: 'visible' });
    assert.equal(await outsiderPage.locator('#sel-panel').isVisible(), false);
    await outsiderPage.close();

    await page.goto(`${base}/admin/analytics`, { waitUntil: 'networkidle' });
    const analyticsDenied = page.locator('#analytics-denied');
    // Analytics page retries auth for 5s before showing denied for unauthenticated users
    await analyticsDenied.waitFor({ state: 'visible', timeout: 10000 });
    assert.match(await analyticsDenied.textContent() || '', /analytics/i);
    assert.equal(await page.locator('#analytics-panel').isVisible(), false);

    await page.goto(`${base}/`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1800);
    // Homepage data sections depend on live Supabase — only assert when data loaded
    const heroLoaded = await page.locator('#hero-cycle-status').isVisible();
    if (heroLoaded) {
      assert.equal(await page.locator('#hero-countdown-area').isVisible(), false);
      assert.match(await page.locator('#hero-event-area').textContent() || '', /Kick-off|Gravação|Recording|Google Meet|Meet/i);
      const tribesState = page.locator('#tribes-selection-state');
      const tribesDeadline = page.locator('#tribes-deadline-badge');
      const tribesNotice = page.locator('#tribes-selection-notice');
      await tribesState.waitFor({ state: 'visible' });
      await tribesDeadline.waitFor({ state: 'visible' });
      await tribesNotice.waitFor({ state: 'visible' });
      assert.match(await tribesState.textContent() || '', /SELEÇÃO ABERTA|SELEÇÃO ENCERRADA|CRONOGRAMA PENDENTE/);
      assert.equal(((await tribesDeadline.textContent()) || '').trim().length > 0, true);
      assert.equal(((await tribesNotice.textContent()) || '').trim().length > 0, true);
      assert.equal(((await tribesDeadline.textContent()) || '').includes('Encerra Sáb 08/Mar 12h BRT'), false);
      const firstTribeHeader = page.locator('[data-tribe-header]').first();
      await firstTribeHeader.click();
      const expandedBody = page.locator('[id^="tb-"]').first();
      await page.waitForTimeout(120);
      const expandedHeight = await expandedBody.evaluate((el) => el.scrollHeight);
      assert.equal(expandedHeight > 0, true);
    }
    assert.equal(await page.locator('#loginPrompt').isVisible(), true);

    await page.goto(`${base}/tribe/1`, { waitUntil: 'networkidle' });
    const tribeDenied = page.locator('#tribe-denied');
    await tribeDenied.waitFor({ state: 'visible' });
    assert.match(await tribeDenied.textContent() || '', /Acesso restrito a membros ativos da plataforma/);
    assert.equal(await page.locator('#tribe-shell').isVisible(), false);

    // /webinars is now public (GC-160) — verify it loads without denied gate
    await page.goto(`${base}/webinars`, { waitUntil: 'networkidle' });
    // Public page shows content sections — never shows denied
    assert.equal(await page.locator('#webinars-denied').count(), 0);

    await page.goto(`${base}/admin/curatorship`, { waitUntil: 'networkidle' });
    const curDenied = page.locator('#cur-denied');
    await curDenied.waitFor({ state: 'visible' });
    assert.match(await curDenied.textContent() || '', /Acesso restrito a administradores e l[íi]deres/);
    assert.equal(await page.locator('#cur-board').isVisible(), false);

    await page.goto(`${base}/admin/governance-v2`, { waitUntil: 'networkidle' });
    const boardGovDenied = page.locator('#boardgov-denied');
    await boardGovDenied.waitFor({ state: 'visible' });
    assert.match(await boardGovDenied.textContent() || '', /Acesso restrito a gestão de projeto/);

    const boardGovPage = await browser.newPage({ locale: 'pt-BR' });
    await boardGovPage.goto(`${base}/admin/governance-v2`, { waitUntil: 'networkidle' });
    await boardGovPage.evaluate(() => {
      const fakeMember = {
        auth_id: 'board-gov-admin-test',
        operational_role: 'manager',
        designations: ['co_gp'],
        is_superadmin: false,
        name: 'Board Governance Admin',
      };
      const fakeRows = [
        {
          id: '00000000-0000-0000-0000-000000000001',
          board_id: 1,
          board_name: 'Quadro Geral',
          board_scope: 'tribe',
          domain_key: 'research_delivery',
          title: 'Card Arquivado Teste',
        },
      ];
      const fakeSb = {
        rpc(name) {
          if (name === 'admin_list_archived_board_items') return Promise.resolve({ data: fakeRows, error: null });
          if (name === 'admin_restore_board_item') return Promise.resolve({ data: { success: true }, error: null });
          return Promise.resolve({ data: [], error: null });
        },
      };
      window.navGetMember = () => fakeMember;
      window.navGetSb = () => fakeSb;
      window.dispatchEvent(new CustomEvent('nav:member', { detail: fakeMember }));
    });
    await boardGovPage.locator('#boardgov-panel').waitFor({ state: 'visible' });
    assert.equal(await boardGovPage.locator('[data-action="restore-archived-item"]').count() > 0, true);
    await boardGovPage.locator('[data-action="restore-archived-item"]').first().click();
    await boardGovPage.close();

    const curatorshipPage = await browser.newPage({ locale: 'pt-BR' });
    await curatorshipPage.goto(`${base}/admin/curatorship`, { waitUntil: 'networkidle' });
    await curatorshipPage.evaluate(() => {
      const fakeMember = {
        auth_id: 'curator-manager-test',
        operational_role: 'manager',
        designations: [],
        is_superadmin: false,
        name: 'Curatorship Manager',
      };
      const fakeItems = [
        {
          id: 'artifact-cur-1',
          _table: 'artifacts',
          status: 'draft',
          title: 'Knowledge Ops Board Review',
          author_name: 'PM Core Team',
          tribe_name: 'Tribo de Comunicacao',
          source: 'manual',
          tags: ['governance'],
          suggested_tags: ['community'],
          tribe_id: null,
          audience_level: null,
        },
      ];
      const fakeTags = [
        { tag_key: 'governance', label_pt: 'Governanca', category: 'governance' },
        { tag_key: 'community', label_pt: 'Comunidade', category: 'community' },
      ];
      const fakeTribes = [
        { id: 6, name: 'Comunicacao', is_active: true },
      ];
      const fakeSb = {
        auth: {
          getSession() {
            return Promise.resolve({ data: { session: null } });
          },
          getUser() {
            return Promise.resolve({ data: { user: { id: 'curator-manager-test' } } });
          },
        },
        rpc(name) {
          if (name === 'list_curation_board') return Promise.resolve({ data: fakeItems, error: null });
          if (name === 'list_pending_curation') return Promise.resolve({ data: fakeItems, error: null });
          if (name === 'list_taxonomy_tags') return Promise.resolve({ data: fakeTags, error: null });
          if (name === 'curate_item') return Promise.resolve({ data: { success: true }, error: null });
          if (name === 'get_member_by_auth') return Promise.resolve({ data: fakeMember, error: null });
          return Promise.resolve({ data: [], error: null });
        },
        from(table) {
          if (table === 'tribes') {
            return {
              select() { return this; },
              eq() { return this; },
              order() { return Promise.resolve({ data: fakeTribes, error: null }); },
            };
          }
          return {
            select() { return this; },
            eq() { return this; },
            order() { return Promise.resolve({ data: [], error: null }); },
          };
        },
      };
      window.navGetMember = () => fakeMember;
      window.navGetSb = () => fakeSb;
      window.dispatchEvent(new CustomEvent('nav:member', { detail: fakeMember }));
    });
    await curatorshipPage.locator('#cur-board').waitFor({ state: 'visible' });
    assert.match(await curatorshipPage.locator('#cur-count').textContent() || '', /item/);
    const approveBtn = curatorshipPage.locator('.cur-btn-approve').first();
    const approveVisible = await approveBtn.isVisible().catch(() => false);
    if (approveVisible) {
      await approveBtn.click();
      assert.equal(await curatorshipPage.locator('.cur-confirm-approve').first().isVisible(), true);
      assert.equal(await curatorshipPage.locator('.cur-approve-tribe').first().isVisible(), true);
    }
    await curatorshipPage.locator('#cur-search').fill('inexistente');
    assert.equal(await curatorshipPage.locator('.kanban-card').count(), 0);
    await curatorshipPage.close();

    // /webinars is now public (GC-160) — test that it loads and calls list_webinars_v2
    await page.goto(`${base}/webinars`, { waitUntil: 'networkidle' });
    await page.evaluate(() => {
      const fakeMember = {
        auth_id: 'admin-browser-test',
        operational_role: 'manager',
        designations: [],
        is_superadmin: false,
        name: 'Admin Browser',
      };
      const fakeEvents = [
        {
          id: 'webinar-past-1',
          type: 'webinar',
          title: 'AI Delivery Review',
          date: '2026-03-01',
          duration_minutes: 90,
          attendee_count: 12,
          is_recorded: true,
          youtube_url: 'https://youtube.com/watch?v=webinar1',
          meeting_link: null,
          audience_level: 'leadership',
        },
        {
          id: 'webinar-future-1',
          type: 'webinar',
          title: 'Autonomous Agents Deep Dive',
          date: '2099-04-20',
          duration_minutes: 60,
          attendee_count: 0,
          is_recorded: false,
          youtube_url: null,
          meeting_link: 'https://meet.google.com/future-webinar',
          audience_level: 'all',
        },
        {
          id: 'webinar-past-2',
          type: 'webinar',
          title: 'Research Ops Retrospective',
          date: '2026-02-20',
          duration_minutes: 75,
          attendee_count: 8,
          is_recorded: true,
          youtube_url: 'https://youtube.com/watch?v=webinar2',
          meeting_link: null,
          audience_level: 'tribe',
        },
      ];
      const fakeArtifacts = [
        {
          id: 'artifact-1',
          event_id: 'webinar-past-1',
          title: 'AI Delivery Review',
          meeting_date: '2026-03-01',
          recording_url: 'https://youtube.com/watch?v=webinar1',
          tribe_id: null,
        },
      ];
      const fakeResources = [
        {
          id: 'resource-1',
          asset_type: 'webinar',
          title: 'AI Delivery Review',
          tribe_id: null,
          url: 'https://youtube.com/watch?v=webinar1',
          is_active: true,
        },
      ];
      const fakeSb = {
        rpc(name) {
          if (name === 'get_events_with_attendance') return Promise.resolve({ data: fakeEvents, error: null });
          if (name === 'list_meeting_artifacts') return Promise.resolve({ data: fakeArtifacts, error: null });
          return Promise.resolve({ data: [], error: null });
        },
        from(table) {
          if (table === 'hub_resources') {
            return {
              select() { return this; },
              eq() { return this; },
              order() { return Promise.resolve({ data: fakeResources, error: null }); },
            };
          }
          return {
            select() { return this; },
            eq() { return this; },
            order() { return Promise.resolve({ data: [], error: null }); },
          };
        },
      };
      window.navGetMember = () => fakeMember;
      window.navGetSb = () => fakeSb;
      window.dispatchEvent(new CustomEvent('nav:member', { detail: fakeMember }));
    });
    // Public /webinars page: verify it renders sections (upcoming/past) or empty state
    // The page calls list_webinars_v2 via navGetSb — with fake data it should show cards
    const hasUpcoming = await page.locator('#webinars-upcoming-section').count();
    const hasPast = await page.locator('#webinars-past-section').count();
    const hasEmpty = await page.locator('#webinars-empty').count();
    // At least one of these sections should exist in the DOM
    assert.ok(hasUpcoming > 0 || hasPast > 0 || hasEmpty > 0, 'Public webinars page has content sections');

    const analyticsPage = await browser.newPage({ locale: 'pt-BR' });
    await analyticsPage.goto(`${base}/admin/analytics`, { waitUntil: 'networkidle' });
    await analyticsPage.evaluate(() => {
      (window).__copiedSummary = '';
      try {
        Object.defineProperty(navigator, 'clipboard', {
          value: {
            writeText(value) {
              (window).__copiedSummary = String(value || '');
              return Promise.resolve();
            },
          },
          configurable: true,
        });
      } catch {
        // ignore clipboard override failures in strict environments
      }
      const fakeMember = {
        auth_id: 'analytics-observer-test',
        operational_role: 'researcher',
        designations: ['sponsor'],
        is_superadmin: false,
        name: 'Sponsor Analytics',
      };
      const fakeSb = {
        auth: {
          getSession() {
            return Promise.resolve({ data: { session: { access_token: 'fake-token' } } });
          },
        },
        rpc(name) {
          if (name === 'exec_funnel_summary') {
            return Promise.resolve({
              data: {
                cycle_code: '2026.1',
                cycle_label: 'Cycle 2026.1',
                stages: {
                  total_members: 10,
                  members_with_full_core_trail: 7,
                  members_allocated_to_tribe: 6,
                  members_with_published_artifact: 3,
                },
              },
              error: null,
            });
          }
          if (name === 'exec_impact_hours_v2') {
            return Promise.resolve({
              data: {
                total_impact_hours: 42.5,
                percent_of_target: 12.5,
                breakdown_by_tribe: [{ tribe_id: 1, impact_hours: 42.5 }],
                breakdown_by_chapter: [{ chapter: 'PMI-GO', impact_hours: 18 }, { chapter: 'PMI-MG', impact_hours: 24.5 }],
              },
              error: null,
            });
          }
          if (name === 'exec_certification_delta') {
            return Promise.resolve({
              data: {
                summary: { prior_background: 1, hub_impact: 4 },
                series: [{ certification_type: 'CPMAI', prior_background: 1, hub_impact: 4 }],
              },
              error: null,
            });
          }
          if (name === 'exec_chapter_roi') {
            return Promise.resolve({
              data: {
                chapters: [{ chapter_code: 'PMI-GO', current_active_affiliates: 5, attributed_conversions: 3 }],
              },
              error: null,
            });
          }
          if (name === 'exec_role_transitions') {
            return Promise.resolve({
              data: {
                summary: { promoted_members: 2, tracked_transitions: 4 },
                conversions_by_cycle: [{ cycle_code: '2026.1', cycle_label: 'Cycle 2026.1', promoted_members: 2 }],
                transition_matrix: [{ from_role_bucket: 'researcher', to_role_bucket: 'tribe_leader', transitions: 2 }],
              },
              error: null,
            });
          }
          if (name === 'exec_analytics_v2_quality') {
            return Promise.resolve({
              data: {
                ok: true,
                attribution_window: { before_days: 30, after_days: 90 },
                issues: [],
                warnings: [],
              },
              error: null,
            });
          }
          return Promise.resolve({ data: {}, error: null });
        },
        from(table) {
          if (table === 'cycles') {
            return {
              select() { return this; },
              order() { return Promise.resolve({ data: [{ cycle_code: '2026.1', cycle_label: 'Cycle 2026.1', is_current: true, sort_order: 1 }], error: null }); },
            };
          }
          if (table === 'tribes') {
            return {
              select() { return this; },
              eq() { return this; },
              order() { return Promise.resolve({ data: [{ id: 1, name: 'Radar Tecnologico', is_active: true }], error: null }); },
            };
          }
          return {
            select() { return this; },
            eq() { return this; },
            order() { return Promise.resolve({ data: [], error: null }); },
          };
        },
      };
      window.navGetMember = () => fakeMember;
      window.navGetSb = () => fakeSb;
      window.dispatchEvent(new CustomEvent('nav:member', { detail: fakeMember }));
    });
    await analyticsPage.locator('#analytics-panel').waitFor({ state: 'visible' });
    assert.equal(await analyticsPage.locator('#analytics-denied').isVisible(), false);
    assert.equal(await analyticsPage.locator('#analytics-filter-cycle').isVisible(), true);
    assert.equal(await analyticsPage.locator('#analytics-interpretation-card').isVisible(), true);
    // p211: exec_funnel_summary + exec_analytics_v2_quality dropped p59 (see
    // analytics.astro:loadAnalyticsV2 comment). Removed assertions that depended
    // on mock data from those RPCs — funnel/quality renders null in real prod.
    // Coverage retained: filter shell, interpretation card, leadership matrix,
    // copy button + Scope line all flow through exec_role_transitions (live).
    await analyticsPage.waitForFunction(
      () => (document.getElementById('analytics-transition-matrix')?.textContent || '').match(/researcher|tribe_leader/),
      { timeout: 10000 }
    );
    assert.match(await analyticsPage.locator('#analytics-transition-matrix').textContent() || '', /researcher|tribe_leader/);
    await analyticsPage.locator('#analytics-copy-summary').click();
    const copiedSummary = await analyticsPage.evaluate(() => (window).__copiedSummary || '');
    assert.match(copiedSummary, /Scope:/);
    await analyticsPage.close();

    await page.close();
    console.log('Browser guard, home runtime, webinars/curatorship admin, and analytics readonly test passed.');
  } finally {
    await browser.close();
    devServer?.kill('SIGTERM');
  }
}

run().catch((error) => {
  console.error(error?.stack || error?.message || error);
  process.exit(1);
});
