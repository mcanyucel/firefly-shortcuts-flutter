import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../settings/settings_repository.dart';
import '../widget/widget_update_service.dart';
import 'auth_state.dart';

class AuthManager {
  final FlutterAppAuth _appAuth;
  final FlutterSecureStorage _secureStorage;
  final SettingsRepository _settings;

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyExpiry = 'token_expiry';

  // The widget only holds an access token and cannot refresh it, so refresh
  // well before expiry whenever the app runs.
  static const _refreshAhead = Duration(days: 30);

  AuthState _state = const AuthState.unauthenticated();
  AuthState get state => _state;

  Future<bool>? _refreshing;

  AuthManager(this._appAuth, this._secureStorage, this._settings);

  Future<void> initialize() async {
    final accessToken = await _secureStorage.read(key: _keyAccessToken);
    final refreshToken = await _secureStorage.read(key: _keyRefreshToken);
    final expiryStr = await _secureStorage.read(key: _keyExpiry);

    if (accessToken != null) {
      _state = AuthState(
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessTokenExpiry: expiryStr != null ? DateTime.parse(expiryStr) : null,
      );
    }
    // Also repairs a widget copy left behind by versions that did not clear
    // it on logout.
    await _syncWidgetToken();
  }

  Future<void> refreshIfExpiringSoon() async {
    final expiry = _state.accessTokenExpiry;
    if (!_state.isOAuth || expiry == null) return;
    if (expiry.difference(DateTime.now()) > _refreshAhead) return;
    await refreshAccessToken();
  }

  Future<bool> login() async {
    final serverUrl = await _settings.getServerUrl();
    final clientId = await _settings.getClientId();
    final redirectUrl = await _settings.getRedirectUrl();

    if (serverUrl == null || clientId == null || redirectUrl == null) {
      return false;
    }

    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUrl,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: '$serverUrl/oauth/authorize',
            tokenEndpoint: '$serverUrl/oauth/token',
          ),
          allowInsecureConnections: !serverUrl.startsWith('https'),
        ),
      );

      await _persistAndUpdate(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Concurrent callers share one request: Firefly revokes a refresh token
  /// once used, so a second parallel refresh would fail.
  Future<bool> refreshAccessToken() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    final refreshToken = _state.refreshToken;
    if (refreshToken == null) return false;

    final serverUrl = await _settings.getServerUrl();
    final clientId = await _settings.getClientId();
    final redirectUrl = await _settings.getRedirectUrl();

    if (serverUrl == null || clientId == null || redirectUrl == null) {
      return false;
    }

    try {
      final result = await _appAuth.token(
        TokenRequest(
          clientId,
          redirectUrl,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: '$serverUrl/oauth/authorize',
            tokenEndpoint: '$serverUrl/oauth/token',
          ),
          refreshToken: refreshToken,
          grantType: GrantType.refreshToken,
          allowInsecureConnections: !serverUrl.startsWith('https'),
        ),
      );

      await _persistAndUpdate(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken ?? refreshToken,
        expiry: result.accessTokenExpirationDateTime,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loginWithPat(String pat) async {
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyExpiry);
    await _secureStorage.write(key: _keyAccessToken, value: pat);
    _state = AuthState(accessToken: pat);
    await _syncWidgetToken();
  }

  Future<void> logout() async {
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyExpiry);
    _state = const AuthState.unauthenticated();
    await _syncWidgetToken();
  }

  Future<void> _persistAndUpdate({
    String? accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) async {
    if (accessToken != null) {
      await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    }
    if (refreshToken != null) {
      await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
    }
    if (expiry != null) {
      await _secureStorage.write(
        key: _keyExpiry,
        value: expiry.toIso8601String(),
      );
    }
    _state = AuthState(
      accessToken: accessToken ?? _state.accessToken,
      refreshToken: refreshToken ?? _state.refreshToken,
      accessTokenExpiry: expiry ?? _state.accessTokenExpiry,
    );
    await _syncWidgetToken();
  }

  Future<void> _syncWidgetToken() => WidgetUpdateService.setAccessToken(
    _state.accessToken,
    _state.tokenExpiry,
  );
}
