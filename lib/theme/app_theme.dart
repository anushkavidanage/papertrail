/// Papertrail's visual theme: colour palette and component styling.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Anushka Vidanage

// Add the library directive as we have doc entries above. We publish the above
// meta doc lines in the docs.

library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Brand palette.
//
// Ember orange, from the Papertrail logo, leads. Deep teal (its near
// complement) is the calm secondary for supporting UI, and ink indigo is the
// tertiary accent. Container and surface roles are derived from these seeds
// by Material's tonal palettes, so container / onContainer pairs hold in both
// brightness modes. The primary itself is pinned (see [AppPalette.emberDeep])
// because Material's tone-40 primary drifts from orange to rust.
// ---------------------------------------------------------------------------

abstract final class AppPalette {
  /// Ember orange: the brand colour from the Papertrail logo.
  static const Color ember = Color(0xFFEF6E37);

  /// Ember deepened just enough to clear WCAG AA both for white text on it
  /// (4.9:1) and as text on the cream page (4.7:1). The light-mode primary;
  /// dark mode uses [ember] itself with dark text.
  static const Color emberDeep = Color(0xFFC24A17);

  /// Text on [ember] in dark mode (5.7:1).
  static const Color onEmber = Color(0xFF2A0E00);

  /// Soft peach and its text (7.3:1): the light primary-container pair, for
  /// brand surfaces built outside the theme such as the REGISTER button.
  static const Color emberSoft = Color(0xFFFFDBCE);
  static const Color onEmberSoft = Color(0xFF7F2A00);

  /// Deep teal: secondary, the complement that balances the orange.
  static const Color teal = Color(0xFF17818A);

  /// Ink indigo: tertiary accent.
  static const Color indigo = Color(0xFF4A55A8);

  /// Status seeds. Reserved for meaning (warranty state), never for series.
  static const Color good = Color(0xFF0CA30C);
  static const Color warning = Color(0xFFFAB219);
  static const Color critical = Color(0xFFD03B3B);

  /// Hero gradient: deep ember to burnt sienna. White text clears WCAG AA
  /// (4.5:1) at every point along it.
  static const List<Color> heroGradient = [emberDeep, Color(0xFF9C3811)];
}

// ---------------------------------------------------------------------------
// Theme extension: the colours Material's ColorScheme has no slot for.
// ---------------------------------------------------------------------------

/// A container/on-container colour pair for a status.
@immutable
class StatusColors {
  const StatusColors({required this.container, required this.onContainer});

  final Color container;
  final Color onContainer;

  static StatusColors lerp(StatusColors a, StatusColors b, double t) =>
      StatusColors(
        container: Color.lerp(a.container, b.container, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
      );
}

/// Papertrail-specific colours, read with `PapertrailColors.of(context)`.
@immutable
class PapertrailColors extends ThemeExtension<PapertrailColors> {
  const PapertrailColors({
    required this.chart,
    required this.chartOther,
    required this.good,
    required this.warning,
    required this.critical,
    required this.heroGradient,
    required this.onHero,
  });

  /// Categorical chart colours in fixed slot order. Slot i always belongs to
  /// the same category (see `CategoryColors` in the analytics view), so a
  /// filter never repaints the survivors. Validated for adjacent-pair CVD
  /// separation in both modes against the card surface.
  final List<Color> chart;

  /// The neutral used for the folded "Other" series.
  final Color chartOther;

  final StatusColors good;
  final StatusColors warning;
  final StatusColors critical;

  final List<Color> heroGradient;
  final Color onHero;

  static PapertrailColors of(BuildContext context) =>
      Theme.of(context).extension<PapertrailColors>()!;

  @override
  PapertrailColors copyWith({
    List<Color>? chart,
    Color? chartOther,
    StatusColors? good,
    StatusColors? warning,
    StatusColors? critical,
    List<Color>? heroGradient,
    Color? onHero,
  }) => PapertrailColors(
    chart: chart ?? this.chart,
    chartOther: chartOther ?? this.chartOther,
    good: good ?? this.good,
    warning: warning ?? this.warning,
    critical: critical ?? this.critical,
    heroGradient: heroGradient ?? this.heroGradient,
    onHero: onHero ?? this.onHero,
  );

