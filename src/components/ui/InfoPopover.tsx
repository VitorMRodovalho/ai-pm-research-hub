import { useState, useRef, useEffect, useCallback, type CSSProperties, type ReactNode } from 'react';
import { createPortal } from 'react-dom';

interface InfoPopoverProps {
  trigger?: ReactNode;
  title: string;
  /** Horizontal anchor of the panel relative to the trigger (default 'left'). */
  align?: 'left' | 'right';
  children: ReactNode;
}

export default function InfoPopover({ trigger, title, align = 'left', children }: InfoPopoverProps) {
  const [open, setOpen] = useState(false);
  const [rect, setRect] = useState<DOMRect | null>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  // Anchor the panel to the trigger's viewport rect. Recomputed on open, scroll
  // and resize so the fixed-position panel tracks the icon.
  const updateRect = useCallback(() => {
    if (triggerRef.current) setRect(triggerRef.current.getBoundingClientRect());
  }, []);

  useEffect(() => {
    if (!open) return;
    updateRect();
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
    // capture=true so scrolling any ancestor container repositions the panel
    window.addEventListener('scroll', updateRect, true);
    window.addEventListener('resize', updateRect);
    return () => {
      document.removeEventListener('mousedown', handleClick);
      document.removeEventListener('keydown', handleEsc);
      window.removeEventListener('scroll', updateRect, true);
      window.removeEventListener('resize', updateRect);
    };
  }, [open, updateRect]);

  // Fixed positioning escapes every ancestor stacking context / overflow / transform
  // (the quadrant card's hover:-translate creates a stacking context that would
  // otherwise trap an absolutely-positioned panel below later siblings).
  const panelStyle: CSSProperties =
    rect
      ? {
          position: 'fixed',
          top: rect.bottom + 8,
          ...(align === 'right'
            ? { right: Math.max(8, window.innerWidth - rect.right) }
            : { left: Math.max(8, rect.left) }),
        }
      : { position: 'fixed', top: -9999, left: -9999 };

  const panel = (
    <div
      ref={popoverRef}
      role="dialog"
      aria-label={title}
      style={panelStyle}
      className="z-[100] w-[340px] max-w-[90vw]
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
  );

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

      {open && typeof document !== 'undefined' && createPortal(panel, document.body)}
    </span>
  );
}
