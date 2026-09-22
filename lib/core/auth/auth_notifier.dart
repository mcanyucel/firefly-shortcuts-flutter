import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../features/sync/sync_notifier.dart';
import '../providers/core_providers.dart';
import '../providers/dao_providers.dart';
import '../widget/widget_update_service.dart';
import 'auth_state.dart';

part 'auth_notifier.g.dart';

enum LoginResult { failed, connected, connectedDataCleared }

@Riverpod(keepAlive: true)
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() {
    final initAsync = ref.watch(appInitProvider);
    return initAsync.when(
      data: (_) => ref.read(authManagerProvider).state,
      loading: () => const AuthState.unauthenticated(),
      error: (_, __) => const AuthState.unauthenticated(),
    );
  }

  Future<LoginResult> login() async {
    if (!await ref.read(authManagerProvider).login()) {
      return LoginResult.failed;
    }
    return _finishLogin();
  }

  Future<LoginResult> loginWithPat(String pat) async {
    await ref.read(authManagerProvider).loginWithPat(pat);
    return _finishLogin();
  }

  Future<String?> dataOwnerServerUrl() =>
      ref.read(dataOwnerGuardProvider).ownerServerUrl();

  // Claiming the local data is the first authenticated request, so it also
  // serves as the connection test. Without knowing the user we cannot tell
  // whether the local shortcuts belong to them, so a failure logs out.
  Future<LoginResult> _finishLogin() async {
    final bool cleared;
    try {
      cleared = await ref.read(dataOwnerGuardProvider).claim();
    } catch (_) {
      await ref.read(authManagerProvider).logout();
      rethrow;
    }
    if (cleared) {
      ref.invalidate(syncProvider);
      await WidgetUpdateService.update(
        shortcutDao: ref.read(shortcutDaoProvider),
        settings: ref.read(settingsRepositoryProvider),
      );
    }
    state = ref.read(authManagerProvider).state;
    return cleared ? LoginResult.connectedDataCleared : LoginResult.connected;
  }

  Future<void> logout() async {
    await ref.read(authManagerProvider).logout();
    state = const AuthState.unauthenticated();
  }
}
