import { useState, useRef, useEffect, type ReactNode } from 'react';

interface InfoPopoverProps {
  trigger?: ReactNode;
  title: string;
  children: ReactNode;
}

export default function InfoPopover({ trigger, title, children }: InfoPopoverProps) {
  const [open, setOpen] = useState(false);
  const popoverRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (
        popoverRef.current && !popoverRef.current.contains(e.target as Node) &&
        triggerRef.current && !triggerRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    }
    function handleEsc(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    document.addEventListener('keydown', handleEsc);
    return () => {
      document.removeEventListener('mousedown', handleClick);
      document.removeEventListener('keydown', handleEsc);
    };
  }, [open]);

  return (
    <span className="relative inline-flex items-center">
      <button
        ref={triggerRef}
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center justify-center w-5 h-5 rounded-full
          text-[11px] leading-none cursor-pointer border-0 bg-transparent
          text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-base)]
          transition-colors"
        aria-label={title}
        aria-expanded={open}
      >
        {trigger ?? 'ℹ️'}
      </button>

      {open && (
        <div
          ref={popoverRef}
          role="dialog"
          aria-label={title}
          className="absolute left-0 top-full mt-2 z-50 w-[340px] max-w-[90vw]
            bg-[var(--surface-card)] border border-[var(--border-default)]
            rounded-xl shadow-lg shadow-black/10 overflow-hidden"
        >
          <div className="flex items-center justify-between px-4 pt-3 pb-2">
            <span className="text-[13px] font-bold text-[var(--text-primary)]">{title}</span>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="w-5 h-5 flex items-center justify-center rounded-full
                text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-base)]
                cursor-pointer border-0 bg-transparent text-xs transition-colors"
              aria-label="Close"
            >
              ✕
            </button>
          </div>
          <div className="px-4 pb-4 max-h-[60vh] overflow-y-auto text-[12px] text-[var(--text-secondary)] leading-relaxed">
            {children}
          </div>
        </div>
      )}
    </span>
  );
}
