import {createServer} from 'node:http';
import {createHash, randomBytes, randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {HttpError} from './wandb.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const day = 86_400_000;

export function createRelay({databasePath, publicUrl, wandb, send, now = Date.now}) {
  const endpoint = new URL(publicUrl);
  if (endpoint.protocol !== 'https:' || endpoint.pathname !== '/' || endpoint.username || endpoint.password) {
    throw new Error('PUBLIC_URL must be an HTTPS origin');
  }
  const db = new DatabaseSync(databasePath);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS devices (token TEXT PRIMARY KEY, owner TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS subscriptions (
      id TEXT PRIMARY KEY, owner TEXT NOT NULL, entity TEXT NOT NULL, project TEXT NOT NULL,
      metric TEXT, name TEXT NOT NULL, config TEXT NOT NULL, fingerprint TEXT NOT NULL,
      callback_hash TEXT UNIQUE NOT NULL, integration_id TEXT, trigger_id TEXT,
      status TEXT NOT NULL DEFAULT 'provisioning', UNIQUE(owner, fingerprint)
    );
    CREATE TABLE IF NOT EXISTS events (
      id TEXT PRIMARY KEY, subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
      owner TEXT NOT NULL, fingerprint TEXT NOT NULL, payload TEXT NOT NULL, created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS events_fingerprint ON events(subscription_id, fingerprint, created_at);
    CREATE TABLE IF NOT EXISTS deliveries (
      event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      token TEXT NOT NULL REFERENCES devices(token) ON DELETE CASCADE,
      attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
      PRIMARY KEY(event_id, token)
    );
    UPDATE subscriptions SET status='failed' WHERE status='provisioning';
  `);
  let draining = false;
  const authenticationCache = new Map();
  const rateLimits = new Map();

  function enforceRateLimit(key) {
    const rate = rateLimits.get(key) ?? {start: now(), count: 0};
    if (now() - rate.start > 60_000) { rate.start = now(); rate.count = 0; }
    rate.count++;
    rateLimits.set(key, rate);
    if (rate.count > 300) throw new HttpError(429, 'Too many requests');
    if (rateLimits.size > 10_000) for (const [key, value] of rateLimits) if (now() - value.start > 60_000) rateLimits.delete(key);
  }

  const server = createServer(async (request, response) => {
    response.setHeader('content-type', 'application/json');
    response.setHeader('cache-control', 'no-store');
    try {
      const path = new URL(request.url, 'http://localhost').pathname;
      if (request.method === 'GET' && path === '/health') {
        response.end(JSON.stringify({status: 'ok', pending: db.prepare("SELECT count(*) AS count FROM deliveries WHERE status='pending'").get().count}));
        return;
      }
      const body = await readJson(request);
      const hook = /^\/hooks\/([A-Za-z0-9_-]{43})$/.exec(path);
      if (request.method === 'POST' && hook) {
        const rule = db.prepare("SELECT * FROM subscriptions WHERE callback_hash=? AND status='active'").get(hash(hook[1]));
        if (!rule) throw new HttpError(404, 'Webhook not found');
        enforceRateLimit(`hook:${rule.id}`);
        if (body.entity !== rule.entity || body.project !== rule.project || typeof body.run !== 'string' || !body.run || body.run.length > 256 || /[\/\x00-\x1f]/.test(body.run)) {
          throw new HttpError(400, 'Webhook project or run does not match the subscription');
        }
        const payload = {
          title: rule.metric ? `${rule.metric} alert` : 'Run failed',
          body: `${body.run}: ${String(body.description ?? body.state ?? rule.name)}`.slice(0, 1000),
          entity: rule.entity, project: rule.project, run: body.run,
        };
        const fingerprint = hash(JSON.stringify(body));
        // W&B does not expose an execution ID in these templates. Deduplicate
        // identical retry payloads for one minute, not forever across reruns.
        const previous = db.prepare('SELECT id FROM events WHERE subscription_id=? AND fingerprint=? AND created_at>?').get(rule.id, fingerprint, now() - 60_000);
        if (!previous) {
          const id = randomUUID();
          db.exec('BEGIN IMMEDIATE');
          try {
            db.prepare('INSERT INTO events VALUES (?, ?, ?, ?, ?, ?)').run(id, rule.id, rule.owner, fingerprint, JSON.stringify(payload), now());
            db.prepare('INSERT INTO deliveries(event_id, token, next_attempt) SELECT ?, token, ? FROM devices WHERE owner=?').run(id, now(), rule.owner);
            db.exec('COMMIT');
          } catch (error) { db.exec('ROLLBACK'); throw error; }
        }
        response.writeHead(202); response.end(JSON.stringify({accepted: true}));
        return;
      }

      const authorization = request.headers.authorization;
      if (!authorization?.startsWith('Basic ')) throw new HttpError(401, 'W&B API key authentication required');
      const cacheKey = hash(authorization);
      let cached = authenticationCache.get(cacheKey);
      if (!cached || cached.expires <= now()) {
        cached = {owner: await wandb.viewer(authorization), expires: now() + 60_000};
        authenticationCache.set(cacheKey, cached);
        if (authenticationCache.size > 1000) for (const [key, value] of authenticationCache) if (value.expires <= now()) authenticationCache.delete(key);
      }
      const owner = cached.owner;
      enforceRateLimit(`owner:${owner}`);
      if (path === '/v1/devices' && (request.method === 'PUT' || request.method === 'DELETE')) {
        if (typeof body.token !== 'string' || body.token.length < 16 || body.token.length > 4096) throw new HttpError(400, 'Invalid device token');
        if (request.method === 'PUT') {
          db.exec('BEGIN IMMEDIATE');
          try {
            db.prepare('DELETE FROM devices WHERE token=? AND owner<>?').run(body.token, owner);
            db.prepare('INSERT INTO devices VALUES (?, ?) ON CONFLICT(token) DO NOTHING').run(body.token, owner);
            db.exec('COMMIT');
          } catch (error) { db.exec('ROLLBACK'); throw error; }
        } else db.prepare('DELETE FROM devices WHERE token=? AND owner=?').run(body.token, owner);
        response.end('{}'); return;
      }
      if (path === '/v1/subscriptions' && request.method === 'GET') {
        response.end(JSON.stringify(db.prepare('SELECT id, entity, project, metric, name, status FROM subscriptions WHERE owner=? ORDER BY rowid DESC').all(owner)));
        return;
      }
      if (path === '/v1/subscriptions' && request.method === 'POST') {
        const rule = validateRule(body);
        const fingerprint = hash(JSON.stringify(rule));
        const existing = db.prepare('SELECT id, status FROM subscriptions WHERE owner=? AND fingerprint=?').get(owner, fingerprint);
        if (existing?.status === 'active') { response.end(JSON.stringify(existing)); return; }
        if (existing) throw new HttpError(409, 'Alert setup is incomplete. Delete it from Manage notifications before retrying.');
        const projectId = await wandb.project(authorization, rule.entity, rule.project);
        const concurrent = db.prepare('SELECT id, status FROM subscriptions WHERE owner=? AND fingerprint=?').get(owner, fingerprint);
        if (concurrent?.status === 'active') { response.end(JSON.stringify(concurrent)); return; }
        if (concurrent) throw new HttpError(409, 'Alert setup is already in progress.');
        const id = randomUUID();
        const secret = randomBytes(32).toString('base64url');
        db.prepare('INSERT INTO subscriptions(id, owner, entity, project, metric, name, config, fingerprint, callback_hash) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)')
          .run(id, owner, rule.entity, rule.project, rule.metric, rule.name, JSON.stringify(rule), fingerprint, hash(secret));
        try {
          const integrationId = await wandb.createIntegration(authorization, rule.entity, `Android alert ${id}`, new URL(`/hooks/${secret}`, endpoint).href);
          db.prepare('UPDATE subscriptions SET integration_id=? WHERE id=?').run(integrationId, id);
          const triggerId = await wandb.createTrigger(authorization, rule, projectId, integrationId);
          db.prepare("UPDATE subscriptions SET trigger_id=?, status='active' WHERE id=?").run(triggerId, id);
          response.writeHead(201); response.end(JSON.stringify({id, status: 'active'}));
        } catch (error) {
          db.prepare("UPDATE subscriptions SET status='failed' WHERE id=?").run(id);
          throw error;
        }
        return;
      }
      const subscription = /^\/v1\/subscriptions\/([A-Za-z0-9-]+)$/.exec(path);
      if (subscription && request.method === 'DELETE') {
        const rule = db.prepare('SELECT * FROM subscriptions WHERE id=? AND owner=?').get(subscription[1], owner);
        if (!rule) throw new HttpError(404, 'Alert not found');
        if (rule.status === 'provisioning') throw new HttpError(409, 'Alert setup is still in progress. Wait for it to finish before deleting.');
        if (rule.trigger_id) {
          await wandb.deleteTrigger(authorization, rule.trigger_id);
          db.prepare('UPDATE subscriptions SET trigger_id=NULL WHERE id=?').run(rule.id);
        }
        if (rule.integration_id) await wandb.deleteIntegration(authorization, rule.integration_id);
        db.prepare('DELETE FROM subscriptions WHERE id=? AND owner=?').run(rule.id, owner);
        response.end('{}'); return;
      }
      throw new HttpError(404, 'Not found');
    } catch (error) {
      response.writeHead(error instanceof HttpError ? error.status : 500);
      response.end(JSON.stringify({error: error instanceof HttpError ? error.message : 'Request failed. Please retry.'}));
    }
  });
  server.requestTimeout = 30_000;
  server.headersTimeout = 10_000;

  async function drain() {
    if (draining) return;
    draining = true;
    try {
      db.prepare("UPDATE deliveries SET status='expired' WHERE event_id IN (SELECT id FROM events WHERE created_at<?) AND status='pending'").run(now() - day);
      const jobs = db.prepare(`SELECT d.*, e.payload, e.owner FROM deliveries d JOIN events e ON d.event_id=e.id
        JOIN devices v ON v.token=d.token AND v.owner=e.owner
        WHERE d.status='pending' AND d.next_attempt<=? LIMIT 50`).all(now());
      for (const job of jobs) {
        try {
          const current = db.prepare(`SELECT e.payload, e.owner FROM deliveries d
            JOIN events e ON e.id=d.event_id
            JOIN subscriptions s ON s.id=e.subscription_id AND s.status='active'
            JOIN devices v ON v.token=d.token AND v.owner=e.owner
            WHERE d.event_id=? AND d.token=? AND d.status='pending' AND e.created_at>?`)
            .get(job.event_id, job.token, now() - day);
          if (!current) continue;
          const payload = JSON.parse(current.payload);
          await send({token: job.token,
            data: {eventId: job.event_id, owner: current.owner, title: payload.title.slice(0, 120), body: payload.body,
              entity: payload.entity, project: payload.project, run: payload.run},
            android: {priority: 'high', ttl: day},
          });
          db.prepare("UPDATE deliveries SET status='sent', attempts=attempts+1 WHERE event_id=? AND token=?").run(job.event_id, job.token);
        } catch (error) {
          if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error.code)) {
            db.prepare('DELETE FROM devices WHERE token=?').run(job.token);
          } else {
            db.prepare('UPDATE deliveries SET attempts=attempts+1, next_attempt=? WHERE event_id=? AND token=?')
              .run(now() + Math.min(3_600_000, 1000 * 2 ** Math.min(job.attempts, 12)), job.event_id, job.token);
          }
        }
      }
      db.prepare('DELETE FROM events WHERE created_at<?').run(now() - 30 * day);
    } finally { draining = false; }
  }

  return {server, drain, close: () => db.close()};
}

async function readJson(request) {
  if (request.method === 'GET') return {};
  if (!request.headers['content-length'] && !request.headers['transfer-encoding']) return {};
  if (request.headers['content-length'] === '0') return {};
  if (!(request.headers['content-type'] ?? '').startsWith('application/json')) throw new HttpError(415, 'Use application/json');
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 65_536) throw new HttpError(413, 'Request body too large');
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!value || Array.isArray(value) || typeof value !== 'object') throw new Error();
    return value;
  } catch { throw new HttpError(400, 'Invalid JSON object'); }
}

export function validateRule(body) {
  for (const field of ['entity', 'project']) {
    if (typeof body[field] !== 'string' || !body[field] || body[field].length > 128 || /[\/\x00-\x1f]/.test(body[field])) throw new HttpError(400, `Invalid ${field}`);
  }
  if (body.metric != null && (typeof body.metric !== 'string' || !body.metric || body.metric.length > 512)) throw new HttpError(400, 'Invalid metric');
  const metric = body.metric ?? null;
  const direction = body.direction ?? 'ANY';
  const basis = body.basis ?? 'ABSOLUTE';
  if (!['ANY', 'INCREASE', 'DECREASE'].includes(direction) || !['ABSOLUTE', 'RELATIVE'].includes(basis)) throw new HttpError(400, 'Invalid metric comparison');
  if (metric && (typeof body.amount !== 'number' || !Number.isFinite(body.amount) || body.amount <= 0)) throw new HttpError(400, 'Change amount must be positive');
  const verb = {ANY: 'increases or decreases', INCREASE: 'increases', DECREASE: 'decreases'}[direction];
  return {entity: body.entity, project: body.project, metric, direction, basis, amount: metric ? body.amount : null,
    name: metric ? `${metric} ${verb} by at least ${body.amount}${basis === 'RELATIVE' ? '%' : ''}` : `${body.project}: run failed`,
  };
}
