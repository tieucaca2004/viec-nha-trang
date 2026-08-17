import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lưu JWT bằng secure storage (Keystore trên Android, Keychain trên iOS) - KHÔNG dùng
/// SharedPreferences cho token (đặc tả §27: JWT/session storage phải dùng secure storage).
class SecureTokenStorage {
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  static const _rolesKey = 'roles';
  static const _activeRoleKey = 'activeRole';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveRoles(List<String> roles) => _storage.write(key: _rolesKey, value: roles.join(','));
  Future<List<String>> readRoles() async {
    final raw = await _storage.read(key: _rolesKey);
    if (raw == null || raw.isEmpty) return [];
    return raw.split(',');
  }

  Future<void> saveActiveRole(String role) => _storage.write(key: _activeRoleKey, value: role);
  Future<String?> readActiveRole() => _storage.read(key: _activeRoleKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _rolesKey);
    await _storage.delete(key: _activeRoleKey);
  }
}
