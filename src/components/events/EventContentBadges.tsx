interface EventContentBadgesProps {
  hasMinutes: boolean;
  hasRecording: boolean;
  hasAgenda: boolean;
}

export function EventContentBadges({ hasMinutes, hasRecording, hasAgenda }: EventContentBadgesProps) {
  if (!hasMinutes && !hasRecording && !hasAgenda) return null;

  return (
    <div className="flex flex-wrap gap-1.5 mt-1">
      {hasMinutes && (
        <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[.6rem] font-semibold bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400" title="Ata disponível">
          📝 Ata
        </span>
      )}
      {hasRecording && (
        <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[.6rem] font-semibold bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400" title="Gravação disponível">
          🎥 Gravação
        </span>
      )}
      {hasAgenda && (
        <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[.6rem] font-semibold bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400" title="Pauta disponível">
          📋 Pauta
        </span>
      )}
    </div>
  );
}
