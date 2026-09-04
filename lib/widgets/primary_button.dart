import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.isDanger = false,
    this.fullWidth = true,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool isLoading;
  final bool isDanger;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDanger ? theme.colorScheme.error : theme.colorScheme.primary;

    Widget child = isLoading
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: DesignTokens.spacingSmall),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );

    final button = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevationNone,
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spacingMedium,
          horizontal: DesignTokens.spacingLarge,
        ),
      ),
      child: child,
    );

    if (fullWidth) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: button,
      );
    }

    return button;
  }
}
