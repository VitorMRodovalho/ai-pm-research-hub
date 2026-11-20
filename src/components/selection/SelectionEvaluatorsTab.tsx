import { useCallback, useEffect, useMemo, useState } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { rpcChecked } from '../../lib/rpc-checked';

/**
 * #3119 (ADR-0134 §3 e §4): aba Avaliadores de /admin/selection, só para manage_platform.
 *
 * Toda escrita do piloto sobre avaliadores ganha tela de ver, auditar e corrigir:
 *   - vínculos: grant_selection_evaluator (dar ou estender a data de fim) e end_selection_evaluator (encerrar hoje);
 *   - calibragens por vaga e parte, com a versão do material: record_selection_evaluator_calibration;
 *   - atribuições por vaga e parte, com prazo, estado e envio: assign_selection_evaluators e
 *     withdraw_selection_evaluator_assignment;
 *   - histórico: admin_audit_log, ações selection_evaluator.*.
 * A leitura é uma só, get_selection_evaluators_admin. Cada escrita relê tudo, para a tela mostrar o banco.
 */

const PARTS = ['objective', 'video', 'fit'] as const;
type Part = (typeof PARTS)[number];

interface Opening { opportunity_id: string; title: string; is_active: boolean | null; initiative_title: string | null }
interface Application { id: string; applicant_name: string; status: string; opportunity_id: string }
interface MemberLite { id: string; name: string }
interface Evaluator {
  engagement_id: string; member_id: string; name: string; status: string; start_date: string; end_date: string | null;
  revoked_at: string | null; revoke_reason: string | null; authoritative: boolean;
}
interface Calibration {
  id: string; member_id: string; name: string; opportunity_id: string; part: Part; material_version: string;
  calibrated_at: string; calibrated_by_name: string | null; notes: string | null;
}
interface Assignment {
  id: string; application_id: string; applicant_name: string; opportunity_id: string; part: Part; member_id: string;
  name: string; assigned_at: string; due_at: string | null; withdrawn_at: string | null; withdrawn_reason: string | null;
  submitted_at: string | null; state: 'withdrawn' | 'submitted' | 'overdue' | 'draft' | 'pending';
}
interface HistoryRow {
  created_at: string; action: string; target_type: string; target_id: string | null; metadata: Record<string, unknown> | null;
  actor_name: string | null; target_name: string | null;
}
interface RubricItem {
  key: string; label: string; question: string | null; anchors: { weak: string; medium: string; strong: string };
  min_level: number | null;
}
interface Rubric {
  id: string; opportunity_id: string; part: 'video' | 'fit'; version: number; items: RubricItem[]; created_at: string;
  created_by_name: string | null; is_current: boolean; locked: boolean;
}
interface AdminData {
  openings: Opening[]; applications: Application[]; members: MemberLite[]; evaluators: Evaluator[];
  calibrations: Calibration[]; assignments: Assignment[]; history: HistoryRow[]; rubrics?: Rubric[];
}
type DraftItem = { key: string; label: string; question: string; weak: string; medium: string; strong: string; min_level: string };
const RUBRIC_PARTS = ['video', 'fit'] as const;
const emptyItem = (): DraftItem => ({ key: '', label: '', question: '', weak: '', medium: '', strong: '', min_level: '' });

const STATE_TONE: Record<Assignment['state'], string> = {
  submitted: 'bg-emerald-100 text-emerald-700',
  pending: 'bg-blue-100 text-blue-700',
  draft: 'bg-amber-100 text-amber-700',
  overdue: 'bg-red-100 text-red-700',
  withdrawn: 'bg-gray-100 text-gray-500',
};

// Rótulo em pt-BR quando o dicionário da página não carregou: nunca mostrar o código cru.
const PT_FALLBACK: Record<string, string> = {
  'part.objective': 'Objetiva', 'part.video': 'Vídeo', 'part.fit': 'Fit',
  'state.pending': 'Pendente', 'state.draft': 'Rascunho', 'state.overdue': 'Vencida', 'state.submitted': 'Enviada', 'state.withdrawn': 'Retirada',
  'action.granted': 'Vínculo dado', 'action.extended': 'Data de fim alterada', 'action.ended': 'Vínculo encerrado',
  'action.calibrated': 'Calibragem registrada', 'action.assigned': 'Atribuição feita', 'action.assignment_withdrawn': 'Atribuição retirada',
  'action.rubric_saved': 'Rubrica salva',
};

