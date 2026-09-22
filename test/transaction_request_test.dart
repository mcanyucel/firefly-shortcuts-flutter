import 'package:firefly_shortcuts/core/api/models/transaction_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransactionItem.formatDate', () {
    test('formats UTC with a zero offset, to the second', () {
      final time = DateTime.utc(2026, 9, 2, 7, 4, 5, 678);
      expect(TransactionItem.formatDate(time), '2026-09-02T07:04:05+00:00');
    });

    test('local time round-trips to the same instant', () {
      final now = DateTime.now();
      final formatted = TransactionItem.formatDate(now);
      expect(
        formatted,
        matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d$')),
      );
      expect(
        DateTime.parse(formatted).millisecondsSinceEpoch,
        now.millisecondsSinceEpoch ~/ 1000 * 1000,
      );
    });
  });

  test('requests ask Firefly to reject duplicates', () {
    const request = TransactionRequest(transactions: []);
    expect(request.toJson()['error_if_duplicate_hash'], isTrue);
  });
}
