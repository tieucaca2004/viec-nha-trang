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

  /// Sửa lỗi High #7 (FULL AUDIT): trước đây chỉ xoá token cục bộ, refresh token vẫn hợp lệ trên
  /// server. Gọi POST /auth/logout để thu hồi refresh token thật TRƯỚC khi xoá session cục bộ.
  /// Best-effort: nếu request thất bại (mất mạng, server lỗi...) vẫn phải cho phép đăng xuất cục
  /// bộ - không được chặn người dùng chỉ vì gọi API logout không thành công.
  Future<void> logout() async {
    final refreshToken = session.refreshToken;
    if (refreshToken != null) {
      try {
        await api.post('/auth/logout', body: {'refreshToken': refreshToken});
      } catch (_) {
        // Không chặn đăng xuất cục bộ khi API logout thất bại - xem docstring ở trên.
      }
    }
    await session.logout();
  }
}
