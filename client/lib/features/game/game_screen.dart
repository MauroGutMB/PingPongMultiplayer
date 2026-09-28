import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'widgets/ball_widget.dart';
import 'widgets/control_buttons.dart';
import 'widgets/paddle_widget.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(flex: 4, child: _FieldSection()),
            Expanded(flex: 1, child: ControlButtons()),
          ],
        ),
      ),
    );
  }
}

class _FieldSection extends StatelessWidget {
  const _FieldSection();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final paddleWidth = constraints.maxWidth * 0.3;
            return Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: PaddleWidget(width: paddleWidth),
                ),
                const BallWidget(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: PaddleWidget(width: paddleWidth),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
