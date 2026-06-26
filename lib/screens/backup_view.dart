/// Backup & Restore screen: export all receipts and attachments to a ZIP,
/// or restore them from a previously saved backup.
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0.

library;

import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../services/receipt_store.dart';

// ignore_for_file: use_build_context_synchronously

class BackupView extends StatefulWidget {
  const BackupView({super.key});

  @override
  State<BackupView> createState() => _BackupViewState();
}

class _BackupViewState extends State<BackupView> {
  final _store = ReceiptStore.instance;

  bool _busy = false;
  String? _message;
  bool _messageError = false;
  int _progressCurrent = 0;
  int _progressTotal = 0;
  String _progressLabel = '';

  @override
  void initState() {
    super.initState();
    _store.addListener(_rebuild);
  }

  @override
  void dispose() {
    _store.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _setMessage(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _messageError = error;
    });
  }

  void _onProgress(int current, int total, String label) {
    if (!mounted) return;
    setState(() {
      _progressCurrent = current;
      _progressTotal = total;
      _progressLabel = label;
    });
  }

  Future<void> _exportBackup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ok = await BackupService.exportBackup(
        _store.receipts,
        onProgress: _onProgress,
      );
      if (ok) {
        _setMessage('Backup saved successfully.');
      } else {
        _setMessage('Backup cancelled.');
      }
    } catch (e) {
      _setMessage('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await BackupService.importBackup(onProgress: _onProgress);
      // Refresh the store so the restored receipts appear immediately.
      if (mounted) {
        await _store.refresh(context, const SizedBox.shrink());
      }
      if (result.hasErrors && result.receiptsRestored == 0) {
        _setMessage('Import failed: ${result.errors.first}', error: true);
      } else {
        final msg = StringBuffer(
          'Restored ${result.receiptsRestored} receipt(s) and '
          '${result.attachmentsRestored} attachment(s).',
        );
        if (result.hasErrors) {
          msg.write(' ${result.errors.length} item(s) had problems.');
        }
        _setMessage(msg.toString(), error: result.hasErrors);
      }
    } catch (e) {
      _setMessage('Import failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final receiptCount = _store.receipts.length;
    final attachmentCount = _store.receipts.fold<int>(
      0,
      (sum, r) => sum + (r.hasAttachment ? 1 : 0) + r.extraAttachments.length,
    );

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backup & Restore',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Save all your receipts and their attachments (images & PDFs) to '
              'a single ZIP file, or restore everything from a previously saved '
              'backup. Importing into an empty Pod recreates it exactly.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              'Currently $receiptCount receipt(s) and $attachmentCount '
              'attachment(s).',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _messageError
                      ? cs.errorContainer
                      : cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _messageError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: _messageError
                          ? cs.onErrorContainer
                          : cs.onSecondaryContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: _messageError
                              ? cs.onErrorContainer
                              : cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_busy && _progressTotal > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progressTotal == 0
                    ? null
                    : _progressCurrent / _progressTotal,
              ),
              const SizedBox(height: 8),
              Text(
                _progressLabel,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Export Backup'),
                  onPressed: _busy ? null : _exportBackup,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload),
                  label: const Text('Import Backup'),
                  onPressed: _busy ? null : _importBackup,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
