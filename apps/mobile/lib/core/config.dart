/// Cấu hình môi trường (development/staging/production) - đặc tả mục 48.
/// Truyền qua --dart-define khi build, không hard-code secret vào code.
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// V1 chỉ có Nha Trang, nhưng UI không hard-code tên - đọc từ market hiện tại.
  static const String defaultCitySlug = String.fromEnvironment(
    'DEFAULT_CITY_SLUG',
    defaultValue: 'nha-trang',
  );
}