  @override
  PapertrailColors lerp(PapertrailColors? other, double t) {
    if (other == null) return this;
    return PapertrailColors(
      chart: [
        for (var i = 0; i < chart.length; i++)
          Color.lerp(chart[i], other.chart[i], t)!,
      ],
      chartOther: Color.lerp(chartOther, other.chartOther, t)!,
      good: StatusColors.lerp(good, other.good, t),
      warning: StatusColors.lerp(warning, other.warning, t),
      critical: StatusColors.lerp(critical, other.critical, t),
      heroGradient: [
        for (var i = 0; i < heroGradient.length; i++)
          Color.lerp(heroGradient[i], other.heroGradient[i], t)!,
      ],
      onHero: Color.lerp(onHero, other.onHero, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// Theme construction.
// ---------------------------------------------------------------------------

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  /// Categorical chart slots, light mode, in a fixed order: brand orange
  /// first, then the order that maximised the worst adjacent colour-blind
  /// separation (deutan ΔE 9.2 light / 9.4 dark, OKLab x100) with every
  /// normal-vision neighbour ΔE >= 19. Aqua, yellow and magenta sit below
  /// 3:1 on the light card, so charts using them show values in text too.
  static const List<Color> _chartLight = [
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFF2A78D6), // blue
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF4A3AA7), // violet
    Color(0xFFE34948), // red
  ];

  /// The same eight hues stepped for the dark card surface (all >= 3:1).
  static const List<Color> _chartDark = [
    Color(0xFFD95926), // orange
    Color(0xFF199E70), // aqua
    Color(0xFF3987E5), // blue
    Color(0xFFC98500), // yellow
    Color(0xFFD55181), // magenta
    Color(0xFF008300), // green
    Color(0xFF9085E9), // violet
    Color(0xFFE66767), // red
  ];

  /// The tonal roles Material derives for [seed] in [brightness]: soft
  /// tone-90 containers in light mode and deep ones in dark mode.
  ///
  /// The brand base uses [DynamicSchemeVariant.vibrant] to keep the ember's
  /// warmth; supporting hues use the calmer default so they never compete
  /// with it.
  static ColorScheme _tones(
    Color seed,
    Brightness brightness, {
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  }) => ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: variant,
  );

  static StatusColors _status(Color seed, Brightness brightness) {
    final t = _tones(seed, brightness);
    return StatusColors(
      container: t.primaryContainer,
      onContainer: t.onPrimaryContainer,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final teal = _tones(AppPalette.teal, brightness);
    final indigo = _tones(AppPalette.indigo, brightness);

    final scheme =
        _tones(
          AppPalette.ember,
          brightness,
          variant: DynamicSchemeVariant.vibrant,
        ).copyWith(
          primary: isDark ? AppPalette.ember : AppPalette.emberDeep,
          onPrimary: isDark ? AppPalette.onEmber : Colors.white,
          secondary: teal.primary,
          onSecondary: teal.onPrimary,
          secondaryContainer: teal.primaryContainer,
          onSecondaryContainer: teal.onPrimaryContainer,
          tertiary: indigo.primary,
          onTertiary: indigo.onPrimary,
          tertiaryContainer: indigo.primaryContainer,
          onTertiaryContainer: indigo.onPrimaryContainer,
        );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
    );
    final text = _textTheme(base.textTheme);

    // Cards sit one step off the page so they read as raised without shadows.
    final cardColor = isDark
        ? scheme.surfaceContainer
        : scheme.surfaceContainerLowest;
    final hairline = scheme.outlineVariant.withValues(
      alpha: isDark ? 0.5 : 0.7,
    );
    final rounded12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [
        PapertrailColors(
          chart: isDark ? _chartDark : _chartLight,
          chartOther: isDark
              ? const Color(0xFF6E6A66)
              : const Color(0xFFA8A29D),
          good: _status(AppPalette.good, brightness),
          warning: _status(AppPalette.warning, brightness),
          critical: _status(AppPalette.critical, brightness),
          heroGradient: AppPalette.heroGradient,
          onHero: Colors.white,
        ),
      ],
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          elevation: 0,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: text.labelLarge,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: hairline),
        backgroundColor: cardColor,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        // No labelStyle: a themed one replaces, rather than merges with, the
        // default state-aware label colour (selected vs unselected).
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          side: BorderSide(color: hairline),
          textStyle: text.labelLarge,
        ),
      ),
      listTileTheme: ListTileThemeData(shape: rounded12),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: rounded12,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: rounded12,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
        circularTrackColor: Colors.transparent,
      ),
    );
  }

  /// Tighter, heavier headings for a crisper hierarchy; body text untouched.
  static TextTheme _textTheme(TextTheme t) => t.copyWith(
    displaySmall: t.displaySmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineMedium: t.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    headlineSmall: t.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleLarge: t.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}
