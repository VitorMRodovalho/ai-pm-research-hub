import { useMemo } from 'react';

type Gate = {
  kind: string;
  order: number;
  threshold: number | 'all';
  signed_count: number;
  signers: Array<{ name: string; chapter: string; signed_at: string; signoff_type: string; hash_short: string }>;
  eligible_pending: Array<{ id: string; name: string; chapter: string }>;
};

type Props = {
  gates: Gate[];
  gateLabels: Record<string, string>;
  compact?: boolean;
  onClickGate?: (kind: string) => void;
};

type GateState = 'satisfied' | 'active' | 'locked' | 'ackDone' | 'ackPending';

// threshold pode chegar como text ("0","1","all") do RPC. Normalize defensively.
function normalizeThreshold(t: number | string | 'all'): { isAll: boolean; isInformational: boolean; num: number } {
  const s = String(t);
  if (s === 'all') return { isAll: true, isInformational: false, num: 0 };
  if (s === '0') return { isAll: false, isInformational: true, num: 0 };
  return { isAll: false, isInformational: false, num: Number(s) };
}

function classifyGate(g: Gate, prevSatisfied: boolean): GateState {
  const t = normalizeThreshold(g.threshold);
  const signed = Number(g.signed_count) || 0;
  if (t.isInformational) {
    if (signed > 0) return 'ackDone';
    return prevSatisfied ? 'ackPending' : 'locked';
  }
  const satisfied = !t.isAll && signed >= t.num;
  if (satisfied) return 'satisfied';
  if (prevSatisfied) return 'active';
  return 'locked';
}

const STATE_STYLES: Record<GateState, { dot: string; label: string; ring: string }> = {
  satisfied:  { dot: 'bg-emerald-500 border-emerald-500 text-white',          label: 'text-emerald-700',             ring: '' },
  active:     { dot: 'bg-amber-500 border-amber-500 text-white animate-pulse', label: 'text-amber-700 font-semibold', ring: 'ring-2 ring-amber-200' },
  locked:     { dot: 'bg-gray-100 border-gray-300 text-gray-400',              label: 'text-gray-400',                ring: '' },
  ackDone:    { dot: 'bg-blue-500 border-blue-500 text-white',                 label: 'text-blue-700',                ring: '' },
  ackPending: { dot: 'bg-blue-100 border-blue-300 text-blue-700',              label: 'text-blue-700',                ring: '' },
};

function countLabel(g: Gate): string {
  const t = normalizeThreshold(g.threshold);
  const signed = Number(g.signed_count) || 0;
  const eligibleTotal = (g.eligible_pending?.length || 0) + signed;
  if (t.isInformational) return `${signed} / ${eligibleTotal} (ciência)`;
  if (t.isAll) return `${signed} / ${eligibleTotal} elegíveis`;
  return eligibleTotal !== t.num
    ? `${signed} / ${t.num} (${eligibleTotal} elegíveis)`
    : `${signed} / ${t.num}`;
}

function tipLabel(g: Gate, state: GateState, label: string): string {
  const t = normalizeThreshold(g.threshold);
  if (state === 'active') return `Aguardando ${t.num} assinatura(s) — ${label}`;
  if (state === 'locked') return 'Aguarda gates anteriores';
  if (state === 'ackDone') return 'Ciência registrada (não bloqueia)';
  if (state === 'ackPending') return 'Ciência pendente (não bloqueia avanço)';
  return `${label}: ${g.signed_count} assinatura(s)`;
}

export default function GovernancePipelineBar({ gates, gateLabels, compact = false, onClickGate }: Props) {
  const enriched = useMemo(() => {
    const sorted = [...gates].sort((a, b) => a.order - b.order);
    const states: GateState[] = [];
    let prevOK = true;
    for (const g of sorted) {
      const s = classifyGate(g, prevOK);
      states.push(s);
      const t = normalizeThreshold(g.threshold);
      if (t.isInformational) {
        // informational não muda prevOK — não bloqueia e não destrava
      } else {
        prevOK = s === 'satisfied';
      }
    }
    return sorted.map((g, i) => ({ ...g, state: states[i] }));
  }, [gates]);

  return (
    <ol className={`flex items-stretch gap-0 ${compact ? 'text-[10px]' : 'text-[11px]'} overflow-x-auto`}>
      {enriched.map((g, idx) => {
        const style = STATE_STYLES[g.state];
        const label = gateLabels[g.kind] || g.kind;
        const countText = countLabel(g);
        const icon = g.state === 'satisfied' ? '✓'
                   : g.state === 'ackDone' ? 'ℹ✓'
                   : g.state === 'ackPending' || (g.state === 'locked' && String(g.threshold) === '0') ? 'ℹ'
                   : String(g.order);
        return (
          <li key={g.kind + idx} className="flex items-center flex-shrink-0">
            <button
              type="button"
              onClick={() => onClickGate?.(g.kind)}
              disabled={!onClickGate}
              className={`flex flex-col items-center gap-1 px-2 py-1 cursor-pointer border-0 bg-transparent ${onClickGate ? 'hover:bg-[var(--surface-hover)] rounded' : 'cursor-default'}`}
              title={tipLabel(g, g.state, label)}
            >
              <span className={`inline-flex items-center justify-center w-6 h-6 rounded-full border-2 text-[10px] font-bold ${style.dot} ${style.ring}`}>
                {icon}
              </span>
              <span className={`whitespace-nowrap ${style.label}`}>{label}</span>
              <span className="text-[9px] text-[var(--text-muted)] tabular-nums">{countText}</span>
            </button>
            {idx < enriched.length - 1 && (
              <span className={`h-0.5 w-6 ${g.state === 'satisfied' || g.state === 'ackDone' ? 'bg-emerald-400' : 'bg-gray-200'}`} />
            )}
          </li>
        );
      })}
    </ol>
  );
}
