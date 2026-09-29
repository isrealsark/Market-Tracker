import 'package:flutter/material.dart';

class SubscriptionRules {
  static const Duration firstMonth = Duration(days: 30);

  static bool isWithinFirstMonth(
    DateTime? firstOrder, {
    required DateTime now,
  }) {
    if (firstOrder == null) return false;
    final expiry = firstOrder.add(firstMonth);
    return !now.isAfter(expiry);
  }

  static bool isPastFirstMonth(DateTime? firstOrder, {required DateTime now}) {
    if (firstOrder == null) return false;
    final expiry = firstOrder.add(firstMonth);
    return now.isAfter(expiry);
  }

  static Future<void> redirectIfLocked({
    required BuildContext context,
    required Future<bool> Function() isLocked,
    required Widget subscriptionScreen,
  }) async {
    final locked = await isLocked();
    if (!context.mounted) return;
    if (locked) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('First month ended'),
          content: const Text(
            'Your 30-day access period has ended. Subscribe to continue using all business features.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => subscriptionScreen),
        (route) => false,
      );
    }
  }
}
