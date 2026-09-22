import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/database/daos/shortcut_dao.dart';
import '../../core/models/transaction_type.dart';
import '../../core/providers/core_providers.dart';
import '../../core/widget/widget_update_service.dart';
import '../../core/providers/dao_providers.dart';

class ShortcutEditorScreen extends ConsumerStatefulWidget {
  final int? shortcutId;
  const ShortcutEditorScreen({super.key, this.shortcutId});

  @override
  ConsumerState<ShortcutEditorScreen> createState() =>
      _ShortcutEditorScreenState();
}

class _ShortcutEditorScreenState extends ConsumerState<ShortcutEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _iconController;

  TransactionType _transactionType = TransactionType.withdrawal;
  String? _fromAccountId;
  String? _toAccountId;
  String? _categoryId;
  String? _billId;
  String? _budgetId;
  String? _piggybankId;
  Set<String> _selectedTagIds = {};

  List<Account>? _accounts;
  List<Category>? _categories;
  List<Bill>? _bills;
  List<Budget>? _budgets;
  List<Piggybank>? _piggybanks;
  List<Tag>? _tags;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _amountController = TextEditingController();
    _descriptionController = TextEditingController();
    _iconController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final (accounts, categories, bills, budgets, piggybanks, tags) = await (
      ref.read(accountDaoProvider).getAll(),
      ref.read(categoryDaoProvider).getAll(),
      ref.read(billDaoProvider).getAll(),
      ref.read(budgetDaoProvider).getAll(),
      ref.read(piggybankDaoProvider).getAll(),
      ref.read(tagDaoProvider).getAll(),
    ).wait;

    ShortcutWithTags? existing;
    if (widget.shortcutId != null) {
      existing = await ref
          .read(shortcutDaoProvider)
          .getByIdWithTags(widget.shortcutId!);
    }

    if (!mounted) return;

    setState(() {
      _accounts = accounts;
      _categories = categories;
      _bills = bills;
      _budgets = budgets;
      _piggybanks = piggybanks;
      _tags = tags;

      if (existing != null) {
        final s = existing.shortcut;
        _nameController.text = s.name;
        _amountController.text = s.amount;
        _descriptionController.text = s.description ?? '';
        _iconController.text = s.icon ?? '';
        _transactionType = s.transactionType;
        _fromAccountId = s.fromAccountId;
        _toAccountId = s.toAccountId;
        _categoryId = s.categoryId;
        _billId = s.billId;
        _budgetId = s.budgetId;
        _piggybankId = s.piggybankId;
        _selectedTagIds = existing.tags.map((t) => t.id).toSet();
      }

      _loading = false;
    });
  }

  List<Account> get _fromAccounts {
    if (_accounts == null) return [];
    return switch (_transactionType) {
      TransactionType.withdrawal =>
        _accounts!.where((a) => a.accountType == 'asset').toList(),
      TransactionType.deposit =>
        _accounts!.where((a) => a.accountType == 'revenue').toList(),
      TransactionType.transfer =>
        _accounts!.where((a) => a.accountType == 'asset').toList(),
    };
  }

  List<Account> get _toAccounts {
    if (_accounts == null) return [];
    return switch (_transactionType) {
      TransactionType.withdrawal =>
        _accounts!.where((a) => a.accountType == 'expense').toList(),
      TransactionType.deposit =>
        _accounts!.where((a) => a.accountType == 'asset').toList(),
      TransactionType.transfer =>
        _accounts!
            .where((a) => a.accountType == 'asset' && a.id != _fromAccountId)
            .toList(),
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dao = ref.read(shortcutDaoProvider);
      final companion = ShortcutsCompanion(
        name: Value(_nameController.text.trim()),
        amount: Value(_amountController.text.trim()),
        transactionType: Value(_transactionType),
        fromAccountId: Value(_fromAccountId!),
        toAccountId: Value(_toAccountId!),
        categoryId: Value(_categoryId),
        billId: Value(_billId),
        budgetId: Value(_budgetId),
        piggybankId: Value(_piggybankId),
        description: Value(
          _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
        ),
        icon: Value(
          _iconController.text.trim().isEmpty
              ? null
              : _iconController.text.trim(),
        ),
      );

      int id;
      if (widget.shortcutId == null) {
        id = await dao.insertShortcut(companion);
      } else {
        await dao.updateShortcut(
          companion.copyWith(id: Value(widget.shortcutId!)),
        );
        id = widget.shortcutId!;
      }
      await dao.setTagsForShortcut(id, _selectedTagIds.toList());

      WidgetUpdateService.update(
        shortcutDao: ref.read(shortcutDaoProvider),
        settings: ref.read(settingsRepositoryProvider),
      );

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.shortcutId == null ? 'New Shortcut' : 'Edit Shortcut',
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TransactionType>(
              value: _transactionType,
              decoration: const InputDecoration(
                labelText: 'Transaction Type',
                border: OutlineInputBorder(),
              ),
              items: TransactionType.values
                  .map(
                    (t) =>
                        DropdownMenuItem(value: t, child: Text(_typeLabel(t))),
                  )
                  .toList(),
              onChanged: (t) {
                if (t == null) return;
                setState(() {
                  _transactionType = t;
                  _fromAccountId = null;
                  _toAccountId = null;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v.trim()) == null) return 'Invalid number';
                return null;
              },
            ),
            const SizedBox(height: 24),
            _sectionTitle('Accounts'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _fromAccountId,
              decoration: InputDecoration(
                labelText: _fromLabel,
                border: const OutlineInputBorder(),
              ),
              items: _fromAccounts
                  .map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _fromAccountId = v;
                if (_transactionType == TransactionType.transfer &&
                    _toAccountId == v) {
                  _toAccountId = null;
                }
              }),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _toAccountId,
              decoration: InputDecoration(
                labelText: _toLabel,
                border: const OutlineInputBorder(),
              ),
              items: _toAccounts
                  .map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _toAccountId = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 24),
            _sectionTitle('Optional'),
            const SizedBox(height: 12),
            _NullableDropdown<Category>(
              label: 'Category',
              value: _categoryId,
              items: _categories ?? [],
              getLabel: (c) => c.name,
              getId: (c) => c.id,
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            _NullableDropdown<Budget>(
              label: 'Budget',
              value: _budgetId,
              items: _budgets ?? [],
              getLabel: (b) => b.name,
              getId: (b) => b.id,
              onChanged: (v) => setState(() => _budgetId = v),
            ),
            const SizedBox(height: 12),
            _NullableDropdown<Bill>(
              label: 'Bill',
              value: _billId,
              items: _bills ?? [],
              getLabel: (b) => b.name,
              getId: (b) => b.id,
              onChanged: (v) => setState(() => _billId = v),
            ),
            const SizedBox(height: 12),
            _NullableDropdown<Piggybank>(
              label: 'Piggy Bank',
              value: _piggybankId,
              items: _piggybanks ?? [],
              getLabel: (p) => p.name,
              getId: (p) => p.id,
              onChanged: (v) => setState(() => _piggybankId = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _iconController,
              decoration: const InputDecoration(
                labelText: 'Icon (emoji)',
                hintText: '💸',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Tags'),
            const SizedBox(height: 8),
            _buildTagChips(),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.shortcutId == null ? 'Create' : 'Save'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTagChips() {
    final tags = _tags ?? [];
    if (tags.isEmpty) {
      return Text(
        'No tags synced yet.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: tags.map((tag) {
        return FilterChip(
          label: Text(tag.name),
          selected: _selectedTagIds.contains(tag.id),
          onSelected: (v) => setState(() {
            if (v) {
              _selectedTagIds = {..._selectedTagIds, tag.id};
            } else {
              _selectedTagIds = _selectedTagIds
                  .where((id) => id != tag.id)
                  .toSet();
            }
          }),
        );
      }).toList(),
    );
  }

  String get _fromLabel => switch (_transactionType) {
    TransactionType.withdrawal => 'Source Account',
    TransactionType.deposit => 'Revenue Account',
    TransactionType.transfer => 'From Account',
  };

  String get _toLabel => switch (_transactionType) {
    TransactionType.withdrawal => 'Expense Account',
    TransactionType.deposit => 'Destination Account',
    TransactionType.transfer => 'To Account',
  };

  String _typeLabel(TransactionType t) => switch (t) {
    TransactionType.withdrawal => 'Withdrawal',
    TransactionType.deposit => 'Deposit',
    TransactionType.transfer => 'Transfer',
  };

  Widget _sectionTitle(String title) =>
      Text(title, style: Theme.of(context).textTheme.titleMedium);
}

class _NullableDropdown<T> extends StatelessWidget {
  final String label;
  final String? value;
  final List<T> items;
  final String Function(T) getLabel;
  final String Function(T) getId;
  final void Function(String?) onChanged;

  const _NullableDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.getLabel,
    required this.getId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('None')),
        ...items.map(
          (item) => DropdownMenuItem<String?>(
            value: getId(item),
            child: Text(getLabel(item)),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
