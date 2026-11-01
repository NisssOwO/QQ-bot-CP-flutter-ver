import 'package:flutter/material.dart';

import 'app_theme_tokens.dart';
import 'theme_controller.dart';

/// The app ships a single dark palette; only the seed colour, corner radius and
/// card opacity stay adjustable so every page keeps the same contrast.
class AppPalette {
  const AppPalette._();

  static const background = Color(0xFF0B1114);
  static const surface = Color(0xFF121A1E);
  static const surfaceAlt = Color(0xFF18242B);
  static const outline = Color(0xFF24333A);
  static const muted = Color(0xFF93A6AE);
  static const success = Color(0xFF3DDC97);
  static const warning = Color(0xFFFFC46B);
  static const error = Color(0xFFFF8B87);
  static const heroStart = Color(0xFF0C6C82);
  static const heroEnd = Color(0xFF17B3A6);

  static const defaultSeed = Color(0xFF0E7490);
}

@immutable
class AppSurfaceTokens extends ThemeExtension<AppSurfaceTokens> {
  const AppSurfaceTokens({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.outline,
    required this.mutedText,
    required this.heroStart,
    required this.heroEnd,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color outline;
  final Color mutedText;
  final Color heroStart;
  final Color heroEnd;

  static AppSurfaceTokens of(BuildContext context) => Theme.of(context).extension<AppSurfaceTokens>()!;

  @override
  AppSurfaceTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? outline,
    Color? mutedText,
    Color? heroStart,
    Color? heroEnd,
  }) =>
      AppSurfaceTokens(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        outline: outline ?? this.outline,
        mutedText: mutedText ?? this.mutedText,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
      );

  @override
  AppSurfaceTokens lerp(covariant AppSurfaceTokens? other, double t) {
    if (other == null) return this;
    return AppSurfaceTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
    );
  }
}

/// Shared card surface: soft border instead of a shadow, so lists of cards stay calm
/// on the dark background.
class AppCard extends StatelessWidget {
  const AppCard({super.key, this.title, this.trailing, this.subtitle, this.child, this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16)});

  final String? title;
  final Widget? trailing;
  final String? subtitle;
  final Widget? child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    final radius = Theme.of(context).cardTheme.shape is RoundedRectangleBorder
        ? ((Theme.of(context).cardTheme.shape as RoundedRectangleBorder).borderRadius as BorderRadius).topLeft.x
        : 16.0;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? tokens.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tokens.outline),
      ),
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (title != null)
          Row(children: [
            Expanded(child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (trailing != null) trailing!,
          ]),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: tokens.mutedText))),
        if (title != null) const SizedBox(height: 10),
        if (child != null) child!,
      ]),
    );
  }
}

ThemeData buildAppTheme(ThemeSettings settings) {
  final scheme = ColorScheme.fromSeed(seedColor: settings.seedColor, brightness: Brightness.dark).copyWith(
    surface: AppPalette.surface,
    onSurface: const Color(0xFFE6EDF0),
  );
  final cardColor = AppPalette.surface.withValues(alpha: settings.cardOpacity);
  final inputFill = AppPalette.surfaceAlt.withValues(alpha: settings.cardOpacity);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: settings.tintedBackground ? const Color(0xFF0A1418) : AppPalette.background,
    canvasColor: settings.tintedBackground ? const Color(0xFF0A1418) : AppPalette.background,
    appBarTheme: AppBarTheme(
      backgroundColor: (settings.tintedBackground ? const Color(0xFF0A1418) : AppPalette.background).withValues(alpha: 0.94),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFE6EDF0)),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(settings.cardRadius)),
    ),
    dividerTheme: const DividerThemeData(color: AppPalette.outline, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppPalette.surface,
      indicatorColor: settings.seedColor.withValues(alpha: 0.22),
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? const Color(0xFFE6EDF0) : AppPalette.muted,
          )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: settings.seedColor)),
      labelStyle: const TextStyle(color: AppPalette.muted, fontSize: 13),
      hintStyle: const TextStyle(color: AppPalette.muted, fontSize: 13),
      helperStyle: const TextStyle(color: AppPalette.muted, fontSize: 11.5),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), side: const BorderSide(color: AppPalette.outline), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: const Color(0xFF7FD8E8))),
    extensions: const [
      AppThemeTokens(muted: AppPalette.muted, success: AppPalette.success, warning: AppPalette.warning, error: AppPalette.error),
      AppSurfaceTokens(
        background: AppPalette.background,
        surface: AppPalette.surface,
        surfaceAlt: AppPalette.surfaceAlt,
        outline: AppPalette.outline,
        mutedText: AppPalette.muted,
        heroStart: AppPalette.heroStart,
        heroEnd: AppPalette.heroEnd,
      ),
    ],
  );
}