interface Props {
  stats: any;
  t: (key: string, fallback?: string) => string;
}

const CARDS = [
  { key: 'total', field: 'total', color: 'bg-gray-100 text-gray-700 border-gray-200', darkColor: 'dark:bg-gray-800 dark:text-gray-300 dark:border-gray-700' },
  { key: 'pending', field: 'pending_review', color: 'bg-blue-50 text-blue-700 border-blue-200', darkColor: 'dark:bg-blue-900/30 dark:text-blue-300 dark:border-blue-800' },
  { key: 'approved', field: 'approved_not_implemented', color: 'bg-green-50 text-green-700 border-green-200', darkColor: 'dark:bg-green-900/30 dark:text-green-300 dark:border-green-800' },
  { key: 'implemented', field: 'implemented', color: 'bg-emerald-50 text-emerald-700 border-emerald-200', darkColor: 'dark:bg-emerald-900/30 dark:text-emerald-300 dark:border-emerald-800' },
  { key: 'rejected', field: null, color: 'bg-red-50 text-red-700 border-red-200', darkColor: 'dark:bg-red-900/30 dark:text-red-300 dark:border-red-800' },
  { key: 'withdrawn', field: 'withdrawn', color: 'bg-gray-50 text-gray-500 border-gray-200', darkColor: 'dark:bg-gray-800/50 dark:text-gray-400 dark:border-gray-700' },
];

export default function GovernanceStats({ stats, t }: Props) {
  if (!stats) return null;

  const getValue = (card: typeof CARDS[0]) => {
    if (card.field) return stats[card.field] ?? 0;
    // rejected comes from by_status
    return stats.by_status?.rejected ?? 0;
  };

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
      {CARDS.map(card => (
        <div key={card.key}
          className={`rounded-xl border px-4 py-3 text-center ${card.color}`}>
          <div className="text-2xl font-extrabold">{getValue(card)}</div>
          <div className="text-[11px] font-semibold uppercase tracking-wider mt-0.5">
            {t(`governance.stats_${card.key}`, card.key)}
          </div>
        </div>
      ))}
    </div>
  );
}
