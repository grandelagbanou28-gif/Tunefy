import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:muzo/providers/settings_provider.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/utils/app_colors.dart';

const String kDefaultFontFamily = 'AR One Sans';

// Extensions from the user's snippet
extension ColorWithHSL on Color {
  HSLColor get hsl => HSLColor.fromColor(this);

  Color withSaturation(double saturation) {
    return hsl.withSaturation(clampDouble(saturation, 0.0, 1.0)).toColor();
  }

  Color withLightness(double lightness) {
    return hsl.withLightness(clampDouble(lightness, 0.0, 1.0)).toColor();
  }

  Color withHue(double hue) {
    return hsl.withHue(clampDouble(hue, 0.0, 360.0)).toColor();
  }
}

extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  String toHex({bool leadingHashSign = true}) =>
      '${((a * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}'
      '${((r * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}'
      '${((g * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}'
      '${((b * 255.0).round() & 0xff).toRadixString(16).padLeft(2, '0')}';
}

// Current Palette Provider
final currentPaletteProvider = FutureProvider<PaletteGenerator?>((ref) async {
  final mediaItem = ref.watch(currentMediaItemProvider).value;

  if (mediaItem?.artUri == null) return null;

  try {
    final imageProvider = NetworkImage(mediaItem!.artUri.toString());
    final paletteGenerator = await PaletteGenerator.fromImageProvider(
      imageProvider,
      maximumColorCount: 20,
    );
    return paletteGenerator;
  } catch (e) {
    debugPrint('Error generating palette: $e');
    return null;
  }
});

// Stable Theme Color Provider to prevent flickering
class ThemeColorNotifier extends StateNotifier<Color?> {
  ThemeColorNotifier(this.ref) : super(null) {
    _init();
  }

  final Ref ref;

  void _init() {
    ref.listen(currentPaletteProvider, (previous, next) {
      next.whenData((palette) {
        if (palette != null) {
          final color =
              palette.dominantColor?.color ??
              palette.darkMutedColor?.color ??
              palette.darkVibrantColor?.color ??
              palette.lightMutedColor?.color ??
              palette.lightVibrantColor?.color;
          if (color != null) {
            state = color;
          }
        }
      });
    });
  }
}

final themeColorProvider = StateNotifierProvider<ThemeColorNotifier, Color?>((
  ref,
) {
  return ThemeColorNotifier(ref);
});

// Dynamic Color Scheme Provider from Device
final dynamicColorSchemeProvider = StateProvider<ColorScheme?>((ref) => null);

/// Tint taken from the artwork of the track that is currently playing, so the
/// whole app can follow the cover the way Material You palettes follow the
/// wallpaper. `null` while nothing plays (or when the user opted out).
final albumArtColorProvider = StateProvider<Color?>((ref) => null);

// Theme Logic Class (Helper)
class ThemeLogic {
  // Global Text Color Controls
  static const Color _darkPrimaryText = AppColors.primaryText;
  static const Color _darkSecondaryText = AppColors.secondaryText;
  static const Color _lightPrimaryText = Colors.black;
  static const Color _lightSecondaryText = Color(0xFF424242);

