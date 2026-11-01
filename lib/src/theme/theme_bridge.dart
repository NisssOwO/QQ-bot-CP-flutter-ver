import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'theme_controller.dart';

class ThemeBridge {
  static const _channel = MethodChannel('qq_bot_cp/runtime');

  static Future<ThemeSettings> load() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('getThemeSettings') ?? {};
    final mode = switch ('${raw['mode'] ?? 'dark'}') { 'light' => ThemeMode.light, 'system' => ThemeMode.system, _ => ThemeMode.dark };
    return ThemeSettings(mode: mode, seedColor: Color((raw['seedColor'] as num?)?.toInt() ?? 0xff8290ff), cardRadius: (raw['cardRadius'] as num?)?.toDouble() ?? 16, cardOpacity: (raw['cardOpacity'] as num?)?.toDouble() ?? 1, tintedBackground: raw['tintedBackground'] == true);
  }

  static Future<void> save(ThemeSettings settings) => _channel.invokeMethod<void>('saveThemeSettings', {'mode': settings.mode.name, 'seedColor': settings.seedColor.toARGB32(), 'cardRadius': settings.cardRadius, 'cardOpacity': settings.cardOpacity, 'tintedBackground': settings.tintedBackground});
}
