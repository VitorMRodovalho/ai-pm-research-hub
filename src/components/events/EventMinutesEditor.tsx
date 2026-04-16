import { useState, useCallback, useMemo } from 'react';
import { marked } from 'marked';
import RichTextEditor from '../shared/RichTextEditor';

// Convert legacy markdown content to HTML so tiptap renders it with formatting.
// Heuristic: if content has no block-level HTML tags, treat as markdown.
function normalizeContent(raw: string): string {
  if (!raw) return '';
  const hasBlockHtml = /<(p|h[1-6]|ul|ol|li|blockquote|pre|hr|img|strong|em|a)\b/i.test(raw);
  if (hasBlockHtml) return raw;
  try {
    return marked.parse(raw, { async: false }) as string;
  } catch {
    return raw;
  }
}

interface EventMinutesEditorProps {
  eventId: string;
  eventTitle: string;
  mode: 'minutes' | 'agenda';
  initialContent?: string;
  initialUrl?: string;
  onSave: () => void;
  onClose: () => void;
}

export function EventMinutesEditor({
  eventId,
  eventTitle,
  mode,
  initialContent = '',
  initialUrl = '',
  onSave,
  onClose,
}: EventMinutesEditorProps) {
  const normalizedInitial = useMemo(() => normalizeContent(initialContent), [initialContent]);
  const [content, setContent] = useState(normalizedInitial);
  const [url, setUrl] = useState(initialUrl);
  const [saving, setSaving] = useState(false);

  const isMinutes = mode === 'minutes';
  const title = isMinutes
    ? (initialContent ? 'Editar ata' : 'Adicionar ata')
    : (initialContent ? 'Editar pauta' : 'Adicionar pauta');
  const placeholder = isMinutes
    ? 'Escreva a ata da reunião...'
    : 'Escreva a pauta da reunião...';

  const handleSave = useCallback(async () => {
    setSaving(true);
    try {
      const sb = (window as any).navGetSb?.();
      if (!sb) throw new Error('No connection');

      const rpcName = isMinutes ? 'upsert_event_minutes' : 'upsert_event_agenda';
      const { data, error } = await sb.rpc(rpcName, {
        p_event_id: eventId,
        p_text: content || null,
        p_url: url.trim() || null,
      });

      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      (window as any).toast?.(
        isMinutes ? 'Ata salva com sucesso!' : 'Pauta salva com sucesso!',
        'success'
      );
      onSave();
      onClose();
    } catch (e: any) {
      (window as any).toast?.(e.message || 'Erro ao salvar', 'error');
    } finally {
      setSaving(false);
    }
  }, [eventId, content, url, isMinutes, onSave, onClose]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') onClose();
  };

  return (
    <div
      id="event-editor-modal"
      className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      onKeyDown={handleKeyDown}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        className="bg-[var(--surface-elevated,#fff)] rounded-2xl border border-[var(--border-default)] shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-[var(--border-default)]">
          <div>
            <h3 className="text-base font-bold text-navy">
              {isMinutes ? '📝' : '📋'} {title}
            </h3>
            <p className="text-xs text-[var(--text-muted)] mt-0.5">{eventTitle}</p>
          </div>
          <button
            onClick={onClose}
            className="text-[var(--text-muted)] hover:text-[var(--text-primary)] cursor-pointer border-0 bg-transparent text-xl"
          >
            ✕
          </button>
        </div>

        {/* Editor */}
        <div className="px-5 py-4 space-y-4">
          <RichTextEditor
            content={content}
            onChange={setContent}
            placeholder={placeholder}
            minHeight="260px"
            toolbar="full"
          />

          {/* URL field */}
          <div>
            <label className="block text-xs font-bold text-[var(--text-secondary)] mb-1">
              📎 Link do documento (opcional)
            </label>
            <input
              type="url"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder="https://drive.google.com/..."
              className="w-full px-3 py-2 text-sm rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-teal-500/40"
            />
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-2 px-5 py-3 border-t border-[var(--border-default)]">
          <button
            onClick={onClose}
            className="px-4 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-base)] text-[var(--text-secondary)] text-sm font-semibold cursor-pointer hover:bg-[var(--surface-hover)] transition-colors"
          >
            Cancelar
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="px-4 py-2 rounded-lg bg-navy text-white text-sm font-semibold cursor-pointer border-0 hover:opacity-90 disabled:opacity-50 transition-colors"
          >
            {saving ? '...' : `💾 ${isMinutes ? 'Salvar ata' : 'Salvar pauta'}`}
          </button>
        </div>
      </div>
    </div>
  );
}
