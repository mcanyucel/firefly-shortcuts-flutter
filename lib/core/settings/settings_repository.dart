 import 'package:flutter_secure_storage/flutter_secure_storage.dart';

  class SettingsRepository {
    final FlutterSecureStorage _storage;

    static const _keyServerUrl = 'server_url';
    static const _keyClientId = 'client_id';
    static const _keyRedirectUrl = 'redirect_url';
    static const _keyPersonalAccessToken = 'personal_access_token';

    SettingsRepository(this._storage);

    Future<String?> getServerUrl() => _storage.read(key: _keyServerUrl);
    Future<String?> getClientId() => _storage.read(key: _keyClientId);
    Future<String?> getRedirectUrl() => _storage.read(key: _keyRedirectUrl);
    Future<String?> getPersonalAccessToken() =>
        _storage.read(key: _keyPersonalAccessToken);

    static String normalizeServerUrl(String url) =>
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    Future<void> saveServerUrl(String url) =>
        _storage.write(key: _keyServerUrl, value: normalizeServerUrl(url));

    Future<void> saveClientId(String id) =>
        _storage.write(key: _keyClientId, value: id);

    Future<void> saveRedirectUrl(String url) =>
        _storage.write(key: _keyRedirectUrl, value: url);

    Future<void> savePersonalAccessToken(String token) =>
        _storage.write(key: _keyPersonalAccessToken, value: token);

    Future<bool> isConfigured() async {
      final url = await getServerUrl();
      if (url == null || url.isEmpty) return false;
      final pat = await getPersonalAccessToken();
      if (pat != null && pat.isNotEmpty) return true;
      final clientId = await getClientId();
      return clientId != null && clientId.isNotEmpty;
    }
  }