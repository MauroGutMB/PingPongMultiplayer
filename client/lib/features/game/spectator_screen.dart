import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'game_screen.dart';
import 'spectator_game_controller.dart';

/// Read only view of a match in progress. Reuses [GameView] with
/// `readOnly: true` (no control buttons) — the actual enforcement that a
/// spectator can never affect the match lives on the server
/// (MatchService.handleSpectateRequest/relay), not here; this only keeps an
/// honest client's UI from offering an action that would do nothing anyway.
class SpectatorScreen extends ConsumerWidget {
  const SpectatorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spectatorGameProvider);
    final controller = ref.read(spectatorGameProvider.notifier);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.leaveSpectate();
      },
      child: GameView(
        state: state,
        onDirectionChanged: (_) {},
        readOnly: true,
        topLabel: 'JOGADOR DE CIMA',
        bottomLabel: 'JOGADOR DE BAIXO',
      ),
    );
  }
}
