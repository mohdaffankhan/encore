import 'package:flutter/material.dart';

/// One of Encore's named themes: all dark, each with its own accent, brand
/// gradient, and a faint tint in the background layers.
class EncoreTheme {
  const EncoreTheme(
    this.name, {
    required this.accent,
    required this.gold,
    required this.coral,
    required this.tint,
    this.tintAmount = 0.07,
  });

  final String name;
  final Color accent;

  /// The brand gradient's two ends (gold to coral in Ember).
  final Color gold;
  final Color coral;

  /// Mixed into the near-black layers, [tintAmount] of it.
  final Color tint;
  final double tintAmount;
}

const encoreThemes = [
  EncoreTheme(
    'Ember',
    accent: Color(0xFFFF8A4C),
    gold: Color(0xFFFFC466),
    coral: Color(0xFFFF5448),
    tint: Color(0xFF000000),
    tintAmount: 0,
  ),
  EncoreTheme(
    'Ocean',
    accent: Color(0xFF4CB4FF),
    gold: Color(0xFF6EE7F9),
    coral: Color(0xFF3B6FFF),
    tint: Color(0xFF1E4D8C),
  ),
  EncoreTheme(
    'Forest',
    accent: Color(0xFF4FD68C),
    gold: Color(0xFFC4F06A),
    coral: Color(0xFF22B573),
    tint: Color(0xFF1F5C3A),
  ),
  EncoreTheme(
    'Orchid',
    accent: Color(0xFFC08BFF),
    gold: Color(0xFFF29BFF),
    coral: Color(0xFF7E5CFF),
    tint: Color(0xFF4B2A7A),
  ),
  EncoreTheme(
    'Rose',
    accent: Color(0xFFFF6E9C),
    gold: Color(0xFFFFB29B),
    coral: Color(0xFFFF3D7F),
    tint: Color(0xFF7A2244),
  ),
  EncoreTheme(
    'Graphite',
    accent: Color(0xFFE4E4E9),
    // Dark enough for white icons on it (the liked songs heart).
    gold: Color(0xFFA6A6AE),
    coral: Color(0xFF45454D),
    tint: Color(0xFF000000),
    tintAmount: 0,
  ),
];

/// Encore's palette: near-black layers, Apple-style greys, and one accent
/// used sparingly, from the chosen [EncoreTheme]. Player screens take
/// their accent from the artwork.
abstract final class EncoreColors {
  static EncoreTheme _theme = encoreThemes.first;
  static EncoreTheme get theme => _theme;

  /// Switches the theme's colours (the app then redraws: see
  /// [redrawAll]).
  static set theme(EncoreTheme theme) {
    _theme = theme;
    Color layer(int argb) =>
        Color.lerp(Color(argb), theme.tint, theme.tintAmount)!;
    background = layer(0xFF09090B);
    surface = layer(0xFF111114);
    surfaceRaised = layer(0xFF18181C);
    surfaceHigh = layer(0xFF212126);
    surfaceHighest = layer(0xFF2A2A30);
    accent = theme.accent;
    accentGold = theme.gold;
    accentCoral = theme.coral;
    brandGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [accentGold, accentCoral],
    );
  }

  static Color background = const Color(0xFF09090B);
  static Color surface = const Color(0xFF111114);
  static Color surfaceRaised = const Color(0xFF18181C);
  static Color surfaceHigh = const Color(0xFF212126);
  static Color surfaceHighest = const Color(0xFF2A2A30);
  static const hairline = Color(0x14FFFFFF);
  static const hover = Color(0x0FFFFFFF);

  static const text = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFF9A9AA2);
  static const textTertiary = Color(0xFF5E5E66);

  static Color accent = const Color(0xFFFF8A4C);
  static Color accentGold = const Color(0xFFFFC466);
  static Color accentCoral = const Color(0xFFFF5448);

  static LinearGradient brandGradient = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFC466), Color(0xFFFF5448)],
  );
}

/// Rebuilds every widget under [context], so colours read from
/// [EncoreColors] (many in const-free build methods) take a new theme,
/// keeping the app's state (the page open, scroll positions).
void redrawAll(BuildContext context) {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}