  static MaterialColor createMaterialColor(Color color) {
    List<double> strengths = <double>[.05];
    Map<int, Color> swatch = {};
    final int r = color.r.toInt(), g = color.g.toInt(), b = color.b.toInt();

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.toARGB32(), swatch);
  }

  /// Applies the Material You accents of [dynamicScheme] on top of the app's
  /// own [base] scheme: the tinted primary/secondary/tertiary take over while
  /// the surfaces stay the ones the app is designed with.
  static ColorScheme tint(ColorScheme? dynamicScheme, ColorScheme base) {
    if (dynamicScheme == null) return base;
    return base.copyWith(
      primary: dynamicScheme.primary,
      onPrimary: dynamicScheme.onPrimary,
      primaryContainer: dynamicScheme.primaryContainer,
      onPrimaryContainer: dynamicScheme.onPrimaryContainer,
      secondary: dynamicScheme.secondary,
      onSecondary: dynamicScheme.onSecondary,
      secondaryContainer: dynamicScheme.secondaryContainer,
      onSecondaryContainer: dynamicScheme.onSecondaryContainer,
      tertiary: dynamicScheme.tertiary,
      onTertiary: dynamicScheme.onTertiary,
    );
  }

  /// Material paints a pale wash under whatever you tap: the ripple
  /// (`splashColor`), the pressed highlight (`highlightColor`) and, on the
  /// M3 buttons, a `overlayColor` state derived from the colour scheme. On this
  /// dark UI that reads as a light flash, and the user wants none of it — so
  /// every theme is post-processed to switch the ink effects off app-wide.
  static ThemeData _noInkFlash(ThemeData theme) {
    const noOverlay = WidgetStatePropertyAll<Color>(Colors.transparent);
    ButtonStyle merged(ButtonStyle? existing) =>
        (existing ?? const ButtonStyle()).copyWith(overlayColor: noOverlay);
    return theme.copyWith(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      textButtonTheme: TextButtonThemeData(style: merged(theme.textButtonTheme.style)),
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: merged(theme.elevatedButtonTheme.style)),
      filledButtonTheme:
          FilledButtonThemeData(style: merged(theme.filledButtonTheme.style)),
      outlinedButtonTheme:
          OutlinedButtonThemeData(style: merged(theme.outlinedButtonTheme.style)),
      iconButtonTheme: IconButtonThemeData(style: merged(theme.iconButtonTheme.style)),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        overlayColor: noOverlay,
      ),
    );
  }

  static ThemeData createThemeData(
    MaterialColor? primarySwatch,
    ThemeType themeType, {
    MaterialColor? titleColorSwatch,
    Color? textColor,
    Brightness? systemBrightness,
    ColorScheme? dynamicColorScheme,
    String fontFamily = kDefaultFontFamily,
    bool isAmoled = false,
  }) {
    // Ensure the effective ColorScheme matches the target brightness
    final Brightness targetBrightness = themeType == ThemeType.light
        ? Brightness.light
        : Brightness.dark;

    ColorScheme? effectiveColorScheme = dynamicColorScheme;
    if (effectiveColorScheme != null &&
        effectiveColorScheme.brightness != targetBrightness) {
      effectiveColorScheme = ColorScheme.fromSeed(
        seedColor: effectiveColorScheme.primary,
        brightness: targetBrightness,
      );
    }

    if (themeType == ThemeType.dark && primarySwatch != null) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.white.withValues(alpha: 0.002),
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: true,
        ),
      );

      final baseTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        ),
        colorScheme: tint(
          effectiveColorScheme,
          ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            secondary: const Color(0xFF888888),
            surface: isAmoled ? Colors.black : const Color(0xFF121212),
            onSurface: Colors.white,
          ),
        ),
        cardColor: isAmoled ? Colors.black : const Color(0xFF181818),
        primaryColorLight: Colors.white,
        primaryColorDark: Colors.white,
        canvasColor: isAmoled ? Colors.black : const Color(0xFF121212),
        scaffoldBackgroundColor: isAmoled ? Colors.black : const Color(0xFF121212), // Darkest shade for bg
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: isAmoled ? Colors.black : const Color(0xFF181818),
          modalBarrierColor: Colors.black54,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: _darkPrimaryText,
          ),
          titleMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: _darkPrimaryText,
          ),
          titleSmall: TextStyle(color: Colors.white70),

          bodyMedium: TextStyle(color: _darkSecondaryText),
          labelMedium: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 23,
            color: _darkPrimaryText,
          ),
          labelSmall: TextStyle(
            fontSize: 15,
            color: _darkSecondaryText,
            letterSpacing: 0,
            fontWeight: FontWeight.bold,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          linearTrackColor: Colors.white10,
          color: Colors.white,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF121212),
          selectedIconTheme: IconThemeData(color: Colors.white),
          unselectedIconTheme: IconThemeData(color: Colors.white70),
          selectedLabelTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          unselectedLabelTextStyle: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.bold,
          ),
        ),
        sliderTheme: const SliderThemeData(
          inactiveTrackColor: Colors.white10,
          activeTrackColor: Colors.white,
          valueIndicatorColor: Color(0xFF181818),
          thumbColor: Colors.white,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.white,
          selectionColor: Colors.white24,
          selectionHandleColor: Colors.white,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white, // Static white color
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          },
        ),
        dialogTheme: DialogThemeData(backgroundColor: isAmoled ? Colors.black : const Color(0xFF181818)),
        tabBarTheme: const TabBarThemeData(indicatorColor: Colors.white),
      );
      return _noInkFlash(baseTheme.copyWith(
        textTheme: fontFamily == 'Karst'
            ? baseTheme.textTheme.apply(fontFamily: 'Karst')
            : GoogleFonts.getTextTheme(fontFamily, baseTheme.textTheme),
      ));
    } else if (themeType == ThemeType.light) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.black.withValues(alpha: 0.002),
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: true,
        ),
      );
      final baseTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.dark,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
        ),
        canvasColor: const Color(0xFFFFFFFF),
        primaryColor: Colors.black,
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        colorScheme: tint(
          effectiveColorScheme,
          const ColorScheme.light(
            primary: Colors.black,
            onPrimary: Colors.white,
            secondary: Color(0xFF888888),
            surface: Color(0xFFFFFFFF),
            onSurface: Colors.black,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Colors.black,
          linearTrackColor: Colors.black12,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: _lightPrimaryText,
          ),
          titleMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: _lightPrimaryText,
          ),
          labelMedium: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 23,
            color: _lightPrimaryText,
          ),
          labelSmall: TextStyle(
            fontSize: 15,
            color: _lightSecondaryText,
            letterSpacing: 0,
            fontWeight: FontWeight.bold,
          ),
          bodyMedium: TextStyle(color: _lightSecondaryText),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFFFFFFFF),
          modalBarrierColor: Colors.black26,
        ),
        sliderTheme: const SliderThemeData(
          thumbColor: Colors.black,
          activeTrackColor: Colors.black,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          focusColor: Colors.black,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            borderSide: BorderSide(color: Colors.black26),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            borderSide: BorderSide(color: Colors.black12),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.black, // Static black color
          ),
        ),
      );
      return _noInkFlash(baseTheme.copyWith(
        textTheme: fontFamily == 'Karst'
            ? baseTheme.textTheme.apply(fontFamily: 'Karst')
            : GoogleFonts.getTextTheme(fontFamily, baseTheme.textTheme),
      ));
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.white.withValues(alpha: 0.002),
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarContrastEnforced: true,
        ),
      );
      final baseTheme = ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        ),
        canvasColor: isAmoled ? Colors.black : const Color(0xFF121212), // Spotify Dark Gray
        primaryColor: Colors.white,
        scaffoldBackgroundColor: isAmoled ? Colors.black : const Color(0xFF121212),
        colorScheme: tint(
          effectiveColorScheme,
          ColorScheme.dark(
            primary: Colors.white,
            onPrimary: Colors.black,
            secondary: const Color(0xFF888888),
            surface: isAmoled ? Colors.black : const Color(0xFF181212),
            onSurface: Colors.white,
          ),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Colors.white,
          linearTrackColor: Colors.white10,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.bold,
            color: _darkPrimaryText,
          ),
          titleMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: _darkPrimaryText,
          ),
          labelMedium: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 23,
            color: _darkPrimaryText,
          ),
          labelSmall: TextStyle(
            fontSize: 15,
            color: _darkSecondaryText,
            letterSpacing: 0,
            fontWeight: FontWeight.bold,
          ),
          bodyMedium: TextStyle(color: _darkSecondaryText),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: isAmoled ? Colors.black : const Color(0xFF181818),
          modalBarrierColor: Colors.black54,
        ),
        sliderTheme: const SliderThemeData(
          thumbColor: Colors.white,
          activeTrackColor: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          focusColor: Colors.white,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            borderSide: BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            borderSide: BorderSide(color: Colors.white12),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white, // Static white color
          ),
        ),
      );
      return _noInkFlash(baseTheme.copyWith(
        textTheme: fontFamily == 'Karst'
            ? baseTheme.textTheme.apply(fontFamily: 'Karst')
            : GoogleFonts.getTextTheme(fontFamily, baseTheme.textTheme),
      ));
    }
  }
}

