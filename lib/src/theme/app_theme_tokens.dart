import 'package:flutter/material.dart';

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({required this.muted, required this.success, required this.warning, required this.error});

  final Color muted;
  final Color success;
  final Color warning;
  final Color error;

  static AppThemeTokens of(BuildContext context) => Theme.of(context).extension<AppThemeTokens>()!;

  @override
  AppThemeTokens copyWith({Color? muted, Color? success, Color? warning, Color? error}) => AppThemeTokens(
        muted: muted ?? this.muted,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        error: error ?? this.error,
      );

  @override
  AppThemeTokens lerp(covariant AppThemeTokens? other, double t) {
    if (other == null) return this;
    return AppThemeTokens(
      muted: Color.lerp(muted, other.muted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}
