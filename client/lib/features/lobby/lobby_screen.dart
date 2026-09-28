import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol.dart';
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
      if (next.matchStart != null && previous?.matchStart != next.matchStart) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Partida encontrada! Lado: ${next.matchStart!.side}')),
        );
      }
    });

    if (state.status == LobbyStatus.disconnected) {
      return _NicknamePrompt(onSubmit: controller.connect);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Jogadores online')),
      body: switch (state.status) {
        LobbyStatus.connecting => const Center(child: CircularProgressIndicator()),
        LobbyStatus.error => const Center(
          child: Text('Erro ao conectar ao servidor.'),
        ),
        _ => _PlayerListView(
          players: state.otherPlayers,
          onTap: (player) => showSendInviteFlow(context, player, controller),
        ),
      },
    );
  }
}

class _NicknamePrompt extends StatefulWidget {
  const _NicknamePrompt({required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<_NicknamePrompt> createState() => _NicknamePromptState();
}

class _NicknamePromptState extends State<_NicknamePrompt> {
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
      return const Center(child: Text('Nenhum outro jogador online no momento.'));
    }
    return ListView.separated(
      itemCount: players.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final player = players[index];
        return ListTile(
          leading: const Icon(Icons.sports_tennis),
          title: Text(player.nickname),
          onTap: () => onTap(player),
        );
      },
    );
  }
}
