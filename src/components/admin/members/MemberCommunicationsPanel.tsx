import { useEffect, useState, useCallback } from 'react';
import { usePageI18n } from '../../../i18n/usePageI18n';

// #2586: histórico de comunicação por pessoa. Lê get_member_communications (manage_member ou manage_platform);
// mostra tema, assunto, quando e o que aconteceu com o e-mail. Nunca o corpo da mensagem.

interface Row {
  send_id: string;
  created_at: string;
  sent_at: string | null;
  theme: string | null;
  subject: string | null;
  source: string | null;
  send_status: string;
  delivered: boolean | null;
  first_opened_at: string | null;
  clicked_at: string | null;
  bounce_type: string | null;
  bounced_at: string | null;
  complained_at: string | null;
  suppressed_at: string | null;
  unsubscribed: boolean | null;
  deferred_until: string | null;
}

function statusOf(r: Row): 'complained' | 'bounced' | 'suppressed' | 'clicked' | 'opened' | 'delivered' | 'deferred' | 'pending' {
  if (r.complained_at) return 'complained';
  if (r.bounced_at) return 'bounced';
  if (r.suppressed_at) return 'suppressed';
  if (r.clicked_at) return 'clicked';
  if (r.first_opened_at) return 'opened';
  if (r.delivered) return 'delivered';
  if (r.deferred_until) return 'deferred';
  return 'pending';
}

const STATUS_STYLE: Record<string, string> = {
  complained: 'bg-red-50 text-red-700', bounced: 'bg-red-50 text-red-700', suppressed: 'bg-amber-50 text-amber-800',
  clicked: 'bg-emerald-50 text-emerald-700', opened: 'bg-emerald-50 text-emerald-700', delivered: 'bg-sky-50 text-sky-700',
  deferred: 'bg-amber-50 text-amber-800', pending: 'bg-gray-100 text-gray-700',
};

export default function MemberCommunicationsPanel({ memberId }: { memberId: string }) {
  const t = usePageI18n();
  const lp: string = (typeof window !== 'undefined' && (window as any).__LANG_PREFIX) || '';
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  useEffect(() => {
    let cancelled = false;
    let tries = 0;
    async function load() {
      const sb = getSb();
      if (!sb) { if (tries++ < 20) setTimeout(load, 300); return; }
      const { data, error: err } = await sb.rpc('get_member_communications', { p_member_id: memberId });
      if (cancelled) return;
      if (err) { setError(err.code === '42501' ? 'forbidden' : 'error'); return; }
      setRows(Array.isArray(data) ? data : []);
    }
    load();
    return () => { cancelled = true; };
  }, [memberId, getSb]);

  const fmt = (iso: string | null) => (iso ? new Date(iso).toLocaleString(undefined, { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—');

  return (
    <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-2xl overflow-hidden">
      <div className="flex items-center justify-between px-4 py-3 border-b border-[var(--border-default)]">
        <span className="text-sm font-semibold text-[var(--text-primary)]">{t('comp.memberDetail.comms.title', 'Comunicações enviadas')}</span>
        <a href={`${lp}/admin/campaigns?tab=oneoff&member=${encodeURIComponent(memberId)}`}
          className="text-xs font-semibold text-teal-600 no-underline hover:underline">
          {t('comp.memberDetail.comms.send', 'Enviar mensagem')} →
        </a>
      </div>
      {error ? (
        <div className="px-4 py-8 text-center text-[var(--text-muted)]" role="status">
          {error === 'forbidden'
            ? t('comp.memberDetail.comms.forbidden', 'Você não tem permissão para ver as comunicações deste membro.')
            : t('comp.memberDetail.comms.error', 'Não foi possível carregar as comunicações.')}
        </div>
      ) : rows === null ? (
        <div className="px-4 py-8 text-center text-[var(--text-muted)]">…</div>
      ) : rows.length === 0 ? (
        <div className="px-4 py-8 text-center text-[var(--text-muted)]">{t('comp.memberDetail.comms.empty', 'Nenhuma comunicação registrada para este membro.')}</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-[.72rem] uppercase tracking-wide text-[var(--text-muted)]">
                <th className="px-4 py-2">{t('comp.memberDetail.comms.when', 'Quando')}</th>
                <th className="px-4 py-2">{t('comp.memberDetail.comms.theme', 'Tema')}</th>
                <th className="px-4 py-2">{t('comp.memberDetail.comms.subject', 'Assunto')}</th>
                <th className="px-4 py-2">{t('comp.memberDetail.comms.status', 'Situação')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-default)]">
              {rows.map((r) => {
                const st = statusOf(r);
                return (
                  <tr key={r.send_id}>
                    <td className="px-4 py-2 whitespace-nowrap text-[var(--text-secondary)]">{fmt(r.sent_at ?? r.created_at)}</td>
                    <td className="px-4 py-2 text-[var(--text-secondary)]">{r.theme ? t(`comp.memberDetail.comms.themes.${r.theme}`, r.theme) : '—'}</td>
                    <td className="px-4 py-2 text-[var(--text-primary)]">{r.subject || '—'}</td>
                    <td className="px-4 py-2">
                      <span className={`inline-block px-2 py-0.5 rounded text-[.72rem] font-semibold ${STATUS_STYLE[st]}`}>
                        {t(`comp.memberDetail.comms.st.${st}`, st)}
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
