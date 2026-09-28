import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/protocol.dart';
import 'lobby_provider.dart';

/// Confirms the invite, sends it, then blocks with a waiting dialog until
/// the target responds (the dialog auto-closes either way).
Future<void> showSendInviteFlow(
  BuildContext context,
  PlayerInfo target,
  LobbyController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Convidar para jogar'),
      content: Text('Convidar ${target.nickname} para uma partida?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Convidar'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  controller.sendInvite(target.id);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WaitingForResponseDialog(target: target),
  );
}

class _WaitingForResponseDialog extends ConsumerWidget {
  const _WaitingForResponseDialog({required this.target});

  final PlayerInfo target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(lobbyControllerProvider, (previous, next) {
      if (next.outgoingInviteToId == null) {
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
      content: Text('${invite.fromNickname} te convidou para uma partida.'),
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
