import { useState, useEffect, useCallback, useRef } from 'react';

interface Notification {
  id: string;
  type: string;
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

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return `${mins}m`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h`;
  return `${Math.floor(hrs / 24)}d`;
}

export default function NotificationBell() {
  const [unreadCount, setUnreadCount] = useState(0);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [open, setOpen] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const [authenticated, setAuthenticated] = useState(false);
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  // Poll unread count every 60s
  const pollCount = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.rpc('get_unread_notification_count');
    if (typeof data === 'number') setUnreadCount(data);
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
    await sb.rpc('mark_notification_read', { p_notification_id: id });
    setNotifications(prev => prev.map(n => n.id === id ? { ...n, is_read: true } : n));
    setUnreadCount(prev => Math.max(0, prev - 1));
  };

  const markAllRead = async () => {
    const sb = getSb();
    if (!sb) return;
    await sb.rpc('mark_all_notifications_read');
    setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
    setUnreadCount(0);
  };

  if (!authenticated) return null;

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => { setOpen(!open); if (!open) { setLoaded(false); } }}
        className="relative p-2 rounded-lg hover:bg-[var(--surface-hover)] cursor-pointer bg-transparent border-0 transition-colors"
        aria-label="Notifications"
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
        <div className="absolute right-0 top-full mt-1 w-[350px] max-h-[400px] bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl shadow-xl overflow-hidden z-50">
          {/* Header */}
          <div className="flex items-center justify-between px-4 py-2.5 border-b border-[var(--border-subtle)]">
            <h3 className="text-sm font-bold text-[var(--text-primary)]">Notifications</h3>
            {unreadCount > 0 && (
              <button onClick={markAllRead}
                className="text-[10px] text-teal font-semibold cursor-pointer bg-transparent border-0 hover:underline">
                Mark all read
              </button>
            )}
          </div>

          {/* List */}
          <div className="overflow-y-auto max-h-[340px]">
            {!loaded ? (
              <div className="py-8 text-center text-[var(--text-muted)] text-sm">...</div>
            ) : notifications.length === 0 ? (
              <div className="py-8 text-center text-[var(--text-muted)] text-sm">No notifications.</div>
            ) : (
              notifications.map(n => (
                <div
                  key={n.id}
                  onClick={() => { if (!n.is_read) markRead(n.id); }}
                  className={`flex items-start gap-2.5 px-4 py-2.5 border-b border-[var(--border-subtle)] cursor-pointer hover:bg-[var(--surface-hover)] transition-colors ${!n.is_read ? 'bg-blue-50/50' : ''}`}
                >
                  <span className="text-base flex-shrink-0 mt-0.5">{TYPE_ICONS[n.type] || '🔔'}</span>
                  <div className="flex-1 min-w-0">
                    <div className="text-[12px] text-[var(--text-primary)]">
                      {n.actor_name && <strong>{n.actor_name}</strong>}
                      {n.source_title && <span className="ml-1">— {n.source_title}</span>}
                    </div>
                    <div className="text-[10px] text-[var(--text-muted)] mt-0.5">{n.type.replace(/_/g, ' ')} · {timeAgo(n.created_at)}</div>
                  </div>
                  {!n.is_read && <span className="w-2 h-2 rounded-full bg-blue-500 flex-shrink-0 mt-1.5" />}
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
