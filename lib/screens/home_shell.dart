/// The main authenticated surface: a [SolidScaffold] with navigation between
/// the recent-receipts home, the full receipts list, and the Pod file browser.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Anushka Vidanage

// Add the library directive as we have doc entries above. We publish the above
// meta doc lines in the docs.

library;

import 'package:flutter/material.dart';

import 'package:solidui/solidui.dart';

import '../constants/app_config.dart';
import '../services/receipt_store.dart';
import '../widgets/locked_backdrop.dart';
import 'add_edit_receipt_screen.dart';
import 'all_receipts_view.dart';
import 'analytics_view.dart';
import 'backup_view.dart';
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddEditReceiptScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return SolidScaffold(
      appBar: const SolidAppBarConfig(title: appTitle),
      aboutConfig: SolidAboutConfig(
        applicationName: appTitle,
        applicationIcon: Image.asset(
          'assets/images/app_icon.png',
          width: 64,
          height: 64,
        ),
        applicationLegalese: '''© 2026 Togaware Pty Ltd''',
        text: '''

        PaperTrail is a private receipts and expense manager that stores your
        receipts encrypted in your personal Solid Pod, so your data stays
        under your control. Your Solid Pod can be hosted on any Solid server
        and being encrypted it is protected against casual access by anyone,
        including the server administrators.

        ### Key features

        - Add, edit and browse receipts with images
        - Search and filter receipts by date, vendor and amount
        - Analytics with charts and spending statistics
        - Browse the raw files stored on your Pod
        - Backup and restore all receipts and attachments as a ZIP
        - Export the receipt list to CSV
        - All receipt data stored encrypted on your Pod
        - Security key management for encrypted data
        - Theme switching (light / dark / system)

        For more information, visit the
        [PaperTrail](https://github.com/anushkavidanage/papertrail) GitHub repository
        and our [Australian Solid Community](https://solidcommunity.au) web
        site.

        ''',
        readmeUrl: 'https://github.com/anushkavidanage/papertrail/',
      ),
      menu: const [
        SolidMenuItem(
          icon: Icons.home_outlined,
          title: 'Receipts',
          tooltip: 'Recent receipts and a quick overview.',
          child: RecentReceiptsView(),
        ),
        SolidMenuItem(
          icon: Icons.receipt_long_outlined,
          title: 'Search',
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
          icon: Icons.save_alt,
          title: 'Backup',
          tooltip: 'Back up and restore all receipts and attachments.',
          child: BackupView(),
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
