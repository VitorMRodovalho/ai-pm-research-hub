import type { CellStatus } from './types';

interface AttendanceCellProps {
  status: CellStatus;
  canToggle: boolean;
  isSelf: boolean;
  canSelfCheckIn: boolean;
  isWithinWindow: boolean;
  onToggle: () => void;
  onCheckIn: () => void;
  loading?: boolean;
}

export function AttendanceCell({
  status,
  canToggle,
  isSelf,
  canSelfCheckIn,
  isWithinWindow,
  onToggle,
  onCheckIn,
  loading = false,
}: AttendanceCellProps) {
  if (status === 'na' || status === 'scheduled') {
    return <span className="text-gray-400 select-none" title={status === 'scheduled' ? 'Evento agendado' : ''}>{status === 'scheduled' ? '📅' : '—'}</span>;
  }

  if (isSelf && canSelfCheckIn && status === 'absent' && isWithinWindow) {
    return (
      <button
        onClick={onCheckIn}
        disabled={loading}
        className="text-[.65rem] px-1.5 py-0.5 rounded bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 transition-colors font-semibold"
      >
        {loading ? '...' : '✓'}
      </button>
    );
  }

  if (isSelf && canSelfCheckIn && status === 'absent' && !isWithinWindow) {
    return <span className="text-red-400 select-none">❌</span>;
  }

  if (canToggle) {
    return (
      <button
        onClick={onToggle}
        disabled={loading}
        className={`w-7 h-7 rounded cursor-pointer transition-all hover:scale-110 disabled:opacity-50 border-0 bg-transparent ${
          status === 'present' ? 'text-green-500' : status === 'excused' ? 'text-yellow-500' : 'text-red-400'
        }`}
        title={status === 'present' ? 'Presente → clique para remover' : 'Ausente → clique para marcar'}
      >
        {loading ? '⏳' : status === 'present' ? '✅' : status === 'excused' ? '⚠️' : '❌'}
      </button>
    );
  }

  return (
    <span className={`select-none ${
      status === 'present' ? 'text-green-500' :
      status === 'excused' ? 'text-yellow-500' : 'text-red-400'
    }`}>
      {status === 'present' ? '✅' : status === 'excused' ? '⚠️' : '❌'}
    </span>
  );
}
