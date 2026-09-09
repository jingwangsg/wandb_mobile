# Android push relay

W&B automations send a webhook to this service. It durably queues an FCM data
message, and the Android app displays it only when the receiving user is still
signed in and has enabled notifications.

## Configure and run

Use Node 24 for deployment. Node 22.13+ can run the tests; its SQLite module is
marked experimental. Run one service instance per SQLite database. Mount the
database directory on persistent storage and put an HTTPS reverse proxy in front
of the service.

Apply unauthenticated request/IP limits and a 64 KiB body limit at the trusted
reverse proxy. The service limits authenticated owners and validated webhook
subscriptions independently; it does not trust forwarded client-IP headers or
share a single quota across every client behind the proxy.

```sh
cd server
npm ci
npm test
export PUBLIC_URL=https://push.example.com
export DATABASE_PATH=/var/lib/wandb-push/relay.sqlite
export GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/firebase-service-account.json
npm start
```

The Firebase service account must belong to the same Firebase project as the
Android app and have permission to send FCM messages. Credentials remain on the
server. Do not place the service-account JSON in the app, repository, or image.
On Google Cloud, Application Default Credentials from the service's identity can
replace the JSON file.

The optional `WANDB_BASE_URL` defaults to `https://api.wandb.ai`; `PORT` defaults
to `8080`. The W&B host is fixed by the operator, never accepted from an HTTP
request. Use separate relay deployments for different W&B installations.

Build the supplied Dockerfile with `docker build -t wandb-push .`; mount a
persistent directory at `/app/data` and mount credentials read-only. The process
runs as the `node` user. `GET /health` checks process/database availability and
reports the pending delivery count. It does not prove Firebase delivery.

## Configure Android

Register `com.wandb.wandb_mobile` as an Android app in your Firebase project.
Copy `config/android.example.json` to the ignored `config/android.json`, and fill
in the public Android Firebase options from Firebase project settings:

| Field | Source |
| --- | --- |
| `PUSH_RELAY_URL` | This service's HTTPS public origin |
| `PUSH_WANDB_BASE_URL` | Must match this relay's `WANDB_BASE_URL`; defaults to SaaS |
| `FIREBASE_API_KEY` | Android Firebase API key |
| `FIREBASE_APP_ID` | Android Firebase app ID |
| `FIREBASE_SENDER_ID` | Firebase project number / messaging sender ID |
| `FIREBASE_PROJECT_ID` | Firebase project ID |

These are client configuration values; they are not the server's private key.
Build from the repository root:

```sh
flutter build apk --release --dart-define-from-file=config/android.json
```

Sign in, enable **Profile → Push notifications**, and allow Android notification
permission. Create a failure alert from a project menu, or a metric alert from
an expanded chart's bell button. W&B team-admin permissions are required to
create the webhook integration. W&B rejects personal-project automations.
Incomplete setup is shown in Manage notifications; deleting that entry removes
any recorded trigger and integration so the user can retry.

Without configuration, the app still builds and its monitoring features work;
the push setting reports that notifications are unavailable in that build.

## Delivery and security properties

- Device registration and rule management verify the caller's W&B identity.
  The service forwards the API key to the configured W&B host for validation;
  it does not persist or log API keys. Authentication results are cached by a
  one-way digest for 60 seconds.
- Each subscription has a cryptographically random 256-bit webhook URL token.
  The database stores its hash. Treat webhook URLs as credentials: do not log
  request paths for `/hooks/` in the proxy or analytics. The request's entity
  and project must match the subscription.
- SQLite transactions queue messages before acknowledging a webhook. The
  worker retries transient Firebase errors with backoff for up to 24 hours.
  Invalid FCM tokens are removed. Events expire from storage after 30 days.
- Delivery is at least once. W&B's current run-event template variables do not
  contain an execution ID, so identical payloads are suppressed for 60 seconds.
  An identical legitimate event inside that interval is also suppressed. A
  process crash after FCM accepts a message but before SQLite records success
  can cause a retry; the app's notification ID replaces the same event.
- Changing the account associated with a device removes its old pending
  deliveries. The app also checks the message's owner before displaying it.
  Logging out clears the local identity and notification opt-in.
- FCM needs Google Play services. Android force-stop and platform delivery
  restrictions still apply; a delivery deadline is not guaranteed.
- W&B integration/trigger creation spans remote requests and is not atomic.
  Known incomplete resources are retained for explicit cleanup. A process crash
  after W&B creates a resource but before its ID is persisted may require team
  admin cleanup of an `Android alert <UUID>` integration in W&B.

The `uuid` override pins 11.1.1 to fix GHSA-w5hq-g745-h8pq in Firebase's
transitive dependencies. The affected consumers use the compatible `v4()` API.
Remove the override once upstream dependencies require a fixed version.

## Checks

```sh
npm test
npm audit
node scripts/check-wandb-schema.mjs
```

The tests exercise real HTTP handlers and SQLite with isolated W&B/Firebase
adapters. They do not send actual notifications or alter production runs.
End-to-end delivery still requires a configured Firebase project, a reachable
HTTPS deployment, and an Android device with notification permission.
