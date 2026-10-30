import 'package:flutter/material.dart';

@immutable
class ThemeSettings {
  const ThemeSettings({this.mode = ThemeMode.dark, this.seedColor = const Color(0xff8290ff), this.cardRadius = 16, this.cardOpacity = 1, this.tintedBackground = false});
  final ThemeMode mode;
  final Color seedColor;
  final double cardRadius;
  final double cardOpacity;
  final bool tintedBackground;

  ThemeSettings copyWith({ThemeMode? mode, Color? seedColor, double? cardRadius, double? cardOpacity, bool? tintedBackground}) => ThemeSettings(mode: mode ?? this.mode, seedColor: seedColor ?? this.seedColor, cardRadius: cardRadius ?? this.cardRadius, cardOpacity: cardOpacity ?? this.cardOpacity, tintedBackground: tintedBackground ?? this.tintedBackground);
}
