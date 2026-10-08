import { useState, useEffect, useCallback } from 'react';

// #2556 — pede o consentimento de localização precisa no mapa público, na home do membro.
// Quem decide se o cartão aparece é o servidor (get_my_public_map_prompt): só para a equipe de pesquisa, sem o
// consentimento preciso e sem ter dispensado. "Autorizo" passa por grant_public_map_consent, que grava a prova no
// ledger consent_records; "Agora não" grava a dispensa no banco (vale em qualquer aparelho).
// O texto do consentimento chega pronto da página: é o rótulo aprovado (parecer legal-counsel 25/06/2026), o mesmo
// do /profile. Não reescreva aqui.

interface Props {
  lang?: string;
  consentText: string;
  title: string;
  accept: string;
  later: string;
  legacyNote: string;
  done: string;
  error: string;
}

export default function MapConsentNudge({ lang = 'pt-BR', consentText, title, accept, later, legacyNote, done, error }: Props) {
  const [prompt, setPrompt] = useState<{ show: boolean; legacy_only?: boolean } | null>(null);
  const [state, setState] = useState<'idle' | 'busy' | 'done' | 'error'>('idle');

  const getSb = useCallback(() => (window as any).navGetSb?.(), []);

  const load = useCallback(async () => {
    const sb = getSb();
    if (!sb) return;
    try {
      const { data, error: e } = await sb.rpc('get_my_public_map_prompt');
      if (!e && data) setPrompt(data);
    } catch { /* sem cartão se a leitura falhar */ }
  }, [getSb]);

  useEffect(() => {
    const onMember = (ev: any) => { if (ev?.detail) load(); };
    window.addEventListener('nav:member', onMember);
    if ((window as any).navGetMember?.()) load();
    return () => window.removeEventListener('nav:member', onMember);
  }, [load]);

  const act = useCallback(async (rpc: 'grant_public_map_consent' | 'dismiss_public_map_prompt') => {
    const sb = getSb();
    if (!sb) return;
    setState('busy');
    try {
      const args = rpc === 'grant_public_map_consent' ? { p_evidence: { surface: 'home_card', lang } } : {};
      const { data, error: e } = await sb.rpc(rpc, args);
      if (e || !data?.success) throw new Error(e?.message || 'failed');
      if (rpc === 'grant_public_map_consent') setState('done');
      else setPrompt({ show: false });
    } catch {
      setState('error');
    }
  }, [getSb, lang]);

  if (!prompt?.show) return null;

  if (state === 'done') {
    return (
      <div className="max-w-3xl mx-auto mt-4 px-4">
        <div className="rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800">{done}</div>
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto mt-4 px-4">
      <div className="rounded-xl border border-[var(--border-default)] bg-[var(--surface-card)] px-4 py-4 shadow-sm" data-testid="map-consent-nudge">
        <div className="text-sm font-bold text-navy mb-2">📍 {title}</div>
        <p className="text-[.78rem] text-[var(--text-primary)] leading-relaxed">{consentText}</p>
        {prompt.legacy_only && <p className="text-[.7rem] text-[var(--text-muted)] mt-2">{legacyNote}</p>}
        <div className="flex flex-wrap gap-2 mt-3">
          <button type="button" onClick={() => act('grant_public_map_consent')} disabled={state === 'busy'}
            className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold cursor-pointer border-0 disabled:opacity-50">
            {accept}
          </button>
          <button type="button" onClick={() => act('dismiss_public_map_prompt')} disabled={state === 'busy'}
            className="px-4 py-2 rounded-lg border border-[var(--border-default)] bg-transparent text-sm font-semibold cursor-pointer text-[var(--text-secondary)] disabled:opacity-50">
            {later}
          </button>
        </div>
        {state === 'error' && <p className="text-xs text-red-600 mt-2">{error}</p>}
      </div>
    </div>
  );
}
