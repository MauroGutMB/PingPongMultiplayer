import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 0 = transparent, 1 = black outline, 2 = white fill. Drawn as flat vector
/// rects (not a scaled bitmap), so edges stay perfectly crisp at any size.
const _kBallSprite = [
  [0, 0, 1, 1, 1, 1, 0, 0],
  [0, 1, 2, 2, 2, 2, 1, 0],
  [1, 2, 2, 2, 2, 2, 2, 1],
  [1, 2, 2, 2, 2, 2, 2, 1],
  [1, 2, 2, 2, 2, 2, 2, 1],
  [1, 2, 2, 2, 2, 2, 2, 1],
  [0, 1, 2, 2, 2, 2, 1, 0],
  [0, 0, 1, 1, 1, 1, 0, 0],
];

class BallWidget extends StatelessWidget {
  const BallWidget({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PixelBallPainter()),
    );
  }
}

class _PixelBallPainter extends CustomPainter {
  static final _outlinePaint = Paint()..color = Colors.black;
  static final _fillPaint = Paint()..color = AppColors.gameElement;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = _kBallSprite.length;
    final cols = _kBallSprite.first.length;
    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final value = _kBallSprite[row][col];
        if (value == 0) continue;
        final rect = Rect.fromLTWH(
          col * cellWidth,
          row * cellHeight,
          cellWidth + 0.5,
          cellHeight + 0.5,
        );
        canvas.drawRect(rect, value == 1 ? _outlinePaint : _fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelBallPainter oldDelegate) => false;
}
