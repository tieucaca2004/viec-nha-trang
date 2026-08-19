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

  // Đăng ký tài khoản bằng email (đặc tả §1 phase kế tiếp) - KHÔNG dùng SMS OTP cho bước tạo
  // tài khoản nữa. Luồng đăng nhập bằng SĐT (requestOtp/verifyOtp ở trên) vẫn giữ nguyên cho
  // người dùng đã có tài khoản qua phone từ trước.
  Future<int> requestEmailVerification(String email) async {
    final res = await api.post('/auth/register/email/request', body: {'email': email});
    return res['expiresInSeconds'] ?? 600;
  }

  Future<void> verifyEmailAndRegister(String email, String code) async {
    final res = await api.post('/auth/register/email/verify', body: {'email': email, 'code': code});
    await session.setTokens(access: res['accessToken'], refresh: res['refreshToken']);
    await refreshMe();
  }

  // Xác minh số điện thoại cho tài khoản ĐÃ đăng nhập (đặc tả §3) - dùng khi cần trước khi ứng
  // tuyển/đăng tuyển, không phải lúc đăng ký. Tái dùng đúng OtpCode/SmsProvider backend hiện có.
  Future<int> requestPhoneLink(String phone) async {
    final res = await api.post('/auth/phone/link/request', body: {'phone': phone});
    return res['expiresInSeconds'] ?? 300;
  }

  Future<void> verifyPhoneLink(String phone, String code) async {
    await api.post('/auth/phone/link/verify', body: {'phone': phone, 'code': code});
    await refreshMe();
  }

  /// Trả về đầy đủ thông tin tài khoản thật từ /me (phone, isPhoneVerified, email,
  /// isEmailVerified, ...) - dùng để hiển thị trạng thái xác minh phone trên hồ sơ (đặc tả §4).
  Future<Map<String, dynamic>> getMe() async {
    return await api.get('/me') as Map<String, dynamic>;
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
