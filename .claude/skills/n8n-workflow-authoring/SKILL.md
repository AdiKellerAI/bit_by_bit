---
name: n8n-workflow-authoring
description: Use when creating, editing, importing, or debugging an n8n workflow in this repo (n8n/workflows/*.json) - there is no browser/UI available, workflows are hand-authored as JSON and imported via the n8n CLI. Covers exact node schemas, credential import, activation, and this n8n version's non-obvious webhook URL scheme, all discovered by reading n8n's own source inside the running container.
---

# Authoring n8n workflows without a browser

Claude Code has no browser - n8n workflows in this repo are hand-authored as JSON
(`n8n/workflows/*.json`) and imported via the n8n CLI, not built by clicking through the
editor UI. This is inherently higher-risk than using the UI (no live parameter validation), so
this skill documents how to get the exact schema right by reading n8n's own source, and the
version-specific gotchas already hit once (n8n 2.34.6 at time of writing - re-verify against
the running container's actual version/source if it's been upgraded).

## Finding the exact node schema (do this before guessing)

Node parameter shapes are not fully guessable from memory - versions change them. Read the
real source inside the running container instead:
```sh
docker compose exec -T n8n sh -c "find /usr/local/lib/node_modules/n8n -path '*nodes-base/dist/nodes/<NodeName>*' ! -name '*.map'"
docker compose exec -T n8n sh -c "cat '<path from above>'"
```
Look for: the node's `name`/`displayName`/`version` (top of the `*.node.js` or
`versionDescription.js` file), its `credentials` array (credential type name), and the
`properties` array for exact parameter `name`s and `default`s. Many nodes' source even embeds
a literal example in a `builderHint`/pattern block (e.g. the IF node's filter condition
shape, the Code node's `jsCode` pattern) - grep for `builderHint`, `pattern`, or `example`
first, it's often faster than reading the whole properties array.

Credential schemas: `docker compose exec -T n8n sh -c "cat '.../dist/credentials/<Name>.credentials.js'"`.

## Confirmed node schemas (this version)

- **Webhook** (`n8n-nodes-base.webhook`, v2.1): `parameters.httpMethod`, `parameters.path`
  (no leading/trailing slash), `parameters.responseMode` = `'responseNode'` to control the
  response yourself via a separate Respond node. Output item shape:
  `{ headers, params, query, body }` - inbound JSON body is at `$json.body`, not spread onto
  `$json` directly.
- **Code** (`n8n-nodes-base.code`, v2): `parameters.mode` = `'runOnceForAllItems'` (usually),
  `parameters.language` = `'javaScript'`, `parameters.jsCode` (string). Return
  `[{ json: {...} }, ...]`. `$env.VAR` access is **blocked by default** - see the env-access
  note below.
- **IF** (`n8n-nodes-base.if`, v2.2): `parameters.conditions` = `{ combinator: 'and'|'or',
  conditions: [{ leftValue, rightValue, operator: { type, operation } }], options: {
  caseSensitive: true, leftValue: '', typeValidation: 'strict', version: 2 } }`. Two outputs,
  index 0 = true branch, index 1 = false branch (`outputNames: ['true','false']`). The
  `options.version` number must match the node's own typeVersion per this formula (from the
  node's own source): `nodeVersion >= 2.3 ? 3 : nodeVersion >= 2.2 ? 2 : 1`.
- **Postgres** (`n8n-nodes-base.postgres`, v2.5, credential type `postgres`):
  `parameters.resource = 'database'`, `parameters.operation = 'executeQuery'`,
  `parameters.query` (raw SQL string, supports `$1`/`$2`/... placeholders),
  `parameters.options.queryReplacement` = an n8n expression evaluating to a comma-joined
  string or array - this fills `$1`/`$2`/etc positionally. Prefer this over interpolating
  values directly into the query string (the node's own description warns about SQL
  injection). Credential fields: `host, database, user, password, port, ssl
  ('disable'|'allow'|'require'), allowUnauthorizedCerts, maxConnections`. Host must be the
  **docker-compose service name** (`postgres`), not `localhost`.
- **Telegram** (`n8n-nodes-base.telegram`, v1.2, credential type `telegramApi`):
  `parameters.resource = 'message'`, `parameters.operation = 'sendMessage'`,
  `parameters.chatId`, `parameters.text`. Credential fields: `accessToken, baseUrl` (default
  `https://api.telegram.org`).
- **Respond to Webhook** (`n8n-nodes-base.respondToWebhook`, v1.4):
  `parameters.respondWith = 'text'`, `parameters.responseBody` (string),
  `parameters.options.responseCode` (number, default 200).

## Cross-node data access

Don't assume the immediately-upstream node's output carries everything you need - a Postgres
node's output is just its query result, dropping earlier fields. Reference any prior node's
item explicitly instead: `$('Node Name').item.json.fieldName`. This avoids needing a Merge
node just to keep earlier fields alive across a DB write.

## Postgres idempotent-insert pattern

`INSERT ... ON CONFLICT DO NOTHING RETURNING ...` returns **zero rows** on a duplicate, which
is awkward to branch on with a per-item IF node (0 items just means nothing downstream runs,
not a clean true/false). Use the `xmax = 0` trick instead - it always returns exactly one row:
```sql
INSERT INTO t (key_col, ...) VALUES ($1, ...)
ON CONFLICT (key_col) DO UPDATE SET key_col = EXCLUDED.key_col
RETURNING (xmax = 0) AS is_new;
```
`is_new = true` means it was actually inserted; `false` means it already existed. Branch an
IF node on `{{ $json.is_new }}`.

## Secrets in Code nodes: `$env` access

`$env.VAR` in a Code node is **blocked by default** (`N8N_BLOCK_ENV_ACCESS_IN_NODE` defaults
to blocking unless explicitly set to `'false'`). This project deliberately enables it (see
`docker-compose.yml`'s n8n service) so secrets like `TELEGRAM_WEBHOOK_SECRET` can be verified
inside a Code node without ever being embedded in the workflow JSON - this is the intended,
safer pattern per PROJECT-SPEC.md §4.3, not a shortcut. Only expose the specific env vars a
Code node genuinely needs to compare against, via `docker-compose.yml`'s `environment:` block.

## Import, activate, and the webhook URL scheme

1. Every workflow/credential JSON needs an explicit top-level `"id"` - imports fail with
   `SQLITE_CONSTRAINT: NOT NULL constraint failed` otherwise (IDs aren't auto-generated here).
2. Copy the file into the container and import:
   ```sh
   docker compose cp n8n/workflows/<file>.json n8n:/tmp/<file>.json
   docker compose exec -T n8n n8n import:workflow --input=/tmp/<file>.json
   ```
3. Import **always deactivates** the workflow, regardless of `"active": true` in the JSON.
   Activate explicitly: `docker compose exec -T n8n n8n publish:workflow --id=<workflowId>`
   (the classic `update:workflow --active` is deprecated in this version).
4. **Restart n8n** - webhook routes are only registered at process startup, so publishing
   alone doesn't make a running instance serve the new route:
   `docker compose restart n8n`, then wait for `healthy`.
5. **The production webhook URL is `/webhook/<workflowId>/webhook/<path>`, not
   `/webhook/<path>`.** Confirmed by reading `webhooks/live-webhooks.js` and
   `webhook.service.js` inside the container, and by querying the `webhook_entity` table
   directly (`findStaticWebhookInDb` matches on the exact stored `webhookPath`, which is
   `<workflowId>/webhook/<path>`). Register this full path with any external provider (e.g.
   Telegram's `setWebhook`) - the shorter path from older n8n docs/tutorials will 404.

## Debugging without the UI

- Executions: n8n's SQLite DB is at `/home/node/.n8n/database.sqlite`. Query it with Node's
  bundled `sqlite3` package, run from inside n8n's own install so module resolution works:
  ```sh
  docker compose exec -T n8n sh -c "cd /usr/local/lib/node_modules/n8n && node -e \"
  const sqlite3 = require('sqlite3');
  const db = new sqlite3.Database('/home/node/.n8n/database.sqlite', sqlite3.OPEN_READONLY);
  db.all('SELECT id, status, finished FROM execution_entity ORDER BY startedAt DESC LIMIT 5', [], (e,r) => { console.log(JSON.stringify(r)); db.close(); });
  \""
  ```
- `execution_data.data` is a flattened/indexed JSON blob (not plain nested JSON) - hard to
  read directly, but a quick `JSON.parse(...).findIndex(...)` / substring search for a known
  field name (e.g. `'x-telegram-bot-api-secret-token'`) will locate the real values fast
  enough without needing to fully deserialize it.
- `docker compose logs n8n --tail 100` shows the same errors the execution DB does (e.g. a
  downstream API's rejection reason) - check here first, it's faster than the DB.
