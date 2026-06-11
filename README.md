# Papertrail

Track your purchase receipts — stored privately in **your own** [Solid](https://solidproject.org) Pod.

Papertrail is a Flutter app built on
[`solidpod`](https://pub.dev/packages/solidpod) and
[`solidui`](https://pub.dev/packages/solidui). Every receipt, photo and PDF is
written to the user's personal online datastore (Pod), encrypted with the
user's security key. Nothing is stored on any Papertrail server — there isn't
one.

## Features

- **Solid login** – authenticate against any Solid server; data lives in your Pod.
- **Add / edit / delete receipts** with:
  - title, amount + currency, purchase date, store/vendor, free-text notes;
  - one or more **categories** (Grocery, Electronics, Garden, … or your own);
  - arbitrary **flags** (Tax deductible, Reimbursable, Important, … or your own);
  - optional **warranty** tracking with an expiry date and an "expired/expires
    in N days" indicator.
- **Attachments** – attach a **photo** or a **PDF** of the receipt. Files are
  uploaded to your Pod with the encrypted large-file API and viewed on demand
  (images inline, PDFs opened with the system viewer).
- **Home overview** – receipt count, tracked total, and your most recent receipts.
- **All receipts** – full list with **text search** and **category filters**.
- **Files** – browse the raw files on your Pod via the built-in Solid file browser.

## How data is stored on the Pod

Everything lives under `papertrail/data/` in the Pod:

| What | Where | Format |
| --- | --- | --- |
| Receipt | `receipts/<uuid>.ttl` | Encrypted Turtle. Human-readable triples plus a canonical base64-encoded JSON payload (`pt:data`) for lossless round-tripping. |
| Attachment | `attachments/<uuid>` | Encrypted blob via the Solid large-file API. |

The receipts container is listed with `getResourcesInContainer`; each file is
read with `readPod` and parsed back into a `Receipt`.

## Project layout

```
lib/
  main.dart                       app entry point
  app.dart                        SolidThemeApp → SolidLogin → HomeShell
  constants/app_config.dart       app id, OIDC client config, categories, flags
  models/receipt.dart             the Receipt domain model
  services/
    receipt_serializer.dart       Receipt ⇄ Turtle
    pod_service.dart              read/write/delete on the Pod (solidpod wrapper)
    receipt_store.dart            shared in-memory state (ChangeNotifier)
  screens/
    home_shell.dart               SolidScaffold with navigation + add FAB
    recent_receipts_view.dart     home overview + recent list
    all_receipts_view.dart        searchable / filterable list
    add_edit_receipt_screen.dart  the receipt form
    receipt_detail_screen.dart    detail view + attachment viewer
  widgets/
    receipt_card.dart             list item
    locked_backdrop.dart          backdrop shown behind the key prompt
  utils/formatting.dart           date / money helpers
test/
  receipt_serializer_test.dart    serialisation round-trip tests
```

## Running

```bash
flutter pub get
flutter run            # choose a device (Windows/macOS/Linux/Android/iOS)
```

Desktop and mobile are the supported targets (the app uses `dart:io` for
attachment files, so it does not run on the web).

### Solid OIDC configuration

`lib/constants/app_config.dart` ships with the publicly published example client
registration so login works out of the box during development. **For a
production release**, register your own client profile document and replace
`clientId` / `redirectUris` with your own values. On mobile you will also need
to register your redirect custom-scheme in the Android manifest / iOS Info.plist
so the OIDC redirect returns to the app; desktop uses a `localhost` loopback and
needs no extra setup.

## Tests

```bash
flutter test
```
