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

type GateState = 'satisfied' | 'active' | 'locked' | 'informational';

function classifyGate(g: Gate, prevSatisfied: boolean): GateState {
  if (g.threshold === 0) return 'informational';
  const needed = g.threshold === 'all' ? Infinity : Number(g.threshold);
  const satisfied = g.threshold === 'all' ? false : g.signed_count >= needed;
  if (satisfied) return 'satisfied';
  if (prevSatisfied) return 'active';
  return 'locked';
}

const STATE_STYLES: Record<GateState, { dot: string; label: string; ring: string }> = {
  satisfied:    { dot: 'bg-emerald-500 border-emerald-500 text-white',  label: 'text-emerald-700',  ring: '' },
  active:       { dot: 'bg-amber-500 border-amber-500 text-white animate-pulse',  label: 'text-amber-700 font-semibold', ring: 'ring-2 ring-amber-200' },
  locked:       { dot: 'bg-gray-100 border-gray-300 text-gray-400', label: 'text-gray-400', ring: '' },
  informational:{ dot: 'bg-blue-100 border-blue-300 text-blue-600',  label: 'text-blue-700', ring: '' },
};

export default function GovernancePipelineBar({ gates, gateLabels, compact = false, onClickGate }: Props) {
  const enriched = useMemo(() => {
    const sorted = [...gates].sort((a, b) => a.order - b.order);
    const states: GateState[] = [];
    let prevOK = true;
    for (const g of sorted) {
      const s = classifyGate(g, prevOK);
      states.push(s);
      if (g.threshold === 0) {
        // informational gate doesn't block
      } else if (s === 'satisfied' || (g.threshold !== 'all' && g.signed_count >= Number(g.threshold))) {
        prevOK = true;
      } else {
        prevOK = false;
      }
    }
    return sorted.map((g, i) => ({ ...g, state: states[i] }));
  }, [gates]);

  return (
    <ol className={`flex items-stretch gap-0 ${compact ? 'text-[10px]' : 'text-[11px]'} overflow-x-auto`}>
      {enriched.map((g, idx) => {
        const style = STATE_STYLES[g.state];
        const label = gateLabels[g.kind] || g.kind;
        const countText = g.threshold === 0
          ? 'ciência'
          : g.threshold === 'all'
            ? `${g.signed_count} / —`
            : `${g.signed_count} / ${g.threshold}`;
        const icon = g.state === 'satisfied' ? '✓' : g.state === 'informational' ? 'ℹ' : String(g.order);
        return (
          <li key={g.kind + idx} className="flex items-center flex-shrink-0">
            <button
              type="button"
              onClick={() => onClickGate?.(g.kind)}
              disabled={!onClickGate}
              className={`flex flex-col items-center gap-1 px-2 py-1 cursor-pointer border-0 bg-transparent ${onClickGate ? 'hover:bg-[var(--surface-hover)] rounded' : 'cursor-default'}`}
              title={g.state === 'active' ? `Aguardando ${label}` : g.state === 'locked' ? `Bloqueado — aguarda gates anteriores` : g.state === 'informational' ? 'Gate informativo (não bloqueia)' : `${label}: ${g.signed_count} assinatura(s)`}
            >
              <span className={`inline-flex items-center justify-center w-6 h-6 rounded-full border-2 text-[11px] font-bold ${style.dot} ${style.ring}`}>
                {icon}
              </span>
              <span className={`whitespace-nowrap ${style.label}`}>{label}</span>
              <span className="text-[9px] text-[var(--text-muted)] tabular-nums">{countText}</span>
            </button>
            {idx < enriched.length - 1 && (
              <span className={`h-0.5 w-6 ${g.state === 'satisfied' ? 'bg-emerald-400' : 'bg-gray-200'}`} />
            )}
          </li>
        );
      })}
    </ol>
  );
}