// Dynamic Theme Provider
final themeProvider = Provider<ThemeData>((ref) {
  final settings = ref.watch(settingsProvider);
  final themeType = settings.themeType;
  final fontFamily = settings.appFontFamily;
  final isAmoled = settings.isAmoled;
  final albumArtColor = ref.watch(albumArtColorProvider);
  final storage = ref.watch(storageServiceProvider);

  // Resolve auto → system brightness
  final effectiveType = themeType == ThemeType.auto
      ? (WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.light
            ? ThemeType.light
            : ThemeType.dark)
      : themeType;

  // Material You follows the artwork of the current track; without a track it
  // falls back to the device wallpaper palette. Either can be switched off,
  // which pins the app back to its Spotify green.
  final brightness =
      effectiveType == ThemeType.light ? Brightness.light : Brightness.dark;
  ColorScheme? dynamicColorScheme;
  if (storage.dynamicColorEnabled) {
    dynamicColorScheme = albumArtColor != null
        ? ColorScheme.fromSeed(seedColor: albumArtColor, brightness: brightness)
        : ref.watch(dynamicColorSchemeProvider);
  }

  if (effectiveType == ThemeType.light) {
    return ThemeLogic.createThemeData(
      null,
      ThemeType.light,
      dynamicColorScheme: dynamicColorScheme,
      fontFamily: fontFamily,
    );
  } else {
    return ThemeLogic.createThemeData(
      null,
      ThemeType.dark,
      dynamicColorScheme: dynamicColorScheme,
      fontFamily: fontFamily,
      isAmoled: isAmoled,
    );
  }
});
