import React, { useEffect, useState, useCallback } from 'react';
import { Command } from 'cmdk';
import { Search } from 'lucide-react';

type SearchResult = {
  chunk_id: string;
  content_snippet: string;
  asset_id: string;
  artifact_id: string;
  tribe_name: string;
  theme_title: string;
};

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return debouncedValue;
}

export default function GlobalSearchIsland() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const debouncedQuery = useDebounce(query, 300);

  const runSearch = useCallback(async (term: string) => {
    const windowRef = globalThis as Window & { navGetSb?: () => { auth: { getSession: () => Promise<{ data: { session: { access_token: string } | null } }> } } };
    const sb = windowRef?.navGetSb?.();
    if (!sb || term.length < 2) {
      setResults([]);
      return;
    }
    setLoading(true);
    try {
      const { data: session } = await sb.auth.getSession();
      const token = session?.session?.access_token;
      if (!token) {
        setResults([]);
        return;
      }
      const res = await fetch(`/api/search?q=${encodeURIComponent(term)}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const json = await res.json();
      setResults(Array.isArray(json.results) ? json.results : []);
    } catch {
      setResults([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (debouncedQuery.length >= 2) {
      runSearch(debouncedQuery);
    } else {
      setResults([]);
    }
  }, [debouncedQuery, runSearch]);

  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      e.preventDefault();
      setOpen((prev) => !prev);
    }
    if (e.key === 'Escape') setOpen(false);
  }, []);

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  return (
    <>
      <button
        type="button"
        data-action="open-global-search"
        onClick={() => setOpen(true)}
        className="flex items-center gap-2 px-2 py-1.5 rounded-lg text-[.73rem] font-medium text-white/80 hover:text-white hover:bg-white/10 transition-all"
        title="Buscar... (⌘K)"
      >
        <Search size={14} />
        <span>Buscar... (⌘K)</span>
      </button>
      {open && (
        <div
          className="fixed inset-0 z-[600] bg-black/40 flex items-start justify-center pt-[15vh]"
          onClick={() => setOpen(false)}
          onKeyDown={(e) => e.key === 'Escape' && setOpen(false)}
          role="presentation"
        >
          <div
            className="w-full max-w-xl rounded-2xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
            onKeyDown={(e) => e.key === 'Escape' && setOpen(false)}
            role="dialog"
            aria-label="Busca global"
          >
            <Command
              className="[&_[cmdk-input]]:h-12 [&_[cmdk-input]]:px-4 [&_[cmdk-input]]:text-[15px] [&_[cmdk-input]]:border-0 [&_[cmdk-input]]:focus:ring-0"
              shouldFilter={false}
            >
              <Command.Input
                placeholder="Buscar em pesquisas e conhecimento..."
                value={query}
                onValueChange={setQuery}
                autoFocus
              />
              <Command.List className="max-h-[320px] overflow-y-auto p-2">
                {loading && (
                  <div className="py-6 text-center text-slate-500 text-sm">Buscando...</div>
                )}
                {!loading && query.length >= 2 && results.length === 0 && (
                  <div className="py-6 text-center text-slate-500 text-sm">Nenhum resultado encontrado.</div>
                )}
                {!loading &&
                  results.map((r) => (
                    <Command.Item
                      key={r.chunk_id}
                      value={r.chunk_id}
                      className="flex flex-col items-stretch gap-1 px-3 py-2 rounded-lg cursor-pointer data-[selected=true]:bg-slate-100 dark:data-[selected=true]:bg-slate-800 data-[selected=true]:outline-none"
                    >
                      <div className="text-[13px] font-semibold text-slate-900 dark:text-slate-100 truncate">
                        {r.theme_title || 'Sem título'}
                      </div>
                      <div className="text-[12px] text-slate-600 dark:text-slate-400 line-clamp-2">
                        {r.content_snippet}
                      </div>
                      {r.tribe_name && (
                        <div className="text-[11px] text-slate-500 dark:text-slate-500">
                          {r.tribe_name}
                        </div>
                      )}
                    </Command.Item>
                  ))}
              </Command.List>
            </Command>
          </div>
        </div>
      )}
    </>
  );
}
