import 'dart:async';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../api/dio_client.dart';
import '../api/firefly_api_service.dart';
import '../auth/auth_manager.dart';
import '../auth/data_owner_guard.dart';
import '../database/app_database.dart';
import '../settings/settings_repository.dart';

part 'core_providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => AppDatabase();

@Riverpod(keepAlive: true)
FlutterSecureStorage secureStorage(Ref ref) =>
    const FlutterSecureStorage();

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) =>
    SettingsRepository(ref.watch(secureStorageProvider));

@Riverpod(keepAlive: true)
AuthManager authManager(Ref ref) => AuthManager(
  const FlutterAppAuth(),
  ref.watch(secureStorageProvider),
  ref.watch(settingsRepositoryProvider),
);

@Riverpod(keepAlive: true)
DioClient dioClient(Ref ref) =>
    DioClient(authManager: ref.watch(authManagerProvider));

@Riverpod(keepAlive: true)
FireflyApiService fireflyApiService(Ref ref) =>
    FireflyApiService(
      dioClient: ref.watch(dioClientProvider),
      settingsRepository: ref.watch(settingsRepositoryProvider),
    );

final dataOwnerGuardProvider = Provider<DataOwnerGuard>(
  (ref) => DataOwnerGuard(
    ref.watch(fireflyApiServiceProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(secureStorageProvider),
  ),
);

@riverpod
Future<void> appInit(Ref ref) async {
  final authManager = ref.read(authManagerProvider);
  await authManager.initialize();
  unawaited(
    ref.read(dataOwnerGuardProvider).adoptLegacyOwner(
      authenticated: authManager.state.isAuthenticated,
    ),
  );
  unawaited(authManager.refreshIfExpiringSoon());
}
