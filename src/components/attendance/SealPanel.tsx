/**
 * SealPanel — a superficie do selo de presenca (#1710).
 *
 * O #1657 tirou o "sem linha = falta": hoje, sem linha num evento NAO selado, a celula diz
 * `unrecorded` e nao acusa ninguem. Isso transferiu todo o peso para o ato de SELAR, que e o que
 * materializa a linha de no-show — e o ato nao tinha nenhuma superficie. Este painel e ela.
 *
 * Duas regras de desenho, nenhuma cosmetica:
 *
 * 1. A confirmacao diz o NUMERO antes de executar. `seal_event_attendance` grava `present=false`
 *    para todo elegivel sem registro, no historico de gente real, e a RPC nao tem desfazer proprio.
 *    O numero vem do dry-run (`preview_seal_attendance`), a mesma fonte que o servidor usa, entao
 *    o que o botao promete e o que a escrita faz.
 *
 * 2. A reversao aparece junto com o ato, nao numa tela de suporte. `unseal_event_attendance` apaga
 *    somente as linhas que o selo criou e que ninguem encostou depois — quem foi marcado presente
 *    ou justificado no meio-tempo PERMANECE, e o painel diz quantas foram preservadas.
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';
import { canForAnyTribe } from '../../lib/permissions';
import { formatDateOnly } from '../../lib/date-only';
import { AlertTriangle, Loader2, Lock, RotateCcw, ShieldCheck } from 'lucide-react';

function getSb() {
  if (typeof window === 'undefined') return null;
  return (window as any).navGetSb?.();
}

async function waitForSb(maxRetries = 15): Promise<any> {
  let sb = getSb();
  let retries = 0;
  while (!sb && retries < maxRetries) {
    await new Promise((r) => setTimeout(r, 250));
    sb = getSb();
    retries++;
  }
  return sb;
}

function getMember() {
  if (typeof window === 'undefined') return null;
  return (window as any).navGetMember?.();
}

/** O island monta antes de a nav resolver o membro. Sem esta espera, quem PODE selar veria a tela
 *  de recusa por uma corrida de boot — a mesma classe de defeito do gate client-side do #1590. */
async function waitForMember(maxRetries = 20): Promise<any> {
  let m = getMember();
  let retries = 0;
  while (!m && retries < maxRetries) {
    await new Promise((r) => setTimeout(r, 250));
    m = getMember();
    retries++;
  }
  return m;
}

/** Mesmo predicado do AttendanceGridTab: o selo e gateado em `manage_event`, e o servidor o aplica
 *  POR EVENTO. Aqui a checagem so decide se vale a pena pedir o dry-run. */
function canSeal(): boolean {
  const m = getMember();
  if (!m) return false;
  if (m.is_superadmin) return true;
  if (m.operational_role === 'manager') return true;
  if ((m.designations || []).includes('deputy_manager')) return true;
  return canForAnyTribe('manage_event');
}

interface PreviewRow {
  event_id: string;
  event_date: string;
  event_type: string;
  event_title: string;
  tribe_id: number | null;
  ends_at: string | null;
  already_sealed_at: string | null;
  eligible_cohort_n: number;
  already_recorded_n: number;
  would_write_absent_n: number;
  blocked_reason: string | null;
}

type Confirmacao =
  | { tipo: 'selar'; linha: PreviewRow }
  | { tipo: 'reverter'; linha: PreviewRow }
  | null;

