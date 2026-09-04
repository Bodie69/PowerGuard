import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

class StandardCard extends StatelessWidget {
  const StandardCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(DesignTokens.spacingMedium),
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        child: content,
      );
    }

    return Card(
      margin: margin ?? const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMedium,
        vertical: DesignTokens.spacingSmall,
      ),
      child: content,
    );
  }
}
