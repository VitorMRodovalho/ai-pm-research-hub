// #2842: cada aparelho com push na conta, com a data do ultimo aviso entregue. Antes a tela so mostrava a contagem,
// e uma inscricao que o navegador ja tinha derrubado contava como ativa ate o proximo envio apaga-la.
//
// Le o que list_my_push_subscriptions devolve (sem o endpoint, que nunca sai do banco para a tela). Sem import: o
// guard chama estas funcoes direto.

export type PushDeviceRow = {
  user_agent?: string | null;
  created_at?: string | null;
  last_success_at?: string | null;
  disabled_at?: string | null;
};

export type PushDeviceLabels = {
  /** com `{browser}` e `{os}` */
  device: string;
  unknown: string;
  /** com `{date}` */
  lastSuccess: string;
  never: string;
  /** com `{date}` */
  disabled: string;
};

// A ordem importa: o Edge e o Samsung Internet tambem dizem "Chrome", e o Chrome tambem diz "Safari".
const BROWSERS: [RegExp, string][] = [
  [/\bEdg(?:e|A|iOS)?\//, 'Edge'],
  [/\bSamsungBrowser\//, 'Samsung Internet'],
  [/\b(?:Firefox|FxiOS)\//, 'Firefox'],
  [/\b(?:Chrome|CriOS)\//, 'Chrome'],
  [/\bSafari\//, 'Safari'],
];
const SYSTEMS: [RegExp, string][] = [
  [/\bAndroid\b/, 'Android'],
  [/\b(?:iPhone|iPad|iPod)\b/, 'iOS'],
  [/\bWindows\b/, 'Windows'],
  [/\bCrOS\b/, 'ChromeOS'],
  [/\bMac OS X\b/, 'macOS'],
  [/\bLinux\b/, 'Linux'],
];

function firstMatch(table: [RegExp, string][], ua: string): string | null {
  for (const [re, name] of table) if (re.test(ua)) return name;
  return null;
}

export function deviceName(userAgent: string | null | undefined, labels: PushDeviceLabels): string {
  const ua = String(userAgent ?? '');
  const browser = firstMatch(BROWSERS, ua);
  const os = firstMatch(SYSTEMS, ua);
  if (!browser && !os) return labels.unknown;
  if (!browser || !os) return (browser ?? os) as string;
  return labels.device.replace('{browser}', browser).replace('{os}', os);
}

/** Um aparelho por linha: nome e situacao. `formatDate` vem da pagina, no idioma dela. */
export function describePushDevice(
  row: PushDeviceRow,
  labels: PushDeviceLabels,
  formatDate: (iso: string) => string,
): string {
  const name = deviceName(row.user_agent, labels);
  const status = row.disabled_at
    ? labels.disabled.replace('{date}', formatDate(row.disabled_at))
    : row.last_success_at
      ? labels.lastSuccess.replace('{date}', formatDate(row.last_success_at))
      : labels.never;
  return `${name} · ${status}`;
}

/** Ativo e o que o envio ainda tenta: sem disabled_at. */
export function activePushDeviceCount(rows: PushDeviceRow[]): number {
  return rows.filter((r) => !r.disabled_at).length;
}
