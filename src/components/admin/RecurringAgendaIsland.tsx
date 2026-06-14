// src/components/admin/RecurringAgendaIsland.tsx
// #676 Slice 2 (read) + Slice 3 (write, V4-scoped).
// Lists the canonical recurring-meeting rules with drift indicators and lets platform
// managers edit / create / reconcile them. Authority is enforced server-side:
//   - read:   get_recurring_meeting_admin_list (manage_platform)
//   - write:  update_recurring_meeting_rule / create_recurring_meeting_rule /
//             reconcile_recurring_meeting — V4-scoped (GP any; initiative leader own).
import { useState, useEffect, useCallback } from 'react';
import { Loader2, CalendarClock, AlertTriangle, ExternalLink, RefreshCw, Pencil, Plus, RotateCw, X } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface RuleRow {
  rule_id: string;
  scope_type: string;
  scope_name: string;
  title: string;
  event_type: string;
  day_of_week: number; // ISO 1=Mon..7=Sun
  time_start: string;
  duration_minutes: number;
  frequency: string;
  timezone: string;
  status: string;
  meeting_link: string | null;
  anchor_date: string;
  next_occurrence: string | null;
  future_events: number;
  expected_future: number;
  missing_future: number;
  time_mismatch: number;
  link_mismatch: number;
  last_reconciled_at: string | null;
}
interface InitiativeOpt { id: string; title: string; legacy_tribe_id: number | null }
interface FormState {
  rule_id: string | null;
  initiative_id: string;
  title: string;
  day_of_week: number;
  time_start: string;
  duration_minutes: number;
  frequency: string;
  status: string;
  meeting_link: string;
  anchor_date: string;
}

function fmtDate(d: string | null): string {
  if (!d) return '—';
  const ts = Date.parse(`${d}T12:00:00Z`);
  if (Number.isNaN(ts)) return d;
  return new Date(ts).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', timeZone: 'UTC' });
}
const fmtTime = (t: string | null) => (t ? t.slice(0, 5) : '—');
const todayISO = () => new Date().toISOString().slice(0, 10);

