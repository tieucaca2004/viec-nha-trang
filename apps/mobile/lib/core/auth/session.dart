import 'package:flutter/foundation.dart';
import '../storage/secure_token_storage.dart';

/// Trạng thái đăng nhập toàn cục: access/refresh token + vai trò hiện tại.
/// Một tài khoản có thể vừa là người tìm việc vừa là nhà tuyển dụng (đặc tả §5),
/// [activeRole] chỉ quyết định UI đang hiển thị ở chế độ nào.
/// Token lưu qua [SecureTokenStorage] (Keystore/Keychain) - không bao giờ log token (§27).
class Session extends ChangeNotifier {
  final SecureTokenStorage _storage;
  Session({SecureTokenStorage? storage}) : _storage = storage ?? SecureTokenStorage();

  String? accessToken;
  String? refreshToken;
  List<String> roles = [];
  String activeRole = 'JOB_SEEKER';

  bool get isLoggedIn => accessToken != null;
  bool get isEmployer => roles.contains('EMPLOYER');
  bool get isJobSeeker => roles.contains('JOB_SEEKER');

  Future<void> restore() async {
    accessToken = await _storage.readAccessToken();
    refreshToken = await _storage.readRefreshToken();
    roles = await _storage.readRoles();
    if (roles.isEmpty) roles = ['JOB_SEEKER'];
    activeRole = await _storage.readActiveRole() ?? 'JOB_SEEKER';
    notifyListeners();
  }

  Future<void> setTokens({required String access, required String refresh, List<String>? roles}) async {
    accessToken = access;
    refreshToken = refresh;
    if (roles != null) this.roles = roles;
    await _storage.saveTokens(accessToken: access, refreshToken: refresh);
    if (roles != null) await _storage.saveRoles(roles);
    notifyListeners();
  }

  Future<void> setActiveRole(String role) async {
    activeRole = role;
    await _storage.saveActiveRole(role);
    notifyListeners();
  }

  /// Gọi khi refresh token cũng hết hạn / bị revoke - đưa user về màn hình đăng nhập với
  /// thông báo dễ hiểu thay vì lỗi kỹ thuật (đặc tả §26).
  Future<void> logout() async {
    accessToken = null;
    refreshToken = null;
    await _storage.clear();
    notifyListeners();
  }
}
