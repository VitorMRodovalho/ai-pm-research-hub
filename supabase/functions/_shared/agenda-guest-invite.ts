// #2593 (C2) — convite e cancelamento ao convidado externo da Agenda Viva: renderização pura, sem Deno nem rede,
// para o send-campaign e para o teste.
//
// Os valores vêm de quem reservou o bloco (título) e do cadastro (nomes). Nada entra cru no HTML: no HTML cada
// valor é escapado; no texto e no assunto entra como texto (o assunto sem quebra de linha, que é cabeçalho).
// O template é o do envio avulso com o miolo trocado, então o rodapé de pessoa externa é o mesmo:
//   HTML:  <!--EXTERNO--> ... <!--/EXTERNO-->      texto: [[EXTERNO]] ... [[/EXTERNO]]
//
// O ICS segue a RFC 5545: linhas terminadas em CRLF, dobradas em 75 octetos, texto escapado (\ ; , e quebra).
// Convite = METHOD:REQUEST; cancelamento = METHOD:CANCEL com o MESMO UID e SEQUENCE maior, que é o que faz a
// agenda do convidado trocar ou remover o evento em vez de criar outro.

import { escapeHtml, firstName } from './freeform-message.ts'

export type AgendaLang = 'pt-BR' | 'en-US' | 'es-LATAM'
export type AgendaKind = 'invite' | 'cancel'

const TZ = 'America/Sao_Paulo'

/** "pt" / "en" / "es" (chave dos templates) → tag da plataforma. */
export function langFromKey(key: string | null | undefined): AgendaLang {
  return key === 'en' ? 'en-US' : key === 'es' ? 'es-LATAM' : 'pt-BR'
}

/** Data e hora da reunião no fuso de Brasília, no idioma do convite. */
export function formatMeetingWhen(startUtcIso: string, lang: AgendaLang): { date: string; time: string } {
  const d = new Date(startUtcIso)
  if (Number.isNaN(d.getTime())) return { date: '', time: '' }
  const locale = lang === 'en-US' ? 'en-US' : lang === 'es-LATAM' ? 'es' : 'pt-BR'
  const date = new Intl.DateTimeFormat(locale, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: TZ }).format(d)
  const time = new Intl.DateTimeFormat(locale, { hour: '2-digit', minute: '2-digit', hour12: lang === 'en-US', timeZone: TZ }).format(d)
  return { date, time }
}

export interface AgendaVars {
  recipientName: string | null | undefined
  memberName: string
  blockTitle: string
  durationMin: number | string
  startUtc: string
  link: string
}

function keepOrDropBlock(source: string, open: string, close: string, keep: boolean): string {
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const re = new RegExp(`${esc(open)}([\\s\\S]*?)${esc(close)}`, 'g')
  return source.replace(re, (_m, inner: string) => (keep ? inner : ''))
}

export function renderAgendaGuestMessage(i: {
  vars: AgendaVars
  lang: AgendaLang
  isExternal: boolean
  templateSubject: string
  templateHtml: string
  templateText: string
}): { subject: string; html: string; text: string } {
  const when = formatMeetingWhen(i.vars.startUtc, i.lang)
  const values: Record<string, string> = {
    first_name: firstName(i.vars.recipientName),
    member_name: (i.vars.memberName ?? '').trim(),
    block_title: (i.vars.blockTitle ?? '').trim(),
    duration: String(i.vars.durationMin ?? ''),
    date: when.date,
    time: when.time,
    link: (i.vars.link ?? '').trim(),
  }
  const fill = (s: string, enc: (v: string) => string) =>
    Object.entries(values).reduce((acc, [k, v]) => acc.split(`{{${k}}}`).join(enc(v)), s)
  const subject = fill(i.templateSubject, (v) => v).replace(/[\r\n]+/g, ' ').trim()
  const html = fill(keepOrDropBlock(i.templateHtml, '<!--EXTERNO-->', '<!--/EXTERNO-->', i.isExternal), escapeHtml)
  const text = fill(keepOrDropBlock(i.templateText, '[[EXTERNO]]', '[[/EXTERNO]]', i.isExternal), (v) => v)
  return { subject, html, text }
}

