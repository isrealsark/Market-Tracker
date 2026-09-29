import 'package:flutter_test/flutter_test.dart';
import 'package:market_tracker/screens/subscription_rules.dart';

void main() {
  group('SubscriptionRules', () {
    test('returns true while the first month is still active', () {
      final firstOrder = DateTime.now().subtract(const Duration(days: 10));

      expect(
        SubscriptionRules.isWithinFirstMonth(firstOrder, now: DateTime.now()),
        isTrue,
      );
    });

    test('does not lock access during the first month', () {
      final firstOrder = DateTime.now().subtract(const Duration(days: 10));

      expect(
        SubscriptionRules.isPastFirstMonth(firstOrder, now: DateTime.now()),
        isFalse,
      );
    });

    test('returns false after the first month has elapsed', () {
      final firstOrder = DateTime.now().subtract(const Duration(days: 35));

      expect(
        SubscriptionRules.isWithinFirstMonth(firstOrder, now: DateTime.now()),
        isFalse,
      );
    });

    test('locks access after the first month has elapsed', () {
      final firstOrder = DateTime.now().subtract(const Duration(days: 35));

      expect(
        SubscriptionRules.isPastFirstMonth(firstOrder, now: DateTime.now()),
        isTrue,
      );
    });

    test('returns false when there is no first order date', () {
      expect(
        SubscriptionRules.isWithinFirstMonth(null, now: DateTime.now()),
        isFalse,
      );
    });
  });
}
