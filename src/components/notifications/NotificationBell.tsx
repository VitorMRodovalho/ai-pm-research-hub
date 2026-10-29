import { useState, useEffect, useCallback, useRef } from 'react';
import { rpcChecked } from '../../lib/rpc-checked';
import { safeNavigationUrl } from '../../lib/escape-html';
import { usePageI18n } from '../../i18n/usePageI18n';

interface Notification {
  id: string;
  type: string;
  title: string | null;
  link: string | null;
  source_type: string | null;
  source_id: string | null;
  source_title: string | null;
  is_read: boolean;
  created_at: string;
  actor_name: string | null;
  actor_photo: string | null;
}

const TYPE_ICONS: Record<string, string> = {
  card_assigned: '📋',
  card_status_changed: '📦',
  review_requested: '🔍',
  cr_status_changed: '⚖️',
  detractor_alert: '⚠️',
};

function timeAgo(dateStr: string, nowLabel: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return nowLabel;
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  return `${Math.floor(hrs / 24)}d`;
}

export default function NotificationBell() {
  const t = usePageI18n();
  const [unreadCount, setUnreadCount] = useState(0);
  // p131: count de cadeias governance com eligible_gates pendentes para
  // o user atual. Surge como link sticky no topo do dropdown se > 0.
  const [pendingRatificationsCount, setPendingRatificationsCount] = useState(0);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [open, setOpen] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const [authenticated, setAuthenticated] = useState(false);
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const langPrefix = typeof window !== 'undefined' && window.location.pathname.startsWith('/en/') ? '/en'
    : typeof window !== 'undefined' && window.location.pathname.startsWith('/es/') ? '/es' : '';

  // Poll counts every 60s
  const pollCount = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const [unreadRes, pendingRes] = await Promise.all([
      sb.rpc('get_unread_notification_count'),
      sb.rpc('get_pending_ratifications'),
    ]);
    if (typeof unreadRes.data === 'number') setUnreadCount(unreadRes.data);
    // p131: filtra rows com eligible_gates não-vazias (matches /governance/my-pending logic)
    if (Array.isArray(pendingRes.data)) {
      setPendingRatificationsCount(
        pendingRes.data.filter((r: any) => Array.isArray(r.eligible_gates) && r.eligible_gates.length > 0).length
      );
    }
  }, [getSb]);

  useEffect(() => {
    let timer: any;
    const boot = () => {
      const m = (window as any).navGetMember?.();
      if (m) {
        setAuthenticated(true);
        pollCount();
        timer = setInterval(pollCount, 60000);
      } else {
        setTimeout(boot, 500);
      }
    };
    boot();
    // Also listen for member event
    const handler = () => { setAuthenticated(true); pollCount(); };
    window.addEventListener('nav:member', handler as any);
    return () => { if (timer) clearInterval(timer); window.removeEventListener('nav:member', handler as any); };
  }, [pollCount]);

  // Load notifications on dropdown open
  const loadNotifications = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.rpc('get_my_notifications', { p_limit: 15, p_unread_only: false });
    if (Array.isArray(data)) setNotifications(data);
    setLoaded(true);
  }, [getSb]);

  useEffect(() => {
    if (open && !loaded) loadNotifications();
  }, [open, loaded, loadNotifications]);

  // Click outside to close
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const markRead = async (id: string) => {
    const sb = getSb();
    if (!sb) return;
    // #2704: sem a gravação, o sino não pode fingir que leu (o contador voltaria no próximo load).
    try { await rpcChecked(sb, 'mark_notification_read', { p_notification_id: id }); }
    catch (e) { console.error('[notif] marcar lida falhou', e); return; }
    setNotifications(prev => prev.map(n => n.id === id ? { ...n, is_read: true } : n));
    setUnreadCount(prev => Math.max(0, prev - 1));
  };

  // #2806: o toque leva ao link do aviso, como o push faz; antes so marcava lida e nao havia como chegar ao assunto.
  const openNotification = async (n: Notification) => {
    if (!n.is_read) await markRead(n.id);
    const href = safeNavigationUrl(n.link);
    if (href) window.location.href = href;
  };

  const markAllRead = async () => {
    const sb = getSb();
    if (!sb) return;
    try { await rpcChecked(sb, 'mark_all_notifications_read'); }
    catch (e) { console.error('[notif] marcar todas falhou', e); return; }
    setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
    setUnreadCount(0);
  };

  if (!authenticated) return null;

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => { setOpen(!open); if (!open) { setLoaded(false); } }}
        className="relative p-2 rounded-lg hover:bg-[var(--surface-hover)] cursor-pointer bg-transparent border-0 transition-colors"
        aria-label={t('comp.notificationBell.title', 'Notificações')}
      >
        <svg className="w-5 h-5 text-[var(--text-secondary)]" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
        </svg>
        {unreadCount > 0 && (
          <span className="absolute -top-0.5 -right-0.5 w-4.5 h-4.5 flex items-center justify-center rounded-full bg-red-500 text-white text-[9px] font-bold min-w-[18px] px-1">
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </button>

      {open && (
        // #2806: no celular o balao ocupa a largura da tela, logo abaixo do nav (top-14, como o menu movel); com
        // 350 px presos a direita do sino ele comecava fora da tela, a esquerda. Do sm para cima, o de antes.
        <div className="fixed inset-x-2 top-14 sm:absolute sm:inset-x-auto sm:right-0 sm:top-full sm:mt-1 sm:w-[350px] max-h-[400px] flex flex-col bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl shadow-xl overflow-hidden z-50">
          {/* Header */}
          <div className="flex items-center justify-between px-4 py-2.5 border-b border-[var(--border-subtle)]">
            <h3 className="text-sm font-bold text-[var(--text-primary)]">{t('comp.notificationBell.title', 'Notificações')}</h3>
            {unreadCount > 0 && (
              <button onClick={markAllRead}
                className="text-[10px] text-teal font-semibold cursor-pointer bg-transparent border-0 hover:underline">
                {t('comp.notificationBell.markAllRead', 'Marcar todas como lidas')}
              </button>
            )}
          </div>

          {/* p131: link sticky de pending ratifications — surge no topo do dropdown
              quando user tem chains de governança com eligible_gates pendentes.
              Auxilia discovery sem poluir o badge do ícone com 2 contadores. */}
          {pendingRatificationsCount > 0 && (
            <a
              href={`${langPrefix}/governance/my-pending`}
              className="block px-4 py-2.5 border-b border-[var(--border-subtle)] bg-blue-50 hover:bg-blue-100 transition-colors no-underline"
            >
              <div className="flex items-center gap-2">
                <span className="text-base">📜</span>
                <div className="flex-1 min-w-0">
                  <div className="text-[12px] font-bold text-navy">
                    {(pendingRatificationsCount === 1
                      ? t('comp.notificationBell.pendingOne', '{n} pendência de assinatura')
                      : t('comp.notificationBell.pendingMany', '{n} pendências de assinatura')
                    ).replace('{n}', String(pendingRatificationsCount))}
                  </div>
                  <div className="text-[10px] text-navy/70">{t('comp.notificationBell.pendingHint', 'Cadeias de governança aguardam você → ver lista')}</div>
                </div>
                <span className="text-navy text-[12px] font-bold">→</span>
              </div>
            </a>
          )}

          {/* List */}
          <div className="flex-1 min-h-0 overflow-y-auto">
            {!loaded ? (
              <div className="py-8 text-center text-[var(--text-muted)] text-sm">...</div>
            ) : notifications.length === 0 ? (
              <div className="py-8 text-center text-[var(--text-muted)] text-sm">{t('comp.notificationBell.empty', 'Nenhuma notificação.')}</div>
            ) : (
              notifications.map(n => (
                <div
                  key={n.id}
                  onClick={() => openNotification(n)}
                  className={`flex items-start gap-2.5 px-4 py-2.5 border-b border-[var(--border-subtle)] cursor-pointer hover:bg-[var(--surface-hover)] transition-colors ${!n.is_read ? 'bg-blue-50/50' : ''}`}
                >
                  <span className="text-base flex-shrink-0 mt-0.5">{TYPE_ICONS[n.type] || '🔔'}</span>
                  <div className="flex-1 min-w-0">
                    {/* #2806: o titulo do aviso; o nome do tipo cru ficava no lugar do assunto */}
                    <div className="text-[12px] text-[var(--text-primary)] break-words">
                      {n.title || n.type.replace(/_/g, ' ')}
                    </div>
                    <div className="text-[10px] text-[var(--text-muted)] mt-0.5">
                      {n.actor_name ? `${n.actor_name} · ` : ''}{timeAgo(n.created_at, t('comp.notificationBell.now', 'agora'))}
                    </div>
                  </div>
                  {!n.is_read && <span className="w-2 h-2 rounded-full bg-blue-500 flex-shrink-0 mt-1.5" />}
                </div>
              ))
            )}
          </div>

          <a
            href={`${langPrefix}/notifications`}
            className="block px-4 py-2 text-center text-[11px] text-teal font-semibold border-t border-[var(--border-subtle)] no-underline hover:underline"
          >
            {t('comp.notificationBell.seeAll', 'Ver todas')}
          </a>
        </div>
      )}
    </div>
  );
}
