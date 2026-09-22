import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../features/sync/sync_notifier.dart';
import '../api/firefly_api_service.dart';
import '../database/app_database.dart';
import '../settings/settings_repository.dart';

/// Ties the local database to the Firefly server and user it was synced
/// from. Shortcuts store raw Firefly IDs, which mean something else on
/// another server or for another user, so the data is wiped when the owner
/// changes.
class DataOwnerGuard {
  final FireflyApiService _api;
  final SettingsRepository _settings;
  final AppDatabase _db;
  final FlutterSecureStorage _storage;

  static const _keyOwnerServer = 'data_owner_server';
  static const _keyOwnerUser = 'data_owner_user';

  DataOwnerGuard(this._api, this._settings, this._db, this._storage);

  Future<String?> ownerServerUrl() => _storage.read(key: _keyOwnerServer);

  /// Call after a successful login. Records the logged-in server and user as
  /// the owner and wipes local data first if they differ from the previous
  /// owner. Returns whether data was wiped. Throws if the user cannot be
  /// identified.
  Future<bool> claim() async {
    final server = await _settings.getServerUrl() ?? '';
    final user = await _api.getCurrentUserId();
    final ownerServer = await _storage.read(key: _keyOwnerServer);
    final ownerUser = await _storage.read(key: _keyOwnerUser);

    // A null owner user with a matching server is a 1.0.2 install adopted by
    // adoptLegacyOwner before its user ID could be fetched.
    final changed = ownerServer != null &&
        (ownerServer != server || (ownerUser != null && ownerUser != user));
    if (changed) {
      await _db.wipe();
      await _storage.delete(key: SyncNotifier.keyLastSync);
    }

    await _storage.write(key: _keyOwnerServer, value: server);
    await _storage.write(key: _keyOwnerUser, value: user);
    return changed;
  }

  /// Versions up to 1.0.2 did not record an owner. Their data belongs to the
  /// configured server, so adopt it rather than treating the first login as
  /// a switch. The user ID needs the network, so it is retried on each start
  /// until it succeeds.
  Future<void> adoptLegacyOwner({required bool authenticated}) async {
    final server = await _settings.getServerUrl();
    if (server == null || server.isEmpty) return;

    var ownerServer = await _storage.read(key: _keyOwnerServer);
    if (ownerServer == null) {
      await _storage.write(key: _keyOwnerServer, value: server);
      ownerServer = server;
    }

    if (!authenticated || ownerServer != server) return;
    if (await _storage.read(key: _keyOwnerUser) != null) return;
    try {
      final user = await _api.getCurrentUserId();
      await _storage.write(key: _keyOwnerUser, value: user);
    } catch (_) {}
  }
}
