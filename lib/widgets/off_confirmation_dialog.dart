import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Returns true if the admin confirmed the off command, false/null otherwise.
Future<bool> showOffConfirmationDialog(
  BuildContext context, {
  required int channel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Turn Off Channel'),
      content: Text(
        'Are you sure you want to turn off this channel? '
        'The breaker must be manually reset.\n\nChannel $channel',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Turn Off'),
        ),
      ],
    ),
  );
  return result ?? false;
}