export default function RecurringAgendaIsland() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const [rows, setRows] = useState<RuleRow[]>([]);
  const [initiatives, setInitiatives] = useState<InitiativeOpt[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [form, setForm] = useState<FormState | null>(null);
  const [saving, setSaving] = useState(false);
  const [busyRule, setBusyRule] = useState<string | null>(null);

  const toast = (msg: string, kind: 'success' | 'error' = 'success') =>
    (window as any).toast?.(msg, kind);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) { setTimeout(load, 300); return; }
    setLoading(true);
    setError(null);
    const { data, error } = await sb.rpc('get_recurring_meeting_admin_list');
    if (error) {
      setError(t('comp.recurringAgenda.loadError', 'Erro ao carregar a agenda recorrente'));
      setLoading(false);
      return;
    }
    setRows(Array.isArray(data) ? data : []);
    setLoading(false);
  }, [getSb, t]);

  useEffect(() => { load(); }, [load]);

  // Initiatives for the create picker (best-effort; GP can read).
  useEffect(() => {
    const sb = getSb();
    if (!sb) return;
    sb.from('initiatives').select('id, title, legacy_tribe_id').order('title')
      .then(({ data }: any) => { if (Array.isArray(data)) setInitiatives(data); })
      .catch(() => {});
  }, [getSb]);

  const dowLabel = (iso: number) =>
    t(`comp.recurringAgenda.dow${iso}`, ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][iso] || '?');
  const freqLabel = (f: string) =>
    f === 'biweekly' ? t('comp.recurringAgenda.biweekly', 'Quinzenal') : t('comp.recurringAgenda.weekly', 'Semanal');
  const statusMeta = (s: string): { label: string; cls: string } => {
    if (s === 'active') return { label: t('comp.recurringAgenda.statusActive', 'Ativa'), cls: 'bg-emerald-50 text-emerald-700' };
    if (s === 'paused') return { label: t('comp.recurringAgenda.statusPaused', 'Pausada'), cls: 'bg-amber-50 text-amber-700' };
    return { label: t('comp.recurringAgenda.statusArchived', 'Arquivada'), cls: 'bg-slate-100 text-slate-500' };
  };

  const openEdit = (r: RuleRow) => setForm({
    rule_id: r.rule_id, initiative_id: '', title: r.title, day_of_week: r.day_of_week,
    time_start: r.time_start.slice(0, 5), duration_minutes: r.duration_minutes, frequency: r.frequency,
    status: r.status, meeting_link: r.meeting_link || '', anchor_date: r.anchor_date,
  });
  const openCreate = () => setForm({
    rule_id: null, initiative_id: initiatives[0]?.id || '', title: '', day_of_week: 1,
    time_start: '19:00', duration_minutes: 60, frequency: 'weekly', status: 'active',
    meeting_link: '', anchor_date: todayISO(),
  });

  const save = async () => {
    if (!form) return;
    const sb = getSb();
    if (!sb) return;
    setSaving(true);
    try {
      if (form.rule_id) {
        const { error } = await sb.rpc('update_recurring_meeting_rule', {
          p_rule_id: form.rule_id,
          p_patch: {
            title: form.title, status: form.status, day_of_week: form.day_of_week,
            time_start: form.time_start, duration_minutes: Number(form.duration_minutes),
            frequency: form.frequency, meeting_link: form.meeting_link,
          },
        });
        if (error) throw error;
        toast(t('comp.recurringAgenda.savedEdit', 'Regra atualizada'));
      } else {
        if (!form.initiative_id) { toast(t('comp.recurringAgenda.pickInitiative', 'Selecione uma iniciativa'), 'error'); setSaving(false); return; }
        const { error } = await sb.rpc('create_recurring_meeting_rule', {
          p_payload: {
            initiative_id: form.initiative_id, title: form.title, day_of_week: form.day_of_week,
            time_start: form.time_start, duration_minutes: Number(form.duration_minutes),
            frequency: form.frequency, anchor_date: form.anchor_date, meeting_link: form.meeting_link, status: form.status,
          },
        });
        if (error) throw error;
        toast(t('comp.recurringAgenda.savedCreate', 'Regra criada'));
      }
      setForm(null);
      await load();
    } catch (e: any) {
      toast(e?.message || t('comp.recurringAgenda.saveError', 'Erro ao salvar'), 'error');
    } finally {
      setSaving(false);
    }
  };

  const reconcile = async (r: RuleRow) => {
    const sb = getSb();
    if (!sb) return;
    setBusyRule(r.rule_id);
    try {
      const { data, error } = await sb.rpc('reconcile_recurring_meeting', { p_rule_id: r.rule_id });
      if (error) throw error;
      const created = data?.created_events ?? 0;
      toast(t('comp.recurringAgenda.reconciled', 'Reconciliado') + ` (+${created})`);
      await load();
    } catch (e: any) {
      toast(e?.message || t('comp.recurringAgenda.saveError', 'Erro ao salvar'), 'error');
    } finally {
      setBusyRule(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 py-20 justify-center text-[var(--text-muted)]">
        <Loader2 size={16} className="animate-spin" />
        <span>{t('comp.recurringAgenda.loading', 'Carregando agenda recorrente…')}</span>
      </div>
    );
  }
  if (error) {
    return (
      <div className="text-center py-16 text-rose-600">
        <p>{error}</p>
        <button onClick={load} className="mt-3 inline-flex items-center gap-1 text-sm text-[var(--accent)] hover:underline">
          <RefreshCw size={14} /> {t('comp.recurringAgenda.retry', 'Tentar novamente')}
        </button>
      </div>
    );
  }

  const driftCount = rows.filter((r) => r.missing_future > 0 || r.time_mismatch > 0 || r.link_mismatch > 0).length;

  return (
    <div>
      <header className="mb-4 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold flex items-center gap-2">
            <CalendarClock size={20} className="text-[var(--accent)]" />
            {t('comp.recurringAgenda.heading', 'Agenda recorrente')}
          </h1>
          <p className="text-sm text-[var(--text-muted)] mt-1">
            {t('comp.recurringAgenda.subtitle', 'Regras canônicas de reuniões recorrentes de tribos e iniciativas.')}
          </p>
          <div className="mt-2 text-xs text-[var(--text-muted)] flex flex-wrap gap-x-4 gap-y-1">
            <span>{rows.length} {t('comp.recurringAgenda.rulesCount', 'regras')}</span>
            {driftCount > 0 && (
              <span className="inline-flex items-center gap-1 text-amber-700">
                <AlertTriangle size={14} />
                {driftCount} {t('comp.recurringAgenda.withDrift', 'com divergência')}
              </span>
            )}
          </div>
        </div>
        <button onClick={openCreate}
          className="shrink-0 inline-flex items-center gap-1 px-3 py-2 rounded-lg bg-[var(--accent)] text-white text-sm hover:opacity-90">
          <Plus size={16} /> {t('comp.recurringAgenda.newRule', 'Nova regra')}
        </button>
      </header>

      <div className="overflow-x-auto rounded-lg border border-[var(--border)]">
        <table className="w-full text-sm">
          <thead className="bg-[var(--bg-subtle)] text-left text-xs uppercase tracking-wide text-[var(--text-muted)]">
            <tr>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colScope', 'Escopo')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colCadence', 'Cadência')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colNext', 'Próxima')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colStatus', 'Status')}</th>
              <th className="px-3 py-2">{t('comp.recurringAgenda.colDrift', 'Divergência')}</th>
              <th className="px-3 py-2 text-right">{t('comp.recurringAgenda.colActions', 'Ações')}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const sm = statusMeta(r.status);
              const hasDrift = r.missing_future > 0 || r.time_mismatch > 0 || r.link_mismatch > 0;
              return (
                <tr key={r.rule_id} className="border-t border-[var(--border)] align-top">
                  <td className="px-3 py-2">
                    <div className="font-medium">{r.scope_name}</div>
                    <div className="text-xs text-[var(--text-muted)]">{r.title}</div>
                    {r.meeting_link && (
                      <a href={r.meeting_link} target="_blank" rel="noopener noreferrer"
                         className="inline-flex items-center gap-1 text-[var(--accent)] hover:underline text-xs mt-0.5">
                        <ExternalLink size={12} /> Meet
                      </a>
                    )}
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">
                    {dowLabel(r.day_of_week)} {fmtTime(r.time_start)}
                    <span className="text-xs text-[var(--text-muted)]"> · {freqLabel(r.frequency)}</span>
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">
                    {fmtDate(r.next_occurrence)}
                    <span className="text-xs text-[var(--text-muted)]"> · {r.future_events}/{r.expected_future}</span>
                  </td>
                  <td className="px-3 py-2">
                    <span className={`inline-block px-2 py-0.5 rounded-full text-xs ${sm.cls}`}>{sm.label}</span>
                  </td>
                  <td className="px-3 py-2">
                    {hasDrift ? (
                      <span className="inline-flex items-center gap-1 text-xs text-amber-700">
                        <AlertTriangle size={14} />
                        {r.missing_future > 0 && <span>{r.missing_future} {t('comp.recurringAgenda.missing', 'faltando')}</span>}
                        {r.time_mismatch > 0 && <span>· {r.time_mismatch} {t('comp.recurringAgenda.timeOff', 'horário')}</span>}
                        {r.link_mismatch > 0 && <span>· {r.link_mismatch} {t('comp.recurringAgenda.linkOff', 'link')}</span>}
                      </span>
                    ) : (
                      <span className="text-xs text-emerald-600">{t('comp.recurringAgenda.inSync', 'Em dia')}</span>
                    )}
                  </td>
                  <td className="px-3 py-2">
                    <div className="flex items-center justify-end gap-1">
                      <button onClick={() => reconcile(r)} disabled={busyRule === r.rule_id}
                        title={t('comp.recurringAgenda.reconcileNow', 'Reconciliar agora')}
                        className="p-1.5 rounded hover:bg-[var(--bg-subtle)] text-[var(--text-muted)] disabled:opacity-50">
                        {busyRule === r.rule_id ? <Loader2 size={15} className="animate-spin" /> : <RotateCw size={15} />}
                      </button>
                      <button onClick={() => openEdit(r)}
                        title={t('comp.recurringAgenda.edit', 'Editar')}
                        className="p-1.5 rounded hover:bg-[var(--bg-subtle)] text-[var(--text-muted)]">
                        <Pencil size={15} />
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {form && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => !saving && setForm(null)}>
          <div className="bg-[var(--surface)] rounded-xl shadow-xl w-full max-w-md p-5" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold">
                {form.rule_id ? t('comp.recurringAgenda.editTitle', 'Editar recorrência') : t('comp.recurringAgenda.createTitle', 'Nova recorrência')}
              </h2>
              <button onClick={() => !saving && setForm(null)} className="text-[var(--text-muted)] hover:text-[var(--text)]"><X size={18} /></button>
            </div>

            <div className="space-y-3 text-sm">
              {!form.rule_id && (
                <label className="block">
                  <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fInitiative', 'Iniciativa')}</span>
                  <select value={form.initiative_id} onChange={(e) => setForm({ ...form, initiative_id: e.target.value })}
                    className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2">
                    {initiatives.map((i) => <option key={i.id} value={i.id}>{i.title}</option>)}
                  </select>
                </label>
              )}
              <label className="block">
                <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fTitle', 'Título')}</span>
                <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })}
                  className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2" />
              </label>
              <div className="grid grid-cols-2 gap-3">
                <label className="block">
                  <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fDay', 'Dia')}</span>
                  <select value={form.day_of_week} onChange={(e) => setForm({ ...form, day_of_week: Number(e.target.value) })}
                    className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2">
                    {[1, 2, 3, 4, 5, 6, 7].map((d) => <option key={d} value={d}>{dowLabel(d)}</option>)}
                  </select>
                </label>
                <label className="block">
                  <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fTime', 'Horário')}</span>
                  <input type="time" value={form.time_start} onChange={(e) => setForm({ ...form, time_start: e.target.value })}
                    className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2" />
                </label>
                <label className="block">
                  <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fDuration', 'Duração (min)')}</span>
                  <input type="number" min={1} value={form.duration_minutes} onChange={(e) => setForm({ ...form, duration_minutes: Number(e.target.value) })}
                    className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2" />
                </label>
                <label className="block">
                  <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fFrequency', 'Frequência')}</span>
                  <select value={form.frequency} onChange={(e) => setForm({ ...form, frequency: e.target.value })}
                    className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2">
                    <option value="weekly">{t('comp.recurringAgenda.weekly', 'Semanal')}</option>
                    <option value="biweekly">{t('comp.recurringAgenda.biweekly', 'Quinzenal')}</option>
                  </select>
                </label>
                <label className="block">
                  <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fStatus', 'Status')}</span>
                  <select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })}
                    className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2">
                    <option value="active">{t('comp.recurringAgenda.statusActive', 'Ativa')}</option>
                    <option value="paused">{t('comp.recurringAgenda.statusPaused', 'Pausada')}</option>
                    <option value="archived">{t('comp.recurringAgenda.statusArchived', 'Arquivada')}</option>
                  </select>
                </label>
                {!form.rule_id && (
                  <label className="block">
                    <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fAnchor', 'Âncora')}</span>
                    <input type="date" value={form.anchor_date} onChange={(e) => setForm({ ...form, anchor_date: e.target.value })}
                      className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2" />
                  </label>
                )}
              </div>
              <label className="block">
                <span className="text-xs text-[var(--text-muted)]">{t('comp.recurringAgenda.fLink', 'Link da reunião')}</span>
                <input value={form.meeting_link} onChange={(e) => setForm({ ...form, meeting_link: e.target.value })}
                  placeholder="https://meet.google.com/…"
                  className="mt-1 w-full rounded-lg border border-[var(--border)] bg-transparent px-3 py-2" />
              </label>
            </div>

            <div className="mt-5 flex justify-end gap-2">
              <button onClick={() => setForm(null)} disabled={saving}
                className="px-3 py-2 rounded-lg text-sm text-[var(--text-muted)] hover:bg-[var(--bg-subtle)]">
                {t('comp.recurringAgenda.cancel', 'Cancelar')}
              </button>
              <button onClick={save} disabled={saving}
                className="px-3 py-2 rounded-lg text-sm bg-[var(--accent)] text-white hover:opacity-90 inline-flex items-center gap-1 disabled:opacity-60">
                {saving && <Loader2 size={14} className="animate-spin" />}
                {t('comp.recurringAgenda.save', 'Salvar')}
              </button>
            </div>
          </div>
        </div>
      )}

      <p className="mt-3 text-xs text-[var(--text-muted)]">
        {t('comp.recurringAgenda.writeNote', 'Editar/criar/reconciliar respeita a autoridade V4 (GP em qualquer regra; líder da iniciativa nas próprias). A geração de eventos é sob demanda via Reconciliar.')}
      </p>
    </div>
  );
}
