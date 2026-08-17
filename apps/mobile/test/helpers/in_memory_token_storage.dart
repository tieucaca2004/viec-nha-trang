import 'package:viec_nha_trang/core/storage/secure_token_storage.dart';

/// Thay [SecureTokenStorage] bằng bộ nhớ trong test - `flutter_secure_storage` cần platform
/// channel thật (Keystore/Keychain) không có sẵn khi chạy `flutter test` trên host.
class InMemoryTokenStorage implements SecureTokenStorage {
  String? _accessToken;
  String? _refreshToken;
  List<String> _roles = [];
  String? _activeRole;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> saveRoles(List<String> roles) async => _roles = roles;

  @override
  Future<List<String>> readRoles() async => _roles;

  @override
  Future<void> saveActiveRole(String role) async => _activeRole = role;

  @override
  Future<String?> readActiveRole() async => _activeRole;

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _roles = [];
    _activeRole = null;
  }
}
