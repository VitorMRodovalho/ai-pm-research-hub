import { useState, useCallback } from 'react';
import { EventMinutesEditor } from './EventMinutesEditor';

/**
 * React island that listens for custom events to open the minutes/agenda editor.
 * Mounted once in the tribe page; opened via:
 *   window.dispatchEvent(new CustomEvent('open-event-editor', { detail: { ... } }))
 */
export default function EventMinutesIsland() {
  const [state, setState] = useState<{
    eventId: string;
    eventTitle: string;
    mode: 'minutes' | 'agenda';
    initialContent: string;
    initialUrl: string;
  } | null>(null);

  // Listen for open-event-editor custom event
  if (typeof window !== 'undefined') {
    window.addEventListener('open-event-editor', ((e: CustomEvent) => {
      setState(e.detail);
    }) as EventListener, { once: false });
  }

  const handleSave = useCallback(() => {
    // Dispatch event so the Astro script can refresh timeline
    window.dispatchEvent(new CustomEvent('event-editor-saved'));
  }, []);

  if (!state) return null;

  return (
    <EventMinutesEditor
      eventId={state.eventId}
      eventTitle={state.eventTitle}
      mode={state.mode}
      initialContent={state.initialContent}
      initialUrl={state.initialUrl}
      onSave={handleSave}
      onClose={() => setState(null)}
    />
  );
}
