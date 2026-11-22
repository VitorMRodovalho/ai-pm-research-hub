// src/components/admin/AffiliationNudgePanel.tsx
// #3110 — aviso de filiação pendente (entry_chapter_action_needed): visibilidade, auditoria e controle pelo front.
// Regra do GP (20/11/2026): toda automação mostra o que vai fazer, o que fez e quem a ligou ou pausou.
//
// Lê get_affiliation_nudge_panel (audiência da fila: filiacao_director ou manage_member) e escreve por
// set_affiliation_nudge_enabled: pausar é da audiência da fila; ligar exige manage_platform (o servidor decide; a tela
// só esconde o botão de quem não pode). O aviso nasce desligado.
import { useState, useEffect, useCallback } from 'react';
import { Loader2, BellRing, PauseCircle, PlayCircle } from 'lucide-react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { useResolvedMember } from '../../hooks/useResolvedMember';

type Variant = 'ambiguous' | 'not_affiliated' | 'profile_private' | 'no_fetch';

interface PreviewRow { member_id: string; name: string; variant: Variant | null; blocked_by_dedupe: boolean }
interface HistoryRow {
  member_id: string; name: string | null; created_at: string; variant: Variant | null;
  email_delivery_status: string | null; email_sent_at: string | null;
}
interface ChangeRow { at: string; by: string | null; enabled: boolean; reason: string | null }
interface Panel {
  enabled: boolean;
  setting: { changed_at: string | null; changed_by: string | null; reason: string | null } | null;
  can_enable: boolean;
  schedule: { schedule: string; active: boolean } | null;
  preview: PreviewRow[];
  history: HistoryRow[];
  changes: ChangeRow[];
}

function fmt(raw: string | null | undefined): string {
  if (!raw) return '—';
  const d = new Date(raw);
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString('pt-BR');
}

