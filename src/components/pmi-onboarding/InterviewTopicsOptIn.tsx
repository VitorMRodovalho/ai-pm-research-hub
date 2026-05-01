import { useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';

interface Props {
  token: string;
  sb: SupabaseClient;
  areasToProbe: any[];
  T: (k: string) => string;
}

export default function InterviewTopicsOptIn({ token, sb, areasToProbe, T }: Props) {
  const [revealed, setRevealed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [skipped, setSkipped] = useState(false);

  if (!areasToProbe || areasToProbe.length === 0) return null;

  const handleReveal = async () => {
    setBusy(true);
    setError(null);
    try {
      const { error: rpcErr } = await sb.rpc('log_topic_view', {
        p_token: token,
        p_ip: null,
        p_ua: typeof navigator !== 'undefined' ? navigator.userAgent.substring(0, 500) : null,
      });
      if (rpcErr) throw new Error(rpcErr.message);
      setRevealed(true);
    } catch (e: any) {
      setError(e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  };

  if (skipped) {
    return (
      <div className="bg-slate-50 border border-slate-200 rounded-lg p-4 my-4">
        <p className="text-sm text-slate-700">
          <span className="font-semibold">{T('pmi.enrichment.topics.skippedTitle')}</span>
          {' '}— {T('pmi.enrichment.topics.skippedBody')}
        </p>
        <button
          type="button"
          onClick={() => setSkipped(false)}
          className="mt-2 text-xs text-slate-600 underline hover:text-slate-900"
        >
          {T('pmi.enrichment.topics.skippedReopen')}
        </button>
      </div>
    );
  }

  if (!revealed) {
    return (
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-5 my-4">
        <h3 className="text-base font-bold text-blue-900 mb-2">
          🔍 {T('pmi.enrichment.topics.title')}
        </h3>
        <p className="text-sm text-blue-800 mb-1">{T('pmi.enrichment.topics.body1')}</p>
        <p className="text-xs text-blue-700 mb-4">{T('pmi.enrichment.topics.body2')}</p>
        {error && <p className="text-sm text-red-700 mb-2">{error}</p>}
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={handleReveal}
            disabled={busy}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-bold hover:bg-blue-700 disabled:opacity-60 disabled:cursor-not-allowed"
          >
            {busy ? T('pmi.enrichment.topics.loading') : T('pmi.enrichment.topics.cta_show')}
          </button>
          <button
            type="button"
            onClick={() => setSkipped(true)}
            disabled={busy}
            className="px-4 py-2 bg-transparent text-blue-700 rounded-lg text-sm font-semibold border border-blue-300 hover:bg-blue-100 disabled:opacity-60"
          >
            {T('pmi.enrichment.topics.cta_skip')}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-blue-50 border border-blue-200 rounded-lg p-5 my-4">
      <h3 className="text-base font-bold text-blue-900 mb-3">
        🔍 {T('pmi.enrichment.topics.revealedTitle')}
      </h3>
      <ul className="space-y-2 mb-3">
        {areasToProbe.map((topic, i) => {
          const label = typeof topic === 'string' ? topic : (topic?.area || topic?.topic || JSON.stringify(topic));
          return (
            <li key={i} className="text-sm text-blue-900 bg-white rounded-md px-3 py-2 border border-blue-100">
              <span className="text-blue-600 font-semibold mr-2">{i + 1}.</span>
              <span>{label}</span>
            </li>
          );
        })}
      </ul>
      <p className="text-xs text-blue-700 italic">
        {T('pmi.enrichment.topics.disclaimer')}
      </p>
    </div>
  );
}
