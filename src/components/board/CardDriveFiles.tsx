import { useState, useEffect } from 'react';
import { getSb } from '../../hooks/useBoard';

interface DriveFile {
  id: string;
  drive_file_id: string;
  drive_file_url: string;
  filename: string;
  mime_type?: string;
  size_bytes?: number | null;
  uploaded_by_name?: string;
  uploaded_via?: string;
  created_at: string;
}

interface Props {
  boardItemId: string;
}

function formatSize(bytes?: number | null): string {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function fileIcon(mimeType?: string): string {
  if (!mimeType) return '📄';
  if (mimeType.includes('pdf')) return '📕';
  if (mimeType.includes('document') || mimeType.includes('word')) return '📝';
  if (mimeType.includes('spreadsheet') || mimeType.includes('excel')) return '📊';
  if (mimeType.includes('presentation') || mimeType.includes('powerpoint')) return '📽️';
  if (mimeType.includes('image')) return '🖼️';
  if (mimeType.includes('video')) return '🎬';
  if (mimeType.includes('audio')) return '🎵';
  if (mimeType.includes('folder')) return '📁';
  return '📄';
}

export default function CardDriveFiles({ boardItemId }: Props) {
  const [files, setFiles] = useState<DriveFile[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const sb = getSb();
      if (!sb) { setLoading(false); return; }
      const { data } = await sb.rpc('list_card_drive_files', { p_board_item_id: boardItemId });
      if (cancelled) return;
      const arr = data?.files ?? [];
      setFiles(Array.isArray(arr) ? arr : []);
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, [boardItemId]);

  if (loading) {
    return (
      <div>
        <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-2 block">📁 Drive Files</label>
        <div className="text-[11px] text-[var(--text-muted)]">Carregando...</div>
      </div>
    );
  }

  if (files.length === 0) return null;

  return (
    <div>
      <label className="text-[11px] font-semibold text-[var(--text-secondary)] mb-2 block">
        📁 Drive Files ({files.length})
      </label>
      <div className="space-y-1">
        {files.map((f) => (
          <a
            key={f.id}
            href={f.drive_file_url}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 px-2 py-1.5 rounded-lg bg-[var(--surface-section-cool)] hover:bg-[var(--surface-hover)]
              text-[11px] text-[var(--text-primary)] no-underline transition-colors"
          >
            <span className="text-base">{fileIcon(f.mime_type)}</span>
            <span className="flex-1 truncate font-medium">{f.filename}</span>
            <span className="text-[10px] text-[var(--text-muted)]">{formatSize(f.size_bytes)}</span>
            {f.uploaded_via === 'drive_native_synced' && (
              <span className="text-[9px] px-1 py-0.5 rounded bg-blue-50 text-blue-700">drive</span>
            )}
          </a>
        ))}
      </div>
    </div>
  );
}
