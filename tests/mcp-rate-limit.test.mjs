import test from 'node:test';
import assert from 'node:assert/strict';
import {
  checkRateLimit,
  extractToolName,
  isDestructive,
  DESTRUCTIVE_TOOLS,
  GENERAL_LIMIT_PER_MIN,
  DESTRUCTIVE_LIMIT_PER_MIN,
} from '../src/lib/mcp-rate-limit.ts';

function makeMockKV(initial = {}) {
  const store = new Map(Object.entries(initial));
  const errors = { get: false, put: false };
  return {
    store,
    errors,
    async get(key) {
      if (errors.get) throw new Error('kv get failure');
      return store.get(key) ?? null;
    },
    async put(key, value, _opts) {
      if (errors.put) throw new Error('kv put failure');
      store.set(key, value);
    },
  };
}

test('extractToolName returns null for non-JSON-RPC body', () => {
  assert.equal(extractToolName(null), null);
  assert.equal(extractToolName(''), null);
  assert.equal(extractToolName('not json'), null);
  assert.equal(extractToolName('{}'), null);
  assert.equal(extractToolName('{"method":"initialize"}'), null);
});

test('extractToolName reads tools/call name', () => {
  const body = JSON.stringify({
    jsonrpc: '2.0',
    id: 1,
    method: 'tools/call',
    params: { name: 'drop_event_instance', arguments: { event_id: 'abc' } },
  });
  assert.equal(extractToolName(body), 'drop_event_instance');
});

test('extractToolName returns null when method is not tools/call', () => {
  const body = JSON.stringify({ method: 'tools/list' });
  assert.equal(extractToolName(body), null);
});

test('isDestructive matches ADR-0018 W1 tool set', () => {
  for (const tool of DESTRUCTIVE_TOOLS) {
    assert.equal(isDestructive(tool), true, `expected ${tool} to be destructive`);
  }
  assert.equal(isDestructive('get_my_profile'), false);
  assert.equal(isDestructive(null), false);
  assert.equal(isDestructive(''), false);
});

test('DESTRUCTIVE_TOOLS set contains exactly the 5 W1 tools', () => {
  const expected = new Set([
    'drop_event_instance',
    'delete_card',
    'archive_card',
    'offboard_member',
    'manage_initiative_engagement',
  ]);
  assert.equal(DESTRUCTIVE_TOOLS.size, expected.size);
  for (const tool of expected) assert.ok(DESTRUCTIVE_TOOLS.has(tool));
});

test('checkRateLimit fail-opens when kv is null', async () => {
  const res = await checkRateLimit(null, 'user-1', 'delete_card');
  assert.equal(res.allowed, true);
  assert.equal(res.remaining, -1);
});

test('checkRateLimit fail-opens when sub is empty', async () => {
  const kv = makeMockKV();
  const res = await checkRateLimit(kv, '', 'delete_card');
  assert.equal(res.allowed, true);
});

test('checkRateLimit allows under general threshold', async () => {
  const kv = makeMockKV();
  const res = await checkRateLimit(kv, 'u1', 'get_my_profile', 60_000);
  assert.equal(res.allowed, true);
  assert.equal(res.remaining, GENERAL_LIMIT_PER_MIN - 1);
  // counter incremented
  assert.equal(kv.store.get('rl:u1:1m:1'), '1');
});

test('checkRateLimit denies when general counter is at threshold', async () => {
  const kv = makeMockKV({ 'rl:u1:1m:1': String(GENERAL_LIMIT_PER_MIN) });
  const res = await checkRateLimit(kv, 'u1', 'get_my_profile', 60_000);
  assert.equal(res.allowed, false);
  assert.equal(res.limitKind, 'general');
  assert.equal(res.retryAfter, 60);
  assert.match(res.reason ?? '', /Rate limit/);
});

test('checkRateLimit denies destructive call even when general under threshold', async () => {
  const kv = makeMockKV({
    'rl:u1:1m:1': '5',
    'rl:u1:dest:1m:1': String(DESTRUCTIVE_LIMIT_PER_MIN),
  });
  const res = await checkRateLimit(kv, 'u1', 'drop_event_instance', 60_000);
  assert.equal(res.allowed, false);
  assert.equal(res.limitKind, 'destructive');
  assert.match(res.reason ?? '', /Destructive rate limit/);
});

test('checkRateLimit increments BOTH counters when tool is destructive', async () => {
  const kv = makeMockKV();
  const res = await checkRateLimit(kv, 'u1', 'offboard_member', 120_000);
  assert.equal(res.allowed, true);
  assert.equal(kv.store.get('rl:u1:1m:2'), '1');
  assert.equal(kv.store.get('rl:u1:dest:1m:2'), '1');
});

test('checkRateLimit fail-opens on KV error', async () => {
  const kv = makeMockKV();
  kv.errors.get = true;
  const res = await checkRateLimit(kv, 'u1', 'delete_card');
  assert.equal(res.allowed, true);
  assert.equal(res.reason, 'kv_error_fail_open');
});

test('checkRateLimit uses separate buckets per minute', async () => {
  const kv = makeMockKV();
  await checkRateLimit(kv, 'u1', 'get_my_profile', 60_000); // bucket=1
  await checkRateLimit(kv, 'u1', 'get_my_profile', 120_000); // bucket=2
  assert.equal(kv.store.get('rl:u1:1m:1'), '1');
  assert.equal(kv.store.get('rl:u1:1m:2'), '1');
});

test('checkRateLimit counts same bucket across calls', async () => {
  const kv = makeMockKV();
  await checkRateLimit(kv, 'u1', 'get_my_profile', 60_000);
  await checkRateLimit(kv, 'u1', 'get_my_profile', 60_500);
  await checkRateLimit(kv, 'u1', 'get_my_profile', 61_000);
  assert.equal(kv.store.get('rl:u1:1m:1'), '3');
});

test('checkRateLimit separates counters per member', async () => {
  const kv = makeMockKV();
  await checkRateLimit(kv, 'u1', 'get_my_profile', 60_000);
  await checkRateLimit(kv, 'u2', 'get_my_profile', 60_000);
  assert.equal(kv.store.get('rl:u1:1m:1'), '1');
  assert.equal(kv.store.get('rl:u2:1m:1'), '1');
});
