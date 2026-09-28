import 'package:flutter/material.dart';

/// App-wide dark palette. The app has no light theme.
class AppColors {
  AppColors._();

  static const background = Color(0xFF000000);
  static const purple = Color(0xFF7C3AED);
  static const purpleDark = Color(0xFF4C1D95);
  static const purpleLight = Color(0xFF9F67FF);
  static const white = Color(0xFFFFFFFF);

  /// Ball and paddle color on the game field.
  static const gameElement = white;
}

const _squareShape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
const _squareBorderRadius = BorderRadius.zero;

/// Thick black outline used across panels/menus for a chunky, pixel-art edge.
const _pixelOutlineShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.zero,
  side: BorderSide(color: Colors.black, width: 3),
);

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    surface: AppColors.purple,
    onSurface: AppColors.white,
    primary: AppColors.purple,
    onPrimary: AppColors.white,
    secondary: AppColors.purpleLight,
    onSecondary: AppColors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.purple,
    foregroundColor: AppColors.white,
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: AppColors.purpleDark,
    shape: _pixelOutlineShape,
    titleTextStyle: TextStyle(
      color: AppColors.white,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
    contentTextStyle: TextStyle(color: AppColors.white),
  ),
  listTileTheme: const ListTileThemeData(
    tileColor: AppColors.purple,
    textColor: AppColors.white,
    iconColor: AppColors.white,
    shape: _pixelOutlineShape,
  ),
  dividerTheme: const DividerThemeData(color: AppColors.purpleDark),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.purple,
      foregroundColor: AppColors.white,
      shape: _pixelOutlineShape,
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.white,
      shape: _squareShape,
    ),
  ),
  textTheme: const TextTheme().apply(
    bodyColor: AppColors.white,
    displayColor: AppColors.white,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    filled: true,
    fillColor: AppColors.purpleDark,
    hintStyle: TextStyle(color: Colors.white54),
    border: OutlineInputBorder(borderRadius: _squareBorderRadius),
    focusedBorder: OutlineInputBorder(
      borderRadius: _squareBorderRadius,
      borderSide: BorderSide(color: AppColors.purpleLight),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: _squareBorderRadius,
      borderSide: BorderSide(color: AppColors.purple),
    ),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: AppColors.purple,
    contentTextStyle: TextStyle(color: AppColors.white),
    shape: _pixelOutlineShape,
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(
    color: AppColors.white,
  ),
);
