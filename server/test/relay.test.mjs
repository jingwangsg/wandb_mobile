import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {createRelay, validateRule} from '../src/relay.mjs';
import {HttpError, automationFilter, WandbGateway} from '../src/wandb.mjs';

const auth = owner => `Basic ${Buffer.from(`api:${owner}`).toString('base64')}`;
const runEvent = {entity: 'team', project: 'training', run: 'run-123', state: 'failed'};

async function fixture(t, options = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'wandb-relay-test-'));
  let clock = 1_800_000_000_000;
  const sent = [];
  const integrations = [];
  const deletedTriggers = [];
  const deletedIntegrations = [];
  const wandb = {
    async viewer(header) {
      for (const owner of ['alice', 'bob']) if (header === auth(owner)) return owner;
      throw new HttpError(401, 'Invalid API key');
    },
    async project(header, entity, project) { assert.equal(entity, 'team'); assert.equal(project, 'training'); return 'project-1'; },
    async createIntegration(header, entity, name, url) { integrations.push({name, url}); return `integration-${integrations.length}`; },
    async createTrigger(header, rule, projectId, integrationId) { assert.equal(projectId, 'project-1'); return `trigger-${integrationId}`; },
    async deleteTrigger(header, id) { deletedTriggers.push(id); },
    async deleteIntegration(header, id) { deletedIntegrations.push(id); },
    ...options.wandb,
  };
  const args = {databasePath: join(directory, 'relay.sqlite'), publicUrl: 'https://push.example.com', wandb,
    now: () => clock, send: options.send ?? (async message => { sent.push(message); })};
  let relay = createRelay(args);
  await start();
  t.after(async () => { await stop(); await rm(directory, {recursive: true, force: true}); });

  async function start() { relay.server.listen(0, '127.0.0.1'); await once(relay.server, 'listening'); }
  async function stop() { await new Promise(resolve => relay.server.close(resolve)); relay.close(); }
  async function request(path, {owner = 'alice', method = 'GET', body, headers = {}} = {}) {
    const response = await fetch(`http://127.0.0.1:${relay.server.address().port}${path}`, {
      method, headers: {...(owner == null ? {} : {authorization: auth(owner)}), ...(body === undefined ? {} : {'content-type': 'application/json'}), ...headers},
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return {status: response.status, data: await response.json()};
  }
  return {
    request, sent, integrations, deletedTriggers, deletedIntegrations,
    drain: () => relay.drain(), advance: amount => { clock += amount; },
    restart: async () => { await stop(); relay = createRelay(args); await start(); },
    create: (extra = {}) => request('/v1/subscriptions', {method: 'POST', body: {entity: 'team', project: 'training', ...extra}}),
    hook: (body = runEvent) => request(new URL(integrations.at(-1).url).pathname, {method: 'POST', owner: null, body}),
  };
}

test('registration and subscriptions require W&B authentication', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/v1/subscriptions', {owner: null})).status, 401);
  assert.equal((await f.request('/v1/subscriptions', {owner: 'invalid'})).status, 401);
  assert.equal((await f.request('/v1/devices', {method: 'PUT', body: {token: 'short'}})).status, 400);
  assert.equal(f.integrations.length, 0);
});

test('webhooks queue privately scoped data messages and suppress immediate retries', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/v1/devices', {method: 'PUT', body: {token: 'alice-device-token'}})).status, 200);
  await f.request('/v1/devices', {owner: 'bob', method: 'PUT', body: {token: 'bob-device-token-1'}});
  assert.equal((await f.create()).status, 201);
  assert.equal((await f.hook()).status, 202);
  assert.equal((await f.hook()).status, 202);
  await f.drain();
  assert.equal(f.sent.length, 1);
  assert.equal(f.sent[0].token, 'alice-device-token');
  assert.equal(f.sent[0].data.owner, 'alice');
  assert.equal(f.sent[0].data.run, 'run-123');
  assert.equal(f.sent[0].notification, undefined);
  f.advance(61_000);
  await f.hook(); await f.drain();
  assert.equal(f.sent.length, 2, 'a later rerun is not permanently deduplicated');
});

test('forged scope and unknown callbacks cannot enqueue messages', async t => {
  const f = await fixture(t);
  await f.create();
  assert.equal((await f.hook({...runEvent, project: 'someone-elses-project'})).status, 400);
  assert.equal((await f.hook({...runEvent, run: '../../private'})).status, 400);
  assert.equal((await f.request('/hooks/' + 'a'.repeat(43), {owner: null, method: 'POST', body: runEvent})).status, 404);
  await f.drain(); assert.equal(f.sent.length, 0);
});

