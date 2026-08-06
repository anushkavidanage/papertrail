/// Inline status banner used by the backup screen sections.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0.

library;

import 'package:flutter/material.dart';

/// Inline status banner mirroring todopod's ImportMessageBanner.

class BackupMessageBanner extends StatelessWidget {
  const BackupMessageBanner({
    super.key,
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
