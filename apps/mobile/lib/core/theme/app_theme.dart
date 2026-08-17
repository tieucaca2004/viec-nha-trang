import 'package:flutter/material.dart';

/// Theme dùng chung - mobile-first, chữ lớn, tương phản tốt, ít animation (đặc tả §24/§29).
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    return ThemeData(
      colorSchemeSeed: const Color(0xFF0F9D58),
      useMaterial3: true,
      visualDensity: VisualDensity.comfortable,
      textTheme: const TextTheme().apply(fontSizeFactor: 1.05),
      // Touch target đủ lớn (§29 accessibility) - Material 3 mặc định đã >= 48dp,
      // giữ nguyên mặc định thay vì thu nhỏ.
    );
  }
}
