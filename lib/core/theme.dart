import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  // Preserve Shirr's original monochrome palette and bundled typefaces.
  static const colorLightRank1 = Color(0xFF000000);
  static const colorLightRank2 = Color(0xFFAEAEAE);
  static const colorLightRank3 = Color(0xFFD5D5D5);
  static const colorLightRank4 = Color(0xFFFCFCFA);
  static const colorDarkRank1 = Color(0xFFFFFFFF);
  static const colorDarkRank2 = Color(0xFF777777);
  static const colorDarkRank3 = Color(0xFF303030);
  static const colorDarkRank4 = Color(0xFF000000);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? colorLightRank3 : const Color(0xFF1A1A1A);
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.grey,
      brightness: brightness,
      primary: ink,
      onPrimary: dark ? Colors.black : Colors.white,
      secondary: ink,
      surface: dark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
      onSurface: ink,
      surfaceContainer:
          dark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
    ).copyWith(
      primaryContainer:
          dark ? const Color(0xFF303030) : const Color(0xFFE5E5E5),
      onPrimaryContainer: ink,
      secondaryContainer:
          dark ? const Color(0xFF303030) : const Color(0xFFE5E5E5),
      onSecondary: dark ? Colors.black : Colors.white,
      onSecondaryContainer: ink,
      tertiary: ink,
      onTertiary: dark ? Colors.black : Colors.white,
      tertiaryContainer:
          dark ? const Color(0xFF303030) : const Color(0xFFE5E5E5),
      onTertiaryContainer: ink,
      surfaceDim: dark ? const Color(0xFF080808) : const Color(0xFFE5E5E5),
      surfaceBright: dark ? const Color(0xFF303030) : Colors.white,
      surfaceContainerLowest: dark ? Colors.black : Colors.white,
      surfaceContainerLow:
          dark ? const Color(0xFF111111) : const Color(0xFFFAFAFA),
      surfaceContainerHigh:
          dark ? const Color(0xFF252525) : const Color(0xFFEAEAEA),
      surfaceContainerHighest:
          dark ? const Color(0xFF303030) : const Color(0xFFE0E0E0),
      onSurfaceVariant:
          dark ? const Color(0xFFAAAAAA) : const Color(0xFF555555),
      outline: const Color(0xFF777777),
      outlineVariant: dark ? const Color(0xFF404040) : const Color(0xFFCCCCCC),
      surfaceTint: Colors.transparent,
      inverseSurface: dark ? const Color(0xFFEAEAEA) : const Color(0xFF202020),
      onInverseSurface: dark ? Colors.black : Colors.white,
      inversePrimary: dark ? Colors.black : Colors.white,
      error: ink,
      onError: dark ? Colors.black : Colors.white,
      errorContainer: dark ? const Color(0xFF303030) : const Color(0xFFE5E5E5),
      onErrorContainer: ink,
    );
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      fontFamily: Constants.fontFamilyBody,
      scaffoldBackgroundColor: dark ? colorDarkRank4 : colorLightRank4,
      dividerColor: dark ? colorDarkRank3 : colorLightRank3,
    );
    return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
        headlineLarge: TextStyle(
          fontFamily: Constants.fontFamilySubHead,
          fontSize: 32,
          color: ink,
        ),
        headlineMedium: TextStyle(
          fontFamily: Constants.fontFamilySubHead,
          fontSize: 28,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontFamily: Constants.fontFamilySubHead,
          fontSize: 24,
          color: ink,
        ),
        bodyMedium: TextStyle(
          fontFamily: Constants.fontFamilyBody,
          fontSize: 18,
          height: 1.35,
          color: ink,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? colorDarkRank4 : colorLightRank4,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
      ),
      chipTheme: theme.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: dark ? colorDarkRank3 : colorLightRank3),
        selectedColor: dark ? colorDarkRank3 : colorLightRank3,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: ink,
        selectedTileColor:
            dark ? const Color(0xFF252525) : const Color(0xFFEAEAEA),
        textColor: ink,
        iconColor: ink,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF080808) : Colors.white,
        modalBackgroundColor: dark ? const Color(0xFF080808) : Colors.white,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: ink.withValues(alpha: .35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbColor: ink,
        activeTrackColor: ink,
        inactiveTrackColor: dark ? colorDarkRank2 : colorLightRank2,
      ),
    );
  }

  static final lightTheme = _theme(Brightness.light);
  static final darkTheme = _theme(Brightness.dark);
}
