import { useState, useEffect, useRef } from 'react';
import {
  type OperationalTier, type Designation,
  TIER_LABELS, DESIGNATION_LABELS, TIER_COLORS,
} from '../../lib/permissions';
import { SimulationProvider, useSimulation } from '../../context/SimulationContext';

interface Props {
  i18n: {
    title: string;
    banner: string;
    viewingAs: string;
    writesWarning: string;
    exit: string;
    selectTier: string;
    designationsLabel: string;
    tribeScope: string;
    noTribe: string;
    start: string;
  };
}

const ALL_TIERS: OperationalTier[] = [
  'manager', 'sponsor', 'chapter_liaison', 'tribe_leader',
  'project_collaborator', 'researcher', 'cop_participant',
  'cop_observer', 'observer', 'candidate', 'visitor',
];

const TOGGLEABLE_DESIGNATIONS: Designation[] = [
  'deputy_manager', 'curator', 'comms_leader', 'comms_member', 'ambassador',
];

function TierViewerInner({ i18n }: Props) {
  const { isSimulating, label, color, startSimulation, stopSimulation } = useSimulation();
  const [open, setOpen] = useState(false);
  const [selectedTier, setSelectedTier] = useState<OperationalTier>('researcher');
  const [selectedDesig, setSelectedDesig] = useState<Designation[]>([]);
  const [selectedTribe, setSelectedTribe] = useState<number | null>(null);
  const [tribes, setTribes] = useState<{ id: number; name: string }[]>([]);
  const panelRef = useRef<HTMLDivElement>(null);

  // Load tribes list
  useEffect(() => {
    (async () => {
      const sb = (window as any).navGetSb?.();
      if (!sb) return;
      const { data } = await sb.from('tribes').select('id, name').order('id');
      if (data) setTribes(data);
    })();
  }, []);

  // Close panel on outside click
  useEffect(() => {
    if (!open) return;
    function handler(e: MouseEvent) {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  function toggleDesig(d: Designation) {
    setSelectedDesig(prev => prev.includes(d) ? prev.filter(x => x !== d) : [...prev, d]);
  }

  function handleStart() {
    startSimulation(selectedTier, selectedDesig, selectedTribe);
    setOpen(false);
    // Refresh page to apply simulation to Astro SSR components
    window.location.reload();
  }

  function handleStop() {
    stopSimulation();
    window.location.reload();
  }

  // ── SIMULATING: full banner ──
  if (isSimulating) {
    return (
      <div
        className="fixed top-0 left-0 right-0 z-[9999] flex items-center justify-between gap-3 px-4 py-2
          bg-[var(--surface-card)] border-b-2 text-[13px]"
        style={{ borderColor: color }}
      >
        <div className="flex items-center gap-3 flex-wrap">
          <span className="font-bold text-[var(--text-primary)]">
            👁️ {i18n.banner}: {label}
          </span>
          <span className="text-[var(--text-muted)] text-[11px]">
            {i18n.writesWarning}
          </span>
        </div>
        <button
          onClick={handleStop}
          className="px-3 py-1 rounded-lg bg-red-50 text-red-600 text-[12px] font-semibold
            cursor-pointer border border-red-200 hover:bg-red-100 transition-colors"
        >
          {i18n.exit} ✕
        </button>
      </div>
    );
  }

  // ── NOT SIMULATING: collapsed trigger + dropdown ──
  return (
    <div className="fixed top-[62px] right-4 z-[999]" ref={panelRef}>
      <button
        onClick={() => setOpen(v => !v)}
        className="px-3 py-1.5 rounded-xl bg-[var(--surface-card)] border border-[var(--border-default)]
          text-[12px] font-semibold text-[var(--text-secondary)] cursor-pointer
          hover:bg-[var(--surface-hover)] transition-colors shadow-sm flex items-center gap-1.5"
      >
        👁️ {i18n.title} ▼
      </button>

      {open && (
        <div className="absolute right-0 top-full mt-2 w-[320px] bg-[var(--surface-card)]
          border border-[var(--border-default)] rounded-xl shadow-xl overflow-hidden">
          {/* Tier selection */}
          <div className="px-4 pt-3 pb-2">
            <div className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-2">
              {i18n.selectTier}
            </div>
            <div className="space-y-0.5 max-h-[220px] overflow-y-auto">
              {ALL_TIERS.map(tier => (
                <button
                  key={tier}
                  onClick={() => setSelectedTier(tier)}
                  className={`w-full text-left px-2.5 py-1.5 rounded-lg text-[12px] cursor-pointer border-0 transition-colors
                    ${selectedTier === tier
                      ? 'bg-blue-50 text-blue-700 font-semibold'
                      : 'bg-transparent text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'
                    }`}
                >
                  {TIER_LABELS[tier].icon} {TIER_LABELS[tier].pt}
                </button>
              ))}
            </div>
          </div>

          {/* Designations */}
          <div className="px-4 py-2 border-t border-[var(--border-subtle)]">
            <div className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-2">
              {i18n.designationsLabel}
            </div>
            <div className="space-y-1">
              {TOGGLEABLE_DESIGNATIONS.map(d => (
                <label key={d} className="flex items-center gap-2 text-[12px] text-[var(--text-secondary)] cursor-pointer">
                  <input
                    type="checkbox"
                    checked={selectedDesig.includes(d)}
                    onChange={() => toggleDesig(d)}
                    className="rounded"
                  />
                  {DESIGNATION_LABELS[d].pt}
                </label>
              ))}
            </div>
          </div>

          {/* Tribe scope */}
          <div className="px-4 py-2 border-t border-[var(--border-subtle)]">
            <div className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-2">
              {i18n.tribeScope}
            </div>
            <select
              value={selectedTribe ?? ''}
              onChange={e => setSelectedTribe(e.target.value ? parseInt(e.target.value) : null)}
              className="w-full px-2 py-1.5 rounded-lg border border-[var(--border-default)]
                bg-[var(--surface-base)] text-[12px] text-[var(--text-primary)]"
            >
              <option value="">{i18n.noTribe}</option>
              {tribes.map(t => (
                <option key={t.id} value={t.id}>T{String(t.id).padStart(2, '0')} {t.name}</option>
              ))}
            </select>
          </div>

          {/* Preview + Start */}
          <div className="px-4 py-3 border-t border-[var(--border-subtle)] bg-[var(--surface-base)]">
            <div className="flex items-center gap-2 mb-2">
              <span className="w-3 h-3 rounded-full" style={{ background: TIER_COLORS[selectedTier] }} />
              <span className="text-[11px] text-[var(--text-secondary)]">
                {TIER_LABELS[selectedTier].icon} {TIER_LABELS[selectedTier].pt}
                {selectedDesig.length > 0 && ` + ${selectedDesig.map(d => DESIGNATION_LABELS[d].pt).join(', ')}`}
                {selectedTribe && ` · T${String(selectedTribe).padStart(2, '0')}`}
              </span>
            </div>
            <button
              onClick={handleStart}
              className="w-full px-3 py-2 rounded-lg bg-blue-900 text-white text-[12px] font-bold
                cursor-pointer border-0 hover:bg-blue-800 transition-colors"
            >
              {i18n.start}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

export default function TierViewerBar(props: Props) {
  return (
    <SimulationProvider>
      <TierViewerInner {...props} />
    </SimulationProvider>
  );
}
