import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../services/supabase_service.dart';
import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import '../widgets/primary_button.dart';
import '../widgets/standard_card.dart';
import '../widgets/status_chip.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<List<Device>>();
    final device = devices.isEmpty ? null : devices.first;
    final service = context.read<SupabaseService>();
    final themeController = context.watch<ThemeController>();
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, y · h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSmall),
        children: [
          StandardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: DesignTokens.spacingMedium),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto_outlined),
                    ),
                  ],
                  selected: {themeController.themeMode},
                  onSelectionChanged: (selection) =>
                      themeController.setThemeMode(selection.first),
                ),
                const SizedBox(height: DesignTokens.spacingLarge),
                Text(
                  'Accent color',
                  style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: DesignTokens.spacingMedium),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: DesignTokens.spacingSmall,
                    crossAxisSpacing: DesignTokens.spacingSmall,
                  ),
                  itemCount: kAccentPresets.length,
                  itemBuilder: (context, index) {
                    final preset = kAccentPresets[index];
                    final selected = preset.color.toARGB32() ==
                        themeController.accentColor.toARGB32();
                    return GestureDetector(
                      onTap: () => themeController.setAccentColor(preset.color),
                      child: Tooltip(
                        message: preset.name,
                        child: Container(
                          decoration: BoxDecoration(
                            color: preset.color,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                                : null,
                          ),
                          child: selected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          StandardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detailed Customization',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: DesignTokens.spacingLarge),
                Text(
                  'Card Roundness: ${themeController.cardRadius.toInt()}px',
                  style: theme.textTheme.labelLarge,
                ),
                Slider(
                  value: themeController.cardRadius,
                  min: 0,
                  max: 32,
                  divisions: 8,
                  onChanged: (v) => themeController.setCardRadius(v),
                ),
                const SizedBox(height: DesignTokens.spacingSmall),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('True Black Mode'),
                  subtitle: const Text('Pure black background in dark mode'),
                  value: themeController.useTrueBlack,
                  onChanged: (v) => themeController.setUseTrueBlack(v),
                ),
                const Divider(height: DesignTokens.spacingXLarge),
                Text(
                  'UI Density',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: DesignTokens.spacingMedium),
                SegmentedButton<AppDensity>(
                  segments: const [
                    ButtonSegment(value: AppDensity.standard, label: Text('Standard')),
                    ButtonSegment(value: AppDensity.comfortable, label: Text('Comfort')),
                    ButtonSegment(value: AppDensity.compact, label: Text('Compact')),
                  ],
                  selected: {themeController.density},
                  onSelectionChanged: (selection) =>
                      themeController.setDensity(selection.first),
                ),
              ],
            ),
          ),
          StandardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      device?.deviceName ?? 'No device registered',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (device != null)
                      StatusChip(
                        label: device.isOnline ? 'ONLINE' : 'OFFLINE',
                        color: device.isOnline ? AppColors.success : AppColors.danger,
                      ),
                  ],
                ),
                if (device != null) ...[
                  const SizedBox(height: DesignTokens.spacingMedium),
                  _InfoRow('Firmware version', device.firmwareVersion ?? 'Unknown'),
                  _InfoRow(
                    'Last seen',
                    device.lastSeen == null
                        ? 'Never'
                        : dateFormat.format(device.lastSeen!.toLocal()),
                  ),
                ],
              ],
            ),
          ),
          StandardCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMedium,
                vertical: DesignTokens.spacingXSmall,
              ),
              leading: const Icon(Icons.email_outlined),
              title: const Text('Signed in as'),
              subtitle: Text(service.currentUser?.email ?? 'Unknown'),
            ),
          ),
          const SizedBox(height: DesignTokens.spacingLarge),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMedium),
            child: PrimaryButton(
              onPressed: () => service.signOut(),
              label: 'Sign Out',
              icon: Icons.logout,
              isDanger: true,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingXLarge),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXSmall),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          Text(value),
        ],
      ),
    );
  }
}
