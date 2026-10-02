import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pixel_art.dart';
import '../../core/theme.dart';
import 'game_constants.dart';
import 'game_loop_controller.dart';
import 'game_state.dart';
import 'network_game_loop_controller.dart';
import 'widgets/ball_widget.dart';
import 'widgets/control_buttons.dart';
import 'widgets/paddle_widget.dart';

/// Renders a [GameState] and wires the control buttons to [onDirectionChanged]
/// — shared by the standalone practice screen and the real networked match.
/// With [readOnly] (spectators), the control section is replaced by a plain
/// label instead of hold-to-move buttons — see SpectatorScreen, and the
/// server side validation in MatchService.handleSpectateRequest, which is
/// what actually keeps a spectator from affecting the match: hiding the
/// buttons here is only a convenience for an honest client, not the thing
/// that enforces read-only access.
class GameView extends StatelessWidget {
  const GameView({
    super.key,
    required this.state,
    required this.onDirectionChanged,
    this.readOnly = false,
    this.topLabel = 'ADVERSÁRIO',
    this.bottomLabel = 'VOCÊ',
  });

  final GameState state;
  final ValueChanged<MoveDirection?> onDirectionChanged;
  final bool readOnly;
  final String topLabel;
  final String bottomLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: _FieldSection(state: state, topLabel: topLabel, bottomLabel: bottomLabel),
            ),
            Expanded(
              flex: 1,
              child: readOnly
                  ? const Center(
                      child: Text(
                        'Modo espectador: acompanhando a partida em tempo real.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    )
                  : ControlButtons(onDirectionChanged: onDirectionChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone local practice: no opponent, no network.
class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameLoopProvider);
    final controller = ref.read(gameLoopProvider.notifier);
    return GameView(state: state, onDirectionChanged: controller.setPlayerDirection);
  }
}

/// A real match against another connected player.
class NetworkGameScreen extends ConsumerWidget {
  const NetworkGameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(networkGameLoopProvider);
    final controller = ref.read(networkGameLoopProvider.notifier);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) controller.leaveMatch();
      },
      child: GameView(state: state, onDirectionChanged: controller.setPlayerDirection),
    );
  }
}

class _FieldSection extends StatelessWidget {
  const _FieldSection({required this.state, required this.topLabel, required this.bottomLabel});

  final GameState state;
  final String topLabel;
  final String bottomLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                _ScoreTimerRow(state: state, topLabel: topLabel, bottomLabel: bottomLabel),
                _SpectatorIndicator(count: state.spectatorCount),
              ],
            ),
          ),
          // The play field gets its own space below the score/timer boxes,
          // so the opponent paddle can never render underneath them.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      final paddleWidthPx = size.width * state.paddleWidth;
                      return Stack(
                        children: [
                          _fieldPositioned(
                            normalized: Offset(
                              state.opponentPaddleX,
                              kPaddleBandOffset,
                            ),
                            size: size,
                            child: PaddleWidget(width: paddleWidthPx),
                          ),
                          _fieldPositioned(
                            normalized: Offset(state.ballX, state.ballY),
                            size: size,
                            child: const BallWidget(),
                          ),
                          _fieldPositioned(
                            normalized: Offset(
                              state.playerPaddleX,
                              1 - kPaddleBandOffset,
                            ),
                            size: size,
                            child: PaddleWidget(width: paddleWidthPx),
                          ),
                        ],
                      );
                    },
                  ),
                  if (state.matchOver) _MatchOverOverlay(state: state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _fieldPositioned({
  required Offset normalized,
  required Size size,
  required Widget child,
}) {
  return Positioned(
    left: normalized.dx * size.width,
    top: normalized.dy * size.height,
    child: FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: child,
    ),
  );
}

class _ScoreTimerRow extends StatelessWidget {
  const _ScoreTimerRow({required this.state, required this.topLabel, required this.bottomLabel});

  final GameState state;
  final String topLabel;
  final String bottomLabel;

  @override
  Widget build(BuildContext context) {
    final minutes = (state.remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (state.remainingSeconds % 60).toString().padLeft(2, '0');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _StatBox(label: topLabel, value: '${state.scoreTop}'),
        _StatBox(label: 'TEMPO', value: '$minutes:$seconds'),
        _StatBox(label: bottomLabel, value: '${state.scoreBottom}'),
      ],
    );
  }
}

/// Eye icon + spectator count, shown right below the score/timer boxes.
/// Collapses to nothing (zero height, not just invisible) when nobody is
/// watching, so an empty count never reserves blank space in the layout —
/// and since it's appended below the score/timer row rather than inserted
/// between its elements, those never shift when this appears or disappears.
class _SpectatorIndicator extends StatelessWidget {
  const _SpectatorIndicator({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        label: '$count ${count == 1 ? 'espectador assistindo' : 'espectadores assistindo'}',
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility, size: 16, color: Colors.white70),
              const SizedBox(width: 4),
              Text('$count', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return PixelBevelBox(
      color: AppColors.purple,
      pixelSize: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.white, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchOverOverlay extends StatelessWidget {
  const _MatchOverOverlay({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.opponentLeft ? 'O adversário desconectou' : 'Fim de partida',
                style: const TextStyle(color: AppColors.white, fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${state.scoreTop} x ${state.scoreBottom}',
                style: const TextStyle(color: AppColors.white, fontSize: 32),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
