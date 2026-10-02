import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol.dart';
import '../game/game_screen.dart';
import '../game/spectator_screen.dart';
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
      if (next.spectateSession != null &&
          previous?.spectateSession != next.spectateSession) {
        controller.acknowledgeSpectateSession();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SpectatorScreen()));
      }
      if (next.spectateError != null && previous?.spectateError != next.spectateError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.spectateError!)));
        controller.acknowledgeSpectateError();
      }
      if (next.refreshFailed && previous?.refreshFailed != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Não foi possível atualizar. Tente novamente.'),
            action: SnackBarAction(label: 'Tentar novamente', onPressed: controller.refreshAll),
          ),
        );
        controller.acknowledgeRefreshFailure();
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
          // Same size/style as the button above (both are plain AppBar
          // IconButtons) so the two sit flush with consistent spacing.
          Tooltip(
            message: 'Atualizar jogadores e partidas',
            child: IconButton(
              // Disabled (onPressed: null) while a refresh is in flight:
              // Flutter dims it and blocks taps on its own, which both
              // prevents duplicate concurrent requests and gives screen
              // readers the right "disabled" state for free.
              onPressed: state.isRefreshing ? null : controller.refreshAll,
              icon: state.isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              style: IconButton.styleFrom(
                disabledForegroundColor: Colors.white70,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 55/45 split: the player list is the primary, more frequent
          // action (inviting someone), so it gets a slightly larger share;
          // the match list is secondary (spectating) but still always
          // visible without one container crowding the other off-screen.
          Expanded(
            flex: 11,
            child: _SectionContainer(
              title: 'Jogadores online',
              icon: Icons.people,
              child: RefreshIndicator(
                onRefresh: controller.refreshPlayers,
                child: _PlayerListView(
                  players: state.otherPlayers,
                  onTap: (player) => showSendInviteFlow(context, player, controller),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 9,
            child: _SectionContainer(
              title: 'Partidas iniciadas',
              icon: Icons.sports_tennis,
              child: RefreshIndicator(
                onRefresh: controller.refreshMatches,
                child: _MatchListView(
                  matches: state.matches,
                  onTap: (match) => controller.requestSpectate(match.matchId),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared chrome for both lobby containers: a header row and the scrollable
/// body underneath it. Each container scrolls independently (its own
/// [RefreshIndicator]/[ListView] below), so a long list in one never pushes
/// the other off screen.
class _SectionContainer extends StatelessWidget {
  const _SectionContainer({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
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
            padding: EdgeInsets.only(top: 48),
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
        // A pending invite (sent or received, by this player) is enforced on
        // the server — see MatchService._pendingInviteFromByTarget — and
        // only reflected here, never decided here: the entry stays visible
        // (so it's clear why someone can't be invited right now) but
        // disabled, instead of silently vanishing from the list.
        final disabled = player.pendingInvite;
        return Semantics(
          button: !disabled,
          enabled: !disabled,
          label: disabled
              ? '${player.nickname}, convite pendente, indisponível'
              : '${player.nickname}, toque para convidar',
          child: ListTile(
            leading: Icon(
              Icons.sports_tennis,
              color: disabled ? Colors.white38 : null,
            ),
            title: Text(
              player.nickname,
              style: disabled ? const TextStyle(color: Colors.white38) : null,
            ),
            subtitle: Text(
              disabled ? 'Convite pendente' : player.ip,
              style: TextStyle(fontSize: 11, color: disabled ? Colors.white38 : Colors.white70),
            ),
            onTap: disabled ? null : () => onTap(player),
          ),
        );
      },
    );
  }
}

class _MatchListView extends StatelessWidget {
  const _MatchListView({required this.matches, required this.onTap});

  final List<MatchSummary> matches;
  final ValueChanged<MatchSummary> onTap;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('Nenhuma partida em andamento no momento.')),
          ),
        ],
      );
    }
    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final match = matches[index];
        final subtitle = match.spectatorCount > 0
            ? '${match.spectatorCount} ${match.spectatorCount == 1 ? 'espectador' : 'espectadores'}'
            : 'Toque para assistir';
        return Semantics(
          button: true,
          label:
              '${match.bottomNickname} contra ${match.topNickname}, $subtitle, toque para espectar',
          child: ListTile(
            leading: const Icon(Icons.visibility),
            title: Text('${match.bottomNickname} x ${match.topNickname}'),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            onTap: () => onTap(match),
          ),
        );
      },
    );
  }
}