/** Texto de propriedade do ICS: barra, ponto e vírgula, vírgula e quebra de linha escapados. */
export function icsText(v: string): string {
  return (v ?? '').replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r\n?|\n/g, '\\n')
}

/** Dobra a linha em 75 octetos (UTF-8), sem partir um caractere; continuação começa com espaço. */
export function foldLine(line: string): string {
  const enc = new TextEncoder()
  const out: string[] = []
  let cur = ''
  let curBytes = 0
  for (const ch of line) {
    const b = enc.encode(ch).length
    const limit = out.length === 0 ? 75 : 74 // a continuação já gasta 1 octeto com o espaço
    if (curBytes + b > limit) {
      out.push(cur)
      cur = ch
      curBytes = b
    } else {
      cur += ch
      curBytes += b
    }
  }
  out.push(cur)
  return out.join('\r\n ')
}

/** 2026-10-18T22:00:00Z → 20261018T220000Z */
export function icsUtc(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) throw new Error(`invalid date: ${iso}`)
  return d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')
}

/** Endereço de e-mail que entra numa URI mailto: do ICS; recusa o que poderia abrir outro parâmetro. */
function mailto(addr: string): string {
  const a = (addr ?? '').trim().toLowerCase()
  if (!/^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(a)) throw new Error('invalid e-mail for ICS')
  return `mailto:${a}`
}

export interface IcsInput {
  kind: AgendaKind
  uid: string
  sequence: number
  startUtc: string
  endUtc: string
  summary: string
  description: string
  url: string
  organizerEmail: string
  organizerName: string
  attendeeEmail: string
  attendeeName: string
  dtstamp?: string
}

export function buildAgendaIcs(i: IcsInput): string {
  const method = i.kind === 'cancel' ? 'CANCEL' : 'REQUEST'
  const cn = (n: string) => `"${(n ?? '').replace(/["\r\n]/g, '').trim()}"`
  const lines = [
    'BEGIN:VCALENDAR',
    'PRODID:-//Nucleo IA & GP//Agenda Viva//PT',
    'VERSION:2.0',
    'CALSCALE:GREGORIAN',
    `METHOD:${method}`,
    'BEGIN:VEVENT',
    `UID:${icsText(i.uid)}`,
    `SEQUENCE:${Math.max(0, Math.trunc(i.sequence))}`,
    `DTSTAMP:${icsUtc(i.dtstamp ?? new Date().toISOString())}`,
    `DTSTART:${icsUtc(i.startUtc)}`,
    `DTEND:${icsUtc(i.endUtc)}`,
    `SUMMARY:${icsText(i.summary)}`,
    `DESCRIPTION:${icsText(i.description)}`,
    ...(i.url ? [`LOCATION:${icsText(i.url)}`, `URL:${icsText(i.url)}`] : []),
    `ORGANIZER;CN=${cn(i.organizerName)}:${mailto(i.organizerEmail)}`,
    `ATTENDEE;CN=${cn(i.attendeeName)};ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=FALSE:${mailto(i.attendeeEmail)}`,
    `STATUS:${i.kind === 'cancel' ? 'CANCELLED' : 'CONFIRMED'}`,
    'TRANSP:OPAQUE',
    'END:VEVENT',
    'END:VCALENDAR',
  ]
  return lines.map(foldLine).join('\r\n') + '\r\n'
}

/** Base64 de texto UTF-8, para o anexo do Resend. */
export function toBase64Utf8(s: string): string {
  const bytes = new TextEncoder().encode(s)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin)
}

/** Anexo no formato do Resend (filename, content em base64, content_type). */
export function icsAttachment(ics: string, kind: AgendaKind): { filename: string; content: string; content_type: string } {
  const method = kind === 'cancel' ? 'CANCEL' : 'REQUEST'
  return {
    filename: kind === 'cancel' ? 'cancelamento.ics' : 'convite.ics',
    content: toBase64Utf8(ics),
    content_type: `text/calendar; charset=utf-8; method=${method}`,
  }
}
