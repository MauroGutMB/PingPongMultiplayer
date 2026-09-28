import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class PaddleWidget extends StatelessWidget {
  const PaddleWidget({super.key, required this.width, this.height = 14});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(width: width, height: height, color: AppColors.gameElement);
  }
}
