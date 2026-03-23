<p align="center">
  <img src="https://raw.githubusercontent.com/wandb/assets/main/wandb-dots-logo.svg" alt="W&B Logo" width="80" />
</p>

<h1 align="center">WandbMobile</h1>

<p align="center">
  <strong>A native mobile client for <a href="https://wandb.ai">Weights & Biases</a></strong><br/>
  Monitor your ML experiments from anywhere.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.7+-02569B?logo=flutter" alt="Flutter 3.7+" />
  <img src="https://img.shields.io/badge/Dart-3.7+-0175C2?logo=dart" alt="Dart 3.7+" />
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20macOS-brightgreen" alt="Platforms" />
</p>

---

## Features

### Experiment Monitoring
- **Project Browser** — Browse all projects across personal and team entities with search and pagination
- **Run Dashboard** — View run state, duration, tags, config, and summary metrics at a glance
- **Real-time Polling** — Active runs auto-refresh every 30 seconds

### Interactive Charts
- **Smart Metric Selection** — Automatically prioritizes headline metrics (loss, accuracy, f1) and groups by prefix (`train/`, `val/`, `eval/`)
- **Native Gestures** — Pinch-to-zoom, pan, double-tap zoom, and trackball tooltip for data inspection
- **Chart Customization** — Per-metric smoothing (EMA), custom Y-axis and X-axis bounds with auto/manual toggle
- **Expandable Full-Screen View** — Tap any chart to expand with full rule editor
- **LTTB Downsampling** — Largest Triangle Three Buckets algorithm preserves visual fidelity while keeping charts snappy

### System Metrics
- **Hardware Monitoring** — GPU utilization, CPU usage, memory, temperature, disk, and network metrics
- **Smart Defaults** — Auto-selects the most relevant system metrics

### Run Files
- **Artifact Browser** — Browse and download run files (logs, checkpoints, model weights)
- **File Metadata** — Size, type, modification date, and MD5 hash

### Adaptive UI
- **Phone** — Bottom navigation, single-column layout, bottom-sheet metric selector
- **Tablet / Desktop** — Navigation rail, master-detail split, collapsible sidebar metric selector
- **Responsive Grid** — 1 / 2 / 3 column layouts based on screen width

---

## Architecture

```
lib/
├── core/                          # Shared infrastructure
│   ├── api/                       #   GraphQL client (Basic Auth + Dio)
│   ├── models/                    #   Data models (Run, Project, MetricPoint, etc.)
│   ├── providers/                 #   API client providers
│   ├── diagnostics/               #   Runtime error logging (circular buffer -> disk)
│   ├── utils/                     #   LTTB downsampling, formatting, responsive breakpoints
│   ├── theme/                     #   W&B brand colors, Material themes
│   └── widgets/                   #   Shared widgets (WandbMarkIcon)
│
├── features/                      # Feature modules (Clean Architecture)
│   ├── auth/                      #   API key login, secure storage, entity switching
│   ├── projects/                  #   Paginated project list with search
│   ├── runs/                      #   Run list, run detail, metrics/system/files panels
│   ├── charts/                    #   Chart preferences, rules, grouped chart area
│   ├── sweeps/                    #   Hyperparameter sweep support
│   ├── dashboard/                 #   Welcome screen
│   └── settings/                  #   Account info, logout, diagnostics viewer
│
└── routing/                       # GoRouter with adaptive shell (tabs <-> rail)
```

**State Management** — [Riverpod](https://riverpod.dev) throughout (StateNotifier for auth, FutureProvider for async data, StateProvider for UI state)

**Navigation** — [GoRouter](https://pub.dev/packages/go_router) with a 3-tab adaptive shell that switches between `BottomNavigationBar` and `NavigationRail` based on screen width

**Charts** — [Syncfusion Flutter Charts](https://pub.dev/packages/syncfusion_flutter_charts) with custom trackball, zoom behavior, and per-metric axis rules

---

## Getting Started

### Prerequisites

- Flutter SDK >= 3.7.0
- A [Weights & Biases](https://wandb.ai) account and API key

### Run

```bash
# Install dependencies
flutter pub get

# Run on connected device or emulator
flutter run

# Build release APK
flutter build apk --release
```

### Login

1. Launch the app
2. Paste your W&B API key (find it at [wandb.ai/authorize](https://wandb.ai/authorize))
3. *(Optional)* Tap **Advanced** to set a custom API base URL for self-hosted instances
4. Select your entity (personal or team)

---

## Key Dependencies

| Category | Package | Purpose |
|----------|---------|---------|
| State | `flutter_riverpod` | Reactive state management |
| Network | `dio` | HTTP client for GraphQL API |
| Charts | `syncfusion_flutter_charts` | Interactive line charts |
| Navigation | `go_router` | Declarative routing |
| Storage | `flutter_secure_storage` | Encrypted credential storage |
| Storage | `hive_flutter` | Local chart preferences |
| UI | `google_fonts` | Typography |
| UI | `shimmer` | Loading skeletons |

---

<p align="center">
  Built with Flutter & the W&B API
</p>