const inputCls = 'px-2 py-1.5 text-[12px] border border-[var(--border-default)] rounded-lg bg-[var(--surface-input)] text-[var(--text-primary)]';
const btnCls = 'px-3 py-1.5 text-[12px] font-semibold rounded-lg bg-navy text-white border-0 cursor-pointer hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed';
const btnGhost = 'px-2 py-1 text-[11px] font-semibold rounded-md border border-[var(--border-default)] bg-transparent text-[var(--text-secondary)] cursor-pointer hover:text-navy';
const cardCls = 'bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-4 space-y-3';
const thCls = 'px-3 py-2 text-[11px] font-bold text-[var(--text-secondary)] text-left whitespace-nowrap';
const tdCls = 'px-3 py-2 text-[12px] text-[var(--text-primary)] align-top';

function fmtDate(v: string | null | undefined): string {
  if (!v) return '—';
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) { const [y, m, d] = v.split('-'); return `${d}/${m}/${y}`; }
  const dt = new Date(v);
  return Number.isNaN(dt.getTime()) ? v : dt.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
}
function isoDatePlus(days: number): string {
  const d = new Date(); d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

export default function SelectionEvaluatorsTab() {
  const t = usePageI18n();
  const tr = (k: string, fb: string) => t(`admin.selection.evaluators.${k}`, fb);
  const partLabel = (p: string) => tr(`part.${p}`, PT_FALLBACK[`part.${p}`] || p);
  const stateLabel = (s: string) => tr(`state.${s}`, PT_FALLBACK[`state.${s}`] || s);
  const actionLabel = (a: string) => {
    const k = a === 'selection_rubric.saved' ? 'action.rubric_saved' : `action.${a.replace('selection_evaluator.', '')}`;
    return tr(k, PT_FALLBACK[k] || a);
  };

  const [data, setData] = useState<AdminData | null>(null);
  const [loading, setLoading] = useState(false);
  const [msg, setMsg] = useState<{ kind: 'ok' | 'err'; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  // formulários
  const [grantMember, setGrantMember] = useState('');
  const [grantEnd, setGrantEnd] = useState(isoDatePlus(90));
  const [grantNote, setGrantNote] = useState('');
  const [endFor, setEndFor] = useState<string | null>(null);
  const [endReason, setEndReason] = useState('');
  const [extendFor, setExtendFor] = useState<string | null>(null);
  const [extendEnd, setExtendEnd] = useState(isoDatePlus(90));
  const [calMember, setCalMember] = useState('');
  const [calOpp, setCalOpp] = useState('');
  const [calPart, setCalPart] = useState<Part>('objective');
  const [calVersion, setCalVersion] = useState('');
  const [calNotes, setCalNotes] = useState('');
  const [asgOpp, setAsgOpp] = useState('');
  const [asgPart, setAsgPart] = useState<Part>('objective');
  const [asgMember, setAsgMember] = useState('');
  const [asgApps, setAsgApps] = useState<string[]>([]);
  const [wdFor, setWdFor] = useState<string | null>(null);
  const [wdReason, setWdReason] = useState('');
  const [filterOpp, setFilterOpp] = useState('');
  const [filterState, setFilterState] = useState('');
  // #3120: editor da rubrica
  const [rubOpp, setRubOpp] = useState('');
  const [rubPart, setRubPart] = useState<'video' | 'fit'>('video');
  const [rubDraft, setRubDraft] = useState<DraftItem[]>([emptyItem(), emptyItem(), emptyItem()]);
  const [rubEditing, setRubEditing] = useState(false);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) return;
    setLoading(true);
    try {
      const d = await rpcChecked<AdminData>(sb, 'get_selection_evaluators_admin');
      setData(d);
      const first = d.openings[0]?.opportunity_id || '';
      setCalOpp((v) => v || first);
      setAsgOpp((v) => v || first);
      setRubOpp((v) => v || first);
    } catch (e: any) {
      setMsg({ kind: 'err', text: e?.message || String(e) });
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  async function run(fn: string, args: Record<string, unknown>, okText: string): Promise<boolean> {
    const sb = (window as any).navGetSb?.();
    if (!sb) return false;
    setBusy(true); setMsg(null);
    try {
      await rpcChecked(sb, fn, args);
      setMsg({ kind: 'ok', text: okText });
      await load();
      return true;
    } catch (e: any) {
      setMsg({ kind: 'err', text: e?.message || String(e) });
      return false;
    } finally {
      setBusy(false);
    }
  }

  const authoritative = useMemo(() => (data?.evaluators || []).filter((e) => e.authoritative), [data]);
  const oppTitle = useCallback((id: string) => {
    const o = data?.openings.find((x) => x.opportunity_id === id);
    return o ? `${o.opportunity_id} · ${o.title}` : id;
  }, [data]);
  const asgCandidates = useMemo(() => (data?.applications || []).filter((a) => a.opportunity_id === asgOpp), [data, asgOpp]);
  const rubrics = useMemo(() => data?.rubrics || [], [data]);
  const currentRubric = useMemo(() => rubrics.find((r) => r.opportunity_id === rubOpp && r.part === rubPart && r.is_current) || null, [rubrics, rubOpp, rubPart]);
  function startEdit() {
    const base = currentRubric?.items?.length
      ? currentRubric.items.map((i) => ({ key: i.key, label: i.label, question: i.question || '', weak: i.anchors?.weak || '', medium: i.anchors?.medium || '', strong: i.anchors?.strong || '', min_level: i.min_level != null ? String(i.min_level) : '' }))
      : (rubPart === 'video' ? [emptyItem(), emptyItem(), emptyItem()] : [emptyItem()]);
    setRubDraft(base);
    setRubEditing(true);
  }
  function setItem(i: number, field: keyof DraftItem, value: string) {
    setRubDraft((d) => d.map((it, j) => (j === i ? { ...it, [field]: value } : it)));
  }
  async function saveRubric() {
    const items = rubDraft.map((it) => ({
      key: it.key.trim(), label: it.label.trim(), question: it.question.trim() || null,
      anchors: { weak: it.weak.trim(), medium: it.medium.trim(), strong: it.strong.trim() },
      min_level: rubPart === 'fit' && it.min_level ? Number(it.min_level) : null,
    }));
    if (await run('save_selection_rubric', { p_opportunity_id: rubOpp, p_part: rubPart, p_items: items }, tr('okRubric', 'Rubrica salva como versão nova.'))) setRubEditing(false);
  }
  const assignments = useMemo(() => (data?.assignments || []).filter((a) =>
    (!filterOpp || a.opportunity_id === filterOpp) && (!filterState || a.state === filterState)), [data, filterOpp, filterState]);

  if (!data) {
    return (
      <div className={cardCls} data-testid="evaluators-tab">
        <p className="text-[12px] text-[var(--text-muted)]">{loading ? tr('loading', 'Carregando…') : (msg?.text || tr('loading', 'Carregando…'))}</p>
      </div>
    );
  }

  return (
    <div className="space-y-4" data-testid="evaluators-tab">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <p className="text-[12px] text-[var(--text-muted)] max-w-3xl">{tr('intro', 'Vínculos, calibragens e atribuições dos avaliadores do piloto da linha (ADR-0134). Toda mudança fica no histórico.')}</p>
        <button type="button" className={btnGhost} onClick={() => load()} disabled={loading}>{tr('reload', 'Recarregar')}</button>
      </div>
      {msg && (
        <div role="status" className={`rounded-lg px-3 py-2 text-[12px] ${msg.kind === 'ok' ? 'bg-emerald-50 text-emerald-800 border border-emerald-200' : 'bg-red-50 text-red-800 border border-red-200'}`}>{msg.text}</div>
      )}

      {/* ── Vínculos ── */}
      <section className={cardCls}>
        <h3 className="text-[14px] font-bold text-navy">{tr('grantsTitle', 'Vínculos de avaliador')}</h3>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead><tr className="bg-[var(--surface-base)]">
              <th className={thCls}>{tr('colName', 'Pessoa')}</th>
              <th className={thCls}>{tr('colStatus', 'Situação')}</th>
              <th className={thCls}>{tr('colStart', 'Início')}</th>
              <th className={thCls}>{tr('colEnd', 'Fim')}</th>
              <th className={thCls}>{tr('colReason', 'Motivo do encerramento')}</th>
              <th className={thCls}></th>
            </tr></thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {data.evaluators.length === 0 && <tr><td className={tdCls} colSpan={6}>{tr('emptyGrants', 'Nenhum vínculo de avaliador.')}</td></tr>}
              {data.evaluators.map((e) => (
                <tr key={e.engagement_id} data-engagement={e.engagement_id}>
                  <td className={tdCls}>{e.name}</td>
                  <td className={tdCls}>
                    <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${e.authoritative ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-500'}`}>
                      {e.authoritative ? tr('valid', 'Válido') : e.status === 'active' ? tr('expired', 'Vencido') : tr('ended', 'Encerrado')}
                    </span>
                  </td>
                  <td className={tdCls}>{fmtDate(e.start_date)}</td>
                  <td className={tdCls}>{fmtDate(e.end_date)}</td>
                  <td className={tdCls}>{e.revoke_reason || '—'}</td>
                  <td className={`${tdCls} whitespace-nowrap`}>
                    {e.status === 'active' && (
                      <div className="flex flex-col gap-1 items-start">
                        {extendFor === e.member_id ? (
                          <div className="flex gap-1 items-center flex-wrap">
                            <input type="date" className={inputCls} value={extendEnd} onChange={(ev) => setExtendEnd(ev.target.value)} aria-label={tr('newEnd', 'Nova data de fim')} />
                            <button type="button" className={btnCls} disabled={busy}
                              onClick={async () => { if (await run('grant_selection_evaluator', { p_member_id: e.member_id, p_end_date: extendEnd, p_note: null }, tr('okExtended', 'Data de fim alterada.'))) setExtendFor(null); }}>{tr('save', 'Salvar')}</button>
                            <button type="button" className={btnGhost} onClick={() => setExtendFor(null)}>{tr('cancel', 'Cancelar')}</button>
                          </div>
                        ) : (
                          <button type="button" className={btnGhost} onClick={() => { setExtendFor(e.member_id); setEndFor(null); }}>{tr('changeEnd', 'Mudar data de fim')}</button>
                        )}
                        {endFor === e.member_id ? (
                          <div className="flex gap-1 items-center flex-wrap">
                            <input type="text" className={inputCls} placeholder={tr('reasonPlaceholder', 'Motivo (obrigatório)')} value={endReason} onChange={(ev) => setEndReason(ev.target.value)} />
                            <button type="button" className={btnCls} disabled={busy || !endReason.trim()}
                              onClick={async () => { if (await run('end_selection_evaluator', { p_member_id: e.member_id, p_reason: endReason.trim() }, tr('okEnded', 'Vínculo encerrado; as atribuições ativas foram retiradas.'))) { setEndFor(null); setEndReason(''); } }}>{tr('confirmEnd', 'Encerrar hoje')}</button>
                            <button type="button" className={btnGhost} onClick={() => setEndFor(null)}>{tr('cancel', 'Cancelar')}</button>
                          </div>
                        ) : (
                          <button type="button" className={btnGhost} onClick={() => { setEndFor(e.member_id); setExtendFor(null); }}>{tr('end', 'Encerrar')}</button>
                        )}
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <form className="flex gap-2 items-end flex-wrap border-t border-[var(--border-subtle)] pt-3"
          onSubmit={async (ev) => { ev.preventDefault(); if (await run('grant_selection_evaluator', { p_member_id: grantMember, p_end_date: grantEnd, p_note: grantNote.trim() || null }, tr('okGranted', 'Vínculo dado.'))) { setGrantMember(''); setGrantNote(''); } }}>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('member', 'Pessoa')}
            <select className={inputCls} value={grantMember} onChange={(ev) => setGrantMember(ev.target.value)} required>
              <option value="">{tr('choose', 'Escolha…')}</option>
              {data.members.map((m) => <option key={m.id} value={m.id}>{m.name}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('endDate', 'Data de fim')}
            <input type="date" className={inputCls} value={grantEnd} onChange={(ev) => setGrantEnd(ev.target.value)} required />
          </label>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)] grow">{tr('note', 'Nota')}
            <input type="text" className={inputCls} value={grantNote} onChange={(ev) => setGrantNote(ev.target.value)} />
          </label>
          <button type="submit" className={btnCls} disabled={busy || !grantMember}>{tr('grant', 'Dar vínculo')}</button>
        </form>
        <p className="text-[11px] text-[var(--text-muted)]">{tr('grantHint', 'A data de fim é obrigatória, de hoje a 180 dias. Dar o vínculo a quem já tem só muda a data de fim.')}</p>
      </section>

      {/* ── Calibragens ── */}
      <section className={cardCls}>
        <h3 className="text-[14px] font-bold text-navy">{tr('calibrationsTitle', 'Calibragens por vaga e parte')}</h3>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead><tr className="bg-[var(--surface-base)]">
              <th className={thCls}>{tr('colName', 'Pessoa')}</th>
              <th className={thCls}>{tr('colOpening', 'Vaga')}</th>
              <th className={thCls}>{tr('colPart', 'Parte')}</th>
              <th className={thCls}>{tr('colVersion', 'Versão do material')}</th>
              <th className={thCls}>{tr('colWhen', 'Quando')}</th>
              <th className={thCls}>{tr('colBy', 'Por')}</th>
              <th className={thCls}>{tr('colNotes', 'Notas')}</th>
            </tr></thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {data.calibrations.length === 0 && <tr><td className={tdCls} colSpan={7}>{tr('emptyCalibrations', 'Nenhuma calibragem.')}</td></tr>}
              {data.calibrations.map((c) => (
                <tr key={c.id}>
                  <td className={tdCls}>{c.name}</td>
                  <td className={tdCls}>{oppTitle(c.opportunity_id)}</td>
                  <td className={tdCls}>{partLabel(c.part)}</td>
                  <td className={`${tdCls} font-mono`}>{c.material_version}</td>
                  <td className={tdCls}>{fmtDate(c.calibrated_at)}</td>
                  <td className={tdCls}>{c.calibrated_by_name || '—'}</td>
                  <td className={tdCls}>{c.notes || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <form className="flex gap-2 items-end flex-wrap border-t border-[var(--border-subtle)] pt-3"
          onSubmit={async (ev) => { ev.preventDefault(); if (await run('record_selection_evaluator_calibration', { p_member_id: calMember, p_opportunity_id: calOpp, p_part: calPart, p_material_version: calVersion.trim(), p_notes: calNotes.trim() || null }, tr('okCalibrated', 'Calibragem registrada.'))) { setCalVersion(''); setCalNotes(''); } }}>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('member', 'Pessoa')}
            <select className={inputCls} value={calMember} onChange={(ev) => setCalMember(ev.target.value)} required>
              <option value="">{tr('choose', 'Escolha…')}</option>
              {authoritative.map((e) => <option key={e.member_id} value={e.member_id}>{e.name}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('colOpening', 'Vaga')}
            <select className={inputCls} value={calOpp} onChange={(ev) => setCalOpp(ev.target.value)} required>
              {data.openings.map((o) => <option key={o.opportunity_id} value={o.opportunity_id}>{oppTitle(o.opportunity_id)}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('colPart', 'Parte')}
            <select className={inputCls} value={calPart} onChange={(ev) => setCalPart(ev.target.value as Part)}>
              {PARTS.map((p) => <option key={p} value={p}>{partLabel(p)}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('colVersion', 'Versão do material')}
            <input type="text" className={inputCls} value={calVersion} onChange={(ev) => setCalVersion(ev.target.value)} required />
          </label>
          <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)] grow">{tr('colNotes', 'Notas')}
            <input type="text" className={inputCls} value={calNotes} onChange={(ev) => setCalNotes(ev.target.value)} />
          </label>
          <button type="submit" className={btnCls} disabled={busy || !calMember || !calOpp || !calVersion.trim()}>{tr('calibrate', 'Registrar calibragem')}</button>
        </form>
      </section>

      {/* ── Atribuições ── */}
      <section className={cardCls}>
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <h3 className="text-[14px] font-bold text-navy">{tr('assignmentsTitle', 'Atribuições por vaga e parte')}</h3>
          <div className="flex gap-2">
            <select className={inputCls} value={filterOpp} onChange={(ev) => setFilterOpp(ev.target.value)} aria-label={tr('colOpening', 'Vaga')}>
              <option value="">{tr('allOpenings', 'Todas as vagas')}</option>
              {data.openings.map((o) => <option key={o.opportunity_id} value={o.opportunity_id}>{o.opportunity_id}</option>)}
            </select>
            <select className={inputCls} value={filterState} onChange={(ev) => setFilterState(ev.target.value)} aria-label={tr('colState', 'Estado')}>
              <option value="">{tr('allStates', 'Todos os estados')}</option>
              {(['pending', 'draft', 'overdue', 'submitted', 'withdrawn'] as const).map((s) => <option key={s} value={s}>{stateLabel(s)}</option>)}
            </select>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead><tr className="bg-[var(--surface-base)]">
              <th className={thCls}>{tr('colApplication', 'Candidatura')}</th>
              <th className={thCls}>{tr('colOpening', 'Vaga')}</th>
              <th className={thCls}>{tr('colPart', 'Parte')}</th>
              <th className={thCls}>{tr('colEvaluator', 'Avaliador')}</th>
              <th className={thCls}>{tr('colAssigned', 'Atribuída em')}</th>
              <th className={thCls}>{tr('colDue', 'Prazo')}</th>
              <th className={thCls}>{tr('colState', 'Estado')}</th>
              <th className={thCls}>{tr('colSubmitted', 'Enviada em')}</th>
              <th className={thCls}></th>
            </tr></thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {assignments.length === 0 && <tr><td className={tdCls} colSpan={9}>{tr('emptyAssignments', 'Nenhuma atribuição.')}</td></tr>}
              {assignments.map((a) => (
                <tr key={a.id} data-assignment={a.id} data-state={a.state}>
                  <td className={tdCls}>{a.applicant_name}</td>
                  <td className={tdCls}>{a.opportunity_id}</td>
                  <td className={tdCls}>{partLabel(a.part)}</td>
                  <td className={tdCls}>{a.name}</td>
                  <td className={tdCls}>{fmtDate(a.assigned_at)}</td>
                  <td className={tdCls}>{fmtDate(a.due_at)}</td>
                  <td className={tdCls}>
                    <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${STATE_TONE[a.state]}`} title={a.withdrawn_reason || ''}>{stateLabel(a.state)}</span>
                  </td>
                  <td className={tdCls}>{fmtDate(a.submitted_at)}</td>
                  <td className={`${tdCls} whitespace-nowrap`}>
                    {!a.withdrawn_at && !a.submitted_at && (wdFor === a.id ? (
                      <div className="flex gap-1 items-center flex-wrap">
                        <input type="text" className={inputCls} placeholder={tr('reasonPlaceholder', 'Motivo (obrigatório)')} value={wdReason} onChange={(ev) => setWdReason(ev.target.value)} />
                        <button type="button" className={btnCls} disabled={busy || !wdReason.trim()}
                          onClick={async () => { if (await run('withdraw_selection_evaluator_assignment', { p_assignment_id: a.id, p_reason: wdReason.trim() }, tr('okWithdrawn', 'Atribuição retirada.'))) { setWdFor(null); setWdReason(''); } }}>{tr('confirmWithdraw', 'Retirar')}</button>
                        <button type="button" className={btnGhost} onClick={() => setWdFor(null)}>{tr('cancel', 'Cancelar')}</button>
                      </div>
                    ) : (
                      <button type="button" className={btnGhost} onClick={() => { setWdFor(a.id); setWdReason(''); }}>{tr('withdraw', 'Retirar')}</button>
                    ))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <form className="space-y-2 border-t border-[var(--border-subtle)] pt-3"
          onSubmit={async (ev) => { ev.preventDefault(); if (await run('assign_selection_evaluators', { p_opportunity_id: asgOpp, p_part: asgPart, p_member_id: asgMember, p_application_ids: asgApps }, tr('okAssigned', 'Atribuição feita; o avaliador foi avisado.'))) setAsgApps([]); }}>
          <div className="flex gap-2 items-end flex-wrap">
            <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('colOpening', 'Vaga')}
              <select className={inputCls} value={asgOpp} onChange={(ev) => { setAsgOpp(ev.target.value); setAsgApps([]); }} required>
                {data.openings.map((o) => <option key={o.opportunity_id} value={o.opportunity_id}>{oppTitle(o.opportunity_id)}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('colPart', 'Parte')}
              <select className={inputCls} value={asgPart} onChange={(ev) => setAsgPart(ev.target.value as Part)}>
                {PARTS.map((p) => <option key={p} value={p}>{partLabel(p)}</option>)}
              </select>
            </label>
            <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('colEvaluator', 'Avaliador')}
              <select className={inputCls} value={asgMember} onChange={(ev) => setAsgMember(ev.target.value)} required>
                <option value="">{tr('choose', 'Escolha…')}</option>
                {authoritative.map((e) => <option key={e.member_id} value={e.member_id}>{e.name}</option>)}
              </select>
            </label>
            <button type="submit" className={btnCls} disabled={busy || !asgMember || asgApps.length === 0}>{tr('assign', 'Atribuir')} ({asgApps.length})</button>
          </div>
          <fieldset className="flex flex-wrap gap-x-4 gap-y-1">
            <legend className="text-[11px] text-[var(--text-secondary)] mb-1">{tr('pickApplications', 'Candidaturas')}</legend>
            {asgCandidates.length === 0 && <span className="text-[12px] text-[var(--text-muted)]">{tr('emptyApplications', 'Nenhuma candidatura nesta vaga.')}</span>}
            {asgCandidates.map((c) => (
              <label key={c.id} className="flex items-center gap-1 text-[12px] text-[var(--text-primary)]">
                <input type="checkbox" checked={asgApps.includes(c.id)}
                  onChange={(ev) => setAsgApps((v) => ev.target.checked ? [...v, c.id] : v.filter((x) => x !== c.id))} />
                {c.applicant_name} <span className="text-[10px] text-[var(--text-muted)]">({c.status})</span>
              </label>
            ))}
          </fieldset>
          <p className="text-[11px] text-[var(--text-muted)]">{tr('assignHint', 'Objetiva: o líder da vaga e 1 de fora, prazo de 7 dias. Vídeo: 2 de fora da linha. Fit: o líder da vaga. Quem atribui precisa de vínculo válido e calibragem da vaga e da parte; a recusa lista todos os motivos.')}</p>
        </form>
      </section>

      {/* ── Rubricas (#3120) ── */}
      <section className={cardCls} data-testid="rubrics">
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <h3 className="text-[14px] font-bold text-navy">{tr('rubricsTitle', 'Rubricas por vaga e parte')}</h3>
          <div className="flex gap-2">
            <select className={inputCls} value={rubOpp} onChange={(ev) => { setRubOpp(ev.target.value); setRubEditing(false); }} aria-label={tr('colOpening', 'Vaga')}>
              {data.openings.map((o) => <option key={o.opportunity_id} value={o.opportunity_id}>{oppTitle(o.opportunity_id)}</option>)}
            </select>
            <select className={inputCls} value={rubPart} onChange={(ev) => { setRubPart(ev.target.value as 'video' | 'fit'); setRubEditing(false); }} aria-label={tr('colPart', 'Parte')}>
              {RUBRIC_PARTS.map((p) => <option key={p} value={p}>{partLabel(p)}</option>)}
            </select>
          </div>
        </div>
        <p className="text-[11px] text-[var(--text-muted)]">{tr('rubricHint', 'Cada item tem nota 1 (fraco), 2 (médio) ou 3 (forte), com a âncora escrita de cada nível. Vídeo: de 3 a 5 perguntas. Fit: os critérios, com mínimo opcional; nota abaixo dele exige justificativa. Salvar cria uma versão nova; a parte trava na primeira nota enviada.')}</p>
        {!rubEditing && (
          <div className="space-y-2">
            {currentRubric ? (
              <>
                <p className="text-[12px] text-[var(--text-secondary)]">
                  <strong className="text-navy">{tr('version', 'Versão')} {currentRubric.version}</strong> · {fmtDate(currentRubric.created_at)} · {currentRubric.created_by_name || '—'}
                  {currentRubric.locked && <span className="ml-2 text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-600">{tr('locked', 'Travada')}</span>}
                </p>
                <ol className="list-decimal pl-5 space-y-2">
                  {currentRubric.items.map((it) => (
                    <li key={it.key} className="text-[12px] text-[var(--text-primary)]">
                      <strong>{it.label}</strong> <span className="font-mono text-[10px] text-[var(--text-muted)]">{it.key}</span>
                      {it.question && <div className="text-[var(--text-secondary)] whitespace-pre-wrap">{it.question}</div>}
                      <div className="grid sm:grid-cols-3 gap-2 mt-1">
                        <div><span className="font-bold">1 · {tr('levelWeak', 'Fraco')}</span> {it.anchors?.weak}</div>
                        <div><span className="font-bold">2 · {tr('levelMedium', 'Médio')}</span> {it.anchors?.medium}</div>
                        <div><span className="font-bold">3 · {tr('levelStrong', 'Forte')}</span> {it.anchors?.strong}</div>
                      </div>
                      {it.min_level != null && <div className="text-amber-700">{tr('minLevel', 'Mínimo')}: {it.min_level}</div>}
                    </li>
                  ))}
                </ol>
              </>
            ) : (
              <p className="text-[12px] text-[var(--text-muted)]">{tr('emptyRubric', 'Esta vaga ainda não tem rubrica desta parte.')}</p>
            )}
            <button type="button" className={btnCls} disabled={busy || !rubOpp || !!currentRubric?.locked} onClick={startEdit}>
              {currentRubric ? tr('newVersion', 'Nova versão') : tr('createRubric', 'Criar rubrica')}
            </button>
            {rubrics.filter((r) => r.opportunity_id === rubOpp && r.part === rubPart && !r.is_current).length > 0 && (
              <p className="text-[11px] text-[var(--text-muted)]">{tr('olderVersions', 'Versões anteriores')}: {rubrics.filter((r) => r.opportunity_id === rubOpp && r.part === rubPart && !r.is_current).map((r) => `v${r.version} (${fmtDate(r.created_at)})`).join(', ')}</p>
            )}
          </div>
        )}
        {rubEditing && (
          <div className="space-y-3">
            {rubDraft.map((it, i) => (
              <fieldset key={i} className="border border-[var(--border-subtle)] rounded-lg p-3 space-y-2" data-rubric-row={i}>
                <div className="flex gap-2 flex-wrap items-end">
                  <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('itemKey', 'Chave')}
                    <input type="text" className={inputCls} value={it.key} onChange={(ev) => setItem(i, 'key', ev.target.value)} placeholder="ex.: q1" />
                  </label>
                  <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)] grow">{tr('itemLabel', 'Rótulo')}
                    <input type="text" className={inputCls} value={it.label} onChange={(ev) => setItem(i, 'label', ev.target.value)} />
                  </label>
                  {rubPart === 'fit' && (
                    <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{tr('minLevel', 'Mínimo')}
                      <select className={inputCls} value={it.min_level} onChange={(ev) => setItem(i, 'min_level', ev.target.value)}>
                        <option value="">{tr('noMinimum', 'Sem mínimo')}</option>
                        <option value="1">1</option><option value="2">2</option><option value="3">3</option>
                      </select>
                    </label>
                  )}
                  <button type="button" className={btnGhost} onClick={() => setRubDraft((d) => d.filter((_, j) => j !== i))}>{tr('removeItem', 'Remover')}</button>
                </div>
                <label className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{rubPart === 'video' ? tr('itemQuestion', 'Pergunta') : tr('itemDescription', 'Descrição (opcional)')}
                  <textarea className={inputCls} rows={2} value={it.question} onChange={(ev) => setItem(i, 'question', ev.target.value)} />
                </label>
                <div className="grid sm:grid-cols-3 gap-2">
                  {(['weak', 'medium', 'strong'] as const).map((lv, n) => (
                    <label key={lv} className="flex flex-col gap-1 text-[11px] text-[var(--text-secondary)]">{n + 1} · {tr(`level${lv[0].toUpperCase()}${lv.slice(1)}`, lv)}
                      <textarea className={inputCls} rows={2} value={it[lv]} onChange={(ev) => setItem(i, lv, ev.target.value)} />
                    </label>
                  ))}
                </div>
              </fieldset>
            ))}
            <div className="flex gap-2 flex-wrap">
              <button type="button" className={btnGhost} onClick={() => setRubDraft((d) => [...d, emptyItem()])}>{tr('addItem', 'Adicionar item')}</button>
              <button type="button" className={btnCls} disabled={busy} onClick={saveRubric}>{tr('saveRubric', 'Salvar versão')}</button>
              <button type="button" className={btnGhost} onClick={() => setRubEditing(false)}>{tr('cancel', 'Cancelar')}</button>
            </div>
          </div>
        )}
      </section>

      {/* ── Histórico ── */}
      <section className={cardCls}>
        <h3 className="text-[14px] font-bold text-navy">{tr('historyTitle', 'Histórico')}</h3>
        <div className="overflow-x-auto max-h-[420px] overflow-y-auto">
          <table className="w-full">
            <thead><tr className="bg-[var(--surface-base)]">
              <th className={thCls}>{tr('colWhen', 'Quando')}</th>
              <th className={thCls}>{tr('colBy', 'Por')}</th>
              <th className={thCls}>{tr('colAction', 'Ação')}</th>
              <th className={thCls}>{tr('colName', 'Pessoa')}</th>
              <th className={thCls}>{tr('colDetails', 'Detalhes')}</th>
            </tr></thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {data.history.length === 0 && <tr><td className={tdCls} colSpan={5}>{tr('emptyHistory', 'Nada registrado ainda. O histórico começa com esta versão da tela.')}</td></tr>}
              {data.history.map((h, i) => (
                <tr key={`${h.created_at}-${i}`}>
                  <td className={`${tdCls} whitespace-nowrap`}>{fmtDate(h.created_at)}</td>
                  <td className={tdCls}>{h.actor_name || '—'}</td>
                  <td className={tdCls}>{actionLabel(h.action)}</td>
                  <td className={tdCls}>{h.target_name || '—'}</td>
                  <td className={`${tdCls} text-[11px] text-[var(--text-secondary)]`}>{historyDetail(h, partLabel, tr)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

function historyDetail(h: HistoryRow, partLabel: (p: string) => string, tr: (k: string, fb: string) => string): string {
  const m = (h.metadata || {}) as Record<string, any>;
  const bits: string[] = [];
  if (m.opportunity_id) bits.push(String(m.opportunity_id));
  if (m.part) bits.push(partLabel(String(m.part)));
  if (m.material_version) bits.push(String(m.material_version));
  if (h.action === 'selection_rubric.saved' && m.version != null) bits.push(`v${m.version}`);
  if (Array.isArray(m.application_ids)) bits.push(tr('detailApplications', '{n} candidatura(s)').replace('{n}', String(m.application_ids.length)));
  if (m.end_date_before) bits.push(`${fmtDate(String(m.end_date_before))} → ${fmtDate(String(m.end_date))}`);
  else if (m.end_date) bits.push(`→ ${fmtDate(String(m.end_date))}`);
  if (m.assignments_withdrawn != null) bits.push(tr('detailWithdrawn', '{n} atribuição(ões) retirada(s)').replace('{n}', String(m.assignments_withdrawn)));
  if (m.reason) bits.push(String(m.reason));
  if (m.note) bits.push(String(m.note));
  return bits.join(' · ') || '—';
}
