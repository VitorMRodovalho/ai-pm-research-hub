import { useEffect, useState, useCallback } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

/**
 * D1 — "Ação hoje" do GP (Wave 2, Épico D re-escopado).
 *
 * Agregação UI sobre `get_selection_dashboard` (RPC já existente, gate
 * view_internal_analytics) — ZERO DB. Tira da invisibilidade os candidatos
 * que envelhecem em silêncio no funil de seleção, nomeando cada pessoa:
 *
 *  - sem convite (in-band/below-target): interview_pending sem cutoff_approved_email_sent_at.
 *    Política PM (2026-06-16): decisão MANUAL do GP — o cron só despacha strict-above-target.
 *  - convite enviado, sem agendamento: interview_pending + email enviado + sem entrevista marcada.
 *  - entrevista vencida: meta.interview_stuck (scheduled no passado, não conduzida).
 *  - no-show: status interview_noshow.
 *  - oferta VEP não aceita (D7): vep_recon.status_raw = 'OfferExtended' (aprovado por nós,
 *    mas sem o ACEITE da vaga no VEP → não vira member).
 *
 * Auto-esconde quando o RPC nega (não-GP) ou quando não há nada a fazer.
 */

interface AppRow {
  id: string;
  applicant_name?: string;
  status?: string;
  cutoff_approved_email_sent_at?: string | null;
  meta?: { interview_scheduled?: boolean; interview_stuck?: boolean };
  vep_recon?: { status_raw?: string | null };
}

interface Bucket {
  key: string;
  emoji: string;
  labelKey: string;
  labelFallback: string;
  hintKey: string;
  hintFallback: string;
  tone: string;
  rows: AppRow[];
}

function localePrefix(): string {
  if (typeof window === 'undefined') return '';
  if (location.pathname.startsWith('/en')) return '/en';
  if (location.pathname.startsWith('/es')) return '/es';
  return '';
}

