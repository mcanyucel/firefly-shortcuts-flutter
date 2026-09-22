class TransactionRequest {
  final List<TransactionItem> transactions;
  const TransactionRequest({required this.transactions});

  // Firefly rejects a request identical to an existing transaction, so a
  // resubmitted request cannot create a second one.
  Map<String, dynamic> toJson() => {
    'error_if_duplicate_hash': true,
    'transactions': transactions.map((t) => t.toJson()).toList(),
  };
}

class TransactionItem {
  final String type;
  final String date;
  final String amount;
  final String description;
  final String sourceId;
  final String sourceName;
  final String destinationId;
  final String destinationName;
  final String? currencyCode;
  final String? categoryId;
  final String? categoryName;
  final String? budgetId;
  final String? budgetName;
  final String? billId;
  final String? billName;
  final String? piggyBankId;
  final String? piggyBankName;
  final List<String>? tags;

  const TransactionItem({
    required this.type,
    required this.date,
    required this.amount,
    required this.description,
    required this.sourceId,
    required this.sourceName,
    required this.destinationId,
    required this.destinationName,
    this.currencyCode,
    this.categoryId,
    this.categoryName,
    this.budgetId,
    this.budgetName,
    this.billId,
    this.billName,
    this.piggyBankId,
    this.piggyBankName,
    this.tags,
  });

  /// ISO 8601 with the UTC offset, to the second. Without an offset Firefly
  /// reads the time in the server's timezone.
  static String formatDate(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final offset = time.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
        '${two(time.day)}T${two(time.hour)}:${two(time.minute)}:'
        '${two(time.second)}$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': type,
      'date': date,
      'amount': amount,
      'description': description,
      'source_id': sourceId,
      'source_name': sourceName,
      'destination_id': destinationId,
      'destination_name': destinationName,
    };
    if (currencyCode != null) map['currency_code'] = currencyCode;
    if (categoryId != null) map['category_id'] = categoryId;
    if (categoryName != null) map['category_name'] = categoryName;
    if (budgetId != null) map['budget_id'] = budgetId;
    if (budgetName != null) map['budget_name'] = budgetName;
    if (billId != null) map['bill_id'] = billId;
    if (billName != null) map['bill_name'] = billName;
    if (piggyBankId != null) map['piggy_bank_id'] = piggyBankId;
    if (piggyBankName != null) map['piggy_bank_name'] = piggyBankName;
    if (tags != null && tags!.isNotEmpty) map['tags'] = tags;
    return map;
  }
}
