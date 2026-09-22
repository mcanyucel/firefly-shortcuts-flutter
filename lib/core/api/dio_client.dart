import 'package:dio/dio.dart';
import '../auth/auth_manager.dart';

class DioClient {
  final Dio _dio;

  DioClient({required AuthManager authManager})
    : _dio = Dio(
        BaseOptions(
          // Dio waits forever by default.
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      ) {
    _dio.options.headers['Accept'] = 'application/vnd.api+json';
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.interceptors.add(_AuthInterceptor(authManager));
  }

  Dio get dio => _dio;
}

class _AuthInterceptor extends Interceptor {
  final AuthManager _authManager;
  _AuthInterceptor(this._authManager);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final authState = _authManager.state;
    if (authState.isAuthenticated) {
      if (authState.isAccessTokenExpired) {
        await _authManager.refreshAccessToken();
      }
      options.headers['Authorization'] =
          'Bearer ${_authManager.state.accessToken}';
    }
    handler.next(options);
  }
}
