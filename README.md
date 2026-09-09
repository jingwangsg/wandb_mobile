# WandbMobile for Android

A Flutter client for Weights & Biases. The Android upgrade uses the official
iOS app's inspected fonts, icons, navigation, and documented interactions.
It is not an official W&B release. Current-version pixel equivalence has not
been verified; see [reference and acceptance notes](docs/android-upgrade.md).

## Implemented workflows

- Five tabs: Runs, Projects, ARIA, Notifications, and Profile.
- Personal/team project browsing, search, project stars, run visibility,
  pagination, and automatic refresh.
- Run Charts, Overview, and Logs; configuration, hardware metadata, files,
  searchable/downloadable logs, and confirmed run termination.
- Training charts from sampled history and hardware charts from system events.
  Metric-name regex search, favorites, full-screen charts, zoom, trackballs,
  TWEMA smoothing, logarithmic scale, and per-metric or scope-wide axis settings.
- Image history with step selection and a full-screen gallery.
- ARIA conversations using W&B's agent API, including history, continuation,
  clarification questions, cancellation, feedback, and references. Availability
  depends on the account. Dedicated-host credentials are not sent to SaaS ARIA.
- Optional self-hosted webhook relay for failure and metric-change alerts,
  delivered to opted-in Android devices using Firebase Cloud Messaging.
- Light/dark appearance and account-scoped saved preferences.

## Build and run

Verified toolchain: Flutter 3.47.2 / Dart 3.13.2, Java 17, Android SDK 36.
Android is the supported release target; existing other-platform scaffolding
is not part of this upgrade's acceptance.

```sh
flutter pub get
flutter run --target=lib/main.dart
flutter build apk --release --target=lib/main.dart
```

Sign in with your W&B API key. Dedicated Cloud accepts a custom W&B API URL.
This client uses API-key login, not the official app's browser SSO flow.
Keys are stored with Android secure storage and must not be compiled into an
APK. The current release build uses the development signing key for previews;
configure an operator-owned release key before distribution.

## Push deployment

Monitoring works without Firebase configuration. Actual notifications require
a Firebase project, a deployed HTTPS relay, and device notification permission.
The relay requires a persistent SQLite volume and server-side Firebase
credentials. Neither is supplied by the APK.

See [the relay setup and security guide](server/README.md). Configure public
client options in the ignored `config/android.json` using
[the example](config/android.example.json), then build:

```sh
flutter build apk --release --target=lib/main.dart --dart-define-from-file=config/android.json
```

Do not copy a Firebase service-account private key into client configuration.
Dedicated W&B installations require their own relay with matching host settings.

## Verification

```sh
flutter analyze
flutter test
cd server
npm ci
npm test
npm audit
node scripts/check-wandb-schema.mjs
```

The app tests exercise real UI/provider logic with strict API fixtures; the
relay tests use its HTTP and SQLite paths with isolated external adapters.
Neither proves production Firebase delivery. Review results, live read-only
checks, APK provenance, and remaining external checks are recorded in
[android-upgrade.md](docs/android-upgrade.md).

An explicitly invoked live check reads the local user's `api.wandb.ai` entry
from `~/.netrc` in memory and exercises read-only Flutter API paths against
`nv-gear/gr00t2_pretrain/rz2hg2jr`. It writes counts, not credentials or training
contents, to `build/review/live-api.json`:

```sh
flutter test tool/live_check_test.dart
```

## Code layout

`lib/core` owns GraphQL, models, preferences, theme, and shared UI.
`lib/features` contains authentication, projects, runs, charts, ARIA,
notifications, and settings. Riverpod owns state; GoRouter owns navigation;
Syncfusion renders interactive charts. `server/` contains the standalone push
relay. Reference resource provenance and font licenses are under `assets/`.
