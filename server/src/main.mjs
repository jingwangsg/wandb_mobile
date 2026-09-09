import {mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
import {applicationDefault, initializeApp} from 'firebase-admin/app';
import {getMessaging} from 'firebase-admin/messaging';
import {createRelay} from './relay.mjs';
import {WandbGateway} from './wandb.mjs';

const configuration = {
  port: Number(process.env.PORT ?? 8080),
  publicUrl: process.env.PUBLIC_URL,
  databasePath: process.env.DATABASE_PATH ?? './data/relay.sqlite',
  wandbBaseUrl: process.env.WANDB_BASE_URL ?? 'https://api.wandb.ai',
};
if (!configuration.publicUrl) throw new Error('PUBLIC_URL is required');
if (!Number.isInteger(configuration.port) || configuration.port < 1 || configuration.port > 65535) throw new Error('Invalid PORT');
mkdirSync(dirname(configuration.databasePath), {recursive: true, mode: 0o700});
initializeApp({credential: applicationDefault()});
const relay = createRelay({
  databasePath: configuration.databasePath, publicUrl: configuration.publicUrl,
  wandb: new WandbGateway(configuration.wandbBaseUrl),
  send: message => getMessaging().send(message),
});
const worker = setInterval(() => relay.drain().catch(() => console.error('delivery_worker_failed')), 1000);
relay.server.listen(configuration.port, '0.0.0.0', () => console.log(`Push relay listening on ${configuration.port}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
  clearInterval(worker);
  relay.server.close(() => { relay.close(); process.exit(0); });
});
