// #2586 — envio avulso de corpo livre: renderização pura, sem Deno nem rede, para o send-campaign e para o teste.
//
// O corpo é TEXTO digitado no admin. Ele nunca entra cru no HTML: é escapado e quebrado em parágrafos. As
// variáveis do envio avulso comum ({{key}}) entram cruas no HTML do template, e por isso o corpo livre NÃO passa
// por aquele laço.
//
// O template tem um bloco que só o destinatário externo recebe (o aviso de privacidade, art. 9 da LGPD):
//   HTML:  <!--EXTERNO--> ... <!--/EXTERNO-->
//   texto: [[EXTERNO]] ... [[/EXTERNO]]
// Para membro o bloco sai inteiro; para externo saem só os marcadores.

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

/** "Maria da Silva" → "Maria". Sem nome, devolve ''. */
export function firstName(full: string | null | undefined): string {
  return (full ?? '').trim().split(/\s+/)[0] ?? ''
}

/** Texto em parágrafos: linha em branco separa parágrafo, quebra simples vira <br>. */
export function textToHtml(text: string): string {
  return text.replace(/\r\n?/g, '\n').trim().split(/\n{2,}/)
    .map((p) => `<p>${escapeHtml(p).replace(/\n/g, '<br>')}</p>`)
    .join('')
}

function keepOrDropBlock(source: string, open: string, close: string, keep: boolean): string {
  const re = new RegExp(`${open.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([\\s\\S]*?)${close.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'g')
  return source.replace(re, (_m, inner: string) => (keep ? inner : ''))
}

export interface FreeformInput {
  subject: string
  body: string
  recipientName: string | null | undefined
  isExternal: boolean
  templateSubject: string
  templateHtml: string
  templateText: string
}

export function renderFreeform(i: FreeformInput): { subject: string; html: string; text: string } {
  const fname = firstName(i.recipientName)
  const fill = (s: string) => s.split('{first_name}').join(fname)
  // cabeçalho de e-mail não aceita quebra de linha
  const subjectText = fill(i.subject).replace(/[\r\n]+/g, ' ').trim()
  const bodyText = fill(i.body)

  const subject = i.templateSubject.split('{{subject}}').join(subjectText)
  const html = keepOrDropBlock(i.templateHtml, '<!--EXTERNO-->', '<!--/EXTERNO-->', i.isExternal)
    .split('{{content_html}}').join(textToHtml(bodyText))
  const text = keepOrDropBlock(i.templateText, '[[EXTERNO]]', '[[/EXTERNO]]', i.isExternal)
    .split('{{content_text}}').join(bodyText.trim())
  return { subject, html, text }
}

/** Reply-to do envio: o do tema; sem ele, o padrão da plataforma; sem os dois, nenhum. */
export function resolveReplyTo(themeReplyTo: string | null | undefined, defaultReplyTo: string | null | undefined): string | null {
  const ok = (v: string | null | undefined) => (typeof v === 'string' && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v.trim()) ? v.trim() : null)
  return ok(themeReplyTo) ?? ok(defaultReplyTo)
}
