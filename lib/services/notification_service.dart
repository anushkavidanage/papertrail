/// Schedules and cancels local warranty-reminder notifications.
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

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/receipt.dart';
import '../utils/formatting.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'warranty_reminders';
  static const _channelName = 'Warranty Reminders';
  static const _channelDesc = 'Reminds you 30 days before a warranty expires.';
  static const _daysBeforeExpiry = 30;

  /// Call once from [main] before [runApp].
  ///
  /// Silently no-ops on Linux (zonedSchedule not supported by libnotify).
  Future<void> init() async {
    if (Platform.isLinux) return;

    try {
      tz_data.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );

      final result = await _plugin.initialize(settings);
      _ready = result ?? false;

      // Request Android 13+ notification permission.
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
    } catch (_) {
      // Notifications are non-critical; fail silently.
      _ready = false;
    }
  }

  /// Stable int notification ID derived from the receipt UUID.
  int _idFor(String receiptId) => receiptId.hashCode.abs() % 2000000000;

  /// Schedules a reminder 30 days before [receipt]'s warranty expires.
  /// Cancels any previous reminder for the same receipt first (handles edits).
  /// Does nothing if the receipt has no warranty or the reminder date is past.
  Future<void> scheduleWarrantyReminder(Receipt receipt) async {
    if (!_ready) return;
    final id = _idFor(receipt.id);

    // Always cancel the old one — handles edits that clear the warranty.
    await _plugin.cancel(id);

    if (!receipt.hasWarranty || receipt.warrantyExpiry == null) return;

    final expiry = receipt.warrantyExpiry!;
    final reminderDay = expiry.subtract(
      const Duration(days: _daysBeforeExpiry),
    );
    // Fire at 9 AM local time on the reminder day.
    final notifyAt = DateTime(
      reminderDay.year,
      reminderDay.month,
      reminderDay.day,
      9,
    );

    if (!notifyAt.isAfter(DateTime.now())) return;

    final scheduled = tz.TZDateTime.from(notifyAt, tz.local);
    final title = receipt.title.isEmpty
        ? 'Warranty expiring soon'
        : receipt.title;
    final body =
        'Warranty expires in $_daysBeforeExpiry days (${formatDate(expiry)}).';

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancels any pending warranty reminder for [receiptId].
  Future<void> cancelWarrantyReminder(String receiptId) async {
    if (!_ready) return;
    await _plugin.cancel(_idFor(receiptId));
  }
}
