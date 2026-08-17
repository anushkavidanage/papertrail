// Widget tests for SolidWindowCloseGuard as wired up by
// AddEditReceiptScreen — the window-close confirmation path (save / discard /
// keep editing).
//
// Runs without a live Pod: the form's write is replaced via onSave, so only
// rendering / state behaviour is exercised.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:solidui/solidui.dart';

import 'package:papertrail/screens/add_edit_receipt_screen.dart';

/// The title field, then the amount field — the two the form validates.
Finder get _titleField => find.byType(TextField).at(0);
Finder get _amountField => find.byType(TextField).at(1);

/// The dialog's Save, distinguished from the app bar's own Save button.
Finder get _dialogSave =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Save'));

Widget _wrap(Widget child) => MaterialApp(home: child);

/// Fill in enough for the form to validate, so Save is a real option.
Future<void> _fillRequired(WidgetTester tester) async {
  await tester.enterText(_titleField, 'Coffee machine');
  await tester.enterText(_amountField, '42.00');
  await tester.pump();
}

void main() {
  // A failed save parks its message in the shared notifier; clear it so one
  // test cannot leak a pending failure into the next.
  tearDown(SolidWriteFailures.clear);

  testWidgets('resolveAll succeeds with no prompt when nothing changed', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AddEditReceiptScreen()));
    await tester.pumpAndSettle();

    expect(await SolidWindowCloseGuard.resolveAll(), isTrue);
    expect(find.text('Unsaved changes'), findsNothing);
  });

  testWidgets('resolveAll prompts and resolves true on Discard', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AddEditReceiptScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(_titleField, 'Coffee machine');
    await tester.pump();

    final future = SolidWindowCloseGuard.resolveAll();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });

  testWidgets('resolveAll prompts and resolves false on Keep editing', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AddEditReceiptScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(_titleField, 'Coffee machine');
    await tester.pump();

    final future = SolidWindowCloseGuard.resolveAll();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(await future, isFalse);
    // The editor is still open with the unsaved title intact.
    expect(find.text('Coffee machine'), findsOneWidget);
  });

  // Regression: the form used to pop the route from inside its save, so the
  // guard had nothing it could await. resolveAll() returned immediately, the
  // window was destroyed mid-write, and the receipt was lost despite the user
  // tapping Save.
  testWidgets('window-close Save waits for the Pod write to finish', (
    tester,
  ) async {
    final podWrite = Completer<void>();
    var written = false;

    await tester.pumpWidget(
      _wrap(
        AddEditReceiptScreen(
          onSave:
              (
                receipt, {
                attachmentPath,
                removeAttachment = false,
                extraAttachmentPaths = const {},
                extraAttachmentIdsToDelete = const [],
              }) async {
                await podWrite.future;
                written = true;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillRequired(tester);

    var resolved = false;
    final future = SolidWindowCloseGuard.resolveAll()
      ..then((_) => resolved = true);
    await tester.pumpAndSettle();

    await tester.tap(_dialogSave);
    // Not pumpAndSettle: the saving overlay spins for as long as the write is
    // in flight, so there is no settled state to wait for.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The Pod write is still in flight, so the guard must NOT have resolved —
    // otherwise the caller would destroy the window and lose the receipt.
    expect(resolved, isFalse);
    expect(written, isFalse);

    podWrite.complete();
    await tester.pump();
    await tester.pump();

    expect(await future, isTrue);
    expect(written, isTrue);
  });

  testWidgets('editor unregisters its resolver on dispose', (tester) async {
    await tester.pumpWidget(_wrap(const AddEditReceiptScreen()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(const SizedBox()));
    await tester.pumpAndSettle();

    // No editor left registered, so nothing to resolve.
    expect(await SolidWindowCloseGuard.resolveAll(), isTrue);
  });

  // Regression: snapshotting the form as saved before awaiting the write left
  // a failed save looking saved, which silenced the window-close prompt and
  // lost the receipt.
  testWidgets('a failed save leaves the receipt unsaved and still prompting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AddEditReceiptScreen(
          onSave:
              (
                receipt, {
                attachmentPath,
                removeAttachment = false,
                extraAttachmentPaths = const {},
                extraAttachmentIdsToDelete = const [],
              }) async => throw Exception('pod unreachable'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillRequired(tester);

    // Save via the window-close prompt.
    final future = SolidWindowCloseGuard.resolveAll();
    await tester.pumpAndSettle();
    await tester.tap(_dialogSave);
    await tester.pumpAndSettle();

    // The whole point: a failed write must abort the close. Returning true
    // here destroys the window and loses the receipt, with no second call to
    // notice anything was wrong.
    expect(await future, isFalse);

    expect(
      SolidWriteFailures.latest.value,
      contains('Failed saving the receipt.'),
    );

    // The write failed, so the form must still consider itself dirty: a
    // second close attempt has to prompt again rather than discard silently.
    final second = SolidWindowCloseGuard.resolveAll();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await second, isTrue);
  });

  // The app bar's own Save must not close the editor over a write that never
  // landed — the receipt would be gone with only a report to say so.
  testWidgets('the Save button keeps the editor open when the write fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddEditReceiptScreen(
                  onSave:
                      (
                        receipt, {
                        attachmentPath,
                        removeAttachment = false,
                        extraAttachmentPaths = const {},
                        extraAttachmentIdsToDelete = const [],
                      }) async => throw Exception('pod unreachable'),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _fillRequired(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // Still on the editor, with everything the user typed.
    expect(find.byType(AddEditReceiptScreen), findsOneWidget);
    expect(find.text('Coffee machine'), findsOneWidget);
    expect(
      SolidWriteFailures.latest.value,
      contains('Failed saving the receipt.'),
    );
  });

  // Back used to leave the editor silently, discarding everything typed —
  // the same loss the window-close prompt exists to prevent.
  testWidgets('back asks before discarding an edited receipt', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddEditReceiptScreen(
                  onSave:
                      (
                        receipt, {
                        attachmentPath,
                        removeAttachment = false,
                        extraAttachmentPaths = const {},
                        extraAttachmentIdsToDelete = const [],
                      }) async => receipt,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _fillRequired(tester);

    // The route's own back button.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    // Still here, still holding the work.
    expect(find.byType(AddEditReceiptScreen), findsOneWidget);
    expect(find.text('Coffee machine'), findsOneWidget);
  });

  // canPop is false, so every back press goes through _confirmDiscard. An
  // untouched editor must still leave immediately rather than nag.
  testWidgets('back leaves at once when nothing was edited', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddEditReceiptScreen(
                  onSave:
                      (
                        receipt, {
                        attachmentPath,
                        removeAttachment = false,
                        extraAttachmentPaths = const {},
                        extraAttachmentIdsToDelete = const [],
                      }) async => receipt,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsNothing);
    expect(find.byType(AddEditReceiptScreen), findsNothing);
  });
}
