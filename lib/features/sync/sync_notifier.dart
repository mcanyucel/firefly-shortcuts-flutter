  import 'package:drift/drift.dart';
  import 'package:firefly_shortcuts/core/database/app_database.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:riverpod_annotation/riverpod_annotation.dart';
  import '../../core/api/models/account_dto.dart';
  import '../../core/api/models/reference_dtos.dart';
  import '../../core/providers/core_providers.dart';
  import '../../core/providers/dao_providers.dart';
  import '../../core/widget/widget_update_service.dart';
  import 'sync_state.dart';

  part 'sync_notifier.g.dart';

  @Riverpod(keepAlive: true)
  class SyncNotifier extends _$SyncNotifier {
    static const keyLastSync = 'last_sync_time';

    @override
    SyncState build() {
      _restoreLastSyncTime();
      return const SyncState();
    }

    Future<void> _restoreLastSyncTime() async {
      final stored = await ref
          .read(secureStorageProvider)
          .read(key: keyLastSync);
      if (stored != null) {
        state = state.copyWith(lastSyncTime: DateTime.tryParse(stored));
      }
    }

    Future<void> syncAll() async {
      if (state.isSyncing) return;

      state = SyncState(isSyncing: true, lastSyncTime: state.lastSyncTime);
      final api = ref.read(fireflyApiServiceProvider);

      await _syncEntity<AccountDto>(
        fetch: api.getAccounts,
        upsert: (dto) => ref
            .read(accountDaoProvider)
            .upsert(
              AccountsCompanion(
                id: Value(dto.id),
                name: Value(dto.name),
                accountType: Value(dto.accountType),
                accountRole: Value(dto.accountRole),
                currencyCode: Value(dto.currencyCode),
                currencySymbol: Value(dto.currencySymbol),
                active: Value(dto.active),
              ),
            ),
        updateState: (s, e) => s.copyWith(accounts: e),
      );

      await _syncEntity<BillDto>(
        fetch: api.getBills,
        upsert: (dto) => ref
            .read(billDaoProvider)
            .upsert(BillsCompanion(id: Value(dto.id), name: Value(dto.name))),
        updateState: (s, e) => s.copyWith(bills: e),
      );

      await _syncEntity<BudgetDto>(
        fetch: api.getBudgets,
        upsert: (dto) => ref
            .read(budgetDaoProvider)
            .upsert(BudgetsCompanion(id: Value(dto.id), name: Value(dto.name))),
        updateState: (s, e) => s.copyWith(budgets: e),
      );

      await _syncEntity<CategoryDto>(
        fetch: api.getCategories,
        upsert: (dto) => ref
            .read(categoryDaoProvider)
            .upsert(
              CategoriesCompanion(id: Value(dto.id), name: Value(dto.name)),
            ),
        updateState: (s, e) => s.copyWith(categories: e),
      );

      await _syncEntity<PiggybankDto>(
        fetch: api.getPiggybanks,
        upsert: (dto) => ref
            .read(piggybankDaoProvider)
            .upsert(
              PiggybanksCompanion(id: Value(dto.id), name: Value(dto.name)),
            ),
        updateState: (s, e) => s.copyWith(piggybanks: e),
      );

      await _syncEntity<TagDto>(
        fetch: api.getTags,
        upsert: (dto) => ref
            .read(tagDaoProvider)
            .upsert(TagsCompanion(id: Value(dto.id), name: Value(dto.tag))),
        updateState: (s, e) => s.copyWith(tags: e),
      );

      final now = DateTime.now();
      await ref
          .read(secureStorageProvider)
          .write(key: keyLastSync, value: now.toIso8601String());

      await WidgetUpdateService.update(
        shortcutDao: ref.read(shortcutDaoProvider),
        settings: ref.read(settingsRepositoryProvider),
      );
      
      state = state.copyWith(isSyncing: false, lastSyncTime: now);
    }

    Future<void> _syncEntity<T>({
      required Future<List<T>> Function() fetch,
      required Future<void> Function(T) upsert,
      required SyncState Function(SyncState, EntitySyncState) updateState,
    }) async {
      state = updateState(state, const EntitySyncState(status: SyncStatus.syncing));
      try {
        final items = await fetch();
        for (final item in items) {
          await upsert(item);
        }
        state = updateState(
          state,
          EntitySyncState(status: SyncStatus.done, count: items.length),
        );
      } catch (e) {
        state = updateState(
          state,
          EntitySyncState(status: SyncStatus.error, errorMessage: e.toString()),
        );
      }
    }
  }