export default function GpActionTodayWidget() {
  const t = usePageI18n();
  const [apps, setApps] = useState<AppRow[] | null>(null);
  const [denied, setDenied] = useState(false);

  const load = useCallback(async () => {
    const sb = (window as any).navGetSb?.();
    if (!sb) { setTimeout(load, 400); return; }
    try {
      const { data, error } = await sb.rpc('get_selection_dashboard');
      if (error) { setDenied(true); return; }
      // Only a genuine auth denial hides the widget. 'No cycle found' (or any
      // other non-auth error) falls through to an empty list, which self-hides
      // via the active.length===0 guard below — without conflating the two.
      if (!data || data.error === 'Unauthorized') { setDenied(true); return; }
      setApps(Array.isArray(data.applications) ? data.applications : []);
    } catch {
      setDenied(true);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  if (denied || !apps) return null;

  const buckets: Bucket[] = [
    {
      key: 'noInvite', emoji: '📨',
      labelKey: 'comp.adminDash.actionToday.noInvite', labelFallback: 'Aguardando decisão de convite',
      hintKey: 'comp.adminDash.actionToday.noInviteHint',
      hintFallback: 'In-band/abaixo da linha — o convite automático não cobre. Decida manualmente.',
      tone: 'bg-amber-50 text-amber-800 dark:bg-amber-950/30 dark:text-amber-200',
      rows: apps.filter((a) => a.status === 'interview_pending' && !a.cutoff_approved_email_sent_at),
    },
    {
      key: 'invitedNotScheduled', emoji: '⏳',
      labelKey: 'comp.adminDash.actionToday.invitedNotScheduled', labelFallback: 'Convite enviado, sem agendamento',
      hintKey: 'comp.adminDash.actionToday.invitedNotScheduledHint',
      hintFallback: 'Receberam o convite mas não marcaram a entrevista. Cobre ou reenvie.',
      tone: 'bg-blue-50 text-blue-800 dark:bg-blue-950/30 dark:text-blue-200',
      rows: apps.filter((a) => a.status === 'interview_pending' && !!a.cutoff_approved_email_sent_at && !a.meta?.interview_scheduled),
    },
    {
      key: 'interviewStuck', emoji: '🔁',
      labelKey: 'comp.adminDash.actionToday.interviewStuck', labelFallback: 'Entrevista vencida — reagendar',
      hintKey: 'comp.adminDash.actionToday.interviewStuckHint',
      hintFallback: 'Horário marcado já passou sem condução. Reagende ou marque no-show.',
      tone: 'bg-orange-50 text-orange-800 dark:bg-orange-950/30 dark:text-orange-200',
      rows: apps.filter((a) => a.meta?.interview_stuck === true),
    },
    {
      key: 'noShow', emoji: '🚫',
      labelKey: 'comp.adminDash.actionToday.noShow', labelFallback: 'No-show — recuperar',
      hintKey: 'comp.adminDash.actionToday.noShowHint',
      hintFallback: 'Não compareceram. Reabra a janela de agendamento ou encerre.',
      tone: 'bg-red-50 text-red-800 dark:bg-red-950/30 dark:text-red-200',
      rows: apps.filter((a) => a.status === 'interview_noshow'),
    },
    {
      key: 'offerNotAccepted', emoji: '✋',
      labelKey: 'comp.adminDash.actionToday.offerNotAccepted', labelFallback: 'Oferta VEP não aceita',
      hintKey: 'comp.adminDash.actionToday.offerNotAcceptedHint',
      hintFallback: 'Aprovados, mas sem o ACEITE da vaga no VEP — não viram members até aceitar.',
      tone: 'bg-purple-50 text-purple-800 dark:bg-purple-950/30 dark:text-purple-200',
      // Guard on approved/converted (the normal flow for an extended VEP offer):
      // avoids double-counting a stale OfferExtended on an app still in the funnel.
      rows: apps.filter((a) => a.vep_recon?.status_raw === 'OfferExtended' && (a.status === 'approved' || a.status === 'converted')),
    },
  ];

  const active = buckets.filter((b) => b.rows.length > 0);
  if (active.length === 0) return null;

  const names = (rows: AppRow[]): string => {
    const ns = rows.map((r) => r.applicant_name).filter(Boolean) as string[];
    const head = ns.slice(0, 4).join(', ');
    const extra = ns.length - 4;
    if (extra > 0) {
      return head + ' · ' + t('comp.adminDash.actionToday.more', '+{n} mais').replace('{n}', String(extra));
    }
    return head;
  };

  const href = localePrefix() + '/admin/selection';

  return (
    <div className="rounded-2xl border border-[var(--border-default)] bg-[var(--surface-card)] p-5 shadow-sm">
      <div className="flex items-center gap-2 mb-1">
        <span className="text-lg">🎯</span>
        <h3 className="text-sm font-extrabold text-navy">
          {t('comp.adminDash.actionToday.title', 'Ação hoje — Processo seletivo')}
        </h3>
      </div>
      <p className="text-xs text-[var(--text-secondary)] mb-4">
        {t('comp.adminDash.actionToday.subtitle', 'Candidatos que precisam de uma ação sua para não ficarem parados.')}
      </p>

      <div className="space-y-2">
        {active.map((b) => (
          <div key={b.key} className={`rounded-xl px-3 py-2 ${b.tone}`}>
            <div className="flex items-center gap-2">
              <span>{b.emoji}</span>
              <span className="text-[13px] font-bold flex-1">{t(b.labelKey, b.labelFallback)}</span>
              <span className="text-xs font-extrabold rounded-full bg-white/70 dark:bg-black/30 px-2 py-0.5">{b.rows.length}</span>
            </div>
            <p className="text-[11px] opacity-80 mt-1">{t(b.hintKey, b.hintFallback)}</p>
            <p className="text-[11px] font-semibold mt-1">{names(b.rows)}</p>
          </div>
        ))}
      </div>

      <div className="mt-4 text-right">
        <a href={href} className="inline-flex items-center gap-1 text-xs font-bold text-navy hover:underline">
          {t('comp.adminDash.actionToday.openSelection', 'Abrir processo seletivo')} →
        </a>
      </div>
    </div>
  );
}
