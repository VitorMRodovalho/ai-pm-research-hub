import { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { usePageI18n } from '../../../i18n/usePageI18n';
import { escapeHtml, renderFreeform } from '../../../../supabase/functions/_shared/freeform-message';

// #2586: mensagem avulsa de corpo livre para UMA pessoa (membro ou e-mail), com tema, prévia e envio rastreado.
// O servidor (admin_send_one_off_message) decide quem pode, resolve o e-mail de membro para o membro, recusa endereço
// suprimido, cria a pessoa externa com prazo de guarda e registra quem enviou. A prévia usa a MESMA renderização da
// EF (_shared/freeform-message.ts) sobre o template real, para mostrar assinatura e rodapé como vão sair.

interface Theme { slug: string; label_i18n: Record<string, string>; sort_order: number }
interface Template { subject: Record<string, string>; body_html: Record<string, string> }

const SUBJECT_MAX = 200;
const BODY_MAX = 10000;
const NAME_MAX = 120;
const EMAIL_RE = /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$/i;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default function OneOffMessageIsland() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const lp: string = (typeof window !== 'undefined' && (window as any).__LANG_PREFIX) || '';
  const langCode = lp === '/en' ? 'en' : lp === '/es' ? 'es' : 'pt';
  const pageLang = lp === '/en' ? 'en-US' : lp === '/es' ? 'es-LATAM' : 'pt-BR';

  const [themes, setThemes] = useState<Theme[]>([]);
  const [themesError, setThemesError] = useState(false);
  const [template, setTemplate] = useState<Template | null>(null);
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState<string>('');
  const [email, setEmail] = useState('');
  const [emailTouched, setEmailTouched] = useState(false);
  const [name, setName] = useState('');
  const [theme, setTheme] = useState('');
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [language, setLanguage] = useState(pageLang);
  const [confirming, setConfirming] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [sent, setSent] = useState<{ kind: string } | null>(null);
  const sendBtnRef = useRef<HTMLButtonElement | null>(null);
  const sentTitleRef = useRef<HTMLParagraphElement | null>(null);

  useEffect(() => {
    let tries = 0;
    async function load() {
      const sb = getSb();
      if (!sb) { if (tries++ < 20) setTimeout(load, 300); return; }
      const [{ data: th, error: thErr }, { data: tp }] = await Promise.all([
        sb.from('campaign_themes').select('slug, label_i18n, sort_order').eq('is_active', true).order('sort_order'),
        sb.from('campaign_templates').select('subject, body_html').eq('slug', 'avulso-corpo-livre').maybeSingle(),
      ]);
      setThemesError(!!thErr);
      setThemes(Array.isArray(th) ? th : []);
      setTemplate(tp ?? null);
      const mid = new URLSearchParams(window.location.search).get('member');
      if (mid && UUID_RE.test(mid)) {
        setMemberId(mid);
        const { data: m } = await sb.from('members').select('name').eq('id', mid).maybeSingle();
        setMemberName(m?.name || '');
      }
    }
    load();
  }, [getSb]);

  useEffect(() => { if (confirming) sendBtnRef.current?.focus(); }, [confirming]);
  useEffect(() => { if (sent) sentTitleRef.current?.focus(); }, [sent]);

  const emailOk = EMAIL_RE.test(email.trim()) && email.trim().length <= 254;
  const recipientName = (memberId ? memberName : name).trim();
  const missing: string[] = [];
  if (!memberId && !emailOk) missing.push(t('campaigns.oneOff.email', 'E-mail do destinatário'));
  if (!theme) missing.push(t('campaigns.oneOff.theme', 'Tema'));
  if (!subject.trim()) missing.push(t('campaigns.oneOff.subject', 'Assunto'));
  if (!body.trim()) missing.push(t('campaigns.oneOff.body', 'Mensagem'));
  const valid = missing.length === 0 && subject.trim().length <= SUBJECT_MAX && body.length <= BODY_MAX;
  const nameMissingForGreeting = body.includes('{first_name}') && !recipientName;

  // prévia: a mesma renderização da EF, sobre o template real, no idioma escolhido
  const preview = useMemo(() => {
    const key = (memberId ? pageLang : language).startsWith('en') ? 'en' : (memberId ? pageLang : language).startsWith('es') ? 'es' : 'pt';
    const tplHtml = template?.body_html?.[key] || template?.body_html?.pt || '{{content_html}}';
    const r = renderFreeform({
      subject, body, recipientName, isExternal: !memberId,
      templateSubject: template?.subject?.[key] || '{{subject}}', templateHtml: tplHtml, templateText: '',
    });
    const html = r.html
      .split('{unsubscribe_url}').join('#')
      .split('{platform.url}').join(typeof window !== 'undefined' ? window.location.origin : '')
      .split('{member.name}').join(escapeHtml(recipientName));
    return { subject: r.subject, html };
  }, [template, subject, body, recipientName, memberId, language, pageLang]);

  function errorText(err: { code?: string; message?: string }): string {
    const msg = err.message || '';
    if (err.code === '42501') return t('campaigns.oneOff.forbidden', 'Só a gestão envia mensagens avulsas.');
    if (msg.includes('Per-address limit')) return t('campaigns.oneOff.errAddressLimit', 'Este endereço já recebeu o máximo de mensagens avulsas permitido (1 por dia, 3 em 30 dias).');
    if (msg.includes('Daily limit')) return t('campaigns.oneOff.errSenderLimit', 'Você atingiu o limite diário de mensagens avulsas.');
    if (msg.includes('suppressed')) return t('campaigns.oneOff.errSuppressed', 'Este endereço está bloqueado (reclamação, devolução permanente ou descadastro). A mensagem não foi enviada.');
    if (msg.includes('Invalid or reserved')) return t('campaigns.oneOff.errInvalidEmail', 'E-mail inválido.');
    if (msg.includes('no e-mail')) return t('campaigns.oneOff.errNoEmail', 'Este membro não tem e-mail cadastrado.');
    if (msg.includes('not found')) return t('campaigns.oneOff.errNotFound', 'Destinatário não encontrado.');
    return t('campaigns.oneOff.error', 'Não foi possível enviar.');
  }

  async function send() {
    const sb = getSb();
    if (!sb || !valid) return;
    setSending(true);
    setError('');
    const { data, error: err } = await sb.rpc('admin_send_one_off_message', {
      p_member_id: memberId,
      p_email: memberId ? null : email.trim(),
      p_name: memberId ? null : (name.trim().slice(0, NAME_MAX) || null),
      p_theme: theme,
      p_subject: subject.trim(),
      p_body: body,
      p_language: memberId ? pageLang : language,
    });
    setSending(false);
    setConfirming(false);
    if (err) { setError(errorText(err)); return; }
    setSent({ kind: data?.recipient_kind || '' });
    (window as any).toast?.(t('campaigns.oneOff.sent', 'Mensagem enviada para a fila de envio.'), 'success');
  }

  function reset() {
    setSent(null); setSubject(''); setBody(''); setEmail(''); setEmailTouched(false); setName('');
    if (!new URLSearchParams(window.location.search).get('member')) { setMemberId(null); setMemberName(''); }
  }

  const input = 'w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--fg)] text-sm';
  const label = 'block text-[12px] font-semibold text-[var(--fg-muted)] mb-1';
  const btn = 'min-h-[40px] px-4 rounded-lg text-sm font-semibold cursor-pointer';

  if (sent) {
    return (
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-6 text-sm" role="status">
        <p ref={sentTitleRef} tabIndex={-1} className="font-semibold text-[var(--fg)] mb-1 outline-none">{t('campaigns.oneOff.sentTitle', 'Mensagem enviada para a fila.')}</p>
        <p className="text-[var(--fg-muted)] mb-4">
          {sent.kind === 'member'
            ? t('campaigns.oneOff.sentMember', 'O destinatário é membro: se ele já recebeu e-mail hoje, a mensagem sai amanhã às 7h. Ela aparece no histórico de comunicações do membro.')
            : t('campaigns.oneOff.sentExternal', 'O destinatário é externo: a mensagem sai com o aviso de privacidade, e o e-mail fica guardado por até 1 ano.')}
        </p>
        <div className="flex flex-wrap gap-2">
          {memberId && (
            <a href={`${lp}/admin/members/${encodeURIComponent(memberId)}`} className={`${btn} inline-flex items-center border border-[var(--border)] text-[var(--fg)] no-underline`}>
              {t('campaigns.oneOff.backToMember', 'Ver o histórico do membro')}
            </a>
          )}
          <button type="button" onClick={reset} className={`${btn} bg-navy text-white border-0`}>
            {t('campaigns.oneOff.another', 'Escrever outra')}
          </button>
        </div>
      </div>
    );
  }

  return (
    <form className="grid grid-cols-1 lg:grid-cols-2 gap-6" onSubmit={(e) => { e.preventDefault(); if (valid) setConfirming(true); }}>
      <div className="space-y-4">
        <p className="text-[13px] text-[var(--fg-muted)]">{t('campaigns.oneOff.intro', 'Uma mensagem para uma pessoa só. Envio para mais de uma pessoa segue pela campanha, com aprovação.')}</p>
        {memberId ? (
          <div className="rounded-lg border border-[var(--border)] px-3 py-2 text-sm">
            <span className="text-[var(--fg-muted)]">{t('campaigns.oneOff.toMember', 'Para o membro')}: </span>
            <strong className="text-[var(--fg)]">{memberName || memberId}</strong>
          </div>
        ) : (
          <>
            <div>
              <label className={label} htmlFor="oneoff-email">{t('campaigns.oneOff.email', 'E-mail do destinatário')} *</label>
              <input id="oneoff-email" type="email" required className={input} value={email} autoComplete="off"
                aria-invalid={emailTouched && !emailOk} aria-describedby="oneoff-email-hint"
                onChange={(e) => setEmail(e.target.value)} onBlur={() => setEmailTouched(true)} />
              <p id="oneoff-email-hint" className={`text-[11px] mt-1 ${emailTouched && email && !emailOk ? 'text-red-700' : 'text-[var(--fg-muted)]'}`}>
                {emailTouched && email && !emailOk
                  ? t('campaigns.oneOff.errInvalidEmail', 'E-mail inválido.')
                  : t('campaigns.oneOff.emailHint', 'Se o e-mail for de um membro, a mensagem vai para o membro.')}
              </p>
            </div>
            <div>
              <label className={label} htmlFor="oneoff-name">{t('campaigns.oneOff.name', 'Nome (opcional)')}</label>
              <input id="oneoff-name" type="text" className={input} value={name} maxLength={NAME_MAX} autoComplete="off" onChange={(e) => setName(e.target.value)} />
            </div>
          </>
        )}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className={label} htmlFor="oneoff-theme">{t('campaigns.oneOff.theme', 'Tema')} *</label>
            <select id="oneoff-theme" className={input} value={theme} required aria-describedby="oneoff-theme-hint" onChange={(e) => setTheme(e.target.value)}>
              <option value="">{t('campaigns.oneOff.chooseTheme', 'Escolha o tema')}</option>
              {themes.map((th) => <option key={th.slug} value={th.slug}>{th.label_i18n?.[langCode] || th.label_i18n?.pt || th.slug}</option>)}
            </select>
            <p id="oneoff-theme-hint" className="text-[11px] text-[var(--fg-muted)] mt-1">
              {themesError ? t('campaigns.oneOff.themesError', 'Não foi possível carregar os temas.') : t('campaigns.oneOff.themeHint', 'Classifica a mensagem no histórico e define a caixa que recebe a resposta.')}
            </p>
          </div>
          {!memberId && (
            <div>
              <label className={label} htmlFor="oneoff-lang">{t('campaigns.oneOff.language', 'Idioma do e-mail')}</label>
              <select id="oneoff-lang" className={input} value={language} onChange={(e) => setLanguage(e.target.value)}>
                <option value="pt-BR">Português</option>
                <option value="en-US">English</option>
                <option value="es-LATAM">Español</option>
              </select>
            </div>
          )}
        </div>
        <div>
          <label className={label} htmlFor="oneoff-subject">{t('campaigns.oneOff.subject', 'Assunto')} *</label>
          <input id="oneoff-subject" type="text" required className={input} value={subject} maxLength={SUBJECT_MAX} aria-describedby="oneoff-subject-count" onChange={(e) => setSubject(e.target.value)} />
          <p id="oneoff-subject-count" className="text-[11px] text-[var(--fg-muted)] mt-1">{subject.length}/{SUBJECT_MAX}</p>
        </div>
        <div>
          <label className={label} htmlFor="oneoff-body">{t('campaigns.oneOff.body', 'Mensagem')} *</label>
          <textarea id="oneoff-body" rows={10} required className={input} value={body} maxLength={BODY_MAX} aria-describedby="oneoff-body-hint" onChange={(e) => setBody(e.target.value)} />
          <p id="oneoff-body-hint" className="text-[11px] text-[var(--fg-muted)] mt-1">
            {body.length}/{BODY_MAX} · {t('campaigns.oneOff.bodyHint', 'Texto simples. Linha em branco separa parágrafos. Use {first_name} para o primeiro nome. A assinatura da equipe entra sozinha.')}
          </p>
          {nameMissingForGreeting && (
            <p className="text-[12px] text-amber-800 bg-amber-50 rounded px-2 py-1 mt-1" role="status">
              {t('campaigns.oneOff.nameMissing', 'O texto usa {first_name}, mas não há nome: o e-mail sairá sem o nome. Preencha o nome ou ajuste o texto.')}
            </p>
          )}
        </div>
        {error && <p className="text-sm text-red-700 bg-red-50 rounded-lg px-3 py-2" role="alert">{error}</p>}
        {!confirming ? (
          <div>
            <button type="submit" disabled={!valid} className={`${btn} bg-navy text-white border-0 disabled:opacity-50`}>
              {t('campaigns.oneOff.review', 'Revisar e enviar')}
            </button>
            {!valid && missing.length > 0 && (
              <p className="text-[11px] text-[var(--fg-muted)] mt-1">{t('campaigns.oneOff.missing', 'Falta')}: {missing.join(', ')}</p>
            )}
          </div>
        ) : (
          <div role="group" aria-label={t('campaigns.oneOff.confirmTitle', 'Confirmar envio')} className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-3 text-sm text-amber-900 space-y-2">
            <p>{t('campaigns.oneOff.confirm', 'Enviar esta mensagem para')} <strong>{memberId ? (memberName || memberId) : email.trim()}</strong>?</p>
            <p className="text-[12px]">{t('campaigns.oneOff.subject', 'Assunto')}: <strong>{preview.subject}</strong></p>
            <p className="text-[12px]">
              {memberId
                ? t('campaigns.oneOff.confirmMember', 'É membro: entra no histórico dele e respeita o limite de 1 e-mail por dia.')
                : t('campaigns.oneOff.confirmExternal', 'Se não for e-mail de membro: sai com o aviso de privacidade, e o e-mail fica guardado por até 1 ano.')}
            </p>
            <div className="flex gap-2">
              <button ref={sendBtnRef} type="button" onClick={send} disabled={sending} className={`${btn} bg-navy text-white border-0 disabled:opacity-50`}>
                {sending ? '…' : t('campaigns.oneOff.send', 'Enviar')}
              </button>
              <button type="button" onClick={() => setConfirming(false)} className={`${btn} border border-[var(--border)] bg-transparent`}>
                {t('campaigns.oneOff.cancel', 'Cancelar')}
              </button>
            </div>
          </div>
        )}
      </div>

      <section className="rounded-2xl border border-[var(--border)] bg-white text-gray-900 p-5 text-sm self-start" aria-label={t('campaigns.oneOff.preview', 'Prévia')}>
        <div className="text-[11px] uppercase tracking-wide text-gray-600 mb-2">{t('campaigns.oneOff.preview', 'Prévia')}</div>
        <div className="font-semibold mb-3">{preview.subject || '—'}</div>
        {/* conteúdo escapado pela mesma função da EF; template vem do banco (texto da gestão aprovado pelo GP) */}
        <div className="[&_p]:mb-3" dangerouslySetInnerHTML={{ __html: preview.html }} />
      </section>
    </form>
  );
}
