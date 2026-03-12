interface Toast { id: number; message: string; type: 'success' | 'error' }

export default function ToastContainer({ toasts }: { toasts: Toast[] }) {
  if (toasts.length === 0) return null;
  return (
    <div className="fixed bottom-4 right-4 z-[700] flex flex-col gap-2">
      {toasts.map((t) => (
        <div key={t.id}
          className={`px-4 py-2.5 rounded-xl text-[12px] font-semibold shadow-lg
            ${t.type === 'success' ? 'bg-emerald-600 text-white' : 'bg-red-600 text-white'}`}
          style={{ animation: 'slideIn 0.3s ease-out' }}>
          {t.type === 'success' ? '✅ ' : '❌ '}{t.message}
        </div>
      ))}
    </div>
  );
}