test('users cannot list or delete each others subscriptions', async t => {
  const f = await fixture(t);
  const created = await f.create();
  assert.deepEqual((await f.request('/v1/subscriptions', {owner: 'bob'})).data, []);
  assert.equal((await f.request(`/v1/subscriptions/${created.data.id}`, {owner: 'bob', method: 'DELETE'})).status, 404);
  assert.equal(f.deletedTriggers.length, 0);
  assert.equal((await f.request(`/v1/subscriptions/${created.data.id}`, {method: 'DELETE'})).status, 200);
  assert.equal(f.deletedTriggers.length, 1);
  assert.equal(f.deletedIntegrations.length, 1);
  assert.deepEqual((await f.request('/v1/subscriptions')).data, []);
});

test('queue survives process restart and retries transient Firebase failures', async t => {
  let attempts = 0;
  const delivered = [];
  const f = await fixture(t, {send: async message => { if (++attempts === 1) throw new Error('temporary outage'); delivered.push(message); }});
  await f.request('/v1/devices', {method: 'PUT', body: {token: 'alice-device-token'}});
  await f.create(); await f.hook();
  await f.restart(); await f.drain();
  assert.equal(attempts, 1);
  await f.drain(); assert.equal(attempts, 1);
  f.advance(1001); await f.drain();
  assert.equal(delivered.length, 1);
  await f.drain(); assert.equal(delivered.length, 1);
});

test('rotating a device to a new account cannot deliver queued old-account data', async t => {
  const f = await fixture(t);
  await f.request('/v1/devices', {method: 'PUT', body: {token: 'shared-device-token'}});
  await f.create(); await f.hook();
  await f.request('/v1/devices', {owner: 'bob', method: 'PUT', body: {token: 'shared-device-token'}});
  await f.drain(); assert.equal(f.sent.length, 0);
});

test('dead Firebase tokens are removed and not retried', async t => {
  let attempts = 0;
  const f = await fixture(t, {send: async () => { attempts++; throw Object.assign(new Error('gone'), {code: 'messaging/registration-token-not-registered'}); }});
  await f.request('/v1/devices', {method: 'PUT', body: {token: 'alice-device-token'}});
  await f.create(); await f.hook(); await f.drain();
  f.advance(61_000); await f.hook(); await f.drain();
  assert.equal(attempts, 1);
});

test('subscription retries are idempotent and incomplete setup is visible', async t => {
  const f = await fixture(t);
  const first = await f.create(); const second = await f.create();
  assert.equal(first.data.id, second.data.id);
  assert.equal(f.integrations.length, 1);
  const failed = await fixture(t, {wandb: {async createTrigger() { throw new HttpError(403, 'Insufficient permission'); }}});
  assert.equal((await failed.create()).status, 403);
  const rules = (await failed.request('/v1/subscriptions')).data;
  assert.equal(rules[0].status, 'failed');
  assert.equal((await failed.request(`/v1/subscriptions/${rules[0].id}`, {method: 'DELETE'})).status, 200);
  assert.equal(failed.deletedIntegrations.length, 1);
});

test('metric rules keep the documented change window and percentage semantics', () => {
  const rule = validateRule({entity: 'team', project: 'training', metric: 'train/loss', direction: 'DECREASE', basis: 'RELATIVE', amount: 10});
  assert.deepEqual(automationFilter(rule), {
    run_filter: '{"$and":[]}', run_metric_filter: {change_filter: {
      name: 'train/loss', agg_op: 'AVERAGE', current_window_size: 10, prior_window_size: 50,
      change_type: 'RELATIVE', change_dir: 'DECREASE', change_amount: 10,
    }},
  });
  for (const amount of [-1, 0, NaN, Infinity, '1']) assert.throws(() => validateRule({...rule, amount}), HttpError);
});

test('the W&B gateway rejects null viewers and upstream redirects', async () => {
  let options;
  const gateway = new WandbGateway('https://api.wandb.ai', async (url, request) => { options = request; assert.equal(url.href, 'https://api.wandb.ai/graphql'); return Response.json({data: {viewer: null}}); });
  await assert.rejects(gateway.viewer(auth('alice')), error => error.status === 401);
  assert.equal(options.redirect, 'error');
  assert.throws(() => new WandbGateway('http://untrusted.example'), /HTTPS/);
});
