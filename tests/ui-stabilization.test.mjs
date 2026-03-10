import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = '/home/vitormrodovalho/Desktop/ai-pm-research-hub';

function read(relativePath) {
  return readFileSync(resolve(ROOT, relativePath), 'utf8');
}

test('profile uses delegated credly normalization instead of per-render rebind helper', () => {
  const content = read('src/pages/profile.astro');
  assert.equal(content.includes('bindCredlyField('), false);
  assert.equal(content.includes("target.id === 'self-credly'"), true);
});

test('selection page no longer hardcodes cycle tabs or snapshot cycle title', () => {
  const content = read('src/pages/admin/selection.astro');
  assert.equal(content.includes('data-cycle="3"'), false);
  assert.equal(content.includes('Comparação de Snapshots — Ciclo 3'), false);
  assert.equal(content.includes('loadSelectionCycles()'), true);
});

test('confirm dialog no longer mutates confirm button onclick directly', () => {
  const content = read('src/components/ui/ConfirmDialog.astro');
  assert.equal(content.includes('btn.onclick ='), false);
  assert.equal(content.includes("document.getElementById('confirm-btn')?.addEventListener('click'"), true);
});

test('admin webinars now reuses the events stack instead of staying a placeholder', () => {
  const content = read('src/pages/admin/webinars.astro');
  assert.equal(content.includes('Em Breve'), false);
  assert.equal(content.includes("sb.rpc('get_events_with_attendance'"), true);
  assert.equal(content.includes("sb.rpc('list_meeting_artifacts'"), true);
  assert.equal(content.includes("sb.from('hub_resources').select('*').eq('is_active', true).eq('asset_type', 'webinar')"), true);
  assert.equal(content.includes("ev.type === 'webinar'"), true);
  assert.equal(content.includes("canAccessAdminRoute(member, 'admin_webinars')"), true);
  assert.equal(content.includes("navSb?.auth?.getSession"), true);
  assert.equal(content.includes('list_webinars'), false);
  assert.equal(content.includes('Agenda & Presenca'), true);
  assert.equal(content.includes('/admin/comms'), true);
  assert.equal(content.includes('Publicacao de replay'), true);
  assert.equal(content.includes("publicationBadge('Presentations'"), true);
  assert.equal(content.includes("publicationBadge('Workspace'"), true);
  assert.equal(content.includes('Acoes rapidas prioritarias'), true);
  assert.equal(content.includes('function operatorAction(ev: any)'), true);
  assert.equal(content.includes('buildAttendanceHref(ev: any'), true);
  assert.equal(content.includes('buildCommsHref(ev: any'), true);
  assert.equal(content.includes('buildPresentationsHref(ev: any)'), true);
  assert.equal(content.includes('buildWorkspaceHref(ev: any)'), true);
  assert.equal(content.includes("params.set('eventId', String(ev.id))"), true);
  assert.equal(content.includes("params.set('focus', 'broadcasts')"), true);
  assert.equal(content.includes("params.set('tab', 'events')"), true);
  assert.equal(content.includes("params.set('type', 'webinar')"), true);
  assert.equal(content.includes('Proxima acao:'), true);
  assert.equal(content.includes('renderActions(webinars);'), true);
});

