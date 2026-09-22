import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/auth/auth_state.dart';
import '../../core/providers/dao_providers.dart';
import '../../core/settings/settings_repository.dart';
import 'settings_notifier.dart';
import 'settings_state.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _serverUrlController;
  late final TextEditingController _clientIdController;
  late final TextEditingController _redirectUrlController;
  late final TextEditingController _patController;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController();
    _clientIdController = TextEditingController();
    _redirectUrlController = TextEditingController();
    _patController = TextEditingController();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _clientIdController.dispose();
    _redirectUrlController.dispose();
    _patController.dispose();
    super.dispose();
  }

  void _populateControllers(SettingsState state) {
    _serverUrlController.text = state.serverUrl;
    _clientIdController.text = state.clientId;
    _redirectUrlController.text = state.redirectUrl;
    _patController.text = state.personalAccessToken;
  }

  Future<void> _save() async {
    try {
      await ref
          .read(settingsProvider.notifier)
          .save(
            serverUrl: _serverUrlController.text.trim(),
            clientId: _clientIdController.text.trim(),
            redirectUrl: _redirectUrlController.text.trim(),
            personalAccessToken: _patController.text.replaceAll(RegExp(r'\s+'), ''),
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    }
  }

  // Shortcuts hold Firefly IDs from the server they were created on, and
  // connecting elsewhere wipes them. Ask while the user can still back out.
  // A different account on the same server is only known after login.
  Future<bool> _confirmServerSwitch() async {
    final newUrl = SettingsRepository.normalizeServerUrl(
      _serverUrlController.text.trim(),
    );
    final ownerUrl = await ref.read(authProvider.notifier).dataOwnerServerUrl();
    if (ownerUrl == null || ownerUrl == newUrl) return true;
    final count = await ref.read(shortcutDaoProvider).count();
    if (count == 0) return true;
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch server?'),
        content: Text(
          'Your $count shortcut${count == 1 ? '' : 's'} belong to $ownerUrl. '
          'Connecting to $newUrl deletes them, along with the synced '
          'accounts, categories and tags.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete and connect'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _connect() async {
    // Captured up front: a successful login navigates away from this screen.
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirmServerSwitch()) return;
    setState(() => _isConnecting = true);
    try {
      await _save();
      final pat = _patController.text.replaceAll(RegExp(r'\s+'), '');
      final LoginResult result;
      if (pat.isNotEmpty) {
        result = await ref.read(authProvider.notifier).loginWithPat(pat);
        if (mounted) context.go('/home');
      } else {
        result = await ref.read(authProvider.notifier).login();
      }
      if (result == LoginResult.connectedDataCleared) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Shortcuts from the previous Firefly account were removed',
            ),
          ),
        );
      } else if (result == LoginResult.failed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OAuth login failed or was cancelled'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (previous, next) {
      if (previous?.value == null && next.value != null) {
        _populateControllers(next.value!);
      }
    });

    ref.listen(authProvider, (prev, next) {
      if (next.isAuthenticated && !(prev?.isAuthenticated ?? false)) {
        context.go('/home');
      }
    });

    final settingsAsync = ref.watch(settingsProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: settingsAsync.when(
        data: (_) => _buildBody(context, authState),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading settings: $e')),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AuthState authState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(context, 'Server'),
          const SizedBox(height: 12),
          TextField(
            controller: _serverUrlController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://your-firefly.example.com',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Personal Access Token'),
          const SizedBox(height: 4),
          Text(
            'Takes priority over OAuth if filled.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _patController,
            decoration: const InputDecoration(
              labelText: 'Personal Access Token',
              hintText:
                  'Firefly III → Profile → OAuth → Personal Access Tokens',
              border: OutlineInputBorder(),
            ),
            maxLines: 5,
            minLines: 3,
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'OAuth2'),
          const SizedBox(height: 4),
          Text(
            'Used when no Personal Access Token is provided.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clientIdController,
            decoration: const InputDecoration(
              labelText: 'Client ID',
              hintText: '12345678-1234-1234-1234-123456789abc',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.text,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _redirectUrlController,
            decoration: const InputDecoration(
              labelText: 'Redirect URL',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Connection'),
          const SizedBox(height: 12),
          _buildConnectionStatus(context, authState),
          const SizedBox(height: 16),
          if (authState.isAuthenticated)
            OutlinedButton(
              onPressed: _disconnect,
              child: const Text('Disconnect'),
            )
          else
            FilledButton(
              onPressed: _isConnecting ? null : _connect,
              child: _isConnecting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(BuildContext context, AuthState authState) {
    if (!authState.isAuthenticated) {
      return _statusRow(
        icon: Icons.cancel,
        color: Colors.red,
        text: 'Not connected',
      );
    }

    if (authState.isOAuth) {
      return _statusRow(
        icon: Icons.check_circle,
        color: Colors.green,
        text: 'Connected via OAuth',
      );
    }

    final expiry = authState.patExpiry;
    if (expiry == null) {
      return _statusRow(
        icon: Icons.check_circle,
        color: Colors.green,
        text: 'Connected via Access Token',
      );
    }

    final daysLeft = expiry.difference(DateTime.now()).inDays;
    if (daysLeft <= 0) {
      return _statusRow(
        icon: Icons.error,
        color: Colors.red,
        text: 'Access Token expired — please reconnect',
      );
    }
    if (daysLeft <= 30) {
      return _statusRow(
        icon: Icons.warning,
        color: Colors.orange,
        text: 'Access Token expires in $daysLeft days',
      );
    }
    return _statusRow(
      icon: Icons.check_circle,
      color: Colors.green,
      text: 'Connected via Access Token ($daysLeft days remaining)',
    );
  }

  Widget _statusRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}
