import 'dart:convert';
import 'package:flutter/services.dart';
import '../database/daos/shortcut_dao.dart';
import '../settings/settings_repository.dart';

class WidgetUpdateService {
  static const _channel = MethodChannel('firefly_shortcuts/widget');

  static Future<void> update({
    required ShortcutDao shortcutDao,
    required SettingsRepository settings,
  }) async {
    try {
      final details = await shortcutDao.watchAllWithDetails().first;
      final shortcutsJson = jsonEncode(
        details.map((d) => {
          'id': d.shortcut.id,
          'name': d.shortcut.name,
          'amount': d.shortcut.amount,
          'type': d.shortcut.transactionType.apiValue,
          'description': d.shortcut.description ?? d.shortcut.name,
          'fromAccountId': d.fromAccount.id,
          'fromAccountName': d.fromAccount.name,
          'toAccountId': d.toAccount.id,
          'toAccountName': d.toAccount.name,
          'categoryId': d.shortcut.categoryId,
          'budgetId': d.shortcut.budgetId,
          'billId': d.shortcut.billId,
          'piggybankId': d.shortcut.piggybankId,
          'tags': d.tags.map((t) => t.name).toList(),
        }).toList(),
      );

      await _channel.invokeMethod('updateWidgetData', {
        'shortcuts': shortcutsJson,
        'server_url': await settings.getServerUrl() ?? '',
      });
    } catch (_) {}
  }

  /// Mirrors the access token and its expiry into the native storage the
  /// widget worker reads. Pass a null token to remove it.
  static Future<void> setAccessToken(String? token, DateTime? expiry) async {
    try {
      await _channel.invokeMethod('setAccessToken', {
        'access_token': token,
        'expiry': expiry?.millisecondsSinceEpoch,
      });
    } catch (_) {}
  }
}
