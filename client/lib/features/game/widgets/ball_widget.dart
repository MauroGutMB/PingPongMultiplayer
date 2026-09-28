import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class BallWidget extends StatelessWidget {
  const BallWidget({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, color: AppColors.gameElement);
  }
}
