// src/components/initiative/InitiativeRecurringMeetingsPanel.tsx
// #676 Slice B — leader self-service panel for an initiative's recurring meetings.
// Renders ONLY for callers who can manage this initiative's rules (GP or the initiative
// leader): it reads get_recurring_meeting_admin_list(null, initiativeId) which RAISES for
// anyone else, so the panel self-gates (renders nothing on error). Write actions reuse the
// V4-scoped RPCs (update/create/reconcile_recurring_meeting). The global GP screen
// (/admin/agenda-recorrente) stays as the centralized oversight surface.
import { useState, useEffect, useCallback } from 'react';
import { Loader2, CalendarClock, AlertTriangle, ExternalLink, Pencil, Plus, RotateCw, X } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface RuleRow {
  rule_id: string;
  title: string;
  day_of_week: number;
  time_start: string;
  duration_minutes: number;
  frequency: string;
  status: string;
  meeting_link: string | null;
  next_occurrence: string | null;
  future_events: number;
  expected_future: number;
  missing_future: number;
  time_mismatch: number;
  link_mismatch: number;
}
interface FormState {
  rule_id: string | null;
  title: string;
  day_of_week: number;
  time_start: string;
  duration_minutes: number;
  frequency: string;
  status: string;
  meeting_link: string;
  anchor_date: string;
}

const fmtTime = (t: string | null) => (t ? t.slice(0, 5) : '—');
function fmtDate(d: string | null): string {
  if (!d) return '—';
  const ts = Date.parse(`${d}T12:00:00Z`);
  if (Number.isNaN(ts)) return d;
  return new Date(ts).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', timeZone: 'UTC' });
}
const todayISO = () => new Date().toISOString().slice(0, 10);

