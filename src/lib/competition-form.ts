// #2529 / ADR-0133 — the public competition registration form, shared by the registration page and the
// page the e-mail link opens (confirm, correct, withdraw). The edition's form version decides which fields
// appear, their labels per language and which are required; the fixed order below is the one the database
// validates (competition.normalize_answers). Client checks mirror a few server ones only to spare a round
// trip: the server is the authority, and its error codes are the ones used here.

export type Lang = 'pt-BR' | 'en-US' | 'es-LATAM';
type Loc = Partial<Record<Lang, string>>;
export type FieldDef = { label?: Loc; required?: boolean; help?: Loc; options?: { value: string; label?: Loc }[] };
export type Declaration = { key: string; version: number; required?: boolean; text?: Loc };
export type FormVersion = { version: number; fields: Record<string, FieldDef>; declarations: Declaration[] };
export type Problem = { code: string; field?: string | null };

export const FIELD_ORDER = [
  'full_name', 'social_name', 'email', 'email_confirm', 'institution', 'course', 'team_name', 'is_leader',
  'leader_email', 'technical_profile', 'technical_area', 'github_username', 'origin', 'heard_from',
] as const;
const BOOLEAN_FIELDS = new Set(['is_leader', 'technical_profile']);
const EMAIL_FIELDS = new Set(['email', 'email_confirm', 'leader_email']);
// Same pattern as the database (lower-cased before the test).
const EMAIL_RE = /^[a-z0-9._%+-]{1,64}@([a-z0-9-]+\.)+[a-z]{2,63}$/;

export const esc = (s: unknown) => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const pick = (loc: Loc | undefined, lang: Lang, fallback: string) => (loc?.[lang] || loc?.['pt-BR'] || fallback);

/** The label a field shows, from the form version or the dictionary. */
export const fieldLabel = (form: FormVersion, key: string, lang: Lang, t: (k: string) => string) =>
  pick(form.fields[key]?.label, lang, t(`competition.field.${key}`));

const INPUT = 'mt-1 w-full px-3 py-2 rounded-lg border border-[var(--border-default)] bg-[var(--surface-input)] text-sm text-[var(--text-primary)] focus:outline-none focus:border-navy';
const LABEL = 'text-sm font-semibold text-[var(--text-secondary)]';

/**
 * Renders the fields the form version declares, in the validated order, plus the declarations.
 * With `emailShown`, the e-mail is shown as text (it cannot change after registering) and the
 * declarations are left out (they were accepted at registration).
 */
export function renderForm(form: FormVersion, lang: Lang, t: (k: string) => string, values: Record<string, unknown> = {}, opts: { emailShown?: string } = {}): string {
  const parts: string[] = [];
  const editing = opts.emailShown !== undefined;
  for (const key of FIELD_ORDER) {
    const def = form.fields[key];
    if (!def) continue;
    if (editing && key === 'email_confirm') continue;
    const label = esc(fieldLabel(form, key, lang, t));
    const req = def.required ? ' <span class="text-red-600" aria-hidden="true">*</span>' : '';
    const help = def.help ? `<span class="block text-[.72rem] text-[var(--text-muted)]">${esc(pick(def.help, lang, ''))}</span>` : '';
    if (editing && key === 'email') {
      parts.push(`<div data-field="email"><span class="${LABEL}">${label}</span>
        <p class="mt-1 text-sm text-[var(--text-primary)]">${esc(opts.emailShown)}</p></div>`);
    } else if (BOOLEAN_FIELDS.has(key)) {
      const v = values[key];
      parts.push(`<fieldset class="block" data-field="${key}"><legend class="${LABEL}">${label}${req}</legend>${help}
        <label class="mr-4 text-sm"><input type="radio" name="${key}" value="true" ${v === true ? 'checked' : ''}> ${esc(t('competition.yes'))}</label>
        <label class="text-sm"><input type="radio" name="${key}" value="false" ${v === false ? 'checked' : ''}> ${esc(t('competition.no'))}</label></fieldset>`);
    } else if (def.options?.length) {
      const opt = def.options.map((o) => `<option value="${esc(o.value)}" ${values[key] === o.value ? 'selected' : ''}>${esc(pick(o.label, lang, o.value))}</option>`).join('');
      parts.push(`<label class="block" data-field="${key}"><span class="${LABEL}">${label}${req}</span>${help}
        <select name="${key}" class="${INPUT}"><option value="">${esc(t('competition.choose'))}</option>${opt}</select></label>`);
    } else {
      const type = EMAIL_FIELDS.has(key) ? 'email' : 'text';
      const auto = key === 'full_name' ? 'name' : key === 'email' || key === 'email_confirm' ? 'email' : 'off';
      parts.push(`<label class="block" data-field="${key}"><span class="${LABEL}">${label}${req}</span>${help}
        <input name="${key}" type="${type}" class="${INPUT}" value="${esc(values[key] ?? '')}" autocomplete="${auto}"></label>`);
    }
  }
  if (form.declarations.length && !editing) {
    const decl = form.declarations.map((d) => `<label class="flex gap-2 items-start text-sm text-[var(--text-primary)]">
        <input type="checkbox" name="decl:${esc(d.key)}" class="mt-1">
        <span>${esc(pick(d.text, lang, d.key))}${d.required ? ' <span class="text-red-600" aria-hidden="true">*</span>' : ''}</span></label>`).join('');
    parts.push(`<fieldset class="space-y-2"><legend class="${LABEL}">${esc(t('competition.declarations'))}</legend>${decl}</fieldset>`);
  }
  return parts.join('\n');
}

