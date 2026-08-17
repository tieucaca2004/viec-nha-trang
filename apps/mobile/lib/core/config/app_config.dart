/// Cấu hình môi trường (DEV/STAGING/PRODUCTION) - đặc tả Phase 3 §4/§34.
/// Truyền qua --dart-define khi build, KHÔNG hard-code URL production vào source.
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static bool get isProduction => environment == 'production';

  /// V1 chỉ có Nha Trang, nhưng UI không hard-code tên (đặc tả §36: không hard-code Nha Trang
  /// vào business logic) - đọc từ market hiện tại, backend quyết định danh sách khu vực thật.
  static const String defaultCitySlug = String.fromEnvironment(
    'DEFAULT_CITY_SLUG',
    defaultValue: 'nha-trang',
  );
}
