import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/models/transaction_request.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/database/daos/shortcut_dao.dart';
import '../../core/models/transaction_type.dart';
import '../../core/providers/core_providers.dart';
import '../../core/widget/widget_update_service.dart';
import '../../core/providers/dao_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final Set<int> _executing = {};

  // On app start, ensure widgets are updated with latest shortcuts and settings
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetUpdateService.update(
        shortcutDao: ref.read(shortcutDaoProvider),
        settings: ref.read(settingsRepositoryProvider),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (prev, next) {
      if (!next.isAuthenticated) context.go('/settings');
    });

    final shortcutsAsync = ref.watch(shortcutListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firefly Shortcuts'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/shortcut/new'),
        child: const Icon(Icons.add),
      ),
      body: shortcutsAsync.when(
        data: (shortcuts) {
          if (shortcuts.isEmpty) {
            return const Center(
              child: Text('No shortcuts yet. Tap + to create one.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: shortcuts.length,
            itemBuilder: (context, i) => _ShortcutCard(
              item: shortcuts[i],
              executing: _executing.contains(shortcuts[i].shortcut.id),
              onExecute: () => _confirmExecute(shortcuts[i]),
              onEdit: () =>
                  context.push('/shortcut/${shortcuts[i].shortcut.id}'),
              onDelete: () => _confirmDelete(shortcuts[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _confirmExecute(ShortcutDetail item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Execute "${item.shortcut.name}"?'),
        content: Text(
          '${_typeLabel(item.shortcut.transactionType)}  ${item.shortcut.amount}\n'
          '${item.fromAccount.name} → ${item.toAccount.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Execute'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _execute(item);
  }

  Future<void> _execute(ShortcutDetail item) async {
    final id = item.shortcut.id;
    setState(() => _executing.add(id));
    try {
      await ref
          .read(fireflyApiServiceProvider)
          .createTransaction(
            TransactionRequest(
              transactions: [
                TransactionItem(
                  type: item.shortcut.transactionType.apiValue,
                  date: TransactionItem.formatDate(DateTime.now()),
                  amount: item.shortcut.amount,
                  description: item.shortcut.description ?? item.shortcut.name,
                  sourceId: item.fromAccount.id,
                  sourceName: item.fromAccount.name,
                  destinationId: item.toAccount.id,
                  destinationName: item.toAccount.name,
                  categoryId: item.shortcut.categoryId,
                  budgetId: item.shortcut.budgetId,
                  billId: item.shortcut.billId,
                  piggyBankId: item.shortcut.piggybankId,
                  tags: item.tags.map((t) => t.name).toList(),
                ),
              ],
            ),
          );
      await ref.read(shortcutDaoProvider).updateLastUsed(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.shortcut.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${item.shortcut.amount}  •  ${item.fromAccount.name} → ${item.toAccount.name}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failureMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _executing.remove(id));
    }
  }

  // After a send or receive timeout, or a dropped connection, the server may
  // already have stored the transaction. A retry would carry a new date and
  // not be caught as a duplicate, so say so rather than just "failed".
  String _failureMessage(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.unknown:
          return 'No response from Firefly. The transaction may have been '
              'created; check Firefly before trying again.';
        case DioExceptionType.badResponse:
          final data = e.response?.data;
          final message = data is Map ? data['message'] : null;
          if (message is String && message.isNotEmpty) {
            return 'Failed: $message';
          }
        default:
      }
    }
    return 'Failed: $e';
  }

  Future<void> _confirmDelete(ShortcutDetail item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete shortcut?'),
        content: Text('"${item.shortcut.name}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(shortcutDaoProvider).deleteShortcut(item.shortcut.id);
      WidgetUpdateService.update(
          shortcutDao: ref.read(shortcutDaoProvider),
          settings: ref.read(settingsRepositoryProvider),
        );
    }
  }

  String _typeLabel(TransactionType t) => switch (t) {
    TransactionType.withdrawal => 'Withdrawal',
    TransactionType.deposit => 'Deposit',
    TransactionType.transfer => 'Transfer',
  };
}

class _ShortcutCard extends StatelessWidget {
  final ShortcutDetail item;
  final bool executing;
  final VoidCallback onExecute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ShortcutCard({
    required this.item,
    required this.executing,
    required this.onExecute,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = item.shortcut;
    final hasIcon = s.icon != null && s.icon!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: executing ? null : onExecute,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: hasIcon
                    ? Text(s.icon!, style: const TextStyle(fontSize: 28))
                    : Icon(
                        _typeIcon(s.transactionType),
                        size: 28,
                        color: _typeColor(s.transactionType),
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.fromAccount.name} → ${item.toAccount.name}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _TypeBadge(type: s.transactionType),
                        const SizedBox(width: 8),
                        Text(
                          s.amount,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (executing)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(TransactionType t) => switch (t) {
    TransactionType.withdrawal => Icons.arrow_upward,
    TransactionType.deposit => Icons.arrow_downward,
    TransactionType.transfer => Icons.swap_horiz,
  };

  Color _typeColor(TransactionType t) => switch (t) {
    TransactionType.withdrawal => Colors.red,
    TransactionType.deposit => Colors.green,
    TransactionType.transfer => Colors.blue,
  };
}

class _TypeBadge extends StatelessWidget {
  final TransactionType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      TransactionType.withdrawal => ('Withdrawal', Colors.red),
      TransactionType.deposit => ('Deposit', Colors.green),
      TransactionType.transfer => ('Transfer', Colors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