export default function SealPanel() {
  const t = usePageI18n();
  const [linhas, setLinhas] = useState<PreviewRow[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const [mostrarBloqueados, setMostrarBloqueados] = useState(false);
  const [confirmacao, setConfirmacao] = useState<Confirmacao>(null);
  const [executando, setExecutando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);
  const [permitido, setPermitido] = useState<boolean | null>(null);

  const carregar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    const sb = await waitForSb();
    if (!sb) {
      setErro(t('comp.attendance.seal.errNoSession', 'Sessão indisponível.'));
      setCarregando(false);
      return;
    }
    const { data, error } = await sb.rpc('preview_seal_attendance', {});
    if (error) {
      setErro(error.message);
      setLinhas([]);
    } else {
      setLinhas((data ?? []) as PreviewRow[]);
    }
    setCarregando(false);
  }, [t]);

  useEffect(() => {
    let vivo = true;
    (async () => {
      // O papel so decide se pedimos o ensaio; quem recusa de verdade e o servidor, por evento.
      await waitForSb();
      await waitForMember();
      if (!vivo) return;
      const ok = canSeal();
      setPermitido(ok);
      if (ok) await carregar();
      else setCarregando(false);
    })();
    return () => { vivo = false; };
  }, [carregar]);

  // O quadro de presenca do evento (RosterModal) manda o foco para ca em vez de abrir uma segunda
  // confirmacao. Uma confirmacao so, alimentada pelo mesmo dry-run que o servidor usa.
  const [focoPedido, setFocoPedido] = useState<string | null>(null);
  useEffect(() => {
    const ouvir = (e: Event) => {
      const id = (e as CustomEvent)?.detail?.eventId;
      if (typeof id === 'string') setFocoPedido(id);
    };
    window.addEventListener('seal:focus', ouvir);
    return () => window.removeEventListener('seal:focus', ouvir);
  }, []);

  useEffect(() => {
    if (!focoPedido || carregando) return;
    const alvo = linhas.find((l) => l.event_id === focoPedido);
    setFocoPedido(null);
    if (!alvo) {
      setAviso(t('comp.attendance.seal.notInPreview',
        'Este evento não está no ensaio de selagem: ou você não tem autoridade sobre ele, ou ele está fora do ciclo corrente.'));
      return;
    }
    if (alvo.blocked_reason && alvo.blocked_reason !== 'already_sealed') {
      setAviso(`${alvo.event_title}: ${motivo(alvo.blocked_reason)}`);
      return;
    }
    setConfirmacao({ tipo: alvo.blocked_reason === 'already_sealed' ? 'reverter' : 'selar', linha: alvo });
  }, [focoPedido, carregando, linhas]);

  const selaveis = useMemo(() => linhas.filter((l) => !l.blocked_reason), [linhas]);
  const selados = useMemo(() => linhas.filter((l) => l.blocked_reason === 'already_sealed'), [linhas]);
  const faltasPendentes = useMemo(
    () => selaveis.reduce((acc, l) => acc + l.would_write_absent_n, 0),
    [selaveis],
  );

  const visiveis = useMemo(() => {
    const base = mostrarBloqueados ? linhas : [...selaveis, ...selados];
    return [...base].sort((a, b) => (a.event_date < b.event_date ? 1 : -1));
  }, [linhas, selaveis, selados, mostrarBloqueados]);

  async function executar() {
    if (!confirmacao) return;
    setExecutando(true);
    setAviso(null);
    const sb = await waitForSb();
    const rpc = confirmacao.tipo === 'selar' ? 'seal_event_attendance' : 'unseal_event_attendance';
    const { data, error } = await sb.rpc(rpc, { p_event_id: confirmacao.linha.event_id });
    setExecutando(false);
    setConfirmacao(null);
    if (error) {
      setAviso(error.message);
    } else if (data && data.success === false) {
      setAviso(String(data.error ?? 'erro'));
    } else if (confirmacao.tipo === 'selar') {
      setAviso(t('comp.attendance.seal.doneSeal', 'Evento selado: {n} falta(s) gravada(s).')
        .replace('{n}', String(data?.sealed_absent_count ?? 0)));
    } else {
      const preservadas = Number(data?.kept_touched_count ?? 0);
      setAviso(
        t('comp.attendance.seal.doneUnseal', 'Selo revertido: {n} linha(s) removida(s).')
          .replace('{n}', String(data?.removed_absent_count ?? 0))
        + (preservadas > 0
          ? ' ' + t('comp.attendance.seal.keptTouched', '{k} linha(s) foram preservadas porque alguém as editou depois do selo.')
            .replace('{k}', String(preservadas))
          : ''),
      );
    }
    await carregar();
  }

  if (permitido === false) {
    return (
      <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] p-6 text-sm text-[var(--text-secondary)]">
        {t('comp.attendance.seal.denied', 'Selar a lista de um evento requer autoridade sobre o evento.')}
      </div>
    );
  }

  const motivo = (r: string | null) => {
    if (!r) return '';
    const mapa: Record<string, string> = {
      not_ended_yet: t('comp.attendance.seal.reason.notEnded', 'ainda não terminou'),
      cancelled: t('comp.attendance.seal.reason.cancelled', 'cancelado'),
      skipped_empty_cohort: t('comp.attendance.seal.reason.emptyCohort', 'sem ninguém elegível'),
      already_sealed: t('comp.attendance.seal.reason.alreadySealed', 'já selado'),
    };
    return mapa[r] ?? r;
  };

  return (
    <div className="bg-[var(--surface-card)] rounded-xl border border-[var(--border-default)] overflow-hidden">
      <div className="px-5 py-3.5 border-b border-[var(--border-default)] flex items-center justify-between flex-wrap gap-2">
        <h3 className="text-sm font-bold text-navy flex items-center gap-2">
          <Lock className="w-4 h-4" />
          {t('comp.attendance.seal.title', 'Selagem de presença')}
        </h3>
        <button
          type="button"
          onClick={carregar}
          className="px-3 py-1.5 rounded-lg text-[12px] font-semibold border-[1.5px] border-navy text-navy bg-transparent hover:bg-[var(--surface-hover)] cursor-pointer"
        >
          {t('comp.attendance.seal.refresh', 'Atualizar')}
        </button>
      </div>

      <div className="px-5 py-4 border-b border-[var(--border-subtle)] text-[13px] text-[var(--text-secondary)]">
        <p className="mb-3">
          {t('comp.attendance.seal.intro',
            'Selar fecha a lista de um evento: quem estava na coorte e não tem registro passa a constar como falta. É escrita no histórico de pessoas reais e não há desfazer automático — a reversão é por evento e só apaga o que este selo criar.')}
        </p>
        <div className="flex gap-4 flex-wrap">
          <span className="font-bold text-[var(--text-primary)]">
            {selaveis.length} {t('comp.attendance.seal.kpiSealable', 'evento(s) prontos para selar')}
          </span>
          <span className="font-bold text-amber-700 dark:text-amber-400">
            {faltasPendentes} {t('comp.attendance.seal.kpiAbsences', 'falta(s) seriam gravadas')}
          </span>
          <span className="text-[var(--text-muted)]">
            {selados.length} {t('comp.attendance.seal.kpiSealed', 'já selado(s)')}
          </span>
        </div>
        <label className="mt-3 flex items-center gap-2 text-[12px] cursor-pointer">
          <input type="checkbox" checked={mostrarBloqueados} onChange={(e) => setMostrarBloqueados(e.target.checked)} />
          {t('comp.attendance.seal.showBlocked', 'Mostrar também os que não podem ser selados, com o motivo')}
        </label>
      </div>

      {aviso && (
        <div className="px-5 py-3 border-b border-[var(--border-subtle)] text-[13px] text-[var(--text-primary)] bg-[var(--surface-base)]">
          {aviso}
        </div>
      )}

      {carregando ? (
        <div className="p-6 flex items-center gap-2 text-sm text-[var(--text-muted)]">
          <Loader2 className="w-4 h-4 animate-spin" /> {t('comp.attendance.seal.loading', 'Carregando ensaio…')}
        </div>
      ) : erro ? (
        <div className="p-6 text-sm text-red-600 flex items-center gap-2">
          <AlertCircleSafe /> {erro}
        </div>
      ) : visiveis.length === 0 ? (
        <div className="p-6 text-sm text-[var(--text-muted)]">
          {t('comp.attendance.seal.empty', 'Nenhum evento para selar neste ciclo.')}
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-[13px]">
            <thead className="bg-[var(--surface-base)]">
              <tr>
                <Th>{t('comp.attendance.seal.colDate', 'Data')}</Th>
                <Th>{t('comp.attendance.seal.colEvent', 'Evento')}</Th>
                <Th center>{t('comp.attendance.seal.colCohort', 'Elegíveis')}</Th>
                <Th center>{t('comp.attendance.seal.colRecorded', 'Com registro')}</Th>
                <Th center>{t('comp.attendance.seal.colWouldWrite', 'Viram falta')}</Th>
                <Th center>{t('comp.attendance.seal.colAction', 'Ação')}</Th>
              </tr>
            </thead>
            <tbody>
              {visiveis.map((l) => (
                <tr key={l.event_id} className="border-b border-[var(--border-subtle)]">
                  <td className="px-3 py-2 whitespace-nowrap text-[var(--text-secondary)]">
                    {formatDateOnly(l.event_date, { day: '2-digit', month: '2-digit' })}
                  </td>
                  <td className="px-3 py-2 text-[var(--text-primary)]">
                    {l.event_title}
                    {l.already_sealed_at && (
                      <span className="ml-2 text-[11px] text-emerald-700 dark:text-emerald-400 whitespace-nowrap">
                        <ShieldCheck className="inline w-3 h-3 mr-0.5" />
                        {t('comp.attendance.seal.sealedAt', 'selado em {d}')
                          .replace('{d}', new Date(l.already_sealed_at).toLocaleString())}
                      </span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-center">{l.eligible_cohort_n}</td>
                  <td className="px-3 py-2 text-center">{l.already_recorded_n}</td>
                  <td className={`px-3 py-2 text-center font-bold ${l.would_write_absent_n > 0 ? 'text-amber-700 dark:text-amber-400' : 'text-[var(--text-muted)]'}`}>
                    {l.would_write_absent_n}
                  </td>
                  <td className="px-3 py-2 text-center whitespace-nowrap">
                    {!l.blocked_reason ? (
                      <button
                        type="button"
                        onClick={() => setConfirmacao({ tipo: 'selar', linha: l })}
                        className="px-2.5 py-1 rounded-lg text-[12px] font-semibold bg-navy text-white border-0 cursor-pointer hover:opacity-90"
                      >
                        {t('comp.attendance.seal.actSeal', 'Selar')}
                      </button>
                    ) : l.blocked_reason === 'already_sealed' ? (
                      <button
                        type="button"
                        onClick={() => setConfirmacao({ tipo: 'reverter', linha: l })}
                        className="px-2.5 py-1 rounded-lg text-[12px] font-semibold border-[1.5px] border-[var(--border-default)] text-[var(--text-secondary)] bg-transparent cursor-pointer hover:bg-[var(--surface-hover)]"
                      >
                        <RotateCcw className="inline w-3 h-3 mr-1" />
                        {t('comp.attendance.seal.actUnseal', 'Reverter')}
                      </button>
                    ) : (
                      <span className="text-[12px] text-[var(--text-muted)]">{motivo(l.blocked_reason)}</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {confirmacao && (
        <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4">
          <div className="bg-[var(--surface-card)] rounded-2xl w-full max-w-[520px] p-5">
            <h4 className="text-base font-bold text-navy mb-3 flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-amber-500" />
              {confirmacao.tipo === 'selar'
                ? t('comp.attendance.seal.confirmSealTitle', 'Confirmar selagem')
                : t('comp.attendance.seal.confirmUnsealTitle', 'Confirmar reversão')}
            </h4>
            <p className="text-[13px] text-[var(--text-secondary)] mb-2">
              <strong className="text-[var(--text-primary)]">{confirmacao.linha.event_title}</strong>
              {' · '}
              {formatDateOnly(confirmacao.linha.event_date, { day: '2-digit', month: '2-digit', year: 'numeric' })}
            </p>
            <p className="text-[13px] text-[var(--text-primary)] mb-4">
              {confirmacao.tipo === 'selar'
                ? t('comp.attendance.seal.confirmSealBody',
                    'Isto grava {n} falta(s) para quem está na coorte de {c} pessoa(s) e não tem registro. A reversão é por evento e apaga apenas as linhas criadas por este selo.')
                    .replace('{n}', String(confirmacao.linha.would_write_absent_n))
                    .replace('{c}', String(confirmacao.linha.eligible_cohort_n))
                : t('comp.attendance.seal.confirmUnsealBody',
                    'Isto remove as faltas criadas pelo selo e reabre o evento. Linhas em que alguém marcou presença ou justificou depois do selo permanecem.')}
            </p>
            <div className="flex gap-2 justify-end">
              <button
                type="button"
                disabled={executando}
                onClick={() => setConfirmacao(null)}
                className="px-3 py-1.5 rounded-lg text-[13px] font-semibold border-[1.5px] border-[var(--border-default)] bg-transparent text-[var(--text-secondary)] cursor-pointer"
              >
                {t('comp.attendance.seal.cancel', 'Cancelar')}
              </button>
              <button
                type="button"
                disabled={executando}
                onClick={executar}
                className="px-3 py-1.5 rounded-lg text-[13px] font-semibold border-0 bg-navy text-white cursor-pointer disabled:opacity-60"
              >
                {executando && <Loader2 className="inline w-3 h-3 mr-1 animate-spin" />}
                {confirmacao.tipo === 'selar'
                  ? t('comp.attendance.seal.confirmSealCta', 'Gravar {n} falta(s)')
                      .replace('{n}', String(confirmacao.linha.would_write_absent_n))
                  : t('comp.attendance.seal.confirmUnsealCta', 'Reverter o selo')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function Th({ children, center }: { children: any; center?: boolean }) {
  return (
    <th className={`px-3 py-2 text-[11px] font-bold uppercase tracking-wider text-[var(--text-secondary)] ${center ? 'text-center' : 'text-left'}`}>
      {children}
    </th>
  );
}

function AlertCircleSafe() {
  return <AlertTriangle className="w-4 h-4" />;
}
