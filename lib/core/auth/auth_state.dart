import 'dart:convert';

class AuthState {
  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiry;

  AuthState({this.accessToken, this.refreshToken, this.accessTokenExpiry});

  const AuthState.unauthenticated()
    : accessToken = null,
      refreshToken = null,
      accessTokenExpiry = null;

  bool get isAuthenticated => accessToken != null;

  bool get isOAuth => refreshToken != null;

  DateTime? get patExpiry {
    if (accessToken == null || isOAuth) return null;
    return _decodeJwtExpiry(accessToken!);
  }

  /// When the current access token stops working, if known.
  DateTime? get tokenExpiry => isOAuth ? accessTokenExpiry : patExpiry;

  bool get isAccessTokenExpired {
    if (isOAuth) {
      return accessTokenExpiry != null &&
          DateTime.now().isAfter(
            accessTokenExpiry!.subtract(const Duration(minutes: 2)),
          );
    }
    final expiry = patExpiry;
    return expiry != null && DateTime.now().isAfter(expiry);
  }

  static DateTime? _decodeJwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      switch (payload.length % 4) {
        case 2:
          payload += '==';
        case 3:
          payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = data['exp'];
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
    } catch (_) {
      return null;
    }
  }
}
