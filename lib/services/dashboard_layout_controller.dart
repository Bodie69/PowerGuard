import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DashboardViewMode {
  relative,
  absolute,
  stack,
}

enum ChannelDisplayMode { digital, analog }

/// All metric keys a [ChannelCard] can show, in their default display order.
const kAllChannelMetrics = [
  'voltage',
  'current',
  'power',
  'energy',
  'frequency',
  'power_factor',
];

const kChannelMetricLabels = {
  'voltage': 'Voltage',
  'current': 'Current',
  'power': 'Power',
  'energy': 'Energy',
  'frequency': 'Frequency',
  'power_factor': 'Power Factor',
};

const _viewModeKey = 'dashboard_view_mode';
const _channelOrderKey = 'dashboard_channel_order';
const _visibleMetricsKey = 'dashboard_visible_metrics';
const _channelDisplayModesKey = 'dashboard_channel_display_modes';
const _channelColorsKey = 'dashboard_channel_colors';

/// Persists the admin's preferred dashboard layout: grid vs list, the order
/// channel cards appear in, and which metrics show on each card.
class DashboardLayoutController extends ChangeNotifier {
  DashboardViewMode _viewMode = DashboardViewMode.relative;
  List<int> _channelOrder = [1, 2, 3, 4];
  Set<String> _visibleMetrics = kAllChannelMetrics.toSet();
  Map<int, ChannelDisplayMode> _channelDisplayModes = {};
  Map<int, Color> _channelColors = {};
  SharedPreferences? _prefs;

  DashboardViewMode get viewMode => _viewMode;

  List<int> get channelOrder => List.unmodifiable(_channelOrder);

  Set<String> get visibleMetrics => Set.unmodifiable(_visibleMetrics);

  ChannelDisplayMode getChannelDisplayMode(int channel) =>
      _channelDisplayModes[channel] ?? ChannelDisplayMode.digital;

  Color getChannelColor(int channel, Color defaultColor) =>
      _channelColors[channel] ?? defaultColor;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final storedMode = prefs.getString(_viewModeKey);
    if (storedMode != null) {
      _viewMode = DashboardViewMode.values.firstWhere(
        (mode) => mode.name == storedMode,
        orElse: () => DashboardViewMode.relative,
      );
    }

    final storedOrder = prefs.getString(_channelOrderKey);
    if (storedOrder != null) {
      try {
        final decoded = (jsonDecode(storedOrder) as List).cast<int>();
        if (decoded.toSet().containsAll(_channelOrder) &&
            decoded.length == _channelOrder.length) {
          _channelOrder = decoded;
        }
      } catch (_) {
        // Ignore malformed prefs, keep default order.
      }
    }

    final storedMetrics = prefs.getStringList(_visibleMetricsKey);
    if (storedMetrics != null && storedMetrics.isNotEmpty) {
      _visibleMetrics = storedMetrics.toSet()..retainAll(kAllChannelMetrics);
    }

    final storedDisplayModes = prefs.getString(_channelDisplayModesKey);
    if (storedDisplayModes != null) {
      try {
        final decoded = jsonDecode(storedDisplayModes) as Map<String, dynamic>;
        _channelDisplayModes = decoded.map(
          (key, value) => MapEntry(
            int.parse(key),
            ChannelDisplayMode.values.firstWhere((e) => e.name == value),
          ),
        );
      } catch (_) {}
    }

    final storedColors = prefs.getString(_channelColorsKey);
    if (storedColors != null) {
      try {
        final decoded = jsonDecode(storedColors) as Map<String, dynamic>;
        _channelColors = decoded.map(
          (key, value) => MapEntry(int.parse(key), Color(value as int)),
        );
      } catch (_) {}
    }
  }

  Future<void> setViewMode(DashboardViewMode mode) async {
    if (mode == _viewMode) return;
    _viewMode = mode;
    notifyListeners();
    await _prefs?.setString(_viewModeKey, mode.name);
  }

  /// Reorders using the semantics of [ReorderableListView.onReorder].
  Future<void> reorderChannel(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List<int>.from(_channelOrder);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _channelOrder = updated;
    notifyListeners();
    await _prefs?.setString(_channelOrderKey, jsonEncode(_channelOrder));
  }

  Future<void> setMetricVisible(String metric, bool visible) async {
    if (visible == _visibleMetrics.contains(metric)) return;
    final updated = Set<String>.from(_visibleMetrics);
    if (visible) {
      // At least one metric must stay visible.
      updated.add(metric);
    } else if (updated.length > 1) {
      updated.remove(metric);
    } else {
      return;
    }
    _visibleMetrics = updated;
    notifyListeners();
    await _prefs?.setStringList(_visibleMetricsKey, updated.toList());
  }

  Future<void> setChannelDisplayMode(int channel, ChannelDisplayMode mode) async {
    if (_channelDisplayModes[channel] == mode) return;
    _channelDisplayModes[channel] = mode;
    notifyListeners();
    await _prefs?.setString(
      _channelDisplayModesKey,
      jsonEncode(_channelDisplayModes.map((k, v) => MapEntry(k.toString(), v.name))),
    );
  }

  Future<void> setChannelColor(int channel, Color color) async {
    if (_channelColors[channel]?.toARGB32() == color.toARGB32()) return;
    _channelColors[channel] = color;
    notifyListeners();
    await _prefs?.setString(
      _channelColorsKey,
      jsonEncode(_channelColors.map((k, v) => MapEntry(k.toString(), v.toARGB32()))),
    );
  }

  /// Sorts [channels] by the saved channel order, falling back to channel
  /// number for any channel not present in [channelOrder] (e.g. newly seen).
  List<T> sortByChannelOrder<T>(
    List<T> channels,
    int Function(T) channelNumberOf,
  ) {
    final sorted = List<T>.from(channels);
    sorted.sort((a, b) {
      final aIndex = _channelOrder.indexOf(channelNumberOf(a));
      final bIndex = _channelOrder.indexOf(channelNumberOf(b));
      final aRank = aIndex == -1 ? 1 << 30 : aIndex;
      final bRank = bIndex == -1 ? 1 << 30 : bIndex;
      if (aRank != bRank) return aRank.compareTo(bRank);
      return channelNumberOf(a).compareTo(channelNumberOf(b));
    });
    return sorted;
  }
}
