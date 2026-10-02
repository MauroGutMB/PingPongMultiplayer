import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol.dart';
import 'lobby_provider.dart';

/// Confirms the invite (letting the inviter pick the match settings), sends
/// it, then blocks with a waiting dialog until the target responds (the
/// dialog auto-closes either way).
Future<void> showSendInviteFlow(
  BuildContext context,
  PlayerInfo target,
  LobbyController controller,
) async {
  final config = await showDialog<MatchConfig>(
    context: context,
    builder: (context) => _ConfigureInviteDialog(target: target),
  );
  if (config == null) return;

  controller.sendInvite(target.id, config);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WaitingForResponseDialog(target: target),
  );
}

const _ballSpeedPresets = {'Lenta': 0.7, 'Normal': 1.0, 'Rápida': 1.4};
const _winningScorePresets = {'Sem limite': 0, '5 pontos': 5, '11 pontos': 11, '21 pontos': 21};
const _durationPresets = {'1 min': 60, '2 min': 120, '3 min': 180, '5 min': 300};

/// Lets the inviter pick the match's ball speed, winning score and duration
/// before the invite goes out. The invitee only ever sees a summary of these
/// (see [showInviteReceivedDialog]) and can't change them — the half-court
/// netcode needs both sides simulating with the exact same numbers, so only
/// one side ever decides.
class _ConfigureInviteDialog extends StatefulWidget {
  const _ConfigureInviteDialog({required this.target});

  final PlayerInfo target;

  @override
  State<_ConfigureInviteDialog> createState() => _ConfigureInviteDialogState();
}

class _ConfigureInviteDialogState extends State<_ConfigureInviteDialog> {
  double _ballSpeed = 1.0;
  int _winningScore = 0;
  int _duration = 120;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Convidar ${widget.target.nickname} para uma partida'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Velocidade da bola'),
            const SizedBox(height: 4),
            _PresetSelector(
              options: _ballSpeedPresets,
              value: _ballSpeed,
              onChanged: (v) => setState(() => _ballSpeed = v),
            ),
            const SizedBox(height: 16),
            const Text('Pontuação para vencer'),
            const SizedBox(height: 4),
            _PresetSelector(
              options: _winningScorePresets,
              value: _winningScore,
              onChanged: (v) => setState(() => _winningScore = v),
            ),
            const SizedBox(height: 16),
            const Text('Duração da partida'),
            const SizedBox(height: 4),
            _PresetSelector(
              options: _durationPresets,
              value: _duration,
              onChanged: (v) => setState(() => _duration = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            MatchConfig(
              ballSpeedMultiplier: _ballSpeed,
              winningScore: _winningScore,
              durationSeconds: _duration,
            ),
          ),
          child: const Text('Convidar'),
        ),
      ],
    );
  }
}

/// A row of selectable chips for one setting, built generically over the
/// preset's value type so the three pickers above share one widget.
class _PresetSelector<T> extends StatelessWidget {
  const _PresetSelector({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<String, T> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in options.entries)
          ChoiceChip(
            label: Text(entry.key),
            selected: entry.value == value,
            onSelected: (_) => onChanged(entry.value),
          ),
      ],
    );
  }
}

String _describeConfig(MatchConfig config) {
  final speed = _ballSpeedPresets.entries
      .firstWhere(
        (e) => e.value == config.ballSpeedMultiplier,
        orElse: () => const MapEntry('personalizada', 0.0),
      )
      .key;
  final score = config.winningScore <= 0
      ? 'sem limite de pontos'
      : '${config.winningScore} pontos';
  final minutes = config.durationSeconds ~/ 60;
  final seconds = config.durationSeconds % 60;
  final duration = seconds == 0 ? '$minutes min' : '$minutes min ${seconds}s';
  return 'Bola $speed, $score, $duration.';
}

class _WaitingForResponseDialog extends ConsumerWidget {
  const _WaitingForResponseDialog({required this.target});

  final PlayerInfo target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(lobbyControllerProvider, (previous, next) {
      // Must be an edge (was set, now cleared), not just "currently null" —
      // otherwise any later unrelated state change (e.g. acknowledging the
      // rejection, or even a player_list update) re-fires this and pops a
      // second route: since this dialog is already gone by then, that
      // second pop takes out the lobby screen underneath it, leaving an
      // empty Navigator stack (a black screen).
      if (previous?.outgoingInviteToId != null && next.outgoingInviteToId == null) {
        Navigator.of(context).pop();
      }
    });
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text('Aguardando resposta de ${target.nickname}...')),
        ],
      ),
    );
  }
}

/// Shown when another player invites us to a match.
Future<void> showInviteReceivedDialog(
  BuildContext context,
  IncomingInvite invite,
  LobbyController controller,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Convite recebido'),
      content: Text(
        '${invite.fromNickname} te convidou para uma partida.\n'
        '${_describeConfig(invite.config)}',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            controller.respondToInvite(false);
          },
          child: const Text('Recusar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            controller.respondToInvite(true);
          },
          child: const Text('Aceitar'),
        ),
      ],
    ),
  );
}
