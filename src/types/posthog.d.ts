declare global {
  interface Window {
    posthog?: {
      capture: (event: string, properties?: Record<string, unknown>) => void;
      identify: (id: string, properties?: Record<string, unknown>) => void;
    };
    __nucleoTrack?: (event: string, properties?: Record<string, unknown>) => void;
    __nucleoAnalyticsSanitize?: (properties?: Record<string, unknown>) => Record<string, unknown>;
  }
}
export {};
