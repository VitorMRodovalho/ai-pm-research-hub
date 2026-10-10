import { useEffect, useMemo, useState, useCallback } from 'react';
import { usePageI18n } from '../../../i18n/usePageI18n';

// #2586: mensagem avulsa de corpo livre para UMA pessoa (membro ou e-mail), com tema, prévia e envio rastreado.
// O servidor (admin_send_one_off_message) decide quem pode, resolve o e-mail de membro para o membro, cria a
// pessoa externa com prazo de guarda e registra quem enviou. A EF escapa o corpo e põe o aviso de privacidade
// só para quem é externo. Esta tela não vê nada disso além do tipo de destinatário que o servidor devolve.

interface Theme { slug: string; label_i18n: Record<string, string>; sort_order: number }

const SUBJECT_MAX = 200;
const BODY_MAX = 10000;

function paragraphs(text: string): string[] {
  return text.replace(/\r\n?/g, '\n').trim().split(/\n{2,}/).filter(Boolean);
}

export default function OneOffMessageIsland() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const lp: string = (typeof window !== 'undefined' && (window as any).__LANG_PREFIX) || '';
  const langCode = lp === '/en' ? 'en' : lp === '/es' ? 'es' : 'pt';

  const [themes, setThemes] = useState<Theme[]>([]);
  const [memberId, setMemberId] = useState<string | null>(null);
  const [memberName, setMemberName] = useState<string>('');
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [theme, setTheme] = useState('');
  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [language, setLanguage] = useState('pt-BR');
  const [confirming, setConfirming] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [sent, setSent] = useState<{ kind: string } | null>(null);

  useEffect(() => {
    let tries = 0;
    async function load() {
      const sb = getSb();
      if (!sb) { if (tries++ < 20) setTimeout(load, 300); return; }
      const { data } = await sb.from('campaign_themes').select('slug, label_i18n, sort_order').eq('is_active', true).order('sort_order');
      setThemes(Array.isArray(data) ? data : []);
      const params = new URLSearchParams(window.location.search);
      const mid = params.get('member');
      if (mid) {
        setMemberId(mid);
        const { data: m } = await sb.from('members').select('name').eq('id', mid).maybeSingle();
        setMemberName(m?.name || '');
      }
    }
    load();
  }, [getSb]);

  const recipientLabel = memberId ? (memberName || memberId) : email.trim();
  const previewName = (memberId ? memberName : name).trim().split(/\s+/)[0] || '';
  const fill = (s: string) => s.split('{first_name}').join(previewName);
  const valid = useMemo(() => (
    (memberId || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim()))
    && theme && subject.trim().length > 0 && subject.trim().length <= SUBJECT_MAX
    && body.trim().length > 0 && body.length <= BODY_MAX
  ), [memberId, email, theme, subject, body]);

  async function send() {
    const sb = getSb();
    if (!sb || !valid) return;
    setSending(true);
    setError('');
    const { data, error: err } = await sb.rpc('admin_send_one_off_message', {
      p_member_id: memberId,
      p_email: memberId ? null : email.trim(),
      p_name: memberId ? null : (name.trim() || null),
      p_theme: theme,
      p_subject: subject.trim(),
      p_body: body,
      p_language: language,
    });
    setSending(false);
    setConfirming(false);
    if (err) {
      setError(err.code === '42501' ? t('campaigns.oneOff.forbidden', 'Só a gestão envia mensagens avulsas.') : (err.message || t('campaigns.oneOff.error', 'Não foi possível enviar.')));
      return;
    }
    setSent({ kind: data?.recipient_kind || '' });
    (window as any).toast?.(t('campaigns.oneOff.sent', 'Mensagem enviada para a fila de envio.'), 'success');
  }

  function reset() {
    setSent(null); setSubject(''); setBody(''); setEmail(''); setName('');
    if (!new URLSearchParams(window.location.search).get('member')) { setMemberId(null); setMemberName(''); }
  }

  const input = 'w-full px-3 py-2 rounded-lg border border-[var(--border)] bg-[var(--surface)] text-[var(--fg)] text-sm';
  const label = 'block text-[12px] font-semibold text-[var(--fg-muted)] mb-1';

  if (sent) {
    return (
      <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-6 text-sm" role="status">
        <p className="font-semibold text-[var(--fg)] mb-1">{t('campaigns.oneOff.sentTitle', 'Mensagem enviada para a fila.')}</p>
        <p className="text-[var(--fg-muted)] mb-4">
          {sent.kind === 'member'
            ? t('campaigns.oneOff.sentMember', 'O destinatário é membro: a mensagem respeita o limite de 1 e-mail por dia e aparece no histórico dele.')
            : t('campaigns.oneOff.sentExternal', 'O destinatário é externo: a mensagem sai com o aviso de privacidade e o e-mail fica guardado por até 1 ano.')}
        </p>
        <button type="button" onClick={reset} className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold border-0 cursor-pointer">
          {t('campaigns.oneOff.another', 'Escrever outra')}
        </button>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <div className="space-y-4">
        <p className="text-[13px] text-[var(--fg-muted)]">{t('campaigns.oneOff.intro', 'Uma mensagem para uma pessoa só, com registro de entrega, abertura e clique. Envio para mais de uma pessoa segue pela campanha, com aprovação.')}</p>
        {memberId ? (
          <div className="rounded-lg border border-[var(--border)] px-3 py-2 text-sm">
            <span className="text-[var(--fg-muted)]">{t('campaigns.oneOff.toMember', 'Para o membro')}: </span>
            <strong className="text-[var(--fg)]">{memberName || memberId}</strong>
          </div>
        ) : (
          <>
            <div>
              <label className={label} htmlFor="oneoff-email">{t('campaigns.oneOff.email', 'E-mail do destinatário')}</label>
              <input id="oneoff-email" type="email" className={input} value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="off" />
              <p className="text-[11px] text-[var(--fg-muted)] mt-1">{t('campaigns.oneOff.emailHint', 'Se o e-mail for de um membro, a mensagem vai para o membro.')}</p>
            </div>
            <div>
              <label className={label} htmlFor="oneoff-name">{t('campaigns.oneOff.name', 'Nome (opcional)')}</label>
              <input id="oneoff-name" type="text" className={input} value={name} onChange={(e) => setName(e.target.value)} autoComplete="off" />
            </div>
          </>
        )}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className={label} htmlFor="oneoff-theme">{t('campaigns.oneOff.theme', 'Tema')}</label>
            <select id="oneoff-theme" className={input} value={theme} onChange={(e) => setTheme(e.target.value)} required>
              <option value="">{t('campaigns.oneOff.chooseTheme', 'Escolha o tema')}</option>
              {themes.map((th) => <option key={th.slug} value={th.slug}>{th.label_i18n?.[langCode] || th.label_i18n?.pt || th.slug}</option>)}
            </select>
          </div>
          <div>
            <label className={label} htmlFor="oneoff-lang">{t('campaigns.oneOff.language', 'Idioma do rodapé')}</label>
            <select id="oneoff-lang" className={input} value={language} onChange={(e) => setLanguage(e.target.value)}>
              <option value="pt-BR">Português</option>
              <option value="en-US">English</option>
              <option value="es-LATAM">Español</option>
            </select>
          </div>
        </div>
        <div>
          <label className={label} htmlFor="oneoff-subject">{t('campaigns.oneOff.subject', 'Assunto')} ({subject.trim().length}/{SUBJECT_MAX})</label>
          <input id="oneoff-subject" type="text" className={input} value={subject} maxLength={SUBJECT_MAX} onChange={(e) => setSubject(e.target.value)} />
        </div>
        <div>
          <label className={label} htmlFor="oneoff-body">{t('campaigns.oneOff.body', 'Mensagem')} ({body.length}/{BODY_MAX})</label>
          <textarea id="oneoff-body" rows={10} className={input} value={body} maxLength={BODY_MAX} onChange={(e) => setBody(e.target.value)} />
          <p className="text-[11px] text-[var(--fg-muted)] mt-1">{t('campaigns.oneOff.bodyHint', 'Texto simples. Linha em branco separa parágrafos. Use {first_name} para o primeiro nome.')}</p>
        </div>
        {error && <p className="text-sm text-red-700 bg-red-50 rounded-lg px-3 py-2" role="alert">{error}</p>}
        {!confirming ? (
          <button type="button" disabled={!valid} onClick={() => setConfirming(true)}
            className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold border-0 cursor-pointer disabled:opacity-50">
            {t('campaigns.oneOff.review', 'Revisar e enviar')}
          </button>
        ) : (
          <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-3 text-sm text-amber-900">
            <p className="mb-2">{t('campaigns.oneOff.confirm', 'Enviar esta mensagem para')} <strong>{recipientLabel}</strong>?</p>
            <div className="flex gap-2">
              <button type="button" onClick={send} disabled={sending} className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold border-0 cursor-pointer disabled:opacity-50">
                {sending ? '…' : t('campaigns.oneOff.send', 'Enviar')}
              </button>
              <button type="button" onClick={() => setConfirming(false)} className="px-4 py-2 rounded-lg border border-[var(--border)] text-sm font-semibold bg-transparent cursor-pointer">
                {t('campaigns.oneOff.cancel', 'Cancelar')}
              </button>
            </div>
          </div>
        )}
      </div>

      <div className="rounded-2xl border border-[var(--border)] bg-white text-gray-900 p-5 text-sm self-start" aria-label={t('campaigns.oneOff.preview', 'Prévia')}>
        <div className="text-[11px] uppercase tracking-wide text-gray-500 mb-2">{t('campaigns.oneOff.preview', 'Prévia')}</div>
        <div className="font-semibold mb-3">{fill(subject) || '—'}</div>
        {paragraphs(fill(body)).map((p, i) => (
          <p key={i} className="mb-3 whitespace-pre-line">{p}</p>
        ))}
        <p className="text-gray-500 text-[12px] border-t border-gray-200 pt-2 mt-2">{t('campaigns.oneOff.footerNote', 'Para quem não é membro, o e-mail sai com o aviso de privacidade e o link de descadastro no rodapé.')}</p>
      </div>
    </div>
  );
}