const _font = 'PlusJakartaSans';

ThemeData appTheme() {
  const c = EncoreColors.text;
  const muted = EncoreColors.textSecondary;
  final colors =
      ColorScheme.fromSeed(
        seedColor: EncoreColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: EncoreColors.accent,
        onPrimary: Colors.black,
        secondary: EncoreColors.text,
        onSecondary: Colors.black,
        surface: EncoreColors.background,
        onSurface: c,
        onSurfaceVariant: muted,
        surfaceContainerLowest: EncoreColors.background,
        surfaceContainerLow: EncoreColors.surface,
        surfaceContainer: EncoreColors.surfaceRaised,
        surfaceContainerHigh: EncoreColors.surfaceHigh,
        surfaceContainerHighest: EncoreColors.surfaceHighest,
        outline: EncoreColors.textTertiary,
        outlineVariant: EncoreColors.hairline,
      );

  const text = TextTheme(
    displaySmall: TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.05,
    ),
    headlineMedium: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodySmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );

  final pill = WidgetStatePropertyAll(const StadiumBorder());
  const pillPadding = WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 22, vertical: 14),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: _font,
    colorScheme: colors,
    textTheme: text.apply(bodyColor: c, displayColor: c),
    scaffoldBackgroundColor: EncoreColors.background,
    canvasColor: EncoreColors.background,
    // Cheap ripples: InkSparkle compiles a shader and redraws every frame.
    splashFactory: InkRipple.splashFactory,
    hoverColor: EncoreColors.hover,
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values) p: const _FadeSlideTransitions(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    iconTheme: const IconThemeData(color: c, size: 22),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(c),
        foregroundColor: const WidgetStatePropertyAll(Colors.black),
        shape: pill,
        padding: pillPadding,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: _font, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(c),
        side: const WidgetStatePropertyAll(
          BorderSide(color: EncoreColors.textTertiary),
        ),
        shape: pill,
        padding: pillPadding,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: _font, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: muted,
        textStyle: const TextStyle(
          fontFamily: _font,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: EncoreColors.surfaceHigh,
      selectedColor: c,
      showCheckmark: false,
      labelStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(
        fontFamily: _font,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(EncoreColors.surfaceHigh),
      overlayColor: WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(StadiumBorder()),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18)),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w500),
      ),
      hintStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: _font,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: EncoreColors.textTertiary,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: EncoreColors.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.fromMap({
        WidgetState.selected: IconThemeData(color: c, size: 24),
        WidgetState.any: IconThemeData(color: EncoreColors.textTertiary),
      }),
      labelTextStyle: WidgetStateProperty.fromMap({
        WidgetState.selected: TextStyle(
          fontFamily: _font,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: c,
        ),
        WidgetState.any: TextStyle(
          fontFamily: _font,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: EncoreColors.textTertiary,
        ),
      }),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 8,
      iconColor: muted,
      titleTextStyle: TextStyle(
        fontFamily: _font,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: c,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: _font,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: EncoreColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: EncoreColors.hairline),
      ),
      textStyle: const TextStyle(
        fontFamily: _font,
        fontWeight: FontWeight.w600,
        color: c,
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: c,
      inactiveTrackColor: EncoreColors.surfaceHighest,
      thumbColor: c,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c,
      linearTrackColor: EncoreColors.surfaceHighest,
    ),
    tabBarTheme: const TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: c,
      labelColor: c,
      unselectedLabelColor: EncoreColors.textTertiary,
      labelStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w700),
      indicatorSize: TabBarIndicatorSize.label,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: EncoreColors.surfaceHighest,
      contentTextStyle: const TextStyle(
        fontFamily: _font,
        fontWeight: FontWeight.w600,
        color: c,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.18)),
    ),
    dividerTheme: const DividerThemeData(
      color: EncoreColors.hairline,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: EncoreColors.surfaceHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        fontFamily: _font,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}

/// A short fade with a slight rise: cheap to render (no snapshots or
/// shadows), unlike the default zoom transition on desktop.
class _FadeSlideTransitions extends PageTransitionsBuilder {
  const _FadeSlideTransitions();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
