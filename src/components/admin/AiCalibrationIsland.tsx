import { useState, useEffect, useCallback, useMemo } from 'react';
import { Loader2, RefreshCw, Bot, TrendingUp, TrendingDown, Minus } from 'lucide-react';
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
            onClick={fetchData}
            className="px-3 py-2 rounded-lg bg-[var(--accent-primary)] text-white text-sm font-medium hover:opacity-90 flex items-center gap-1.5"
          >
            <RefreshCw className="h-4 w-4" aria-hidden />
            {t('comp.aiCalibration.refresh', 'Atualizar')}
          </button>
        </div>
      </header>

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
                        <tr key={v.validator_id} className="border-b border-[var(--border-default)] last:border-b-0">
                          <td className="py-2 pr-3">{v.name || DASH}</td>
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
    </div>
  );
}
