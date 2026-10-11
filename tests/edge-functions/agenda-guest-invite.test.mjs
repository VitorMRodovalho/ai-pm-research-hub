// #2593 (C2) — convite e cancelamento ao convidado externo da Agenda Viva: renderização e ICS (send-campaign).
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  renderAgendaGuestMessage, buildAgendaIcs, foldLine, icsText, icsUtc, formatMeetingWhen, toBase64Utf8,
  icsAttachment, langFromKey,
} from '../../supabase/functions/_shared/agenda-guest-invite.ts';

const TEMPLATE_HTML = '<p>Olá, {{first_name}},</p><p>{{member_name}} confirmou. Bloco: {{block_title}} ({{duration}} min). '
  + 'Quando: {{date}}, às {{time}}. <a href="{{link}}">{{link}}</a></p><p>Equipe</p><!--EXTERNO--><p>Aviso</p><!--/EXTERNO-->';
const TEMPLATE_TEXT = 'Olá, {{first_name}},\n\n{{member_name}} confirmou: {{block_title}}\n\nEquipe[[EXTERNO]]\n\n--\nAviso[[/EXTERNO]]';

const vars = {
  recipientName: 'Ana Convidada Exemplo',
  memberName: 'Membro <b>Exemplo</b>',
  blockTitle: 'IA & "governança" <script>alert(1)</script>',
  durationMin: 15,
  startUtc: '2026-10-22T22:00:00Z', // 19:00 em Brasília
  link: 'https://meet.example.org/abc?x=1&y=2',
};

const render = (over = {}) => renderAgendaGuestMessage({
  vars, lang: 'pt-BR', isExternal: true,
  templateSubject: 'Convite: {{block_title}} na Reunião Geral, {{date}}',
  templateHtml: TEMPLATE_HTML, templateText: TEMPLATE_TEXT, ...over,
});

