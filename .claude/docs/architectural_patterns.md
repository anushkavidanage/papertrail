# Architectural Patterns & Conventions

Patterns observed across multiple files in Papertrail. Follow these when
extending the app.

## Layered Architecture

Strict one-way data flow; each layer only talks to the one below it:

```
screens/  ──►  ReceiptStore  ──►  PodService  ──►  solidpod API
(widgets)      (in-memory state)  (Pod I/O)        (network + encryption)
```

- **Screens never call `PodService` for receipt CRUD** — they go through
  `ReceiptStore.instance` (`lib/services/receipt_store.dart:15`), which
  persists via `PodService` and then updates its cached list and notifies
  listeners (`lib/services/receipt_store.dart:79-102`).
- The single exception is attachment byte streaming, which screens read
  directly via `PodService.instance.readAttachmentBytes`
  (`lib/screens/receipt_detail_screen.dart:266`) because bytes are
  loaded on demand and not cached in the store.
- Serialisation is isolated in `ReceiptSerializer`
  (`lib/services/receipt_serializer.dart:16`); only `PodService` uses it.

## Singleton Services (no DI framework)

Services are private-constructor singletons exposed via a static `instance`:

- `PodService._(); static final PodService instance = PodService._();`
  (`lib/services/pod_service.dart:28-29`)
- `ReceiptStore._(); static final ReceiptStore instance = ReceiptStore._();`
  (`lib/services/receipt_store.dart:16-17`)

There is no provider/get_it/riverpod. New services should follow the same
pattern unless the dependency graph grows enough to justify a change.

## State Management: ChangeNotifier + ListenableBuilder

- `ReceiptStore` extends `ChangeNotifier` and is the single source of truth
  for receipt data plus a `StoreStatus` enum (`idle/loading/ready/error`) and
  an `error` string (`lib/services/receipt_store.dart:13-29`).
- Screens subscribe with `ListenableBuilder(listenable: ReceiptStore.instance)`
  rather than holding their own copies:
  `lib/screens/all_receipts_view.dart:58`,
  `lib/screens/receipt_detail_screen.dart:76`.
- Detail screens hold only an **id** and look the object up from the store on
  each build (`lib/screens/receipt_detail_screen.dart:79`), so edits/deletes
  elsewhere are reflected automatically and a deleted receipt renders a
  graceful "no longer available" fallback.
- Local, screen-only state (search query, filter, form fields) lives in
  `StatefulWidget` state with `setState`.

## Pod Readiness & the LockedBackdrop

Encrypted Pod access needs login + the user's security key. The convention:

- All loads go through `ReceiptStore.refresh(context, backdrop)`
  (`lib/services/receipt_store.dart:56`), which calls
  `PodService.ensureReady` (`lib/services/pod_service.dart:47-52`) to trigger
  the solidui key prompt if required.
- A `const LockedBackdrop()` widget is always passed as the backdrop
  (`lib/screens/home_shell.dart:30`, `lib/screens/all_receipts_view.dart:31`).
- The initial load is deferred to `addPostFrameCallback` so the key prompt has
  a valid Navigator context (`lib/screens/home_shell.dart:28-32`).
- Pod methods guard with `isUserLoggedIn()` and throw `NotReadyException`
  with a user-readable message (`lib/services/pod_service.dart:20-25,70-72`).

## Dual-Format Turtle Serialisation

Each receipt file carries two representations
(`lib/services/receipt_serializer.dart:1-10`):

1. Human-readable RDF triples (`rdfs:label`, `schema:price`, `pt:category`…)
   for transparency when browsed with other Solid tools.
2. A canonical base64-encoded JSON payload in a single `pt:data` triple —
   **the only thing read back** (`lib/services/receipt_serializer.dart:67-77`),
   guaranteeing a lossless round-trip regardless of Turtle escaping.

When adding a model field: extend `Receipt.toJson`/`fromJson` (with a
backward-compatible default in `fromJson`,
`lib/models/receipt.dart:166-188`), optionally emit a readable triple, and
extend the round-trip test (`test/receipt_serializer_test.dart`).

## Model Conventions

- `Receipt` uses an immutable `id`/`createdAt` with mutable other fields, plus
  `copyWith` that includes explicit `clearX` booleans for nullable fields
  (`clearWarrantyExpiry`, `clearAttachment` —
  `lib/models/receipt.dart:109-145`) since `null` can't distinguish
  "unchanged" from "cleared".
- `fromJson` is defensive: every field has a fallback default so older or
  partial payloads still parse (`lib/models/receipt.dart:166-188`).
- Derived state lives on the model as getters (`hasAttachment`,
  `attachmentKind`, `isWarrantyExpired`, `warrantyDaysRemaining` —
  `lib/models/receipt.dart:88-107`).
- Receipt ids are UUIDs generated at creation
  (`lib/screens/add_edit_receipt_screen.dart:29`) and double as the Pod file
  name stem.

## Error-Handling Conventions

- **Best-effort cleanup ops swallow errors** with an explanatory comment:
  container creation (`lib/services/pod_service.dart:55-63`) and attachment
  deletion (`lib/services/pod_service.dart:163-169`).
- **Unreadable individual files are skipped, not fatal**: `loadReceipts`
  logs via `debugPrint` and continues (`lib/services/pod_service.dart:89-96`).
- **User-facing failures use SnackBars** with a short message + the exception
  (`lib/screens/receipt_detail_screen.dart:67-71,281-289`).
- **Async UI actions set a busy flag** (`_busy`, `_saving`, `_openingPdf`)
  that disables buttons / wraps the body in `AbsorbPointer`
  (`lib/screens/receipt_detail_screen.dart:28,103`), reset in
  `finally`/error paths.
- **Always check `mounted`** after an `await` before touching `context`
  (`lib/services/pod_service.dart:49`,
  `lib/screens/receipt_detail_screen.dart:64,291`).

## File & Widget Organisation

- Every file opens with a `///` doc comment describing its purpose, followed
  by `library;` (all files under `lib/`).
- One screen per file in `lib/screens/`; screen-private helper widgets are
  private classes in the same file (`_InfoRow`, `_ChipBlock`,
  `_AttachmentViewer` in `lib/screens/receipt_detail_screen.dart`).
- Only genuinely shared widgets go in `lib/widgets/`.
- All tunable values (Pod paths, OIDC config, default categories/flags,
  currencies, accepted extensions, theme colour) are constants in
  `lib/constants/app_config.dart` — never inline them.
- Formatting helpers in `lib/utils/formatting.dart` are deliberately
  dependency-free (no `intl`); use `formatDate`/`formatMoney`/`relativeDay`
  rather than ad-hoc formatting.
- Add/edit is a single form screen distinguished by an optional `existing`
  parameter (`lib/screens/add_edit_receipt_screen.dart:16-21`), not separate
  create/edit screens.

## Navigation

Plain `Navigator.push` with `MaterialPageRoute` for detail/form screens
(`lib/screens/all_receipts_view.dart:48-53`,
`lib/screens/home_shell.dart:35-39`); top-level tab navigation is handled by
solidui's `SolidScaffold` menu (`lib/screens/home_shell.dart:43-64`). No named
routes or router package.
