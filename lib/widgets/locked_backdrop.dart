/// A simple branded backdrop shown behind the Solid security-key prompt.
library;

import 'package:flutter/material.dart';

import '../constants/app_config.dart';

class LockedBackdrop extends StatelessWidget {
  const LockedBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text(appTitle,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enter your security key to unlock your receipts.'),
          ],
        ),
      ),
    );
  }
}
