import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

const _themeModeKey = 'theme_mode';
const _accentColorKey = 'accent_color';
const _cardRadiusKey = 'card_radius';
const _useTrueBlackKey = 'use_true_black';
const _densityKey = 'visual_density';

enum AppDensity { standard, comfortable, compact }

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = kAccentPresets.first.color;
  double _cardRadius = 12.0;
  bool _useTrueBlack = false;
  AppDensity _density = AppDensity.standard;
  
  SharedPreferences? _prefs;

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  double get cardRadius => _cardRadius;
  bool get useTrueBlack => _useTrueBlack;
  AppDensity get density => _density;

  VisualDensity get visualDensity {
    switch (_density) {
      case AppDensity.standard:
        return VisualDensity.standard;
      case AppDensity.comfortable:
        return VisualDensity.comfortable;
      case AppDensity.compact:
        return VisualDensity.compact;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final storedMode = prefs.getString(_themeModeKey);
    if (storedMode != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == storedMode,
        orElse: () => ThemeMode.system,
      );
    }

    final storedColor = prefs.getInt(_accentColorKey);
    if (storedColor != null) {
      _accentColor = Color(storedColor);
    }

    _cardRadius = prefs.getDouble(_cardRadiusKey) ?? 12.0;
    _useTrueBlack = prefs.getBool(_useTrueBlackKey) ?? false;
    
    final storedDensity = prefs.getString(_densityKey);
    if (storedDensity != null) {
      _density = AppDensity.values.firstWhere(
        (d) => d.name == storedDensity,
        orElse: () => AppDensity.standard,
      );
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs?.setString(_themeModeKey, mode.name);
  }

  Future<void> setAccentColor(Color color) async {
    if (color.toARGB32() == _accentColor.toARGB32()) return;
    _accentColor = color;
    notifyListeners();
    await _prefs?.setInt(_accentColorKey, color.toARGB32());
  }

  Future<void> setCardRadius(double radius) async {
    if (radius == _cardRadius) return;
    _cardRadius = radius;
    notifyListeners();
    await _prefs?.setDouble(_cardRadiusKey, radius);
  }

  Future<void> setUseTrueBlack(bool value) async {
    if (value == _useTrueBlack) return;
    _useTrueBlack = value;
    notifyListeners();
    await _prefs?.setBool(_useTrueBlackKey, value);
  }

  Future<void> setDensity(AppDensity density) async {
    if (density == _density) return;
    _density = density;
    notifyListeners();
    await _prefs?.setString(_densityKey, density.name);
  }
}
