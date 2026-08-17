import '../../../core/network/api_client.dart';
import '../../../core/auth/session.dart';

/// Đăng nhập bằng SĐT + OTP (đặc tả §5 gốc, Phase 3 §5). Google/Apple Sign-In: backend hiện
/// trả 501 (chưa implement) - KHÔNG tự bịa endpoint hay UI cho luồng đó, xem docs/MOBILE.md.
class AuthService {
  final ApiClient api;
  final Session session;
  AuthService(this.api, this.session);

  Future<int> requestOtp(String phone) async {
    final res = await api.post('/auth/otp/request', body: {'phone': phone});
    return res['expiresInSeconds'] ?? 300;
  }

  Future<void> verifyOtp(String phone, String code) async {
    final res = await api.post('/auth/otp/verify', body: {'phone': phone, 'code': code});
    await session.setTokens(access: res['accessToken'], refresh: res['refreshToken']);
    await refreshMe();
  }

  Future<void> refreshMe() async {
    final me = await api.get('/me');
    final roles = (me['roles'] as List).map((r) => r.toString()).toList();
    await session.setTokens(access: session.accessToken!, refresh: session.refreshToken!, roles: roles);
  }

  /// Thêm vai trò EMPLOYER vào tài khoản hiện có - không tạo tài khoản mới (đặc tả §5 gốc).
  Future<void> becomeEmployer() async {
    await api.patch('/me/roles', body: {'role': 'EMPLOYER'});
    await refreshMe();
  }

  Future<void> logout() => session.logout();
}
