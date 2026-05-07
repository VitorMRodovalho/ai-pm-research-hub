import { useState, useEffect, useCallback, useMemo } from 'react';
import { Loader2, RefreshCw, Bot, TrendingUp, TrendingDown, Minus, PlayCircle, X, ThumbsUp, ThumbsDown, Edit3 } from 'lucide-react';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, ReferenceLine,
} from 'recharts';
import { usePageI18n } from '../../i18n/usePageI18n';

interface ValidatorRow {
  validator_id: string;
  name: string | null;
  validations_n: number;
  agreement_rate: number;
  bias_signal: number | null;
  override_n: number;
}

interface PurposeBreakdown {
  total: number;
  agree_n: number;
  disagree_n: number;
  override_n: number;
  mean_override_delta: number | null;
}

interface ValidatorBreakdown {
  global: {
    total_validations: number;
    agree_n: number;
    disagree_n: number;
    override_n: number;
    mean_override_delta: number | null;
    window_start: string;
    window_end: string;
  };
  by_validator: ValidatorRow[];
  by_purpose: Record<string, PurposeBreakdown>;
}

interface ValidationDetail {
  id: string;
  application_id: string;
  applicant_name: string;
  cycle_code: string | null;
  application_status: string | null;
  ai_purpose: string;
  ai_model: string | null;
  ai_score: number | null;
  ai_verdict: string | null;
  validation_action: 'agree' | 'disagree' | 'override' | string;
  override_score: number | null;
  comment: string | null;
  validated_at: string;
}

interface ValidationDetailsResponse {
  validator_id: string;
  validator_name: string | null;
  validations: ValidationDetail[];
  count: number;
  cycle_filter: string | null;
  limit: number;
  error?: string;
}

interface OutlierRow {
  application_id: string;
  applicant_name: string;
  ai_score: number;
  human_score_normalized: number;
  delta_signed: number;
}

interface CalibrationRun {
  id: string;
  cycle_id: string;
  cycle_code: string | null;
  ran_at: string;
  n_compared: number;
  mean_delta_signed: number | null;
  mean_delta_abs: number | null;
  drift_count_high: number;
  drift_threshold: number;
  triggered_by: string;
  sample_payload: OutlierRow[] | null;
  validator_breakdown: ValidatorBreakdown | null;
}

interface ListResponse {
  runs: CalibrationRun[];
  count: number;
  cycle_filter: string | null;
  limit: number;
}

const DASH = '—';

function fmtDateTime(s: string | null | undefined, lang: string): string {
  if (!s) return DASH;
  const d = new Date(s);
  return d.toLocaleDateString(lang === 'pt-BR' ? 'pt-BR' : lang === 'es-LATAM' ? 'es-ES' : 'en-US', {
    day: '2-digit', month: 'short', year: 'numeric'
  }) + ' ' + d.toLocaleTimeString(lang === 'pt-BR' ? 'pt-BR' : lang === 'es-LATAM' ? 'es-ES' : 'en-US', {
    hour: '2-digit', minute: '2-digit'
  });
}

function fmtNum(n: number | null | undefined, decimals = 2): string {
  if (n === null || n === undefined || Number.isNaN(n)) return DASH;
  return Number(n).toFixed(decimals);
}

function fmtPct(n: number | null | undefined): string {
  if (n === null || n === undefined || Number.isNaN(n)) return DASH;
  return (Number(n) * 100).toFixed(0) + '%';
}

function agreementColor(rate: number): string {
  if (rate >= 0.7) return 'text-emerald-600 bg-emerald-50 dark:bg-emerald-950';
  if (rate >= 0.4) return 'text-amber-600 bg-amber-50 dark:bg-amber-950';
  return 'text-rose-600 bg-rose-50 dark:bg-rose-950';
}

function biasIcon(bias: number | null): JSX.Element {
  if (bias === null || bias === undefined) return <Minus className="h-4 w-4 text-[var(--text-muted)]" aria-hidden />;
  if (bias > 0.5) return <TrendingUp className="h-4 w-4 text-emerald-600" aria-hidden />;
  if (bias < -0.5) return <TrendingDown className="h-4 w-4 text-rose-600" aria-hidden />;
  return <Minus className="h-4 w-4 text-[var(--text-muted)]" aria-hidden />;
}

