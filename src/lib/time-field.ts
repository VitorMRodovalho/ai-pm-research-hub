/**
 * time-field — SSOT para campo de HORÁRIO em 24h, independente do locale do navegador (#1645).
 *
 * Por que existe: os campos de horário da agenda eram `<input type="time">`. Esse controle
 * nativo renderiza segundo o locale do NAVEGADOR, não o da página. Em navegador `en-US` ele
 * vira um widget de 12 horas com segmento AM/PM — e aí:
 *
 *   1. O hint da plataforma diz "Horário de Brasília (BRT)" e o placeholder é "19:00", um
 *      formato que aquele widget nunca aceita. (`placeholder` é ignorado em `type="time"`,
 *      então a dica sequer aparece.) Foi o relato literal do líder da Tribo 14 em 06/08/2026:
 *      "só aceita até 12".
 *   2. Pior: com QUALQUER segmento em branco, `value` é string vazia e `validity.badInput` é
 *      `true` — o NAVEGADOR bloqueia o submit antes do evento `submit`. Medido em Chromium
 *      `en-US` sobre a `/attendance` de produção:
 *
 *        digitar 7,0,0 (sem tocar no AM/PM) → value ""     badInput true   form bloqueado
 *        digitar 7,0,0,p                    → value "19:00" badInput false  form OK
 *        digitar 1,9 (tentando "19")        → value ""     badInput true   form bloqueado
 *
 *      Como o bloqueio é nativo, `createRecurring()` nunca roda e NENHUM toast nosso aparece.
 *      O usuário vê só o balão do navegador e conclui que a plataforma está quebrada.
 *
 * A escolha aqui: `type="text"` com `inputmode="numeric"`, máscara de dois pontos e
 * normalização no blur. Sempre 24h, em qualquer locale, casando com o que o hint promete.
 *
 * Deliberadamente SEM `pattern`: `pattern` devolveria exatamente o defeito que este módulo
 * existe para matar — validação nativa que bloqueia o submit com balão do navegador e sem
 * mensagem nossa. A validação é feita em JS por `readTimeField`, que devolve `invalid` para
 * o chamador transformar em toast da plataforma.
 */

/** Formato que a plataforma fala com o banco (`events.time_start`, tipo `time`). */
const HHMM = /^([01]\d|2[0-3]):([0-5]\d)$/;

/**
 * Converte entrada tolerante em `HH:MM` 24h, ou devolve `null` se não der para interpretar.
 *
 * Aceita, porque são as formas que aparecem na prática:
 *   - `"19:00"`                     → `"19:00"`  (já canônico)
 *   - `"19:00:00"`                  → `"19:00"`  (o que vem do banco: `time` serializa com segundos)
 *   - `"1900"` / `"930"` / `"9"`    → `"19:00"` / `"09:30"` / `"09:00"`
 *   - `"9:5"`, `" 19 : 00 "`        → `"09:05"`, `"19:00"`
 *
 * Recusa (devolve `null`) hora ≥ 24 ou minuto ≥ 60. `""` também devolve `null`, e o chamador
 * distingue os dois casos: horário é OPCIONAL, então vazio não pode ser tratado como erro.
 */
export function normalizeTime(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  if (s === '') return null;

  // Caminho com separador: aceita ":" ou "." e ignora espaço em volta.
  const parts = s.split(/[:.]/);
  if (parts.length >= 2) {
    const h = parts[0].trim();
    const m = parts[1].trim();
    if (!/^\d{1,2}$/.test(h) || !/^\d{1,2}$/.test(m)) return null;
    return pad(h, m);
  }

  // Caminho só-dígitos: 9 → 09:00, 930 → 09:30, 1900 → 19:00.
  if (!/^\d{1,4}$/.test(s)) return null;
  if (s.length <= 2) return pad(s, '0');
  const cut = s.length - 2;
  return pad(s.slice(0, cut), s.slice(cut));
}

function pad(hRaw: string, mRaw: string): string | null {
  const h = Number(hRaw);
  const m = Number(mRaw);
  if (!Number.isInteger(h) || !Number.isInteger(m)) return null;
  if (h > 23 || m > 59) return null;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

/**
 * Troca um `<input type="time">` pelo controle 24h. Idempotente: chamar duas vezes no mesmo
 * elemento não duplica listener (guardado por `dataset.time24`).
 */
export function upgradeTimeField(el: HTMLInputElement | null): void {
  if (!el || el.dataset.time24 === '1') return;
  el.dataset.time24 = '1';

  // O valor tem de ser lido ANTES de mexer no type: trocar o type de um input de data/hora
  // descarta o valor no navegador.
  const initial = normalizeTime(el.value);

  el.type = 'text';
  el.inputMode = 'numeric';
  el.maxLength = 5;
  el.autocomplete = 'off';
  if (!el.placeholder) el.placeholder = '19:00';
  el.setAttribute('aria-label', el.getAttribute('aria-label') || 'Horário (24h, HH:MM)');
  el.value = initial ?? '';

  // Máscara enquanto digita: só dígito e ":", e o ":" entra sozinho depois da hora. Não
  // normaliza aqui — normalizar no meio da digitação rouba o cursor do usuário.
  el.addEventListener('input', () => {
    const digits = el.value.replace(/\D/g, '').slice(0, 4);
    el.value = digits.length <= 2 ? digits : `${digits.slice(0, 2)}:${digits.slice(2)}`;
  });

  // No blur, canoniza o que dá para canonizar e deixa intacto o que não dá — apagar a
  // digitação do usuário esconderia o erro em vez de mostrá-lo.
  el.addEventListener('blur', () => {
    const norm = normalizeTime(el.value);
    if (norm) el.value = norm;
  });
}

/** Escreve um horário no campo já canonizado (aceita o `HH:MM:SS` que vem do banco). */
export function setTimeField(el: HTMLInputElement | null, value: unknown): void {
  if (!el) return;
  el.value = normalizeTime(value) ?? '';
}

/**
 * Lê o campo para mandar ao banco.
 *
 * `{ time: null, invalid: false }` = campo vazio, que é LEGÍTIMO (horário é opcional; o
 * chamador manda `null` e o padrão da tribo vale).
 * `{ time: null, invalid: true }`  = tem texto e não é horário → o chamador mostra o toast.
 */
export function readTimeField(el: HTMLInputElement | null): { time: string | null; invalid: boolean } {
  if (!el) return { time: null, invalid: false };
  const raw = el.value.trim();
  if (raw === '') return { time: null, invalid: false };
  const norm = normalizeTime(raw);
  if (!norm || !HHMM.test(norm)) return { time: null, invalid: true };
  return { time: norm, invalid: false };
}