export default function AffiliationNudgePanel() {
  const t = usePageI18n();
  const getSb = useCallback(() => (window as any).navGetSb?.(), []);
  // #2974: a primeira chamada espera o membro resolvido pelo Nav, sem laço próprio
  const { memberId } = useResolvedMember();
  const [panel, setPanel] = useState<Panel | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [reason, setReason] = useState('');

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    const { data, error: e } = await sb.rpc('get_affiliation_nudge_panel');
    if (e) { setError(e.message); return; }
    setError(null);
    setPanel(data as Panel);
  }, [getSb]);

  useEffect(() => { if (memberId) load(); }, [memberId, load]);

  const toggle = async (enable: boolean) => {
    const sb = getSb(); if (!sb) return;
    if (!reason.trim()) {
      (window as any).toast?.(t('comp.affiliationNudge.reasonRequired', 'Escreva o motivo.'), 'error');
      return;
    }
    setSaving(true);
    const { error: e } = await sb.rpc('set_affiliation_nudge_enabled', { p_enabled: enable, p_reason: reason.trim() });
    setSaving(false);
    if (e) { (window as any).toast?.(e.message, 'error'); return; }
    setReason('');
    (window as any).toast?.(enable ? t('comp.affiliationNudge.enabledDone', 'Aviso ligado') : t('comp.affiliationNudge.pausedDone', 'Aviso pausado'), 'success');
    await load();
  };

  const variantLabel = (v: Variant | null) =>
    v ? t(`comp.affiliationNudge.variant_${v}`, v) : t('comp.affiliationNudge.variant_internal', 'só na fila');

  // falha visível: quem está na audiência e não vê o painel precisa saber por quê
  if (error) return (
    <div data-testid="an-error" className="mt-8 text-[13px] text-rose-700">
      {t('comp.affiliationNudge.loadError', 'Não foi possível carregar o aviso de filiação pendente.')} ({error})
    </div>
  );
  if (!panel) return <div className="py-6 text-center"><Loader2 className="inline animate-spin" size={16} /></div>;

  const toSend = panel.preview.filter((p) => p.variant && !p.blocked_by_dedupe).length;

  return (
    <section data-testid="affiliation-nudge-panel" className="mt-8 rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5">
      <div className="flex items-center gap-2 flex-wrap">
        <BellRing size={16} className="text-[var(--text-secondary)]" />
        <h2 className="text-base font-bold text-[var(--text-primary)] m-0">{t('comp.affiliationNudge.title', 'Aviso de filiação pendente')}</h2>
        <span data-testid="an-state" className={`text-[11px] px-2 py-0.5 rounded-full font-semibold ${panel.enabled ? 'bg-teal-50 text-teal-700' : 'bg-slate-100 text-slate-600'}`}>
          {panel.enabled ? t('comp.affiliationNudge.stateOn', 'ligado') : t('comp.affiliationNudge.stateOff', 'desligado')}
        </span>
      </div>
      <p className="text-[13px] text-[var(--text-secondary)] mt-2">{t('comp.affiliationNudge.intro', '')}</p>
      <p className="text-[12px] text-[var(--text-muted)]">
        {panel.schedule
          ? `${t('comp.affiliationNudge.schedule', 'Roda todo dia às 09:30 (Brasília).')} (cron ${panel.schedule.schedule} UTC${panel.schedule.active ? '' : ', inativo'})`
          : t('comp.affiliationNudge.noSchedule', 'Sem agendamento.')}
        {panel.setting?.changed_at && (
          <> · {t('comp.affiliationNudge.lastChange', 'última mudança')}: {fmt(panel.setting.changed_at)}
            {panel.setting.changed_by ? ` · ${panel.setting.changed_by}` : ''}{panel.setting.reason ? ` · ${panel.setting.reason}` : ''}</>
        )}
      </p>

      {/* controle: pausar é da audiência da fila; ligar só aparece para quem pode (manage_platform) */}
      <div className="flex gap-2 items-center flex-wrap mt-3">
        <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={300}
          placeholder={t('comp.affiliationNudge.reasonPlaceholder', 'Motivo (obrigatório)')}
          className="flex-1 min-w-[220px] px-3 py-1.5 rounded-lg border border-[var(--border-default)] text-sm bg-[var(--surface-card)] text-[var(--text-primary)]" />
        {panel.enabled && (
          <button data-testid="an-pause" onClick={() => toggle(false)} disabled={saving}
            className="inline-flex items-center gap-1 px-3 py-1.5 text-[13px] bg-amber-500 text-white rounded-lg border-0 cursor-pointer hover:bg-amber-600 disabled:opacity-50">
            <PauseCircle size={14} /> {t('comp.affiliationNudge.pause', 'Pausar')}
          </button>
        )}
        {!panel.enabled && panel.can_enable && (
          <button data-testid="an-enable" onClick={() => toggle(true)} disabled={saving}
            className="inline-flex items-center gap-1 px-3 py-1.5 text-[13px] bg-teal-600 text-white rounded-lg border-0 cursor-pointer hover:bg-teal-700 disabled:opacity-50">
            <PlayCircle size={14} /> {t('comp.affiliationNudge.enable', 'Ligar')} ({toSend})
          </button>
        )}
        {!panel.enabled && !panel.can_enable && (
          <span className="text-[12px] text-[var(--text-muted)]">{t('comp.affiliationNudge.enableByGp', 'Só a gestão da plataforma liga o aviso.')}</span>
        )}
      </div>

      {/* prévia: quem receberia se o aviso rodasse agora */}
      <h3 className="text-sm font-semibold text-[var(--text-primary)] mt-5 mb-2">
        {t('comp.affiliationNudge.previewTitle', 'Quem receberia agora')} ({toSend})
      </h3>
      <table data-testid="an-preview" className="w-full text-[13px]">
        <tbody>
          {panel.preview.map((p) => (
            <tr key={p.member_id} className="border-t border-[var(--border-default)]">
              <td className="py-1.5 text-[var(--text-primary)]">{p.name}</td>
              <td className="py-1.5 text-[var(--text-secondary)]">{variantLabel(p.variant)}</td>
              <td className="py-1.5 text-[var(--text-muted)]">{p.blocked_by_dedupe ? t('comp.affiliationNudge.dedupe', 'já avisado nos últimos 30 dias') : ''}</td>
            </tr>
          ))}
          {panel.preview.length === 0 && (
            <tr><td className="py-2 text-[var(--text-muted)]">{t('comp.affiliationNudge.previewEmpty', 'Ninguém.')}</td></tr>
          )}
        </tbody>
      </table>

      {/* histórico: quem recebeu, quando, qual aviso e o estado do e-mail */}
      <h3 className="text-sm font-semibold text-[var(--text-primary)] mt-5 mb-2">{t('comp.affiliationNudge.historyTitle', 'Enviados (180 dias)')}</h3>
      <table data-testid="an-history" className="w-full text-[13px]">
        <tbody>
          {panel.history.map((h, i) => (
            <tr key={`${h.member_id}-${i}`} className="border-t border-[var(--border-default)]">
              <td className="py-1.5 text-[var(--text-primary)]">{h.name ?? '—'}</td>
              <td className="py-1.5 text-[var(--text-secondary)]">{fmt(h.created_at)}</td>
              <td className="py-1.5 text-[var(--text-secondary)]">{h.variant ? variantLabel(h.variant) : '—'}</td>
              <td className="py-1.5 text-[var(--text-muted)]">{h.email_delivery_status ?? (h.email_sent_at ? fmt(h.email_sent_at) : '—')}</td>
            </tr>
          ))}
          {panel.history.length === 0 && (
            <tr><td className="py-2 text-[var(--text-muted)]">{t('comp.affiliationNudge.historyEmpty', 'Nenhum envio.')}</td></tr>
          )}
        </tbody>
      </table>

      {/* auditoria: quem ligou ou pausou */}
      <h3 className="text-sm font-semibold text-[var(--text-primary)] mt-5 mb-2">{t('comp.affiliationNudge.changesTitle', 'Quem ligou ou pausou')}</h3>
      <ul data-testid="an-changes" className="text-[13px] text-[var(--text-secondary)] list-none p-0 m-0">
        {panel.changes.map((c, i) => (
          <li key={i} className="py-1 border-t border-[var(--border-default)]">
            {fmt(c.at)} · {c.by ?? '—'} · {c.enabled ? t('comp.affiliationNudge.stateOn', 'ligado') : t('comp.affiliationNudge.stateOff', 'desligado')}{c.reason ? ` · ${c.reason}` : ''}
          </li>
        ))}
        {panel.changes.length === 0 && <li className="py-1 text-[var(--text-muted)]">{t('comp.affiliationNudge.changesEmpty', 'Nenhuma mudança desde a criação (nasce desligado).')}</li>}
      </ul>
    </section>
  );
}
