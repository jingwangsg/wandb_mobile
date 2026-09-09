import {readFile} from 'node:fs/promises';
import {buildClientSchema, getIntrospectionQuery, parse, validate} from 'graphql';
import {fileURLToPath} from 'node:url';

const root = new URL('../../', import.meta.url);
const response = await fetch('https://api.wandb.ai/graphql', {
  method: 'POST', headers: {'content-type': 'application/json'},
  body: JSON.stringify({query: getIntrospectionQuery()}), signal: AbortSignal.timeout(30_000),
});
const payload = await response.json();
if (!response.ok || payload.errors) throw new Error('Unable to retrieve the W&B schema');
const schema = buildClientSchema(payload.data);
const operations = [];
for (const filename of ['lib/core/api/graphql_queries.dart', 'lib/core/api/mobile_queries.dart']) {
  const source = await readFile(new URL(filename, root), 'utf8');
  const constants = new Map();
  for (const match of source.matchAll(/static const (\w+)\s*=([\s\S]*?);/g)) {
    const parts = [...match[2].matchAll(/r?'''([\s\S]*?)'''|\b(runFields)\b/g)];
    const text = parts.map(part => part[1] ?? constants.get(part[2])).join('');
    constants.set(match[1], text);
    if (/^\s*(query|mutation)\b/.test(text)) operations.push({name: match[1], text});
  }
}
const gateway = await readFile(new URL('server/src/wandb.mjs', root), 'utf8');
for (const match of gateway.matchAll(/this\.query\(authorization,\s*(?:`([\s\S]*?)`|'([^']*)')/g)) {
  operations.push({name: 'relay', text: match[1] ?? match[2]});
}
let failures = 0;
for (const operation of operations) {
  const errors = validate(schema, parse(operation.text));
  if (errors.length) {
    failures++;
    console.error(operation.name, errors.map(error => error.message));
  }
}
console.log(`${operations.length - failures}/${operations.length} GraphQL operations match the live W&B schema.`);
console.log(`Source root: ${fileURLToPath(root)}`);
process.exitCode = failures ? 1 : 0;
