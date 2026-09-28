import 'package:flutter/material.dart';

import '../../../core/pixel_art.dart';
import '../../../core/theme.dart';

enum MoveDirection { left, right }

/// Bottom control section: two large hold-to-move buttons. Highlights while
/// pressed and reports the held direction (or null on release) via
/// [onDirectionChanged].
class ControlButtons extends StatefulWidget {
  const ControlButtons({super.key, this.onDirectionChanged});

  final ValueChanged<MoveDirection?>? onDirectionChanged;

  @override
  State<ControlButtons> createState() => _ControlButtonsState();
}

class _ControlButtonsState extends State<ControlButtons> {
  MoveDirection? _pressed;

  void _setPressed(MoveDirection? direction) {
    setState(() => _pressed = direction);
    widget.onDirectionChanged?.call(direction);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ControlButton(
            icon: Icons.arrow_left,
            pressed: _pressed == MoveDirection.left,
            onPressStart: () => _setPressed(MoveDirection.left),
            onPressEnd: () => _setPressed(null),
          ),
        ),
        Container(width: 4, color: AppColors.background),
        Expanded(
          child: _ControlButton(
            icon: Icons.arrow_right,
            pressed: _pressed == MoveDirection.right,
            onPressStart: () => _setPressed(MoveDirection.right),
            onPressEnd: () => _setPressed(null),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.pressed,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final IconData icon;
  final bool pressed;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onPressStart(),
      onTapUp: (_) => onPressEnd(),
      onTapCancel: onPressEnd,
      child: PixelBevelBox(
        color: AppColors.purple,
        pixelSize: 5,
        pressed: pressed,
        child: Center(child: Icon(icon, color: AppColors.white, size: 48)),
      ),
    );
  }
}
