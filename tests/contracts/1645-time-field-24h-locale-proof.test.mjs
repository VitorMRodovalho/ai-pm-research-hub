/**
 * #1645 — o campo de horário tem de ser 24h e nunca bloquear o submit calado.
 *
 * O defeito original NÃO era o valor: era o `<input type="time">`, que renderiza segundo o
 * locale do NAVEGADOR. Em `en-US` vira widget de 12h com AM/PM, e com qualquer segmento em
 * branco `value` é "" e `validity.badInput` é true — o navegador bloqueia o submit antes do
 * evento, então `createRecurring()` nunca roda e nenhum toast nosso aparece.
 *
 * Estes testes exercitam o COMPORTAMENTO do helper (normalização, leitura, upgrade do campo).
 * Um teste de grep provaria que o helper está escrito, jamais que ele CASA — a mesma classe
 * de defesa decorativa registrada em #1620 e #1629.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeTime, setTimeField, readTimeField, upgradeTimeField } from '../../src/lib/time-field.ts';

/** Elemento falso: o repo não tem jsdom, e o helper só usa esta superfície. */
function fakeInput(initial = '', type = 'time') {
  const listeners = {};
  return {
    value: initial,
    type,
    inputMode: '',
    maxLength: -1,
    autocomplete: '',
    placeholder: '',
    dataset: {},
    _attrs: {},
    setAttribute(k, v) { this._attrs[k] = v; },
    getAttribute(k) { return this._attrs[k] ?? null; },
    addEventListener(evt, fn) { (listeners[evt] ||= []).push(fn); },
    fire(evt) { (listeners[evt] || []).forEach((fn) => fn()); },
    _count(evt) { return (listeners[evt] || []).length; },
  };
}

test('normalizeTime aceita as formas que aparecem na prática', () => {
  assert.equal(normalizeTime('19:00'), '19:00');
  assert.equal(normalizeTime('19:00:00'), '19:00', 'o banco serializa `time` com segundos');
  assert.equal(normalizeTime('1900'), '19:00');
  assert.equal(normalizeTime('930'), '09:30');
  assert.equal(normalizeTime('9'), '09:00');
  assert.equal(normalizeTime('9:5'), '09:05');
  assert.equal(normalizeTime('  19 : 00  '), '19:00');
  assert.equal(normalizeTime('19.30'), '19:30');
});

test('normalizeTime recusa hora/minuto fora de faixa e lixo', () => {
  assert.equal(normalizeTime('24:00'), null);
  assert.equal(normalizeTime('19:60'), null);
  assert.equal(normalizeTime('7 pm'), null, 'o campo é 24h; AM/PM foi justamente o que quebrou');
  assert.equal(normalizeTime('abc'), null);
  assert.equal(normalizeTime('12345'), null);
});

test('vazio NÃO é erro: horário é opcional (vazio = padrão da tribo)', () => {
  assert.equal(normalizeTime(''), null);
  assert.equal(normalizeTime(null), null);
  assert.equal(normalizeTime(undefined), null);

  const el = fakeInput('');
  const r = readTimeField(el);
  assert.deepEqual(r, { time: null, invalid: false },
    'vazio e inválido têm de ser estados DISTINTOS, senão o toast dispara em uso legítimo');
});

test('readTimeField separa vazio de inválido e canoniza o resto', () => {
  assert.deepEqual(readTimeField(fakeInput('19:00')), { time: '19:00', invalid: false });
  assert.deepEqual(readTimeField(fakeInput('1900')), { time: '19:00', invalid: false });
  assert.deepEqual(readTimeField(fakeInput('   ')), { time: null, invalid: false });
  assert.deepEqual(readTimeField(fakeInput('7 pm')), { time: null, invalid: true });
  assert.deepEqual(readTimeField(fakeInput('25:00')), { time: null, invalid: true });
  assert.deepEqual(readTimeField(null), { time: null, invalid: false });
});

test('setTimeField corta os segundos que vêm do banco', () => {
  const el = fakeInput('');
  setTimeField(el, '19:00:00');
  assert.equal(el.value, '19:00');
  setTimeField(el, null);
  assert.equal(el.value, '', 'null vira vazio, não a string "null"');
});

test('upgradeTimeField tira o campo do type=time — a origem do bug', () => {
  const el = fakeInput('19:00', 'time');
  upgradeTimeField(el);
  assert.equal(el.type, 'text',
    'enquanto for type=time o widget segue o locale do navegador e o badInput volta');
  assert.equal(el.inputMode, 'numeric');
  assert.equal(el.maxLength, 5);
  assert.equal(el.placeholder, '19:00');
  assert.equal(el.value, '19:00', 'o valor tem de sobreviver à troca de type');
});

test('upgradeTimeField preserva valor com segundos e não inventa valor em campo vazio', () => {
  const comSegundos = fakeInput('19:00:00', 'time');
  upgradeTimeField(comSegundos);
  assert.equal(comSegundos.value, '19:00');

  const vazio = fakeInput('', 'time');
  upgradeTimeField(vazio);
  assert.equal(vazio.value, '');
});

test('a máscara insere os dois pontos e descarta não-dígito enquanto digita', () => {
  const el = fakeInput('', 'time');
  upgradeTimeField(el);

  el.value = '1'; el.fire('input');
  assert.equal(el.value, '1');
  el.value = '19'; el.fire('input');
  assert.equal(el.value, '19');
  el.value = '190'; el.fire('input');
  assert.equal(el.value, '19:0');
  el.value = '1900'; el.fire('input');
  assert.equal(el.value, '19:00');
  el.value = '19:00x'; el.fire('input');
  assert.equal(el.value, '19:00', 'letra digitada não pode entrar no campo');
});

test('o blur canoniza o que dá, e NÃO apaga o que não dá', () => {
  const ok = fakeInput('', 'time');
  upgradeTimeField(ok);
  ok.value = '9'; ok.fire('blur');
  assert.equal(ok.value, '09:00');

  const ruim = fakeInput('', 'time');
  upgradeTimeField(ruim);
  ruim.value = '99:99'; ruim.fire('blur');
  assert.equal(ruim.value, '99:99',
    'apagar a digitação esconderia o erro; quem acusa é o toast do readTimeField');
  assert.equal(readTimeField(ruim).invalid, true);
});

test('upgradeTimeField é idempotente — não duplica listener', () => {
  const el = fakeInput('', 'time');
  upgradeTimeField(el);
  upgradeTimeField(el);
  upgradeTimeField(el);
  assert.equal(el._count('input'), 1);
  assert.equal(el._count('blur'), 1);
});

test('upgradeTimeField não quebra com elemento ausente', () => {
  assert.doesNotThrow(() => upgradeTimeField(null));
});
