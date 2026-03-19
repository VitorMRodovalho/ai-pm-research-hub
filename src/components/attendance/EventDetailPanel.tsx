import { useState, useEffect, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { usePageI18n } from '../../i18n/usePageI18n';

/* ── helpers ── */
function getSb() { return (window as any).navGetSb?.(); }

/* ── types ── */
interface EventInfo {
  id: string;
  title: string;
  date: string;
  type: string;
  tribe_id: number;
  visibility: string;
  recording_url?: string;
  recording_type?: string;
}

interface AgendaInfo {
  text?: string;
  url?: string;
  posted_at?: string;
  posted_by?: string;
}

interface MinutesInfo {
  text?: string;
  url?: string;
  posted_at?: string;
  posted_by?: string;
}

interface ActionItem {
  id: string;
  description: string;
  assignee_name: string;
  due_date: string;
  status: string;
}

interface AttendanceMember {
  id: string;
  name: string;
  present: boolean;
  excused: boolean;
}

interface AttendanceInfo {
  present_count: number;
  members: AttendanceMember[];
}

interface EventDetail {
  event: EventInfo;
  agenda: AgendaInfo | null;
  minutes: MinutesInfo | null;
  action_items: ActionItem[];
  attendance: AttendanceInfo;
}

interface Props {
  eventId: string;
  canEdit: boolean;
  tribeId?: number;
}

/* ── collapsible section ── */
function Section({
  icon,
  title,
  defaultOpen = true,
  children,
}: {
  icon: string;
  title: string;
  defaultOpen?: boolean;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className="border border-[var(--border-subtle)] rounded-xl overflow-hidden mb-4">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-2 px-4 py-3 bg-[var(--surface-card)] hover:bg-[var(--surface-base)] transition-colors cursor-pointer border-0 text-left"
      >
        <span className="text-base">{icon}</span>
        <span className="font-bold text-sm text-[var(--text-primary)] flex-1">{title}</span>
        <span className="text-[var(--text-muted)] text-xs select-none">{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className="px-4 py-3 bg-[var(--surface-card)] border-t border-[var(--border-subtle)]">
          {children}
        </div>
      )}
    </div>
  );
}

/* ── recording icon ── */
function recordingIcon(type?: string) {
  if (!type) return '🔗';
  const lower = type.toLowerCase();
  if (lower.includes('youtube')) return '🎥';
  if (lower.includes('fathom')) return '📹';
  return '🔗';
}

