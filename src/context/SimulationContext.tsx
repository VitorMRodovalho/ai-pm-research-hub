import { createContext, useContext, useState, useCallback, useEffect, type ReactNode } from 'react';
import {
  type OperationalTier, type Designation, type Permission,
  setSimulation, clearSimulation, getEffectivePermissions,
  TIER_LABELS, DESIGNATION_LABELS, TIER_COLORS,
} from '../lib/permissions';

interface SimulationContextType {
  isSimulating: boolean;
  simulatedTier: OperationalTier | null;
  simulatedDesignations: Designation[];
  simulatedTribeId: number | null;
  effectivePermissions: Permission[];
  startSimulation: (tier: OperationalTier, designations?: Designation[], tribeId?: number | null) => void;
  stopSimulation: () => void;
  label: string;
  color: string;
}

const SimulationContext = createContext<SimulationContextType>({
  isSimulating: false,
  simulatedTier: null,
  simulatedDesignations: [],
  simulatedTribeId: null,
  effectivePermissions: [],
  startSimulation: () => {},
  stopSimulation: () => {},
  label: '',
  color: '',
});

function setCookie(name: string, value: string) {
  document.cookie = `${name}=${encodeURIComponent(value)};path=/;max-age=86400;SameSite=Lax`;
}

function clearCookie(name: string) {
  document.cookie = `${name}=;path=/;max-age=0`;
}

export function SimulationProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<{
    active: boolean;
    tier: OperationalTier | null;
    designations: Designation[];
    tribeId: number | null;
  }>({ active: false, tier: null, designations: [], tribeId: null });

  // Restore from cookies on mount
  useEffect(() => {
    const tier = getCookie('sim_tier') as OperationalTier | null;
    if (tier && TIER_LABELS[tier]) {
      const desig = getCookie('sim_designations');
      const tribe = getCookie('sim_tribe');
      const designations = desig ? JSON.parse(desig) as Designation[] : [];
      const tribeId = tribe ? parseInt(tribe) : null;
      setSimulation({ active: true, tier, designations, tribe_id: tribeId });
      setState({ active: true, tier, designations, tribeId });
    }
  }, []);

  const startSimulation = useCallback((
    tier: OperationalTier,
    designations: Designation[] = [],
    tribeId: number | null = null
  ) => {
    const simState = { active: true, tier, designations, tribe_id: tribeId };
    setSimulation(simState);
    setState({ active: true, tier, designations, tribeId });

    // Persist to cookies for Astro SSR pages
    setCookie('sim_tier', tier);
    setCookie('sim_designations', JSON.stringify(designations));
    if (tribeId) setCookie('sim_tribe', String(tribeId));
    else clearCookie('sim_tribe');

    // Notify other components
    window.dispatchEvent(new CustomEvent('simulation:changed', { detail: simState }));
  }, []);

  const stopSimulation = useCallback(() => {
    clearSimulation();
    setState({ active: false, tier: null, designations: [], tribeId: null });

    clearCookie('sim_tier');
    clearCookie('sim_designations');
    clearCookie('sim_tribe');

    window.dispatchEvent(new CustomEvent('simulation:changed', { detail: { active: false } }));
  }, []);

  const label = state.active && state.tier
    ? [
        `${TIER_LABELS[state.tier]?.icon || ''} ${TIER_LABELS[state.tier]?.pt || state.tier}`,
        ...state.designations.map(d => DESIGNATION_LABELS[d]?.pt || d),
        state.tribeId ? `Tribo ${state.tribeId}` : null,
      ].filter(Boolean).join(' · ')
    : '';

  const color = state.active && state.tier ? (TIER_COLORS[state.tier] || '#94A3B8') : '';

  const effectivePermissions = state.active && state.tier
    ? getEffectivePermissions({
        operational_role: state.tier,
        designations: state.designations,
        is_superadmin: false,
        tribe_id: state.tribeId,
      })
    : [];

  return (
    <SimulationContext.Provider value={{
      isSimulating: state.active,
      simulatedTier: state.tier,
      simulatedDesignations: state.designations,
      simulatedTribeId: state.tribeId,
      effectivePermissions,
      startSimulation, stopSimulation,
      label, color,
    }}>
      {children}
    </SimulationContext.Provider>
  );
}

export function useSimulation() {
  return useContext(SimulationContext);
}

function getCookie(name: string): string | null {
  const match = document.cookie.match(new RegExp(`(?:^|; )${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : null;
}
