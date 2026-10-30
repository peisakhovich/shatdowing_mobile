import 'package:flutter/material.dart';

class PlayerControls extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSettings;
  final VoidCallback? onRepeat;
  final bool repeatEnabled;

  const PlayerControls({
    super.key,
    required this.child,
    required this.onSettings,
    required this.onRepeat,
    this.repeatEnabled = false,
  });

  Widget _buildSideButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: selected ? Colors.deepOrange : null,
          foregroundColor: selected ? Colors.white : null,
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSideButton(
          context: context,
          icon: Icons.settings,
          tooltip: 'Настройки',
          onPressed: onSettings,
        ),
        const SizedBox(width: 12),
        child,
        const SizedBox(width: 12),
        _buildSideButton(
          context: context,
          icon: Icons.repeat,
          tooltip: repeatEnabled ? 'Повтор включён: ×5' : 'Повтор выключен',
          onPressed: onRepeat,
          selected: repeatEnabled,
        ),
      ],
    );
  }
}
