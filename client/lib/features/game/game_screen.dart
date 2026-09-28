import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'game_constants.dart';
import 'game_loop_controller.dart';
import 'game_state.dart';
import 'widgets/ball_widget.dart';
import 'widgets/control_buttons.dart';
import 'widgets/paddle_widget.dart';

class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameLoopProvider);
    final controller = ref.read(gameLoopProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(flex: 4, child: _FieldSection(state: state)),
            Expanded(
              flex: 1,
              child: ControlButtons(
                onDirectionChanged: controller.setPlayerDirection,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldSection extends StatelessWidget {
  const _FieldSection({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final paddleWidthPx = size.width * state.paddleWidth;
                return Stack(
                  children: [
                    _fieldPositioned(
                      normalized: Offset(state.opponentPaddleX, kPaddleBandOffset),
                      size: size,
                      child: PaddleWidget(width: paddleWidthPx),
                    ),
                    _fieldPositioned(
                      normalized: Offset(state.ballX, state.ballY),
                      size: size,
                      child: const BallWidget(),
                    ),
                    _fieldPositioned(
                      normalized: Offset(state.playerPaddleX, 1 - kPaddleBandOffset),
                      size: size,
                      child: PaddleWidget(width: paddleWidthPx),
                    ),
                  ],
                );
              },
            ),
            Positioned(top: 0, left: 0, right: 0, child: _ScoreBar(state: state)),
            if (state.matchOver) _MatchOverOverlay(state: state),
          ],
        ),
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

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    final minutes = (state.remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (state.remainingSeconds % 60).toString().padLeft(2, '0');
    const style = TextStyle(
      color: AppColors.white,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${state.scoreTop}', style: style),
          Text('$minutes:$seconds', style: style.copyWith(fontSize: 18)),
          Text('${state.scoreBottom}', style: style),
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
