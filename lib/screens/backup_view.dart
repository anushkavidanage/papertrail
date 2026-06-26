/// Backup & Restore screen: export all receipts and attachments to a ZIP,
/// restore from a backup, or export the receipt list to CSV.
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
import '../utils/csv_exporter.dart';

// ignore_for_file: use_build_context_synchronously

class BackupView extends StatefulWidget {
  const BackupView({super.key});

  @override
  State<BackupView> createState() => _BackupViewState();
}

class _BackupViewState extends State<BackupView> {
  final _store = ReceiptStore.instance;

  bool _busy = false;

  // Per-section status messages, matching the todopod layout where each
  // section shows its own banner.
  String? _backupMessage;
  bool _backupError = false;
  String? _exportMessage;
  bool _exportError = false;

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

  void _setBackupMsg(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _backupMessage = msg;
      _backupError = error;
    });
  }

  void _setExportMsg(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _exportMessage = msg;
      _exportError = error;
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
      _backupMessage = null;
    });
    try {
      final ok = await BackupService.exportBackup(
        _store.receipts,
        onProgress: _onProgress,
      );
      _setBackupMsg(ok ? 'Backup saved successfully.' : 'Backup cancelled.');
    } catch (e) {
      _setBackupMsg('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() {
      _busy = true;
      _backupMessage = null;
    });
    try {
      final result = await BackupService.importBackup(onProgress: _onProgress);
      if (mounted) {
        await _store.refresh(context, const SizedBox.shrink());
      }
      if (result.hasErrors && result.receiptsRestored == 0) {
        _setBackupMsg('Import failed: ${result.errors.first}', error: true);
      } else {
        final msg = StringBuffer(
          'Restored ${result.receiptsRestored} receipt(s) and '
          '${result.attachmentsRestored} attachment(s).',
        );
        if (result.hasErrors) {
          msg.write(' ${result.errors.length} item(s) had problems.');
        }
        _setBackupMsg(msg.toString(), error: result.hasErrors);
      }
    } catch (e) {
      _setBackupMsg('Import failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() {
      _busy = true;
      _exportMessage = null;
    });
    try {
      final path = await exportReceiptsToCsvFile(_store.receipts);
      _setExportMsg(path == null ? 'CSV export cancelled.' : 'Saved to $path');
    } catch (e) {
      _setExportMsg('CSV export failed: $e', error: true);
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Backup & Restore ────────────────────────────────────────
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
          const SizedBox(height: 8),
          Text(
            'Currently $receiptCount receipt(s) and $attachmentCount '
            'attachment(s).',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (_backupMessage != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(
              message: _backupMessage!,
              isError: _backupError,
              cs: cs,
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
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Export Backup'),
                onPressed: _busy ? null : _exportBackup,
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text('Import Backup'),
                onPressed: _busy ? null : _importBackup,
              ),
            ],
          ),

          // ── Export ──────────────────────────────────────────────────
          const SizedBox(height: 32),
          Text('Export', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Save the receipt list (without attachments) to a CSV spreadsheet '
            'that opens in Excel or Google Sheets.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          if (_exportMessage != null) ...[
            const SizedBox(height: 12),
            _MessageBanner(
              message: _exportMessage!,
              isError: _exportError,
              cs: cs,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export to CSV'),
                onPressed: _busy ? null : _exportCsv,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline status banner mirroring todopod's ImportMessageBanner.

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.message,
    required this.isError,
    required this.cs,
  });

  final String message;
  final bool isError;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? cs.errorContainer : cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? cs.onErrorContainer : cs.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? cs.onErrorContainer : cs.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
