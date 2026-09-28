import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class GameView extends StatelessWidget {
  const GameView({super.key, required this.state, required this.onDirectionChanged});

  final GameState state;
  final ValueChanged<MoveDirection?> onDirectionChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(flex: 4, child: _FieldSection(state: state)),
            Expanded(
              flex: 1,
              child: ControlButtons(onDirectionChanged: onDirectionChanged),
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
    return GameView(state: state, onDirectionChanged: controller.setPlayerDirection);
  }
}

class _FieldSection extends StatelessWidget {
  const _FieldSection({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _ScoreTimerRow(state: state),
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
  const _ScoreTimerRow({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final minutes = (state.remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (state.remainingSeconds % 60).toString().padLeft(2, '0');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _StatBox(label: 'ADVERSÁRIO', value: '${state.scoreTop}'),
        _StatBox(label: 'TEMPO', value: '$minutes:$seconds'),
        _StatBox(label: 'VOCÊ', value: '${state.scoreBottom}'),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.purple,
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.purpleLight),
        ),
      ),
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
              const Text(
                'Fim de partida',
                style: TextStyle(color: AppColors.white, fontSize: 22),
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
