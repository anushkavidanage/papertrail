# CLAUDE.md

## Project Overview

**Papertrail** — a Flutter app for tracking purchase receipts, stored privately
in the user's own [Solid](https://solidproject.org) Pod. There is no app
server: every receipt (encrypted Turtle file) and attachment (encrypted blob)
is written to the user's personal online datastore via the `solidpod` /
`solidui` packages, encrypted with the user's security key.

## Tech Stack

- **Flutter / Dart** (SDK ^3.12.0), Material 3
- **solidpod** — Solid Pod storage, encryption, auth (`readPod`, `writePod`, large-file API)
- **solidui** — ready-made Solid UI: `SolidLogin`, `SolidScaffold`, `SolidThemeApp`, `SolidFile`
- **file_picker**, **open_filex**, **path_provider**, **uuid**
- Targets: desktop + mobile only (uses `dart:io`; **no web support**)

## Key Directories

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | Entry point |
| `lib/app.dart` | Root widget: `SolidThemeApp` → `SolidLogin` → `HomeShell` |
| `lib/constants/app_config.dart` | All app constants: Pod directory names, OIDC client config, default categories/flags/currencies, theme seed |
| `lib/models/receipt.dart` | `Receipt` domain model (JSON-serialisable, `copyWith`) |
| `lib/services/receipt_serializer.dart` | `Receipt` ⇄ Turtle conversion |
| `lib/services/pod_service.dart` | Thin singleton wrapper around `solidpod` (read/write/delete receipts + attachments) |
| `lib/services/receipt_store.dart` | Shared in-memory state, `ChangeNotifier` singleton |
| `lib/screens/` | One file per screen/tab (home shell, recent, all, add/edit form, detail) |
| `lib/widgets/` | Reusable widgets (`ReceiptCard`, `LockedBackdrop`) |
| `lib/utils/formatting.dart` | Dependency-free date/money formatting helpers |
| `test/` | Unit tests (serialisation round-trip) |

## Data Layout on the Pod

Everything lives under `papertrail/data/` in the user's Pod:

- Receipts: `receipts/<uuid>.ttl` — encrypted Turtle with human-readable
  triples plus a canonical base64 JSON payload in `pt:data` (only `pt:data`
  is read back; see `lib/services/receipt_serializer.dart:1-10`)
- Attachments: `attachments/<uuid>` — encrypted blob via the large-file API

Directory names are constants in `lib/constants/app_config.dart:20-26`.

## Essential Commands

```bash
flutter pub get        # install dependencies
flutter run            # run on a connected device (Windows/macOS/Linux/Android/iOS)
flutter test           # run unit tests
flutter analyze        # static analysis (flutter_lints via analysis_options.yaml)
```

## Important Notes

- The OIDC client config in `lib/constants/app_config.dart:39-51` is the
  public example registration — fine for development; must be replaced for a
  production release.
- Pod operations require both login **and** the security key; always go
  through `PodService.ensureReady` / `ReceiptStore.refresh` with a
  `LockedBackdrop` (see `lib/services/pod_service.dart:47-52`).
- Changing the Turtle format must keep `pt:data` round-trip compatibility —
  update `test/receipt_serializer_test.dart` accordingly.

## Additional Documentation

Check these when relevant to the task:

- `.claude/docs/architectural_patterns.md` — architectural patterns and
  conventions used throughout the codebase (singleton services, layered data
  flow, ChangeNotifier state management, error-handling conventions, file
  organisation). Read before adding new screens, services, or model fields.