test('presentations and workspace accept deep-link query filters for webinar follow-through', () => {
  const presentations = read('src/pages/presentations.astro');
  const workspace = read('src/pages/workspace.astro');
  assert.equal(presentations.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(presentations.includes("const q = params.get('q')"), true);
  assert.equal(presentations.includes("const tribe = params.get('tribe')"), true);
  assert.equal(presentations.includes("document.getElementById('pres-search')"), true);
  assert.equal(workspace.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(workspace.includes("activeType = params.get('type') || ''"), true);
  assert.equal(workspace.includes("searchQuery = (params.get('q') || '').trim()"), true);
  assert.equal(workspace.includes('syncTypeButtons();'), true);
});

test('attendance and admin comms accept contextual webinar handoff state from URL', () => {
  const attendance = read('src/pages/attendance.astro');
  const comms = read('src/pages/admin/comms.astro');
  assert.equal(attendance.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(attendance.includes("ATTENDANCE_ROUTE.eventId = params.get('eventId') || ''"), true);
  assert.equal(attendance.includes("ATTENDANCE_ROUTE.edit = params.get('edit') === '1'"), true);
  assert.equal(attendance.includes("document.getElementById('attendance-search')"), true);
  assert.equal(attendance.includes("openEditEvent(focused);"), true);
  assert.equal(attendance.includes("document.getElementById('edit-ev-context')"), true);
  assert.equal(attendance.includes('buildAttendanceCommsHref(ev: any)'), true);
  assert.equal(attendance.includes("data-action=\"open-focused-edit\""), true);
  assert.equal(comms.includes("new URLSearchParams(window.location.search)"), true);
  assert.equal(comms.includes("COMMS_ROUTE.focus = params.get('focus') || ''"), true);
  assert.equal(comms.includes("COMMS_ROUTE.context = params.get('context') || ''"), true);
  assert.equal(comms.includes("document.getElementById('comms-broadcast-search')"), true);
  assert.equal(comms.includes("document.getElementById('broadcast-section')?.scrollIntoView"), true);
  assert.equal(comms.includes('buildCommsPlaybook()'), true);
  assert.equal(comms.includes('navigator.clipboard?.writeText'), true);
  assert.equal(comms.includes('data-action="copy-template"'), true);
});

test('schedule flow no longer depends on far-future deadline sentinel', () => {
  const scheduleContent = read('src/lib/schedule.ts');
  const tribesContent = read('src/components/sections/TribesSection.astro');
  const heroContent = read('src/components/sections/HeroSection.astro');
  assert.equal(scheduleContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(tribesContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(heroContent.includes('2030-12-31T23:59:59Z'), false);
  assert.equal(tribesContent.includes('selectionUnavailable'), true);
});

test('tribes section touched links no longer use inline onclick handlers', () => {
  const content = read('src/components/sections/TribesSection.astro');
  assert.equal(content.includes('onclick='), false);
  assert.equal(content.includes('data-stop-propagation'), true);
});

test('home pages resolve shared home schedule instead of fetching only the deadline', () => {
  const pt = read('src/pages/index.astro');
  const en = read('src/pages/en/index.astro');
  const es = read('src/pages/es/index.astro');
  for (const content of [pt, en, es]) {
    assert.equal(content.includes('getHomeSchedule'), true);
    assert.equal(content.includes('schedule={homeSchedule}'), true);
    assert.equal(content.includes('AgendaSection deadline={deadlineIso}'), true);
    assert.equal(content.includes('ResourcesSection deadline={deadlineIso}'), true);
  }
});

test('home fallback copy no longer hardcodes kickoff dates or recurring meeting times', () => {
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');
  const hero = read('src/components/sections/HeroSection.astro');

  assert.equal(pt.includes('5 de Março de 2026 · 19:30 BRT · Google Meet'), false);
  assert.equal(en.includes('March 5, 2026 · 7:30 PM BRT · Google Meet'), false);
  assert.equal(es.includes('5 de Marzo de 2026 · 19:30 BRT · Google Meet'), false);
  assert.equal(pt.includes('Quintas · 19:30 → 20:30 BRT'), false);
  assert.equal(en.includes('Thursdays · 7:30 → 8:30 PM BRT'), false);
  assert.equal(es.includes('Jueves · 19:30 → 20:30 BRT'), false);
  assert.equal(hero.includes("hi18n.meetingSchedule || 'Quintas · 19:30 → 20:30 BRT'"), false);
  assert.equal(hero.includes("hi18n.recurringMeeting || 'Reunião Recorrente · Quintas 19:30 BRT'"), false);
});

test('resources fallback playlist no longer hardcodes saturday deadline copy', () => {
  const resources = read('src/components/sections/ResourcesSection.astro');
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');

  assert.equal(resources.includes('8 vídeos. Escolha até Sáb 12h.'), false);
  assert.equal(resources.includes("title: 'Playlist YouTube'"), false);
  assert.equal(resources.includes("t('resources.playlist.descPrefix', lang)"), true);
  assert.equal(pt.includes("'resources.playlist.descPrefix'"), true);
  assert.equal(en.includes("'resources.playlist.descPrefix'"), true);
  assert.equal(es.includes("'resources.playlist.descPrefix'"), true);
});

test('public home locale copy no longer hardcodes cycle 3 labels', () => {
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');

  assert.equal(pt.includes('KICK-OFF OFICIAL — CICLO 03 (2026/1)'), false);
  assert.equal(en.includes('OFFICIAL KICK-OFF — CYCLE 03 (2026/1)'), false);
  assert.equal(es.includes('KICK-OFF OFICIAL — CICLO 03 (2026/1)'), false);
  assert.equal(pt.includes('os primeiros certificados do Ciclo 3 serão exibidos aqui.'), false);
  assert.equal(en.includes('the first Cycle 3 certifications will be displayed here.'), false);
  assert.equal(es.includes('las primeras certificaciones del Ciclo 3 se mostrarán aquí.'), false);
  assert.equal(pt.includes('coordenação e governança · Ciclo 3'), false);
  assert.equal(en.includes('coordination and governance · Cycle 3'), false);
  assert.equal(es.includes('coordinación y gobernanza · Ciclo 3'), false);
  assert.equal(pt.includes('participantes ativos · Ciclo 3'), false);
  assert.equal(en.includes('active participants · Cycle 3'), false);
  assert.equal(es.includes('participantes activos · Ciclo 3'), false);
  assert.equal(pt.includes('gestão, operações & comunicação · Ciclo 3'), false);
  assert.equal(en.includes('management, operations & communications · Cycle 3'), false);
  assert.equal(es.includes('gestión, operaciones & comunicación · Ciclo 3'), false);
});

test('hero post-kickoff state now uses runtime kickoff metadata before optional event enrichment', () => {
  const hero = read('src/components/sections/HeroSection.astro');

  assert.equal(hero.includes("kickoffAt: schedule?.kickoffAt ?? null"), true);
  assert.equal(hero.includes("platformLabel: schedule?.platformLabel ?? null"), true);
  assert.equal(hero.includes("const heroKickoffPassed ="), true);
  assert.equal(hero.includes("const evDate = new Date(ev.date + 'T22:30:00Z');"), false);
  assert.equal(hero.includes("eventArea.innerHTML = kickoffFallbackHtml(dateStr);"), true);
});

test('tribes deadline formatting no longer relies on manual UTC math or stale fixed fallback copy', () => {
  const tribes = read('src/components/sections/TribesSection.astro');
  const pt = read('src/i18n/pt-BR.ts');
  const en = read('src/i18n/en-US.ts');
  const es = read('src/i18n/es-LATAM.ts');

  assert.equal(tribes.includes("const months = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];"), false);
  assert.equal(tribes.includes("d.getUTCHours() - 3"), false);
  assert.equal(tribes.includes("new Intl.DateTimeFormat(currentLang"), true);
  assert.equal(pt.includes("'tribes.deadline': 'Encerra Sáb 08/Mar 12h BRT'"), false);
  assert.equal(en.includes("'tribes.deadline': 'Closes Sat 03/08 12PM BRT'"), false);
  assert.equal(es.includes("'tribes.deadline': 'Cierra Sáb 08/Mar 12h BRT'"), false);
});