export default function InitiativeRecurringMeetingsPanel({ initiativeId }: { initiativeId: string }) {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  const [rows, setRows] = useState<RuleRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [canManage, setCanManage] = useState(false);
  const [form, setForm] = useState<FormState | null>(null);
  const [saving, setSaving] = useState(false);
  const [busyRule, setBusyRule] = useState<string | null>(null);

  const toast = (msg: string, kind: 'success' | 'error' = 'success') => (window as any).toast?.(msg, kind);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb || !initiativeId) { setTimeout(load, 300); return; }
    const { data, error } = await sb.rpc('get_recurring_meeting_admin_list', {
      p_horizon_end: null, p_initiative_id: initiativeId,
    });
    if (error) {
      // RPC RAISEs for callers who can't manage this initiative → hide the panel.
      setCanManage(false);
      setLoading(false);
      return;
    }
    setCanManage(true);
    setRows(Array.isArray(data) ? data : []);
    setLoading(false);
  }, [getSb, initiativeId]);

  useEffect(() => { load(); }, [load]);

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
    rule_id: r.rule_id, title: r.title, day_of_week: r.day_of_week, time_start: r.time_start.slice(0, 5),
    duration_minutes: r.duration_minutes, frequency: r.frequency, status: r.status,
    meeting_link: r.meeting_link || '', anchor_date: todayISO(),
  });
  const openCreate = () => setForm({
    rule_id: null, title: '', day_of_week: 1, time_start: '19:00', duration_minutes: 60,
    frequency: 'weekly', status: 'active', meeting_link: '', anchor_date: todayISO(),
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
        const { error } = await sb.rpc('create_recurring_meeting_rule', {
          p_payload: {
            initiative_id: initiativeId, title: form.title, day_of_week: form.day_of_week,
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
      toast(t('comp.recurringAgenda.reconciled', 'Reconciliado') + ` (+${data?.created_events ?? 0})`);
      await load();
    } catch (e: any) {
      toast(e?.message || t('comp.recurringAgenda.saveError', 'Erro ao salvar'), 'error');
    } finally {
      setBusyRule(null);
    }
  };

  if (loading) return null;
  if (!canManage) return null; // self-gate: only GP / this initiative's leader sees the panel

  return (
    <section className="mt-6 rounded-xl border border-[var(--border)] p-4">
      <header className="mb-3 flex items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold flex items-center gap-2">
            <CalendarClock size={18} className="text-[var(--accent)]" />
            {t('comp.recurringAgenda.panelHeading', 'Reuniões recorrentes')}
          </h2>
          <p className="text-xs text-[var(--text-muted)] mt-0.5">
            {t('comp.recurringAgenda.panelSubtitle', 'Gerencie a cadência das reuniões desta iniciativa.')}
          </p>
        </div>
        <button onClick={openCreate}
          className="shrink-0 inline-flex items-center gap-1 px-3 py-1.5 rounded-lg bg-[var(--accent)] text-white text-sm hover:opacity-90">
          <Plus size={15} /> {t('comp.recurringAgenda.newRule', 'Nova regra')}
        </button>
      </header>

      {rows.length === 0 ? (
        <p className="text-sm text-[var(--text-muted)] py-3">
          {t('comp.recurringAgenda.panelEmpty', 'Nenhuma reunião recorrente configurada para esta iniciativa.')}
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-left text-xs uppercase tracking-wide text-[var(--text-muted)]">
              <tr>
                <th className="py-1.5 pr-3">{t('comp.recurringAgenda.colCadence', 'Cadência')}</th>
                <th className="py-1.5 pr-3">{t('comp.recurringAgenda.colNext', 'Próxima')}</th>
                <th className="py-1.5 pr-3">{t('comp.recurringAgenda.colStatus', 'Status')}</th>
                <th className="py-1.5 pr-3">{t('comp.recurringAgenda.colDrift', 'Divergência')}</th>
                <th className="py-1.5 text-right">{t('comp.recurringAgenda.colActions', 'Ações')}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const sm = statusMeta(r.status);
                const hasDrift = r.missing_future > 0 || r.time_mismatch > 0 || r.link_mismatch > 0;
                return (
                  <tr key={r.rule_id} className="border-t border-[var(--border)] align-top">
                    <td className="py-2 pr-3">
                      <div className="font-medium">{r.title}</div>
                      <div className="text-xs text-[var(--text-muted)]">
                        {dowLabel(r.day_of_week)} {fmtTime(r.time_start)} · {freqLabel(r.frequency)}
                        {r.meeting_link && (
                          <a href={r.meeting_link} target="_blank" rel="noopener noreferrer"
                             className="inline-flex items-center gap-0.5 text-[var(--accent)] hover:underline ml-2">
                            <ExternalLink size={11} /> Meet
                          </a>
                        )}
                      </div>
                    </td>
                    <td className="py-2 pr-3 whitespace-nowrap">
                      {fmtDate(r.next_occurrence)}
                      <span className="text-xs text-[var(--text-muted)]"> · {r.future_events}/{r.expected_future}</span>
                    </td>
                    <td className="py-2 pr-3">
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs ${sm.cls}`}>{sm.label}</span>
                    </td>
                    <td className="py-2 pr-3">
                      {hasDrift ? (
                        <span className="inline-flex items-center gap-1 text-xs text-amber-700">
                          <AlertTriangle size={13} />
                          {r.missing_future > 0 && <span>{r.missing_future} {t('comp.recurringAgenda.missing', 'faltando')}</span>}
                          {r.time_mismatch > 0 && <span>· {r.time_mismatch} {t('comp.recurringAgenda.timeOff', 'horário')}</span>}
                          {r.link_mismatch > 0 && <span>· {r.link_mismatch} {t('comp.recurringAgenda.linkOff', 'link')}</span>}
                        </span>
                      ) : (
                        <span className="text-xs text-emerald-600">{t('comp.recurringAgenda.inSync', 'Em dia')}</span>
                      )}
                    </td>
                    <td className="py-2">
                      <div className="flex items-center justify-end gap-1">
                        <button onClick={() => reconcile(r)} disabled={busyRule === r.rule_id}
                          title={t('comp.recurringAgenda.reconcileNow', 'Reconciliar agora')}
                          className="p-1.5 rounded hover:bg-[var(--bg-subtle)] text-[var(--text-muted)] disabled:opacity-50">
                          {busyRule === r.rule_id ? <Loader2 size={14} className="animate-spin" /> : <RotateCw size={14} />}
                        </button>
                        <button onClick={() => openEdit(r)} title={t('comp.recurringAgenda.edit', 'Editar')}
                          className="p-1.5 rounded hover:bg-[var(--bg-subtle)] text-[var(--text-muted)]">
                          <Pencil size={14} />
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {form && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => !saving && setForm(null)}>
          <div className="bg-[var(--surface)] rounded-xl shadow-xl w-full max-w-md p-5" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold">
                {form.rule_id ? t('comp.recurringAgenda.editTitle', 'Editar recorrência') : t('comp.recurringAgenda.createTitle', 'Nova recorrência')}
              </h3>
              <button onClick={() => !saving && setForm(null)} className="text-[var(--text-muted)] hover:text-[var(--text)]"><X size={18} /></button>
            </div>
            <div className="space-y-3 text-sm">
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
    </section>
  );
}
