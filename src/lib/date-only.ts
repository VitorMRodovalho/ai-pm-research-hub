/**
 * #1501 — parsing e formatação de colunas `date` (sem hora) do Postgres.
 *
 * O problema: `new Date('2026-07-27')` segue a regra do ES para strings ISO
 * **date-only** e produz MEIA-NOITE UTC. Em qualquer fuso negativo (o Brasil é
 * UTC-3) isso retrocede para o dia anterior assim que é formatado ou comparado
 * no fuso local:
 *
 *   new Date('2026-07-27')            -> 2026-07-27T00:00:00Z
 *   em America/Sao_Paulo              -> 2026-07-26 21:00
 *   toLocaleDateString('pt-BR')       -> "26/07/2026"   <- um dia a menos
 *
 * Colunas `timestamptz` (completed_at, created_at, curation_due_at, ...) NÃO
 * sofrem disso: elas carregam instante e offset, e `new Date()` é o tratamento
 * correto. Este módulo é só para as colunas `date`:
 * board_items.{due_date,baseline_date,forecast_date,actual_completion_date} e
 * board_item_checklists.target_date.
 *
 * #1511 — a varredura estendeu o helper a todo o repo (widgets, atas, fila de
 * filiação, perfil, publicações, admin de seleção, RSS). A forma proibida e a
 * forma certa, lado a lado, para o próximo leitor:
 *
 *   ERRADO:  new Date(item.due_date)          <- meia-noite UTC, recua um dia
 *   CERTO:   parseDateOnly(item.due_date)     <- meia-noite local
 *
 * O guard `tests/contracts/1511-date-only-sweep-repo-wide.test.mjs` varre o repo
 * atrás da forma errada. Ele lê o fonte SEM COMENTÁRIOS justamente para que este
 * bloco (e qualquer prosa que cite o anti-padrão) não vire um falso positivo.
 */

/**
 * #1511 — discriminador para as superfícies que recebem as DUAS famílias no mesmo
 * campo (o caso `application_date || created_at`): só 'YYYY-MM-DD' exato é coluna
 * `date`. Qualquer coisa com hora é instante e deve seguir em `new Date()`, porque
 * aplicar o parse date-only nela trocaria o dia em fuso negativo — a regressão
 * inversa da descrita no #1501.
 */
export function isDateOnlyString(value: unknown): boolean {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

/** Aceita 'YYYY-MM-DD' (com ou sem sufixo de hora) e devolve meia-noite LOCAL. */
export function parseDateOnly(value: string | Date | null | undefined): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  // Sem o formato date-only esperado, cai no parser padrão em vez de silenciar o dado.
  if (!m) {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

/** Formata uma coluna `date` no fuso local, sem o deslocamento de um dia. */
export function formatDateOnly(
  value: string | Date | null | undefined,
  options: Intl.DateTimeFormatOptions = {},
  locale = 'pt-BR',
): string {
  const d = parseDateOnly(value);
  return d ? d.toLocaleDateString(locale, options) : '';
}

/**
 * Uma coluna `date` só está atrasada depois de vencer o DIA INTEIRO no fuso
 * local. Comparar `parseDateOnly(x) < new Date()` marcaria como atrasado algo
 * que vence hoje já a 00:00:01, que é o segundo defeito descrito no #1501.
 */
export function isOverdueDateOnly(
  value: string | Date | null | undefined,
  now: Date = new Date(),
): boolean {
  const d = parseDateOnly(value);
  if (!d) return false;
  const endOfDay = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
  return endOfDay.getTime() < now.getTime();
}

/**
 * #1511 — distância em DIAS DE CALENDÁRIO local até uma coluna `date`
 * (0 = vence hoje, negativo = passou). Substitui
 * `Math.ceil((new Date(col) - Date.now()) / 86400000)`, que herda o parse UTC
 * e ainda mistura hora do dia com contagem de dias: às 21h de UTC-3 aquela
 * conta já devolvia -1 para uma data que vence hoje.
 *
 * A subtração é feita em UTC sobre os componentes Y/M/D justamente para não
 * perder um dia em fronteira de horário de verão.
 */
export function daysUntilDateOnly(
  value: string | Date | null | undefined,
  now: Date = new Date(),
): number | null {
  const d = parseDateOnly(value);
  if (!d) return null;
  const target = Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
  const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((target - today) / 86400000);
}