/* ── main component ── */
export default function EventDetailPanel({ eventId, canEdit, tribeId }: Props) {
  const t = usePageI18n();

  const [detail, setDetail] = useState<EventDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [restricted, setRestricted] = useState(false);

  // Agenda editing
  const [editingAgenda, setEditingAgenda] = useState(false);
  const [agendaDraft, setAgendaDraft] = useState('');
  const [agendaSaving, setAgendaSaving] = useState(false);
  const [generatingTemplate, setGeneratingTemplate] = useState(false);

  // Minutes editing
  const [editingMinutes, setEditingMinutes] = useState(false);
  const [minutesDraft, setMinutesDraft] = useState('');
  const [minutesSaving, setMinutesSaving] = useState(false);

  // Action items editing
  const [newAction, setNewAction] = useState({ description: '', assignee_name: '', due_date: '' });
  const [actionSaving, setActionSaving] = useState(false);

  /* ── load data ── */
  const loadDetail = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;

    setLoading(true);
    setError(null);

    const { data, error: rpcErr } = await sb.rpc('get_event_detail', { p_event_id: eventId });

    if (rpcErr) {
      setError(rpcErr.message);
      setLoading(false);
      return;
    }

    if (!data) {
      setError(t('eventDetail.notFound', 'Event not found'));
      setLoading(false);
      return;
    }

    const parsed = typeof data === 'string' ? JSON.parse(data) : data;

    if (parsed.event?.visibility === 'restricted' && !canEdit) {
      setRestricted(true);
      setLoading(false);
      return;
    }

    setDetail(parsed);
    setLoading(false);
  }, [eventId, canEdit, t]);

  useEffect(() => { loadDetail(); }, [loadDetail]);

  /* ── agenda save ── */
  const saveAgenda = async () => {
    const sb = getSb();
    if (!sb) return;
    setAgendaSaving(true);
    const { error: err } = await sb.rpc('upsert_event_agenda', {
      p_event_id: eventId,
      p_text: agendaDraft,
    });
    setAgendaSaving(false);
    if (!err) {
      setEditingAgenda(false);
      loadDetail();
    }
  };

  /* ── generate agenda template ── */
  const generateTemplate = async () => {
    const sb = getSb();
    if (!sb || !tribeId) return;
    setGeneratingTemplate(true);
    const { data, error: err } = await sb.rpc('generate_agenda_template', {
      p_tribe_id: tribeId,
    });
    setGeneratingTemplate(false);
    if (!err && data) {
      const template = typeof data === 'string' ? data : data.template || '';
      setAgendaDraft(template);
    }
  };

  /* ── minutes save ── */
  const saveMinutes = async () => {
    const sb = getSb();
    if (!sb) return;
    setMinutesSaving(true);
    const { error: err } = await sb.rpc('upsert_event_minutes', {
      p_event_id: eventId,
      p_text: minutesDraft,
    });
    setMinutesSaving(false);
    if (!err) {
      setEditingMinutes(false);
      loadDetail();
    }
  };

  /* ── action item status toggle ── */
  const toggleActionStatus = async (item: ActionItem, newStatus: string) => {
    const sb = getSb();
    if (!sb) return;
    await sb.rpc('manage_action_items', {
      p_event_id: eventId,
      p_items: [{ id: item.id, description: item.description, assignee_name: item.assignee_name, due_date: item.due_date, status: newStatus }],
    });
    loadDetail();
  };

  /* ── add action item ── */
  const addActionItem = async () => {
    const sb = getSb();
    if (!sb) return;
    if (!newAction.description.trim()) return;
    setActionSaving(true);
    await sb.rpc('manage_action_items', {
      p_event_id: eventId,
      p_items: [{ description: newAction.description, assignee_name: newAction.assignee_name, due_date: newAction.due_date || null, status: 'open' }],
    });
    setActionSaving(false);
    setNewAction({ description: '', assignee_name: '', due_date: '' });
    loadDetail();
  };

  /* ── render states ── */
  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <p className="text-[var(--text-muted)] text-sm">{t('eventDetail.loading', 'Loading...')}</p>
      </div>
    );
  }

  if (restricted) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl px-6 py-8 text-center max-w-sm">
          <p className="text-2xl mb-2">🔒</p>
          <p className="text-sm font-semibold text-[var(--text-primary)]">
            {t('eventDetail.restricted', 'Restricted content')}
          </p>
          <p className="text-xs text-[var(--text-muted)] mt-1">
            {t('eventDetail.restrictedDesc', 'You do not have permission to view this event.')}
          </p>
        </div>
      </div>
    );
  }

  if (error || !detail) {
    return (
      <div className="flex items-center justify-center py-12">
        <p className="text-red-500 text-sm">{error || t('eventDetail.notFound', 'Event not found')}</p>
      </div>
    );
  }

  const { event, agenda, minutes, action_items, attendance } = detail;

  return (
    <div className="space-y-2">
      {/* ── Header ── */}
      <div className="mb-4">
        <h2 className="text-lg font-bold text-[var(--text-primary)]">{event.title}</h2>
        <p className="text-xs text-[var(--text-muted)] mt-0.5">
          {new Date(event.date).toLocaleDateString()} &middot; {event.type}
        </p>
      </div>

      {/* ── Recording ── */}
      {event.recording_url && (
        <div className="flex items-center gap-2 px-4 py-2 bg-[var(--surface-base)] border border-[var(--border-subtle)] rounded-lg mb-4">
          <span>{recordingIcon(event.recording_type)}</span>
          <a
            href={event.recording_url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm font-semibold text-[var(--color-teal)] hover:underline"
          >
            {t('eventDetail.watchRecording', 'Watch Recording')}
          </a>
          {event.recording_type && (
            <span className="text-[10px] text-[var(--text-muted)] ml-auto">{event.recording_type}</span>
          )}
        </div>
      )}

      {/* ── Section 1: Agenda ── */}
      <Section icon="📋" title={t('eventDetail.agenda', 'Agenda')}>
        {editingAgenda ? (
          <div className="space-y-3">
            <textarea
              value={agendaDraft}
              onChange={(e) => setAgendaDraft(e.target.value)}
              rows={10}
              className="w-full rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] text-sm p-3 resize-y focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
              placeholder={t('eventDetail.agendaPlaceholder', 'Write agenda in Markdown...')}
            />
            <div className="flex gap-2 flex-wrap">
              <button
                onClick={saveAgenda}
                disabled={agendaSaving}
                className="px-4 py-1.5 rounded-lg bg-navy text-white text-xs font-semibold border-0 cursor-pointer hover:bg-navy/90 disabled:opacity-50 transition-colors"
              >
                {agendaSaving ? t('eventDetail.saving', 'Saving...') : t('eventDetail.save', 'Save')}
              </button>
              {tribeId && (
                <button
                  onClick={generateTemplate}
                  disabled={generatingTemplate}
                  className="px-4 py-1.5 rounded-lg bg-[var(--surface-base)] border border-[var(--border-default)] text-[var(--text-secondary)] text-xs font-semibold cursor-pointer hover:bg-[var(--surface-card)] disabled:opacity-50 transition-colors"
                >
                  {generatingTemplate
                    ? t('eventDetail.generating', 'Generating...')
                    : t('eventDetail.generateTemplate', 'Generate Template')}
                </button>
              )}
              <button
                onClick={() => setEditingAgenda(false)}
                className="px-4 py-1.5 rounded-lg bg-transparent border border-[var(--border-default)] text-[var(--text-muted)] text-xs font-semibold cursor-pointer hover:bg-[var(--surface-base)] transition-colors"
              >
                {t('eventDetail.cancel', 'Cancel')}
              </button>
            </div>
          </div>
        ) : (
          <>
            {agenda?.text ? (
              <div className="prose prose-sm max-w-none text-[var(--text-primary)] dark:prose-invert">
                <ReactMarkdown remarkPlugins={[remarkGfm]}>{agenda.text}</ReactMarkdown>
              </div>
            ) : agenda?.url ? null : canEdit ? (
              <p className="text-xs text-[var(--text-muted)] italic">
                {t('eventDetail.noAgenda', 'No agenda yet.')}
              </p>
            ) : (
              <p className="text-xs text-[var(--text-muted)] italic">
                {t('eventDetail.noAgenda', 'No agenda yet.')}
              </p>
            )}
            {agenda?.url && (
              <a
                href={agenda.url}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1.5 mt-2 px-3 py-1.5 rounded-lg bg-[var(--surface-base)] border border-[var(--border-default)] text-xs font-semibold text-[var(--color-teal)] hover:underline transition-colors"
              >
                📄 {t('eventDetail.openGoogleDocs', 'Open in Google Docs')}
              </a>
            )}
            {canEdit && !agenda?.text && !agenda?.url && (
              <button
                onClick={() => { setAgendaDraft(''); setEditingAgenda(true); }}
                className="mt-2 px-4 py-1.5 rounded-lg bg-navy text-white text-xs font-semibold border-0 cursor-pointer hover:bg-navy/90 transition-colors"
              >
                {t('eventDetail.addAgenda', 'Add Agenda')}
              </button>
            )}
            {canEdit && (agenda?.text || agenda?.url) && (
              <button
                onClick={() => { setAgendaDraft(agenda?.text || ''); setEditingAgenda(true); }}
                className="mt-2 ml-2 px-3 py-1 rounded-lg bg-transparent border border-[var(--border-default)] text-[var(--text-muted)] text-xs cursor-pointer hover:bg-[var(--surface-base)] transition-colors"
              >
                ✏️ {t('eventDetail.edit', 'Edit')}
              </button>
            )}
          </>
        )}
      </Section>

      {/* ── Section 2: Minutes + Action Items ── */}
      <Section icon="📝" title={t('eventDetail.minutes', 'Minutes & Action Items')}>
        {/* Minutes */}
        <h4 className="text-xs font-bold text-[var(--text-secondary)] uppercase tracking-wider mb-2">
          {t('eventDetail.minutesLabel', 'Minutes')}
        </h4>
        {editingMinutes ? (
          <div className="space-y-3 mb-4">
            <textarea
              value={minutesDraft}
              onChange={(e) => setMinutesDraft(e.target.value)}
              rows={8}
              className="w-full rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] text-sm p-3 resize-y focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
              placeholder={t('eventDetail.minutesPlaceholder', 'Write minutes in Markdown...')}
            />
            <div className="flex gap-2">
              <button
                onClick={saveMinutes}
                disabled={minutesSaving}
                className="px-4 py-1.5 rounded-lg bg-navy text-white text-xs font-semibold border-0 cursor-pointer hover:bg-navy/90 disabled:opacity-50 transition-colors"
              >
                {minutesSaving ? t('eventDetail.saving', 'Saving...') : t('eventDetail.save', 'Save')}
              </button>
              <button
                onClick={() => setEditingMinutes(false)}
                className="px-4 py-1.5 rounded-lg bg-transparent border border-[var(--border-default)] text-[var(--text-muted)] text-xs font-semibold cursor-pointer hover:bg-[var(--surface-base)] transition-colors"
              >
                {t('eventDetail.cancel', 'Cancel')}
              </button>
            </div>
          </div>
        ) : (
          <div className="mb-4">
            {minutes?.text ? (
              <div className="prose prose-sm max-w-none text-[var(--text-primary)] dark:prose-invert">
                <ReactMarkdown remarkPlugins={[remarkGfm]}>{minutes.text}</ReactMarkdown>
              </div>
            ) : (
              <p className="text-xs text-[var(--text-muted)] italic">
                {t('eventDetail.noMinutes', 'No minutes yet.')}
              </p>
            )}
            {minutes?.url && (
              <a
                href={minutes.url}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1.5 mt-2 px-3 py-1.5 rounded-lg bg-[var(--surface-base)] border border-[var(--border-default)] text-xs font-semibold text-[var(--color-teal)] hover:underline transition-colors"
              >
                📄 {t('eventDetail.openGoogleDocs', 'Open in Google Docs')}
              </a>
            )}
            {canEdit && (
              <button
                onClick={() => { setMinutesDraft(minutes?.text || ''); setEditingMinutes(true); }}
                className="mt-2 ml-2 px-3 py-1 rounded-lg bg-transparent border border-[var(--border-default)] text-[var(--text-muted)] text-xs cursor-pointer hover:bg-[var(--surface-base)] transition-colors"
              >
                ✏️ {canEdit && !minutes?.text && !minutes?.url
                  ? t('eventDetail.addMinutes', 'Add Minutes')
                  : t('eventDetail.edit', 'Edit')}
              </button>
            )}
          </div>
        )}

        {/* Action Items */}
        <h4 className="text-xs font-bold text-[var(--text-secondary)] uppercase tracking-wider mb-2 mt-4 pt-4 border-t border-[var(--border-subtle)]">
          {t('eventDetail.actionItems', 'Action Items')}
        </h4>
        {action_items.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-xs border-collapse">
              <thead>
                <tr className="text-left text-[var(--text-muted)] uppercase tracking-wider">
                  <th className="pb-2 pr-3 font-semibold">{t('eventDetail.description', 'Description')}</th>
                  <th className="pb-2 pr-3 font-semibold">{t('eventDetail.assignee', 'Assignee')}</th>
                  <th className="pb-2 pr-3 font-semibold">{t('eventDetail.dueDate', 'Due Date')}</th>
                  <th className="pb-2 font-semibold">{t('eventDetail.status', 'Status')}</th>
                </tr>
              </thead>
              <tbody>
                {action_items.map((item) => (
                  <tr key={item.id} className="border-t border-[var(--border-subtle)]">
                    <td className="py-2 pr-3 text-[var(--text-primary)]">{item.description}</td>
                    <td className="py-2 pr-3 text-[var(--text-secondary)]">{item.assignee_name}</td>
                    <td className="py-2 pr-3 text-[var(--text-muted)]">
                      {item.due_date ? new Date(item.due_date).toLocaleDateString() : '—'}
                    </td>
                    <td className="py-2">
                      {canEdit && item.status === 'open' ? (
                        <div className="flex gap-1">
                          <button
                            onClick={() => toggleActionStatus(item, 'done')}
                            className="px-2 py-0.5 rounded bg-green-100 text-green-700 text-[10px] font-semibold border-0 cursor-pointer hover:bg-green-200 transition-colors dark:bg-green-900/30 dark:text-green-400"
                            title={t('eventDetail.markDone', 'Mark as done')}
                          >
                            ✓ {t('eventDetail.done', 'Done')}
                          </button>
                          <button
                            onClick={() => toggleActionStatus(item, 'carried_over')}
                            className="px-2 py-0.5 rounded bg-amber-100 text-amber-700 text-[10px] font-semibold border-0 cursor-pointer hover:bg-amber-200 transition-colors dark:bg-amber-900/30 dark:text-amber-400"
                            title={t('eventDetail.carryOver', 'Carry over')}
                          >
                            ↗ {t('eventDetail.carryOver', 'Carry Over')}
                          </button>
                        </div>
                      ) : (
                        <span
                          className={`inline-block px-2 py-0.5 rounded text-[10px] font-semibold ${
                            item.status === 'done'
                              ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                              : item.status === 'carried_over'
                              ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                              : 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                          }`}
                        >
                          {item.status === 'done'
                            ? t('eventDetail.done', 'Done')
                            : item.status === 'carried_over'
                            ? t('eventDetail.carriedOver', 'Carried Over')
                            : t('eventDetail.open', 'Open')}
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-xs text-[var(--text-muted)] italic">
            {t('eventDetail.noActionItems', 'No action items.')}
          </p>
        )}

        {/* Add action item row */}
        {canEdit && (
          <div className="mt-3 flex gap-2 flex-wrap items-end">
            <input
              type="text"
              value={newAction.description}
              onChange={(e) => setNewAction({ ...newAction, description: e.target.value })}
              placeholder={t('eventDetail.actionDescription', 'Description')}
              className="flex-1 min-w-[140px] px-3 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] text-xs focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
            />
            <input
              type="text"
              value={newAction.assignee_name}
              onChange={(e) => setNewAction({ ...newAction, assignee_name: e.target.value })}
              placeholder={t('eventDetail.assignee', 'Assignee')}
              className="w-28 px-3 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] text-xs focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
            />
            <input
              type="date"
              value={newAction.due_date}
              onChange={(e) => setNewAction({ ...newAction, due_date: e.target.value })}
              className="w-32 px-3 py-1.5 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] text-xs focus:outline-none focus:ring-2 focus:ring-[var(--color-teal)]"
            />
            <button
              onClick={addActionItem}
              disabled={actionSaving || !newAction.description.trim()}
              className="px-4 py-1.5 rounded-lg bg-navy text-white text-xs font-semibold border-0 cursor-pointer hover:bg-navy/90 disabled:opacity-50 transition-colors"
            >
              {actionSaving ? '...' : `+ ${t('eventDetail.addItem', 'Add')}`}
            </button>
          </div>
        )}
      </Section>

      {/* ── Section 3: Attendance ── */}
      <Section icon="👥" title={t('eventDetail.attendance', 'Attendance')}>
        <p className="text-sm font-semibold text-[var(--text-primary)] mb-3">
          {attendance.present_count} {t('eventDetail.present', 'present')}
        </p>
        <div className="grid grid-cols-[repeat(auto-fill,minmax(180px,1fr))] gap-1.5">
          {attendance.members.map((m) => (
            <div
              key={m.id}
              className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[var(--surface-base)] text-xs"
            >
              <span>{m.present ? '✅' : m.excused ? '🟡' : '❌'}</span>
              <span
                className={
                  m.present
                    ? 'text-[var(--text-primary)] font-medium'
                    : 'text-[var(--text-muted)]'
                }
              >
                {m.name}
              </span>
              {m.excused && !m.present && (
                <span className="ml-auto text-[10px] text-amber-600 dark:text-amber-400">
                  {t('eventDetail.excused', 'excused')}
                </span>
              )}
            </div>
          ))}
        </div>
      </Section>
    </div>
  );
}
