/// Papertrail — track your purchase receipts, stored in your own Solid Pod.
library;

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/ai_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await AIService.instance.init();
  runApp(const PapertrailApp());
}
