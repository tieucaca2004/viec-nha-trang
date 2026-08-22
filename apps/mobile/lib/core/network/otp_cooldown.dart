import 'dart:async';
import 'package:flutter/foundation.dart';

/// Khoá nút "gửi mã OTP" trong đúng số giây server yêu cầu sau khi bị rate limit (HTTP 429).
///
/// Vì sao phải có state DÙNG CHUNG chứ không để mỗi màn tự đếm:
/// - Backend giới hạn theo ĐỊA CHỈ IP + ROUTE. Nhiều lần bấm "Gửi lại mã" ở CÙNG một màn (hoặc mở
///   lại đúng màn đó) vẫn gọi đúng 1 route nên vẫn ăn chung 1 hạn mức - cooldown phải sống lâu
///   hơn State của một màn hình, không tự reset khi build lại widget.
/// - Đăng ký (`/auth/register/email/request`) và đăng nhập (`/auth/login/email/request`) nay là
///   2 ROUTE + 2 HẠN MỨC RIÊNG (xem auth.controller.ts) - vì vậy có 2 khoá riêng [emailRegister]/
///   [emailLogin], không dùng chung nữa: bấm hỏng ở màn Đăng ký không còn khoá nhầm màn Đăng nhập.
///
/// Đây thuần tuý là sửa UX phía client: KHÔNG nới lỏng, KHÔNG bỏ qua rate limit của server.
/// Client chỉ ngừng bắn thêm request trong lúc chắc chắn sẽ bị từ chối, và đếm ngược đúng bằng
/// giá trị `Retry-After` server trả về (không tự bịa con số cho đẹp).
class OtpCooldown {
  /// Hạn mức OTP email cho ĐĂNG KÝ (`/auth/register/email/request|verify`, và "Gửi lại mã" khi
  /// đang ở luồng đăng ký).
  static final OtpCooldown emailRegister = OtpCooldown._('email-register');

  /// Hạn mức OTP email cho ĐĂNG NHẬP (`/auth/login/email/request|verify`, và "Gửi lại mã" khi
  /// đang ở luồng đăng nhập) - route và hạn mức RIÊNG với đăng ký ở trên.
  static final OtpCooldown emailLogin = OtpCooldown._('email-login');

  /// Hạn mức OTP qua SMS: route riêng (`/auth/otp/request`) nên bucket riêng.
  static final OtpCooldown phone = OtpCooldown._('phone');

  final String name;
  OtpCooldown._(this.name);

  /// Số giây còn phải chờ; 0 nghĩa là được phép gửi.
  final ValueNotifier<int> remainingSeconds = ValueNotifier<int>(0);
  Timer? _timer;

  bool get isActive => remainingSeconds.value > 0;

  /// Bắt đầu (hoặc kéo dài) cooldown. Luôn lấy giá trị LỚN HƠN để một phản hồi 429 cũ, ngắn hơn
  /// không vô tình mở khoá sớm.
  void start(int seconds) {
    if (seconds <= 0) return;
    if (seconds <= remainingSeconds.value) return;
    remainingSeconds.value = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = remainingSeconds.value - 1;
      remainingSeconds.value = next > 0 ? next : 0;
      if (next <= 0) {
        timer.cancel();
        _timer = null;
      }
    });
  }

  /// Chỉ dùng cho test - đưa về trạng thái sạch giữa các case.
  @visibleForTesting
  void reset() {
    _timer?.cancel();
    _timer = null;
    remainingSeconds.value = 0;
  }
}
