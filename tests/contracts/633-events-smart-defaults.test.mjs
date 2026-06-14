import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

const modalPath = 'src/components/attendance/NewEventModal.astro';
const pagePath = 'src/pages/attendance.astro';
const modal = existsSync(modalPath) ? readFileSync(modalPath, 'utf8') : '';
const page = existsSync(pagePath) ? readFileSync(pagePath, 'utf8') : '';

describe('#633 event creation smart defaults', () => {
  it('single-event modal forces an explicit audience type for admins/managers', () => {
    assert.match(modal, /<select id="ev-type" required/);
    assert.match(modal, /<option value="">\{t\('attendance\.modal\.selectEventType', lang\)\}<\/option>/);
    assert.match(page, /getElementById\('ev-type'\)[\s\S]*?\.value = ''/);
    assert.doesNotMatch(page, /getElementById\('ev-type'\)[\s\S]{0,80}\.value = 'geral';/);
  });

  it('keeps the tribe-leader lock to type=tribo + own tribe', () => {
    assert.match(page, /MEMBER\?\.operational_role === 'tribe_leader' && MEMBER\?\.tribe_id/);
    assert.match(page, /typeSelect\.value = 'tribo'/);
    assert.match(page, /typeSelect\.disabled = true/);
    assert.match(page, /tribeSelCreate\.value = String\(MEMBER\.tribe_id\)/);
    assert.match(page, /tribeSelCreate\.disabled = true/);
  });

  it('blocks create_event before RPC when scoped types lack selected scope', () => {
    assert.match(page, /if \(!type\) return toast\(I18N\.msgSelectEventType, 'error'\)/);
    assert.match(page, /if \(type === 'tribo' && !tribeId\) return toast\(I18N\.msgSelectTribe, 'error'\)/);
    assert.match(page, /if \(type === 'iniciativa' && !initiativeIdNew\) return toast\(I18N\.msgSelectInitiative, 'error'\)/);
    assert.match(page, /p_type:\s*type/);
  });

  it('ships i18n keys for the new validation and placeholder text', () => {
    for (const dict of ['src/i18n/pt-BR.ts', 'src/i18n/en-US.ts', 'src/i18n/es-LATAM.ts']) {
      const raw = readFileSync(dict, 'utf8');
      for (const key of [
        'attendance.modal.selectEventType',
        'attendance.msg.selectEventType',
        'attendance.msg.selectTribe',
        'attendance.msg.selectInitiative',
      ]) {
        assert.match(raw, new RegExp(`'${key}':`), `${dict} missing ${key}`);
      }
    }
  });
});
