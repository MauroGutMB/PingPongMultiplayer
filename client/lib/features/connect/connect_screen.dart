import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/gist_config_service.dart';
import '../../core/theme.dart';
import '../lobby/lobby_provider.dart';
import '../lobby/lobby_screen.dart';

/// Overridable in tests to avoid a real HTTP call.
final gistConfigServiceProvider = Provider<GistConfigService>((ref) {
  return GistConfigService(kGistConfigUrl);
});

/// First screen the app shows: pick how to find the server before the lobby
/// (and its WebSocket connection) is ever created.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _loading = false;
  String? _error;

  void _goToLobby(String url) {
    ref.read(serverUrlOverrideProvider.notifier).set(url);
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LobbyScreen()));
  }

  Future<void> _connectAutomatically() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await ref.read(gistConfigServiceProvider).fetchServerUrl();
      if (!mounted) return;
      _goToLobby(url);
    } on GistConfigException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectManually() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualUrlDialog(),
    );
    if (url == null || url.isEmpty || !mounted) return;
    _goToLobby(url);
  }

  Future<void> _showConnectMenu() async {
    final choice = await showDialog<_ConnectMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conectar'),
        content: const Text('Como você quer encontrar o servidor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ConnectMode.manual),
            child: const Text('Usar URL manual'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ConnectMode.automatic),
            child: const Text('Automática'),
          ),
        ],
      ),
    );

    switch (choice) {
      case _ConnectMode.automatic:
        await _connectAutomatically();
      case _ConnectMode.manual:
        await _connectManually();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sports_tennis,
                size: 64,
                color: AppColors.white,
              ),
              const SizedBox(height: 16),
              const Text(
                'PingPong Multiplayer',
                style: TextStyle(color: AppColors.white, fontSize: 22),
              ),
              const SizedBox(height: 32),
              if (_loading)
                const CircularProgressIndicator()
              else
                FilledButton(
                  onPressed: _showConnectMenu,
                  child: const Text('Conectar'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _ConnectMode { automatic, manual }

class _ManualUrlDialog extends StatefulWidget {
  const _ManualUrlDialog();

  @override
  State<_ManualUrlDialog> createState() => _ManualUrlDialogState();
}

class _ManualUrlDialogState extends State<_ManualUrlDialog> {
  late final _controller = TextEditingController(text: kDefaultServerUrl);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('URL do servidor'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'ws://192.168.0.10:8080'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Conectar'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