/** Read-only list of the answers, for the confirmation step and for a registration that can no longer change. */
export function renderSummary(form: FormVersion, lang: Lang, t: (k: string) => string, values: Record<string, unknown>, emailShown: string): string {
  const rows: string[] = [];
  for (const key of FIELD_ORDER) {
    if (!form.fields[key] || key === 'email_confirm') continue;
    const raw = key === 'email' ? emailShown : values[key];
    if (raw === null || raw === undefined || raw === '') continue;
    const shown = typeof raw === 'boolean' ? t(raw ? 'competition.yes' : 'competition.no') : String(raw);
    rows.push(`<div class="py-1.5 border-b border-[var(--border-subtle,#eee)]"><dt class="text-[.72rem] text-[var(--text-muted)]">${esc(fieldLabel(form, key, lang, t))}</dt>
      <dd class="text-sm text-[var(--text-primary)] break-words">${esc(shown)}</dd></div>`);
  }
  return `<dl>${rows.join('')}</dl>`;
}

/** Shows the leader e-mail only for a member who does not lead, and the technical area only for a technical profile. */
export function applyConditionals(formEl: HTMLFormElement): void {
  const val = (name: string) => (formEl.querySelector(`input[name="${name}"]:checked`) as HTMLInputElement | null)?.value;
  const toggle = (field: string, show: boolean) => {
    const el = formEl.querySelector(`[data-field="${field}"]`) as HTMLElement | null;
    if (el) el.hidden = !show;
  };
  toggle('leader_email', val('is_leader') === 'false');
  toggle('technical_area', val('technical_profile') === 'true');
}

/** Reads the form back into the payload the database expects. */
export function collect(formEl: HTMLFormElement, form: FormVersion): Record<string, unknown> {
  const fd = new FormData(formEl);
  const out: Record<string, unknown> = {};
  for (const key of FIELD_ORDER) {
    if (!form.fields[key]) continue;
    const raw = fd.get(key);
    if (raw === null) { if (BOOLEAN_FIELDS.has(key)) out[key] = null; continue; }
    const s = String(raw).trim();
    out[key] = BOOLEAN_FIELDS.has(key) ? (s === '' ? null : s === 'true') : (s === '' ? null : s);
  }
  if (out.is_leader !== false) delete out.leader_email;
  if (out.technical_profile !== true) delete out.technical_area;
  const decl: Record<string, boolean> = {};
  for (const d of form.declarations) decl[d.key] = fd.get(`decl:${d.key}`) === 'on';
  out.declarations = decl;
  return out;
}

/** Client-side mirror of the most common server rules. Returns the same {code, field} the server returns. */
export function precheck(p: Record<string, unknown>, form: FormVersion, opts: { editing?: boolean; teams?: boolean } = {}): Problem | null {
  const str = (k: string) => (typeof p[k] === 'string' ? (p[k] as string) : '');
  for (const key of FIELD_ORDER) {
    const def = form.fields[key];
    if (!def) continue;
    if (opts.editing && (key === 'email' || key === 'email_confirm')) continue;
    if (key === 'leader_email' || key === 'technical_area') continue;
    const required = def.required || key === 'full_name' || key === 'email'
      || (opts.teams && (key === 'team_name' || key === 'is_leader'));
    if (required && (p[key] === null || p[key] === undefined)) return { code: 'required', field: key };
  }
  if (!opts.editing) {
    const email = str('email').toLowerCase();
    if (!EMAIL_RE.test(email) || email.length > 254) return { code: 'email_invalid', field: 'email' };
    if (form.fields.email_confirm && str('email_confirm').toLowerCase() !== email) return { code: 'email_mismatch', field: 'email_confirm' };
  }
  if (p.is_leader === false) {
    const le = str('leader_email').toLowerCase();
    if (!le) return { code: 'required', field: 'leader_email' };
    if (!EMAIL_RE.test(le)) return { code: 'email_invalid', field: 'leader_email' };
  }
  if (p.technical_profile === true && form.fields.technical_area && !p.technical_area) return { code: 'required', field: 'technical_area' };
  const decl = (p.declarations ?? {}) as Record<string, boolean>;
  if (!opts.editing) {
    const missing = form.declarations.find((d) => d.required && !decl[d.key]);
    if (missing) return { code: 'declaration_required', field: missing.key };
  }
  return null;
}

/** The message for a server or client problem, with the field label filled in. */
export function problemMessage(pr: Problem, form: FormVersion | null, lang: Lang, t: (k: string) => string): string {
  const key = `competition.error.${pr.code}`;
  const msg = t(key);
  const base = msg === key ? t('competition.error.generic') : msg;
  const field = pr.field && form?.fields[pr.field] ? fieldLabel(form, pr.field, lang, t) : '';
  return base.replace('{field}', field);
}

/** UTM parameters from the page address; not personal data. */
export function utmFrom(search: string): Record<string, string> | undefined {
  const q = new URLSearchParams(search);
  const out: Record<string, string> = {};
  for (const k of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content']) {
    const v = q.get(k);
    if (v && /^[A-Za-z0-9._~+-]{1,100}$/.test(v)) out[k] = v;
  }
  return Object.keys(out).length ? out : undefined;
}

/** A date in the edition's time zone, as the organizers wrote it. */
export function fmtWhen(iso: string | null | undefined, tz: string, lang: Lang): string {
  if (!iso) return '';
  return new Date(iso).toLocaleString(lang, { timeZone: tz || 'America/Sao_Paulo', dateStyle: 'short', timeStyle: 'short' });
}
