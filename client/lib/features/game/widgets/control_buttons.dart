import 'package:flutter/material.dart';

import '../../../core/theme.dart';

enum MoveDirection { left, right }

/// Bottom control section: two large hold-to-move buttons. Purely visual for
/// now — pressing highlights the button but doesn't move anything yet.
class ControlButtons extends StatefulWidget {
  const ControlButtons({super.key});

  @override
  State<ControlButtons> createState() => _ControlButtonsState();
}

class _ControlButtonsState extends State<ControlButtons> {
  MoveDirection? _pressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ControlButton(
            icon: Icons.arrow_left,
            pressed: _pressed == MoveDirection.left,
            onPressStart: () => setState(() => _pressed = MoveDirection.left),
            onPressEnd: () => setState(() => _pressed = null),
          ),
        ),
        Container(width: 1, color: AppColors.purpleDark),
        Expanded(
          child: _ControlButton(
            icon: Icons.arrow_right,
            pressed: _pressed == MoveDirection.right,
            onPressStart: () => setState(() => _pressed = MoveDirection.right),
            onPressEnd: () => setState(() => _pressed = null),
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
      child: Container(
        color: pressed ? AppColors.purpleLight : AppColors.purple,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.white, size: 48),
      ),
    );
  }
}
