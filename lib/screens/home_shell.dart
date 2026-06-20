/// The main authenticated surface: a [SolidScaffold] with navigation between
/// the recent-receipts home, the full receipts list, and the Pod file browser.
library;

import 'package:flutter/material.dart';
import 'package:solidui/solidui.dart';

import '../constants/app_config.dart';
import '../services/receipt_store.dart';
import '../widgets/locked_backdrop.dart';
import 'add_edit_receipt_screen.dart';
import 'ai_assistant_view.dart';
import 'all_receipts_view.dart';
import 'analytics_view.dart';
import 'recent_receipts_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    // Load receipts once the first frame is rendered so the security-key
    // prompt (if needed) has a valid Navigator context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ReceiptStore.instance.refresh(context, const LockedBackdrop());
      }
    });
  }

  Future<void> _addReceipt() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddEditReceiptScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SolidScaffold(
      appBar: const SolidAppBarConfig(title: appTitle),
      menu: const [
        SolidMenuItem(
          icon: Icons.home_outlined,
          title: 'Home',
          tooltip: 'Recent receipts and a quick overview.',
          child: RecentReceiptsView(),
        ),
        SolidMenuItem(
          icon: Icons.receipt_long_outlined,
          title: 'Receipts',
          tooltip: 'Browse, search and filter all of your receipts.',
          child: AllReceiptsView(),
        ),
        SolidMenuItem(
          icon: Icons.analytics_outlined,
          title: 'Analytics',
          tooltip: 'Charts and statistics about your spending.',
          child: AnalyticsView(),
        ),
        SolidMenuItem(
          icon: Icons.folder_outlined,
          title: 'Files',
          tooltip: 'Browse the raw files stored on your Pod.',
          child: SolidFile(),
        ),
        SolidMenuItem(
          icon: Icons.auto_awesome_outlined,
          title: 'AI',
          tooltip:
              'Natural language receipt search and spending insights — on-device, private.',
          child: AIAssistantView(),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addReceipt,
        icon: const Icon(Icons.add),
        label: const Text('Add receipt'),
      ),
    );
  }
}
