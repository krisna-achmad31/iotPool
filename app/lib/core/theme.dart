import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Token warna "Mono Blue Glass" (desain v3 di iot.pen, variabel `p-*` & `g-*`).
abstract final class AppColors {
  static const blue = Color(0xFF1C6FE8);
  static const blue2 = Color(0xFF4FB3FF);
  static const ink = Color(0xFF0F1B2D);
  static const ink2 = Color(0xFF5B6B82);
  static const muted = Color(0xFF8C99AD);
  static const tint = Color(0xFFE8F1FF);
  static const bgTop = Color(0xFFF4F7FB);
  static const bgBottom = Color(0xFFE6ECF4);
  static const glass = Color(0xA6FFFFFF);
  static const glassStrong = Color(0xD9FFFFFF);
  static const glassStroke = Color(0xE6FFFFFF);
  static const line = Color(0xFFD8E0F5);
  static const green = Color(0xFF22B573);
  static const greenInk = Color(0xFF138A55);
  static const amber = Color(0xFFF5A524);
  static const amberInk = Color(0xFF9A5B00);
  static const red = Color(0xFFEF4E5A);
  static const redInk = Color(0xFFB4232E);

  static const blueGradient = LinearGradient(colors: [blue, blue2], begin: Alignment.bottomLeft, end: Alignment.topRight);
  static const greyGradient = LinearGradient(colors: [Color(0xFF5B6B82), Color(0xFF93A1B5)], begin: Alignment.bottomLeft, end: Alignment.topRight);
}

ThemeData buildTheme({bool largeText = false}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.blue, primary: AppColors.blue, surface: AppColors.bgTop),
    scaffoldBackgroundColor: AppColors.bgTop,
  );
  final text = GoogleFonts.outfitTextTheme(base.textTheme).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);
  return base.copyWith(
    textTheme: text,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentTextStyle: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFFF7F9FC), showDragHandle: true),
  );
}

/// Gaya teks yang sering dipakai. Ukuran minimal 13 (aksesibilitas lansia).
abstract final class T {
  static TextStyle s(double size, {FontWeight w = FontWeight.w400, Color c = AppColors.ink, double? h, double? ls}) =>
      GoogleFonts.outfit(fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls);
  static TextStyle get title => s(28, w: FontWeight.w600, ls: -0.5);
  static TextStyle get h2 => s(20, w: FontWeight.w600, ls: -0.3);
  static TextStyle get body => s(15, c: AppColors.ink2, h: 1.45);
  static TextStyle get label => s(15, w: FontWeight.w500, c: AppColors.ink2);
  static TextStyle get small => s(13, c: AppColors.ink2);
}
