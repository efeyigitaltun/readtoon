import 'package:flutter/material.dart';

/// Uygulamanın tüm renk tanımları.
/// OLED-dostu koyu tema + Pastel Mavi vurgu rengi.
class AppColors {
  AppColors._();

  // ─── Arkaplan Renkleri ─────────────────────────────────────────────────────
  /// Ana ekran arkaplanı – OLED'de tam siyah tasarrufu için çok koyu gri
  static const Color background = Color(0xFF121212);

  /// Kart, BottomSheet, Dialog yüzeyleri
  static const Color surface = Color(0xFF1E1E1E);

  /// Kitap kartı arkaplanı
  static const Color cardBackground = Color(0xFF1A1A1A);

  /// Okuyucu menü arkaplanı (AppBar + BottomBar)
  static const Color readerMenuBackground = Color(0xE6000000); // %90 opak siyah

  // ─── Vurgu Rengi (Accent) ─────────────────────────────────────────────────
  /// İlerleme çubukları, aktif ikonlar, önemli butonlar → Pastel Mavi
  static const Color accent = Color(0xFFAEC6CF);
  static const Color accentLight = Color(0xFFD4E8ED);
  static const Color accentDark = Color(0xFF8BAAB5);

  // ─── Metin Renkleri ────────────────────────────────────────────────────────
  /// Birincil metin – tam beyaz yerine göz yormayan açık gri
  static const Color textPrimary = Color(0xFFE0E0E0);

  /// İkincil / alt bilgi metni
  static const Color textSecondary = Color(0xFFB0B0B0);

  /// Devre dışı / placeholder metin
  static const Color textDisabled = Color(0xFF666666);

  // ─── Durum Renkleri ────────────────────────────────────────────────────────
  static const Color error = Color(0xFFCF6679);
  static const Color success = Color(0xFF81C784);

  // ─── UI Öğeleri ────────────────────────────────────────────────────────────
  /// Ince ayraç çizgileri
  static const Color divider = Color(0xFF2A2A2A);

  /// Shimmer yükleme efekti tabanı
  static const Color shimmerBase = Color(0xFF2A2A2A);
  static const Color shimmerHighlight = Color(0xFF3A3A3A);
}
