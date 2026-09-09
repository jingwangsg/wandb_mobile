import {test} from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {createRelay} from '../src/relay.mjs';
import {HttpError} from '../src/wandb.mjs';

const authorization = owner => `Basic ${Buffer.from(`api:${owner}`).toString('base64')}`;
const runEvent = {entity: 'team', project: 'training', run: 'private-run', state: 'failed'};

async function fixture(t, {send, beforeCreateIntegration} = {}) {
  const sent = [];
  const callbacks = [];
  const integrations = new Set();
  const triggers = new Set();
  const relay = createRelay({
    databasePath: ':memory:',
    publicUrl: 'https://push.example.com',
    now: () => 1_800_000_000_000,
    wandb: {
      async viewer(header) {
        for (const owner of ['alice', 'bob']) if (header === authorization(owner)) return owner;
        throw new HttpError(401, 'Invalid API key');
      },
      async project(header, entity, project) {
        assert.equal(entity, 'team');
        assert.equal(project, 'training');
        return 'project-1';
      },
      async createIntegration(header, entity, name, url) {
        await beforeCreateIntegration?.();
        const id = `integration-${callbacks.length + 1}`;
        callbacks.push(new URL(url).pathname);
        integrations.add(id);
        return id;
      },
      async createTrigger(header, rule, projectId, integrationId) {
        assert.equal(projectId, 'project-1');
        assert.ok(integrations.has(integrationId));
        const id = `trigger-${integrationId}`;
        triggers.add(id);
        return id;
      },
      async deleteTrigger(header, id) { assert.ok(triggers.delete(id)); },
      async deleteIntegration(header, id) { assert.ok(integrations.delete(id)); },
    },
    async send(message) {
      sent.push(message);
      await send?.(message);
    },
  });
  t.after(async () => {
    if (relay.server.listening) await new Promise(resolve => relay.server.close(resolve));
    relay.close();
  });
  relay.server.listen(0, '127.0.0.1');
  await once(relay.server, 'listening');
  const origin = `http://127.0.0.1:${relay.server.address().port}`;

  async function request(path, {owner = 'alice', method = 'GET', body} = {}) {
    const response = await fetch(`${origin}${path}`, {
      method,
      headers: {
        ...(owner == null ? {} : {authorization: authorization(owner)}),
        ...(body === undefined ? {} : {'content-type': 'application/json'}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return {status: response.status, data: await response.json()};
  }

  return {request, relay, sent, callbacks, integrations, triggers};
}

for (const action of ['transfer device', 'unregister device', 'delete subscription']) {
  test(`drain stops sending a fetched batch after ${action}`, {timeout: 5000}, async t => {
    const started = Promise.withResolvers();
    const release = Promise.withResolvers();
    const f = await fixture(t, {send: async message => { started.resolve(message); await release.promise; }});
    const tokens = ['alice-device-token-1', 'alice-device-token-2'];
    for (const token of tokens) {
      assert.equal((await f.request('/v1/devices', {method: 'PUT', body: {token}})).status, 200);
    }
    const created = await f.request('/v1/subscriptions', {method: 'POST', body: {entity: 'team', project: 'training'}});
    assert.equal(created.status, 201);
    assert.equal((await f.request(f.callbacks[0], {method: 'POST', owner: null, body: runEvent})).status, 202);

    const draining = f.relay.drain();
    try {
      const first = await started.promise;
      const token = tokens.find(value => value !== first.token);
      const changed = action === 'delete subscription'
        ? await f.request(`/v1/subscriptions/${created.data.id}`, {method: 'DELETE'})
        : await f.request('/v1/devices', {
          method: action === 'transfer device' ? 'PUT' : 'DELETE',
          owner: action === 'transfer device' ? 'bob' : 'alice',
          body: {token},
        });
      assert.equal(changed.status, 200);
    } finally {
      release.resolve();
      await draining;
    }
    assert.equal(f.sent.length, 1, 'the removed delivery must not send old-account data after the first send resumes');
  });
}

test('deletion during provisioning cannot orphan a remote integration or trigger', {timeout: 5000}, async t => {
  const started = Promise.withResolvers();
  const release = Promise.withResolvers();
  const f = await fixture(t, {beforeCreateIntegration: async () => { started.resolve(); await release.promise; }});
  const creating = f.request('/v1/subscriptions', {method: 'POST', body: {entity: 'team', project: 'training'}});
  let deleted;
  let id;
  try {
    await started.promise;
    const listed = await f.request('/v1/subscriptions');
    assert.equal(listed.status, 200);
    assert.equal(listed.data.length, 1);
    id = listed.data[0].id;
    deleted = await f.request(`/v1/subscriptions/${id}`, {method: 'DELETE'});
  } finally {
    release.resolve();
    await creating;
  }

  assert.equal(deleted.status, 409, 'creation must finish before the recorded remote resources can be deleted');
  assert.equal((await creating).status, 201);
  const listed = await f.request('/v1/subscriptions');
  assert.equal(listed.data.length, 1);
  assert.equal(listed.data[0].id, id);
  assert.equal((await f.request(`/v1/subscriptions/${id}`, {method: 'DELETE'})).status, 200);
  assert.deepEqual((await f.request('/v1/subscriptions')).data, []);
  assert.equal(f.integrations.size, 0);
  assert.equal(f.triggers.size, 0);
});

for (const destination of ['authenticated owner', 'webhook']) {
  test(`anonymous traffic behind a shared proxy does not exhaust ${destination} limits`, {timeout: 5000}, async t => {
    const f = await fixture(t);
    assert.equal((await f.request('/v1/devices', {method: 'PUT', body: {token: 'alice-device-token'}})).status, 200);
    assert.equal((await f.request('/v1/subscriptions', {method: 'POST', body: {entity: 'team', project: 'training'}})).status, 201);

    // A reverse proxy presents the same socket address for all of these callers.
    for (let count = 0; count < 301; count++) {
      const denied = await f.request('/v1/subscriptions', {owner: null});
      assert.ok([401, 429].includes(denied.status));
    }

    if (destination === 'authenticated owner') {
      const listed = await f.request('/v1/subscriptions');
      assert.equal(listed.status, 200);
      assert.equal(listed.data.length, 1);
    } else {
      assert.equal((await f.request(f.callbacks[0], {method: 'POST', owner: null, body: runEvent})).status, 202);
      await f.relay.drain();
      assert.equal(f.sent.length, 1);
      assert.equal(f.sent[0].data.run, runEvent.run);
    }
  });
}
