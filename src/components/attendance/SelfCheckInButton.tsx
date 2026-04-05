import { useState } from 'react';
import { usePageI18n } from '../../i18n/usePageI18n';

interface SelfCheckInButtonProps {
  eventId: string;
  eventTitle: string;
  onCheckIn: (eventId: string) => Promise<{ success: boolean; message?: string }>;
}

export function SelfCheckInButton({ eventId, eventTitle, onCheckIn }: SelfCheckInButtonProps) {
  const t = usePageI18n();
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<'idle' | 'success' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState('');

  const handleClick = async () => {
    setLoading(true);
    const res = await onCheckIn(eventId);
    setLoading(false);

    if (res.success) {
      setResult('success');
    } else {
      setResult('error');
      setErrorMsg(res.message || t('comp.attendance.errorRegister', 'Erro ao registrar presença'));
    }
  };

  if (result === 'success') {
    return <span className="text-green-500 text-sm font-semibold">{t('comp.attendance.selfCheckedIn', '✅ Presença registrada')}</span>;
  }

  return (
    <div className="inline-flex flex-col">
      <button
        onClick={handleClick}
        disabled={loading}
        className="px-3 py-1.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 text-xs font-semibold transition-colors border-0 cursor-pointer"
      >
        {loading ? '...' : `Check-in: ${eventTitle}`}
      </button>
      {result === 'error' && (
        <p className="text-red-400 text-[.65rem] mt-1">{errorMsg}</p>
      )}
    </div>
  );
}
