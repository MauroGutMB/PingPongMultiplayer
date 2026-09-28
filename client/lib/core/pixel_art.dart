import 'package:flutter/material.dart';

/// Lightens [base] toward white (positive [amount]) or darkens it toward
/// black (negative [amount]), by up to 100% at |amount| == 1.
Color pixelShade(Color base, double amount) {
  if (amount >= 0) return Color.lerp(base, Colors.white, amount)!;
  return Color.lerp(base, Colors.black, -amount)!;
}

/// A chunky, hard-edged "8-bit" bevel: a black outline, a lighter highlight
/// along the top/left edges, and a darker shadow along the bottom/right
/// edges — the classic retro-UI trick for making a flat color read as a
/// raised (or, when [pressed], pushed-in) button/panel.
class PixelBevelBox extends StatelessWidget {
  const PixelBevelBox({
    super.key,
    required this.child,
    this.color = const Color(0xFF7C3AED),
    this.pixelSize = 4,
    this.pressed = false,
  });

  final Widget child;
  final Color color;
  final double pixelSize;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final highlight = pixelShade(color, pressed ? -0.25 : 0.3);
    final shadow = pixelShade(color, pressed ? 0.15 : -0.35);

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: Padding(
        padding: EdgeInsets.all(pixelSize),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            border: Border(
              top: BorderSide(color: highlight, width: pixelSize),
              left: BorderSide(color: highlight, width: pixelSize),
              bottom: BorderSide(color: shadow, width: pixelSize),
              right: BorderSide(color: shadow, width: pixelSize),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
