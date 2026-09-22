import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../features/sync/sync_notifier.dart';
import '../api/firefly_api_service.dart';
import '../database/app_database.dart';
import '../settings/settings_repository.dart';

/// Ties the local database to the Firefly server and user it was synced
/// from. Shortcuts store raw Firefly IDs, which mean something else on
/// another server or for another user, so the data is wiped when the owner
/// changes.
///
/// The owner is kept in a file next to the database rather than in secure
/// storage, so Android backup restores the two together. Secure storage is
/// excluded from backup, as its Keystore keys cannot be restored.
class DataOwnerGuard {
  final FireflyApiService _api;
  final SettingsRepository _settings;
  final AppDatabase _db;
  final FlutterSecureStorage _storage;

  DataOwnerGuard(this._api, this._settings, this._db, this._storage);

  Future<String?> ownerServerUrl() async => (await _readOwner()).server;

  /// Call after a successful login. Records the logged-in server and user as
  /// the owner and wipes local data first if they differ from the previous
  /// owner. Returns whether data was wiped. Throws if the user cannot be
  /// identified.
  Future<bool> claim() async {
    final server = await _settings.getServerUrl() ?? '';
    final user = await _api.getCurrentUserId();
    final (server: ownerServer, user: ownerUser) = await _readOwner();

    // A null owner user with a matching server is a 1.0.2 install adopted by
    // adoptLegacyOwner before its user ID could be fetched.
    final changed = ownerServer != null &&
        (ownerServer != server || (ownerUser != null && ownerUser != user));
    if (changed) {
      await _db.wipe();
      await _storage.delete(key: SyncNotifier.keyLastSync);
    }

    await _writeOwner(server, user);
    return changed;
  }

  /// Versions up to 1.0.2 did not record an owner. Their data belongs to the
  /// configured server, so adopt it rather than treating the first login as
  /// a switch. The user ID needs the network, so it is retried on each start
  /// until it succeeds.
  Future<void> adoptLegacyOwner({required bool authenticated}) async {
    final server = await _settings.getServerUrl();
    if (server == null || server.isEmpty) return;

    var (server: ownerServer, user: ownerUser) = await _readOwner();
    if (ownerServer == null) {
      await _writeOwner(server, null);
      ownerServer = server;
    }

    if (!authenticated || ownerServer != server || ownerUser != null) return;
    try {
      await _writeOwner(server, await _api.getCurrentUserId());
    } catch (_) {}
  }

  Future<File> _ownerFile() async => File(
    p.join((await getApplicationDocumentsDirectory()).path, 'data_owner.json'),
  );

  Future<({String? server, String? user})> _readOwner() async {
    try {
      final file = await _ownerFile();
      if (!await file.exists()) return (server: null, user: null);
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (server: json['server'] as String?, user: json['user'] as String?);
    } catch (_) {
      return (server: null, user: null);
    }
  }

  Future<void> _writeOwner(String server, String? user) async {
    final file = await _ownerFile();
    await file.writeAsString(
      jsonEncode({'server': server, 'user': user}),
      flush: true,
    );
  }
}