test('valores digitados entram escapados no HTML e como texto no corpo de texto', () => {
  const { html, text } = render();
  assert.doesNotMatch(html, /<script/i);
  assert.doesNotMatch(html, /<b>Exemplo/);
  assert.match(html, /IA &amp; &quot;governança&quot; &lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.match(html, /href="https:\/\/meet\.example\.org\/abc\?x=1&amp;y=2"/);
  assert.match(text, /IA & "governança" <script>alert\(1\)<\/script>/);
  assert.match(text, /^Olá, Ana,/);
});

test('o assunto não carrega quebra de linha (é cabeçalho)', () => {
  const { subject } = render({ vars: { ...vars, blockTitle: 'linha 1\r\nBcc: alguem@example.org' } });
  assert.doesNotMatch(subject, /[\r\n]/);
});

test('o rodapé de pessoa externa fica para o externo e sai para quem é membro', () => {
  assert.match(render().html, /<p>Aviso<\/p>/);
  assert.match(render().text, /--\nAviso/);
  assert.doesNotMatch(render({ isExternal: false }).html, /Aviso/);
  assert.doesNotMatch(render({ isExternal: false }).text, /Aviso/);
  assert.doesNotMatch(render().html, /EXTERNO/);
});

test('data e hora saem no fuso de Brasília, no idioma do convite', () => {
  const pt = formatMeetingWhen(vars.startUtc, 'pt-BR');
  assert.match(pt.date, /quinta-feira, 22 de outubro de 2026/);
  assert.equal(pt.time, '19:00');
  const en = formatMeetingWhen(vars.startUtc, 'en-US');
  assert.match(en.date, /Thursday, October 22, 2026/);
  assert.match(en.time, /7:00\s?PM/);
  const es = formatMeetingWhen(vars.startUtc, 'es-LATAM');
  assert.match(es.date, /jueves, 22 de octubre de 2026/);
  assert.equal(es.time, '19:00');
  assert.equal(langFromKey('en'), 'en-US');
  assert.equal(langFromKey('es'), 'es-LATAM');
  assert.equal(langFromKey('pt'), 'pt-BR');
});

const icsBase = {
  kind: 'invite', uid: 'agenda-block-123@nucleoia.example.org', sequence: 29000000,
  startUtc: '2026-10-22T22:00:00Z', endUtc: '2026-10-22T23:30:00Z',
  summary: 'Convite: IA, governança; e mais', description: 'Linha 1\nLinha 2',
  url: 'https://meet.example.org/abc', organizerEmail: 'organizador@example.org', organizerName: 'Núcleo IA & GP',
  attendeeEmail: 'convidado@example.org', attendeeName: 'Ana "Convidada"', dtstamp: '2026-10-11T12:00:00Z',
};

test('ICS do convite: REQUEST, horários em UTC, organizador e convidado', () => {
  const ics = buildAgendaIcs(icsBase);
  assert.match(ics, /^BEGIN:VCALENDAR\r\n/);
  assert.match(ics, /\r\nMETHOD:REQUEST\r\n/);
  assert.match(ics, /\r\nUID:agenda-block-123@nucleoia\.example\.org\r\n/);
  assert.match(ics, /\r\nSEQUENCE:29000000\r\n/);
  assert.match(ics, /\r\nDTSTART:20261022T220000Z\r\n/);
  assert.match(ics, /\r\nDTEND:20261022T233000Z\r\n/);
  assert.match(ics, /\r\nSTATUS:CONFIRMED\r\n/);
  assert.match(ics, /ORGANIZER;CN="Núcleo IA & GP":mailto:organizador@example\.org/);
  assert.match(ics.replace(/\r\n /g, ''), /ATTENDEE;CN="Ana Convidada";ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=FALSE:mailto:convidado@example\.org/);
  assert.match(ics, /\r\nEND:VCALENDAR\r\n$/);
  // toda linha termina em CRLF: não sobra LF solto
  assert.doesNotMatch(ics.replace(/\r\n/g, ''), /\n/);
});

test('ICS do cancelamento: CANCEL, mesmo UID, status cancelado', () => {
  const ics = buildAgendaIcs({ ...icsBase, kind: 'cancel', sequence: 29000100 });
  assert.match(ics, /\r\nMETHOD:CANCEL\r\n/);
  assert.match(ics, /\r\nUID:agenda-block-123@nucleoia\.example\.org\r\n/);
  assert.match(ics, /\r\nSTATUS:CANCELLED\r\n/);
  assert.match(ics, /\r\nSEQUENCE:29000100\r\n/);
});

test('texto do ICS escapa barra, vírgula, ponto e vírgula e quebra de linha', () => {
  assert.equal(icsText('a\\b,c;d\ne'), 'a\\\\b\\,c\\;d\\ne');
  const ics = buildAgendaIcs(icsBase);
  assert.match(ics, /SUMMARY:Convite: IA\\, governança\\; e mais/);
  assert.match(ics, /DESCRIPTION:Linha 1\\nLinha 2/);
});

test('linha longa dobra em até 75 octetos sem partir caractere', () => {
  const long = 'DESCRIPTION:' + 'ação '.repeat(40);
  const folded = foldLine(long);
  const enc = new TextEncoder();
  for (const part of folded.split('\r\n')) assert.ok(enc.encode(part).length <= 75, `parte com ${enc.encode(part).length} octetos`);
  assert.equal(folded.split('\r\n').map((p, i) => (i === 0 ? p : p.slice(1))).join(''), long);
  assert.doesNotMatch(folded, /�/);
});

test('endereço que abriria outro parâmetro na URI é recusado', () => {
  assert.throws(() => buildAgendaIcs({ ...icsBase, attendeeEmail: 'x@example.org;RSVP=TRUE' }));
  assert.throws(() => buildAgendaIcs({ ...icsBase, organizerEmail: 'org@example.org\r\nATTENDEE:mailto:y@example.org' }));
  assert.throws(() => icsUtc('não é data'));
});

test('anexo no formato do Resend, com base64 de UTF-8 que volta igual', () => {
  const ics = buildAgendaIcs(icsBase);
  const att = icsAttachment(ics, 'invite');
  assert.equal(att.filename, 'convite.ics');
  assert.equal(att.content_type, 'text/calendar; charset=utf-8; method=REQUEST');
  assert.equal(new TextDecoder().decode(Uint8Array.from(atob(att.content), (c) => c.charCodeAt(0))), ics);
  const cancel = icsAttachment(buildAgendaIcs({ ...icsBase, kind: 'cancel' }), 'cancel');
  assert.equal(cancel.filename, 'cancelamento.ics');
  assert.match(cancel.content_type, /method=CANCEL$/);
  assert.equal(toBase64Utf8('ç'), 'w6c=');
});