export default function AiCalibrationIsland() {
  const t = usePageI18n();
  const [data, setData] = useState<ListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [cycleFilter, setCycleFilter] = useState<string>('');
  const [triggering, setTriggering] = useState(false);
  const [triggerToast, setTriggerToast] = useState<string | null>(null);
  const [drillValidator, setDrillValidator] = useState<{ id: string; name: string | null } | null>(null);
  const [drillDetails, setDrillDetails] = useState<ValidationDetailsResponse | null>(null);
  const [drillLoading, setDrillLoading] = useState(false);
  const [drillError, setDrillError] = useState<string | null>(null);

  const lang = useMemo(() => {
    if (typeof window === 'undefined') return 'pt-BR';
    const params = new URLSearchParams(window.location.search);
    return params.get('lang') || 'pt-BR';
  }, []);

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const fetchData = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    setLoading(true);
    setError(null);
    const { data, error } = await sb.rpc('list_ai_calibration_runs', {
      p_cycle_id: cycleFilter || null,
      p_limit: 50,
    });
    if (error) {
      setError(error.message);
      setData(null);
    } else if (data?.error) {
      setError(data.error);
      setData(null);
    } else {
      setData(data as ListResponse);
    }
    setLoading(false);
  }, [cycleFilter, getSb]);

  useEffect(() => {
    const boot = () => {
      if (getSb()) fetchData();
      else setTimeout(boot, 300);
    };
    boot();
  }, [fetchData, getSb]);

  const handleTriggerRun = useCallback(async () => {
    const sb = getSb();
    if (!sb || triggering) return;
    setTriggering(true);
    setError(null);
    setTriggerToast(null);
    const { data: result, error: rpcErr } = await sb.rpc('trigger_ai_calibration_run');
    if (rpcErr) {
      setError(rpcErr.message);
    } else if (result?.error) {
      setError(result.error);
    } else {
      const cycles = result?.cycles_processed ?? 0;
      setTriggerToast(
        t('comp.aiCalibration.triggerSuccess', `Calibração executada — ${cycles} ciclo(s) processado(s).`).replace('{cycles}', String(cycles))
      );
      await fetchData();
      setTimeout(() => setTriggerToast(null), 5000);
    }
    setTriggering(false);
  }, [getSb, fetchData, triggering, t]);

  const openDrill = useCallback(async (validatorId: string, validatorName: string | null) => {
    const sb = getSb();
    if (!sb) return;
    setDrillValidator({ id: validatorId, name: validatorName });
    setDrillLoading(true);
    setDrillError(null);
    setDrillDetails(null);
    const { data: result, error: rpcErr } = await sb.rpc('list_validations_by_validator', {
      p_validator_id: validatorId,
      p_limit: 100,
      p_cycle_id: cycleFilter || null,
    });
    if (rpcErr) {
      setDrillError(rpcErr.message);
    } else if (result?.error) {
      setDrillError(result.error);
    } else {
      setDrillDetails(result as ValidationDetailsResponse);
    }
    setDrillLoading(false);
  }, [getSb, cycleFilter]);

  const closeDrill = useCallback(() => {
    setDrillValidator(null);
    setDrillDetails(null);
    setDrillError(null);
  }, []);

  useEffect(() => {
    if (!drillValidator) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeDrill();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [drillValidator, closeDrill]);

  const cycleOptions = useMemo(() => {
    if (!data?.runs) return [] as Array<{ id: string; code: string }>;
    const seen = new Map<string, string>();
    for (const r of data.runs) {
      if (r.cycle_id && r.cycle_code && !seen.has(r.cycle_id)) {
        seen.set(r.cycle_id, r.cycle_code);
      }
    }
    return Array.from(seen.entries()).map(([id, code]) => ({ id, code }));
  }, [data]);

  const latest = data?.runs?.[0] ?? null;
  const breakdown = latest?.validator_breakdown ?? null;
  const outliers = (latest?.sample_payload ?? []) as OutlierRow[];
  const purposes = breakdown?.by_purpose ? Object.entries(breakdown.by_purpose) : [];

  const driftSeries = useMemo(() => {
    if (!data?.runs || data.runs.length < 2) return [];
    const langTag = lang === 'pt-BR' ? 'pt-BR' : lang === 'es-LATAM' ? 'es-ES' : 'en-US';
    return [...data.runs]
      .reverse()
      .map((r, idx) => ({
        idx,
        ran_at: r.ran_at,
        label: new Date(r.ran_at).toLocaleString(langTag, {
          day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
        }),
        mean_delta_abs: r.mean_delta_abs ?? null,
        mean_delta_signed: r.mean_delta_signed ?? null,
        n_compared: r.n_compared,
        drift_count_high: r.drift_count_high,
        triggered_by: r.triggered_by,
      }));
  }, [data, lang]);

  const driftThreshold = latest?.drift_threshold ?? 2;

  const cardClass = 'bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl p-5';
  const tileClass = 'flex flex-col gap-1';
  const tileLabel = 'text-xs uppercase tracking-wide text-[var(--text-muted)]';
  const tileValue = 'text-2xl font-bold text-[var(--text-primary)]';
  const sectionTitle = 'text-lg font-bold text-[var(--text-primary)] mb-3 flex items-center gap-2';

  if (loading) {
    return (
      <div className="max-w-[1100px] mx-auto py-12 flex items-center justify-center text-[var(--text-muted)]">
        <Loader2 className="h-5 w-5 animate-spin mr-2" />
        {t('comp.aiCalibration.loading', 'Carregando...')}
      </div>
    );
  }

  if (error) {
    return (
      <div className="max-w-[1100px] mx-auto py-12 text-center text-rose-600">
        {error.includes('view_internal_analytics')
          ? t('comp.aiCalibration.unauthorized', 'Acesso restrito.')
          : error}
      </div>
    );
  }

  if (!data || data.count === 0 || !latest) {
    return (
      <div className="max-w-[1100px] mx-auto py-12 text-center text-[var(--text-muted)]">
        {t('comp.aiCalibration.empty', 'Sem dados.')}
      </div>
    );
  }

  return (
    <div className="max-w-[1100px] mx-auto">
      <header className="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-[var(--text-primary)] flex items-center gap-2">
            <Bot className="h-6 w-6 text-[var(--accent-primary)]" aria-hidden />
            {t('comp.aiCalibration.title', 'Calibração de IA')}
          </h1>
          <p className="text-sm text-[var(--text-muted)] mt-1">
            {t('comp.aiCalibration.subtitle', 'Drift entre Sonnet 4.6 (triagem IA) e avaliadores humanos. Última rodada do cron + breakdown por validador.')}
          </p>
        </div>
        <div className="flex flex-wrap gap-2 items-center">
          <label htmlFor="cycle-filter" className="sr-only">
            {t('comp.aiCalibration.cycleFilter', 'Filtrar por ciclo')}
          </label>
          <select
            id="cycle-filter"
            value={cycleFilter}
            onChange={(e) => setCycleFilter(e.target.value)}
            className="px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-card)] text-sm text-[var(--text-primary)]"
          >
            <option value="">{t('comp.aiCalibration.allCycles', 'Todos')}</option>
            {cycleOptions.map((c) => (
              <option key={c.id} value={c.id}>{c.code}</option>
            ))}
          </select>
          <button
            type="button"
            onClick={handleTriggerRun}
            disabled={triggering}
            title={t('comp.aiCalibration.triggerHint', 'Roda agora a calibração e gera nova rodada com as validações desde o último cron.')}
            className="px-3 py-2 rounded-lg border border-[var(--accent-primary)] text-[var(--accent-primary)] text-sm font-medium hover:bg-[var(--accent-primary)] hover:text-white disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1.5"
          >
            {triggering
              ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden />
              : <PlayCircle className="h-4 w-4" aria-hidden />}
            {triggering
              ? t('comp.aiCalibration.triggerRunning', 'Rodando...')
              : t('comp.aiCalibration.triggerRun', 'Rodar agora')}
          </button>
          <button
            type="button"
            onClick={fetchData}
            className="px-3 py-2 rounded-lg bg-[var(--accent-primary)] text-white text-sm font-medium hover:opacity-90 flex items-center gap-1.5"
          >
            <RefreshCw className="h-4 w-4" aria-hidden />
            {t('comp.aiCalibration.refresh', 'Atualizar')}
          </button>
        </div>
      </header>

      {triggerToast && (
        <div
          role="status"
          aria-live="polite"
          className="mb-4 px-4 py-3 rounded-lg bg-emerald-50 dark:bg-emerald-950 border border-emerald-200 dark:border-emerald-800 text-emerald-800 dark:text-emerald-200 text-sm"
        >
          {triggerToast}
        </div>
      )}

      {/* Latest Run card */}
      <section className={cardClass + ' mb-6'} aria-labelledby="latest-run-heading">
        <h2 id="latest-run-heading" className={sectionTitle}>
          {t('comp.aiCalibration.latestRun', 'Última Rodada')}
        </h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
          <div className={tileClass}>
            <span className={tileLabel}>{t('comp.aiCalibration.nCompared', 'Pares')}</span>
            <span className={tileValue}>{latest.n_compared}</span>
          </div>
          <div className={tileClass}>
            <span className={tileLabel}>{t('comp.aiCalibration.meanDeltaSigned', 'Δ signed')}</span>
            <span className={tileValue}>{fmtNum(latest.mean_delta_signed, 3)}</span>
          </div>
          <div className={tileClass}>
            <span className={tileLabel}>{t('comp.aiCalibration.meanDeltaAbs', 'Δ abs')}</span>
            <span className={tileValue}>{fmtNum(latest.mean_delta_abs, 3)}</span>
          </div>
          <div className={tileClass}>
            <span className={tileLabel}>{t('comp.aiCalibration.driftCountHigh', 'Drift alto')}</span>
            <span className={tileValue}>{latest.drift_count_high}</span>
          </div>
        </div>
        <div className="text-xs text-[var(--text-muted)] flex flex-wrap gap-x-4 gap-y-1 pt-3 border-t border-[var(--border-default)]">
          <span>
            <strong>{t('comp.aiCalibration.ranAt', 'Executada')}:</strong> {fmtDateTime(latest.ran_at, lang)}
          </span>
          <span>
            <strong>{t('comp.aiCalibration.triggeredBy', 'Trigger')}:</strong>{' '}
            {latest.triggered_by === 'cron'
              ? t('comp.aiCalibration.triggeredCron', 'cron')
              : t('comp.aiCalibration.triggeredAdmin', 'admin')}
          </span>
          <span>
            <strong>{t('comp.aiCalibration.driftThreshold', 'Threshold')}:</strong> {fmtNum(latest.drift_threshold, 1)}
          </span>
          {latest.cycle_code && (
            <span><strong>{t('comp.aiCalibration.colCycle', 'Ciclo')}:</strong> {latest.cycle_code}</span>
          )}
        </div>
        <p className="text-xs text-[var(--text-muted)] mt-2 italic">
          {t('comp.aiCalibration.deltaTooltip', 'Diferença humano - IA. Positivo = humano deu score maior; negativo = IA superestimou.')}
        </p>
      </section>

      {/* Validator breakdown */}
      <section className={cardClass + ' mb-6'} aria-labelledby="breakdown-heading">
        <h2 id="breakdown-heading" className={sectionTitle}>
          {t('comp.aiCalibration.validatorBreakdown', 'Breakdown')}
          <span className="text-xs font-normal text-[var(--text-muted)] ml-2">
            ({t('comp.aiCalibration.windowLabel', 'janela 4 semanas')})
          </span>
        </h2>

        {!breakdown || breakdown.global.total_validations === 0 ? (
          <p className="text-sm text-[var(--text-muted)] py-2">
            {t('comp.aiCalibration.validatorEmpty', 'Sem validações registradas no período (janela 4 semanas). Use 👍/👎/Override na tela de avaliação para gerar dados.')}
          </p>
        ) : (
          <>
            {/* Global tiles */}
            <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-5">
              <div className={tileClass}>
                <span className={tileLabel}>{t('comp.aiCalibration.totalValidations', 'Total')}</span>
                <span className={tileValue}>{breakdown.global.total_validations}</span>
              </div>
              <div className={tileClass}>
                <span className={tileLabel}>{t('comp.aiCalibration.agreeN', 'Concordâncias')}</span>
                <span className={tileValue + ' text-emerald-600'}>{breakdown.global.agree_n}</span>
              </div>
              <div className={tileClass}>
                <span className={tileLabel}>{t('comp.aiCalibration.disagreeN', 'Discordâncias')}</span>
                <span className={tileValue + ' text-amber-600'}>{breakdown.global.disagree_n}</span>
              </div>
              <div className={tileClass}>
                <span className={tileLabel}>{t('comp.aiCalibration.overrideN', 'Overrides')}</span>
                <span className={tileValue + ' text-rose-600'}>{breakdown.global.override_n}</span>
              </div>
              <div className={tileClass}>
                <span className={tileLabel}>{t('comp.aiCalibration.meanOverrideDelta', 'Δ override')}</span>
                <span className={tileValue}>{fmtNum(breakdown.global.mean_override_delta, 2)}</span>
              </div>
            </div>

            {/* By validator table */}
            {breakdown.by_validator.length > 0 && (
              <div className="mb-5">
                <h3 className="text-sm font-semibold text-[var(--text-primary)] mb-2">
                  {t('comp.aiCalibration.byValidator', 'Por Validador')}
                </h3>
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-left border-b border-[var(--border-default)]">
                        <th className="py-2 pr-3 font-medium text-[var(--text-muted)]">{t('comp.aiCalibration.colName', 'Validador')}</th>
                        <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.colValidations', 'Validações')}</th>
                        <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.colAgreement', 'Taxa')}</th>
                        <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.colBiasSignal', 'Bias')}</th>
                        <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.colOverrides', 'Overrides')}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {breakdown.by_validator.map((v) => (
                        <tr
                          key={v.validator_id}
                          onClick={() => openDrill(v.validator_id, v.name)}
                          onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openDrill(v.validator_id, v.name); } }}
                          tabIndex={0}
                          role="button"
                          aria-label={t('comp.aiCalibration.drillOpenAria', `Ver validações de ${v.name || ''}`).replace('{name}', v.name || '')}
                          className="border-b border-[var(--border-default)] last:border-b-0 cursor-pointer hover:bg-[var(--surface-elevated)] focus:outline-none focus:ring-2 focus:ring-[var(--accent-primary)] focus:ring-inset"
                        >
                          <td className="py-2 pr-3 text-[var(--accent-primary)] font-medium underline-offset-2 hover:underline">{v.name || DASH}</td>
                          <td className="py-2 pr-3 text-right">{v.validations_n}</td>
                          <td className="py-2 pr-3 text-right">
                            <span className={`inline-block px-2 py-0.5 rounded text-xs font-semibold ${agreementColor(v.agreement_rate)}`}>
                              {fmtPct(v.agreement_rate)}
                            </span>
                          </td>
                          <td className="py-2 pr-3 text-right">
                            <span className="inline-flex items-center gap-1 justify-end">
                              {biasIcon(v.bias_signal)}
                              {fmtNum(v.bias_signal, 2)}
                            </span>
                          </td>
                          <td className="py-2 pr-3 text-right">{v.override_n}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {/* By purpose */}
            {purposes.length > 0 && (
              <div>
                <h3 className="text-sm font-semibold text-[var(--text-primary)] mb-2">
                  {t('comp.aiCalibration.byPurpose', 'Por Propósito')}
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  {purposes.map(([key, p]) => (
                    <div key={key} className="border border-[var(--border-default)] rounded-lg p-3 bg-[var(--surface-elevated)]">
                      <div className="text-sm font-semibold mb-2">
                        {key === 'sonnet_triage'
                          ? t('comp.aiCalibration.purposeSonnet', 'Sonnet Triage')
                          : key === 'gemini_eleva_bar'
                            ? t('comp.aiCalibration.purposeGemini', 'Gemini')
                            : key}
                      </div>
                      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                        <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.totalValidations', 'Total')}</dt>
                        <dd className="text-right text-[var(--text-primary)] font-semibold">{p.total}</dd>
                        <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.agreeN', 'Concord.')}</dt>
                        <dd className="text-right text-emerald-600">{p.agree_n}</dd>
                        <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.disagreeN', 'Discord.')}</dt>
                        <dd className="text-right text-amber-600">{p.disagree_n}</dd>
                        <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.overrideN', 'Override')}</dt>
                        <dd className="text-right text-rose-600">{p.override_n}</dd>
                        <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.meanOverrideDelta', 'Δ avg')}</dt>
                        <dd className="text-right text-[var(--text-primary)]">{fmtNum(p.mean_override_delta, 2)}</dd>
                      </dl>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
      </section>

      {/* Top outliers */}
      <section className={cardClass + ' mb-6'} aria-labelledby="outliers-heading">
        <h2 id="outliers-heading" className={sectionTitle}>
          {t('comp.aiCalibration.topOutliers', 'Top Outliers')}
        </h2>
        {outliers.length === 0 ? (
          <p className="text-sm text-[var(--text-muted)] py-2">
            {t('comp.aiCalibration.outliersEmpty', 'Sem outliers (nenhuma app com Sonnet score + final_score neste ciclo).')}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left border-b border-[var(--border-default)]">
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)]">{t('comp.aiCalibration.colApplicant', 'Candidato')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.colAiScore', 'IA')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.colHumanScore', 'Humano')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.colDelta', 'Δ')}</th>
                </tr>
              </thead>
              <tbody>
                {outliers.map((o) => (
                  <tr key={o.application_id} className="border-b border-[var(--border-default)] last:border-b-0">
                    <td className="py-2 pr-3">{o.applicant_name || DASH}</td>
                    <td className="py-2 pr-3 text-right">{fmtNum(o.ai_score, 1)}</td>
                    <td className="py-2 pr-3 text-right">{fmtNum(o.human_score_normalized, 1)}</td>
                    <td className="py-2 pr-3 text-right">
                      <span className={Math.abs(o.delta_signed) > latest.drift_threshold ? 'text-rose-600 font-semibold' : ''}>
                        {fmtNum(o.delta_signed, 2)}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* Drift over time */}
      <section className={cardClass + ' mb-6'} aria-labelledby="drift-trend-heading">
        <h2 id="drift-trend-heading" className={sectionTitle}>
          {t('comp.aiCalibration.driftTrend', 'Drift ao longo do tempo')}
        </h2>
        {driftSeries.length < 2 ? (
          <p className="text-sm text-[var(--text-muted)] py-2">
            {t('comp.aiCalibration.driftTrendEmpty', 'Histórico curto. Plot aparece quando houver 2+ rodadas registradas.')}
          </p>
        ) : (
          <>
            <p className="text-xs text-[var(--text-muted)] mb-3">
              {t('comp.aiCalibration.driftTrendHint', 'Cada ponto = 1 rodada. Linha rosa = média absoluta dos deltas (quanto menor, melhor calibrado). Linha azul = delta médio sinalizado (positivo = humano > IA). Banda tracejada = limite de drift alto.')}
            </p>
            <div className="w-full" style={{ height: 320 }}>
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={driftSeries} margin={{ top: 10, right: 16, bottom: 32, left: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--border-default)" />
                  <XAxis
                    dataKey="label"
                    stroke="var(--text-muted)"
                    tick={{ fontSize: 11 }}
                    angle={-15}
                    textAnchor="end"
                    height={60}
                  />
                  <YAxis stroke="var(--text-muted)" tick={{ fontSize: 11 }} />
                  <Tooltip
                    contentStyle={{ background: 'var(--surface-card)', border: '1px solid var(--border-default)', borderRadius: 8, fontSize: 12 }}
                    labelStyle={{ color: 'var(--text-primary)', fontWeight: 600 }}
                    formatter={(value: number, name: string) => [Number(value).toFixed(2), name]}
                  />
                  <Legend wrapperStyle={{ fontSize: 12 }} />
                  <ReferenceLine
                    y={driftThreshold}
                    stroke="#f43f5e"
                    strokeDasharray="4 2"
                    label={{ value: `+${driftThreshold}`, fill: '#f43f5e', fontSize: 10, position: 'right' }}
                  />
                  <ReferenceLine
                    y={-driftThreshold}
                    stroke="#f43f5e"
                    strokeDasharray="4 2"
                    label={{ value: `−${driftThreshold}`, fill: '#f43f5e', fontSize: 10, position: 'right' }}
                  />
                  <ReferenceLine y={0} stroke="var(--text-muted)" />
                  <Line
                    type="monotone"
                    dataKey="mean_delta_abs"
                    stroke="#f43f5e"
                    strokeWidth={2}
                    dot={{ r: 4 }}
                    name={t('comp.aiCalibration.meanDeltaAbs', 'Δ médio (abs)')}
                    connectNulls
                  />
                  <Line
                    type="monotone"
                    dataKey="mean_delta_signed"
                    stroke="#3b82f6"
                    strokeWidth={2}
                    dot={{ r: 4 }}
                    name={t('comp.aiCalibration.meanDeltaSigned', 'Δ médio (signed)')}
                    connectNulls
                  />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </>
        )}
      </section>

      {/* Run history */}
      <section className={cardClass} aria-labelledby="history-heading">
        <h2 id="history-heading" className={sectionTitle}>
          {t('comp.aiCalibration.history', 'Histórico')}
        </h2>
        {data.runs.length <= 1 ? (
          <p className="text-sm text-[var(--text-muted)] py-2">
            {t('comp.aiCalibration.historyEmpty', 'Apenas 1 rodada disponível. Histórico aparece quando o cron rodar mais vezes.')}
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left border-b border-[var(--border-default)]">
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)]">{t('comp.aiCalibration.colRanAt', 'Data')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)]">{t('comp.aiCalibration.colCycle', 'Ciclo')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.nCompared', 'Pares')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.meanDeltaAbs', 'Δ abs')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)] text-right">{t('comp.aiCalibration.driftCountHigh', 'Drift alto')}</th>
                  <th className="py-2 pr-3 font-medium text-[var(--text-muted)]">{t('comp.aiCalibration.colTrigger', 'Trigger')}</th>
                </tr>
              </thead>
              <tbody>
                {data.runs.map((r) => (
                  <tr key={r.id} className="border-b border-[var(--border-default)] last:border-b-0">
                    <td className="py-2 pr-3">{fmtDateTime(r.ran_at, lang)}</td>
                    <td className="py-2 pr-3">{r.cycle_code || DASH}</td>
                    <td className="py-2 pr-3 text-right">{r.n_compared}</td>
                    <td className="py-2 pr-3 text-right">{fmtNum(r.mean_delta_abs, 3)}</td>
                    <td className="py-2 pr-3 text-right">{r.drift_count_high}</td>
                    <td className="py-2 pr-3 text-xs text-[var(--text-muted)]">
                      {r.triggered_by === 'cron'
                        ? t('comp.aiCalibration.triggeredCron', 'cron')
                        : t('comp.aiCalibration.triggeredAdmin', 'admin')}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {drillValidator && (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 px-4 py-8 overflow-y-auto"
          onClick={(e) => { if (e.target === e.currentTarget) closeDrill(); }}
          role="dialog"
          aria-modal="true"
          aria-labelledby="drill-heading"
        >
          <div className="bg-[var(--surface-card)] border border-[var(--border-default)] rounded-xl w-full max-w-3xl shadow-2xl flex flex-col max-h-[90vh]">
            <header className="flex items-start justify-between gap-4 px-5 py-4 border-b border-[var(--border-default)]">
              <div>
                <h2 id="drill-heading" className="text-lg font-bold text-[var(--text-primary)]">
                  {t('comp.aiCalibration.drillTitle', 'Validações por avaliador')}
                </h2>
                <p className="text-sm text-[var(--text-muted)] mt-0.5">
                  {drillValidator.name || t('comp.aiCalibration.drillUnknown', 'Avaliador sem nome')}
                  {drillDetails && (
                    <span className="ml-2 text-xs">
                      · {drillDetails.count} {t('comp.aiCalibration.drillCountSuffix', 'validações')}
                    </span>
                  )}
                </p>
              </div>
              <button
                type="button"
                onClick={closeDrill}
                aria-label={t('comp.aiCalibration.drillClose', 'Fechar')}
                className="p-1.5 rounded-lg hover:bg-[var(--surface-elevated)] text-[var(--text-muted)] hover:text-[var(--text-primary)]"
              >
                <X className="h-5 w-5" aria-hidden />
              </button>
            </header>

            <div className="overflow-y-auto px-5 py-4 flex-1">
              {drillLoading && (
                <div className="flex items-center justify-center py-12 text-[var(--text-muted)]">
                  <Loader2 className="h-5 w-5 animate-spin mr-2" />
                  {t('comp.aiCalibration.drillLoading', 'Carregando validações...')}
                </div>
              )}
              {drillError && (
                <p className="text-sm text-rose-600 py-3">{drillError}</p>
              )}
              {!drillLoading && !drillError && drillDetails && drillDetails.count === 0 && (
                <p className="text-sm text-[var(--text-muted)] py-3">
                  {t('comp.aiCalibration.drillEmpty', 'Nenhuma validação encontrada para este avaliador no ciclo selecionado.')}
                </p>
              )}
              {!drillLoading && !drillError && drillDetails && drillDetails.count > 0 && (
                <ul className="flex flex-col gap-3">
                  {drillDetails.validations.map((vd) => {
                    const actionBadge =
                      vd.validation_action === 'agree'
                        ? { Icon: ThumbsUp, cls: 'bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-950 dark:text-emerald-300', label: t('comp.aiCalibration.actionAgree', 'Concorda') }
                        : vd.validation_action === 'disagree'
                          ? { Icon: ThumbsDown, cls: 'bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-950 dark:text-amber-300', label: t('comp.aiCalibration.actionDisagree', 'Discorda') }
                          : { Icon: Edit3, cls: 'bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-950 dark:text-rose-300', label: t('comp.aiCalibration.actionOverride', 'Override') };
                    const purposeLabel =
                      vd.ai_purpose === 'sonnet_triage'
                        ? t('comp.aiCalibration.purposeSonnet', 'Sonnet Triage')
                        : vd.ai_purpose === 'gemini_qualitative'
                          ? t('comp.aiCalibration.purposeGeminiQualitative', 'Gemini Qualitative')
                          : vd.ai_purpose === 'gemini_eleva_bar'
                            ? t('comp.aiCalibration.purposeGemini', 'Gemini')
                            : vd.ai_purpose;
                    return (
                      <li key={vd.id} className="border border-[var(--border-default)] rounded-lg p-3 bg-[var(--surface-elevated)]">
                        <div className="flex flex-wrap items-start justify-between gap-2 mb-2">
                          <div className="flex flex-col">
                            <span className="font-semibold text-[var(--text-primary)]">{vd.applicant_name}</span>
                            <span className="text-xs text-[var(--text-muted)]">
                              {vd.cycle_code || DASH}
                              {vd.application_status && <> · {vd.application_status}</>}
                            </span>
                          </div>
                          <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border text-xs font-semibold ${actionBadge.cls}`}>
                            <actionBadge.Icon className="h-3 w-3" aria-hidden />
                            {actionBadge.label}
                          </span>
                        </div>
                        <dl className="grid grid-cols-2 md:grid-cols-4 gap-x-3 gap-y-1 text-xs mb-2">
                          <div className="flex flex-col">
                            <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.drillPurpose', 'Propósito')}</dt>
                            <dd className="text-[var(--text-primary)] font-medium">{purposeLabel}</dd>
                          </div>
                          <div className="flex flex-col">
                            <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.drillAiScore', 'Score IA')}</dt>
                            <dd className="text-[var(--text-primary)] font-medium">{vd.ai_score !== null ? fmtNum(vd.ai_score, 1) : (vd.ai_verdict || DASH)}</dd>
                          </div>
                          <div className="flex flex-col">
                            <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.drillOverride', 'Override')}</dt>
                            <dd className="text-[var(--text-primary)] font-medium">{vd.override_score !== null ? fmtNum(vd.override_score, 1) : DASH}</dd>
                          </div>
                          <div className="flex flex-col">
                            <dt className="text-[var(--text-muted)]">{t('comp.aiCalibration.drillValidatedAt', 'Quando')}</dt>
                            <dd className="text-[var(--text-primary)] font-medium">{fmtDateTime(vd.validated_at, lang)}</dd>
                          </div>
                        </dl>
                        {vd.comment && (
                          <div className="mt-2 pt-2 border-t border-[var(--border-default)]">
                            <p className="text-xs text-[var(--text-muted)] mb-1">{t('comp.aiCalibration.drillComment', 'Comentário')}</p>
                            <p className="text-sm text-[var(--text-primary)] whitespace-pre-wrap">{vd.comment}</p>
                          </div>
                        )}
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
