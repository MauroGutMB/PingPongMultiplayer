import 'package:flutter/material.dart';

import '../../../core/pixel_art.dart';
import '../../../core/theme.dart';

class PaddleWidget extends StatelessWidget {
  const PaddleWidget({super.key, required this.width, this.height = 16});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const PixelBevelBox(
        color: AppColors.gameElement,
        pixelSize: 2,
        child: SizedBox.expand(),
      ),
    );
  }
}
