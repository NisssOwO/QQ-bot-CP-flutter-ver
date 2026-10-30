import 'package:flutter/material.dart';

@immutable
class ThemeSettings {
  const ThemeSettings({this.mode = ThemeMode.dark, this.seedColor = const Color(0xff8290ff), this.cardRadius = 16});
  final ThemeMode mode;
  final Color seedColor;
  final double cardRadius;

  ThemeSettings copyWith({ThemeMode? mode, Color? seedColor, double? cardRadius}) => ThemeSettings(mode: mode ?? this.mode, seedColor: seedColor ?? this.seedColor, cardRadius: cardRadius ?? this.cardRadius);
}
