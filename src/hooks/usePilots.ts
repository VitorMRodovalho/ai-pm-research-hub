import { useState, useEffect, useCallback } from 'react';

function getSb() {
  return (window as any).navGetSb?.();
}

export function usePilots() {
  const [summary, setSummary] = useState<any>(null);
  const [selectedPilot, setSelectedPilot] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const sb = getSb();
      if (!sb) { setLoading(false); return; }
      const { data } = await sb.rpc('get_pilots_summary');
      setSummary(data);
      setLoading(false);
    })();
  }, []);

  const loadPilotDetail = useCallback(async (pilotId: string) => {
    const sb = getSb();
    if (!sb) return;
    const { data } = await sb.rpc('get_pilot_metrics', { p_pilot_id: pilotId });
    setSelectedPilot(data);
  }, []);

  const closePilotDetail = useCallback(() => setSelectedPilot(null), []);

  return { summary, selectedPilot, loading, loadPilotDetail, closePilotDetail };
}
