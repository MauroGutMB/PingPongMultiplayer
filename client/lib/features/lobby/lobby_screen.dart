import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol.dart';
import '../game/game_screen.dart';
import 'invite_dialog.dart';
import 'lobby_provider.dart';

class LobbyScreen extends ConsumerWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lobbyControllerProvider);
    final controller = ref.read(lobbyControllerProvider.notifier);

    ref.listen(lobbyControllerProvider, (previous, next) {
      final invite = next.incomingInvite;
      if (invite != null && previous?.incomingInvite != invite) {
        showInviteReceivedDialog(context, invite, controller);
      }
      if (next.inviteRejected && previous?.inviteRejected != true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Seu convite foi recusado.')));
        controller.acknowledgeRejection();
      }
      if (next.inviteTargetLeft && previous?.inviteTargetLeft != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O jogador saiu antes de responder.')),
        );
        controller.acknowledgeRejection();
      }
      if (next.matchStart != null && previous?.matchStart != next.matchStart) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NetworkGameScreen()));
      }
    });

    if (state.status == LobbyStatus.disconnected) {
      return _NicknamePrompt(onSubmit: controller.connect);
    }

    if (state.status == LobbyStatus.connecting) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Aguardando resposta do servidor...'),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Pode demorar um pouco se o servidor estiver inativo no momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.status == LobbyStatus.error) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Erro ao conectar ao servidor.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: controller.retry,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jogadores online'),
        actions: [
          IconButton(
            tooltip: 'Testar jogo local (sem oponente)',
            icon: const Icon(Icons.sports_esports),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GameScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refreshPlayers,
        child: _PlayerListView(
          players: state.otherPlayers,
          onTap: (player) => showSendInviteFlow(context, player, controller),
        ),
      ),
    );
  }
}

class _NicknamePrompt extends ConsumerStatefulWidget {
  const _NicknamePrompt({required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  ConsumerState<_NicknamePrompt> createState() => _NicknamePromptState();
}

class _NicknamePromptState extends ConsumerState<_NicknamePrompt> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Escolha um apelido'),
              const SizedBox(height: 12),
              TextField(controller: _controller, onSubmitted: _submit),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _submit(_controller.text),
                child: const Text('Entrar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _showManualServerDialog(context),
                child: const Text('Usar outro servidor'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit(String value) {
    final nickname = value.trim();
    if (nickname.isEmpty) return;
    widget.onSubmit(nickname);
  }

  Future<void> _showManualServerDialog(BuildContext context) async {
    final override = ref.read(serverUrlOverrideProvider);
    final urlController = TextEditingController(
      text: override ?? ref.read(serverUrlProvider),
    );
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('URL do servidor'),
        content: TextField(
          controller: urlController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ws://192.168.0.10:8080'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, urlController.text.trim()),
            child: const Text('Usar'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    ref.read(serverUrlOverrideProvider.notifier).set(url);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _PlayerListView extends StatelessWidget {
  const _PlayerListView({required this.players, required this.onTap});

  final List<PlayerInfo> players;
  final ValueChanged<PlayerInfo> onTap;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      // Needs to stay scrollable even though it's empty — a RefreshIndicator
      // above this only detects the pull gesture over a Scrollable, and an
      // empty roster is exactly when someone is most likely to pull-to-refresh.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 96),
            child: Center(child: Text('Nenhum outro jogador online no momento.')),
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: players.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final player = players[index];
        return ListTile(
          leading: const Icon(Icons.sports_tennis),
          title: Text(player.nickname),
          subtitle: Text(
            player.ip,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          onTap: () => onTap(player),
        );
      },
    );
  }
}
