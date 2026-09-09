# Android reference and acceptance

Reference: official Weights & Biases iOS app `6755162576`, bundle
`ai.wandb.wbapp`, downloaded September 9, 2026. Package version `2026.24`, build
`540.1`. IPA SHA-256:
`05ad8fb51af27e0938bf80be4c46ab81bae5d7c2eaa16eda38d983124900c016`.
The licensed IPA and account-specific receipts remain outside the repository.

Package inspection established Source Sans 3 and Inconsolata fonts, 61 design
system icons, five navigation destinations, and localized control labels. Its
executable is encrypted; symbols and resources do not prove runtime equivalence.
Documentation screenshots include older releases, so they are visual references,
not golden screenshots for build 540.1.

Sources:

- [Announcement](https://wandb.ai/wandb_fc/product-announcements-fc/reports/Announcing-the-Weights-Biases-mobile-app-Monitor-AI-training-runs-anytime-anywhere--VmlldzoxNjIyNDQ0MQ)
- [Feature documentation](https://docs.wandb.ai/platform/hosting/monitoring-usage/mobile-app)
- [App Store](https://apps.apple.com/us/app/weights-biases/id6755162576)

## Plan

1. Rebuild Android navigation and screens from verified resources. Verify widget
   interactions, screenshots, and Android builds.
2. Complete project/run search, stars, project panels, live data, logs, overview,
   media, chart options, and ARIA. Check API boundaries against the live schema.
3. Implement the approved W&B webhook → self-hosted relay → Firebase → Android
   path, with deployment instructions. Test authentication, isolation, retries,
   duplicate events, device rotation, and notification deep links.
4. Launch independent functionality, UI, and reliability/security reviewers.
   Address findings and repeat until each approves the tested implementation.
   External verification gaps remain explicit blockers.

## Decisions

- Keep Flutter and the existing data/chart capabilities. Android is the release
  target. Preserve existing API constructors and add optional model metadata.
- Native resource labels identify run tabs as Charts, Overview, and Logs.
- W&B's live schema declares `DevicePlatform = IOS` only. The user selected a
  self-hosted webhook relay. Firebase configuration and a deployed service URL
  are required for actual device delivery; local tests cannot prove delivery.
- Do not automatically commit source or design documents.

## Baseline

- Git: `c66cac44615ff7f9b73564b3f83a282f46bb5c87`.
- Flutter 3.47.2, Dart 3.13.2; 63 baseline tests passed.
- Initial Android build rejected the old Gradle wrapper. Upgrade and reverify.
- IPA downloaded using an isolated ipatool checkout with its upstream redownload
  fallback. The installed Homebrew tool was not modified.

The original preview record is retained below; the final section records the
subsequent fixes and review outcomes for preview 2.0.1.

## Preview verification, September 9

- Flutter suite: 71 tests passed, including full navigation, project stars,
  run visibility, Charts/Overview/Logs, ARIA continuation, alert deletion,
  and appearance selection with screenshot capture.
- Push relay: 10 HTTP/SQLite tests passed; npm audit reports zero vulnerabilities.
- 24 GraphQL operations validated against the live W&B schema.
- Updated user credentials passed the actual Flutter repository path:
  50 projects in one page, 500 loss points, 100 recent log lines with older
  pages available, and 20 system metric rows. No real runs were modified.
- ARIA live read-only checks: availability `true`, history HTTP 200.
- User requested an installable preview before review completion. The preview
  does not include account credentials or configured Firebase deployment values.

## Review round 1: functionality

Original reviewer status: REQUEST_CHANGES. These findings were subsequently
fixed and verified in preview 2.0.1:

1. Fetch/drain final logs when a run reaches a terminal state.
2. Do not invalidate a long-running project chart load on the refresh timer.
3. Preserve loaded pagination during automatic refresh.
4. Remove dismissed alerts synchronously instead of awaiting list refresh.
5. Keep reset chart settings consistent with inherited scope defaults.
6. Support indexed/RGB/background ANSI colors correctly.
7. Display a restored ARIA conversation's actual project context.

At the original preview checkpoint, UI/security review and follow-up fixes were
still pending. Device push delivery and reference pixel equivalence remain
external acceptance gaps; see the updated status below.

## Preview APK

- File: `~/Downloads/WandbMobile-2.0.0-preview-20260909.apk`
- Version: `2.0.0` (`versionCode=2`), package `com.wandb.wandb_mobile`.
- Universal release build: ARM64, ARMv7, x86-64; Android 7.0/API 24 minimum.
- Size reported by Flutter: 61.7 MB. APK v2 signature verified.
- SHA-256: `e2742575187e9b4550facb7275c30078788c3e69bcd332ccfd7347e8b2869362`.
- Installed and cold-launched successfully on the Android API 35 emulator.
- Captured actual launch screen at `build/review/android-preview-login.png`.
- Known review findings above are not yet fixed in this preview. Push needs
  deployment configuration. No user credentials are embedded in the APK.

## Preview 2.0.1: chart fix and review completion, September 9

The reported empty Charts screen was reproduced in the original installed APK
on `nv-gear/gr00t2_pretrain/rz2hg2jr`. Its 85 history metadata keys included 60
system metrics. Those keys were incorrectly sent to training sampled history
and sorted before training metrics. Searching `train/loss` in that same APK
already showed data. This was a client stream-selection and ordering defect,
not evidence that the run had no history.

Training catalogs and previews now exclude both `system/` and `system.` keys.
System event names are normalized to the metadata namespace. Headline training
metrics rank before counters, with logging frequency's ranking contribution
bounded. The shared UI fixture now includes real-shaped mixed history keys
and rejects system queries sent to training history.

Verification on the final source and artifact:

- Flutter: 114/114 tests passed, including image loading across advancing steps,
  push lifecycle recovery, run-stream selection, and full navigation screenshots.
- Relay: 16/16 tests passed; npm audit found zero vulnerabilities. All 24
  GraphQL operations validated against the live W&B schema.
- Live read-only Flutter check at 12:46 UTC: `rz2hg2jr` returned 500 loss points,
  60 system series, 253 CPU points, and 100 log lines with older pages available.
  W&B reported the run state as `crashed`; no run mutations were performed.
- Actual project comparison provider loaded `rz2hg2jr` and `r89j56nv` with
  500 loss points each. Visibility changes were held only in the test's in-memory
  preferences. The harness keeps a subscription alive as the real Panels widget
  does; a one-shot unobserved auto-dispose provider cancels its project scan.
- UI regression verifies two curves with distinct values, full-screen legend,
  hiding a run removing its curve, and restoring it adding the curve back.
  Screenshot: `build/review/compare-runs.png` (fixture data).
- Installed release 2.0.1 on Android API 35, cold-launched, and opened the exact
  target run. `train/loss` is visible first without searching, followed by action
  loss. Screenshot: `build/review/rz2-release-detail.png` (live data).
- Static analysis reported no errors; two pre-existing warnings in diagnostics
  and config_viewer plus style/deprecation infos remain. Builds report upcoming
  Gradle/AGP/Kotlin minimum-version warnings.

Review outcomes after iteration:

- Functionality: APPROVE. Final-log draining, pagination retention, non-cancelling
  numeric refresh, inherited settings reset, ANSI parsing, restored ARIA context,
  and incremental/retryable image history all passed their regressions.
- UI: APPROVE. Image-grid bounds, search synchronization, status-bar icons, dark
  navigation contrast, and mixed-stream chart ordering passed independent tests.
- Security/reliability: APPROVE. Credential host binding, account-scoped push
  opt-in, lifecycle cleanup, ownership rechecks, provisioning races, rate limits,
  cold-start routing, cancellable registration retry, and revoked local identity
  passed their tested failure paths.

These approvals cover the reviewed implementation, not unconfigured Firebase
delivery, current-version pixel identity, or equivalence to official browser SSO.

Delivered artifact:

- `~/OneDrive - Nanyang Technological University/WandbMobile-2.0.1-preview-20260909.apk`
- Version 2.0.1, versionCode 3; universal release APK, 61,825,565 bytes.
- Minimum Android API 24; target API 36; ARM64, ARMv7, and x86-64.
- APK v2 signature verified, using the existing development signing identity.
- SHA-256: `5b132e49b26b42963cd2ba97620ce60a6e49bae829feaf49b3b9160df6479627`.
- The destination was byte-compared with the installed release build. A scan of
  every decompressed APK entry found neither the local W&B key nor its encoded
  variants. No Firebase service-account key or emulator session is packaged.
- The file is present in the requested local OneDrive directory; remote cloud
  synchronization was not verified. The previous preview was not overwritten.
