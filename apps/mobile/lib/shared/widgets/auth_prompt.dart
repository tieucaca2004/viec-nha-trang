import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/network/api_exception.dart';
import '../../features/auth/presentation/auth_gate_screen.dart';

/// Xác thực THEO NGỮ CẢNH - dùng khi 1 khách (chưa đăng nhập) bấm vào 1 hành động THỰC SỰ cần tài
/// khoản (ứng tuyển, lưu việc, đăng tin...). Giải thích lý do rồi để người dùng CHỌN đăng ký (email
/// + email OTP) hay đăng nhập (tài khoản sẵn có) - xem AuthGateScreen.
///
/// Bug thật đã sửa: trước đây hàm này đẩy thẳng sang PhoneLoginScreen, nên mọi hành động - kể cả
/// "Đăng tin ngay" của nhà tuyển dụng mới - đều hiện màn "Xác thực số điện thoại", biến phone OTP
/// thành cửa đăng ký mặc định thay vì email OTP.
///
/// Trả về true nếu xác thực thành công - các màn con chạy ở chế độ `returnOnSuccess` nên chỉ pop
/// về đây, KHÔNG điều hướng sang MainNavScaffold, để caller tự tiếp tục đúng hành động ban đầu
/// (không mất ngữ cảnh, không bị đá về Home).
Future<bool> requireAuthentication(
  BuildContext context, {
  required String reason,
  String intendedRole = 'JOB_SEEKER',
}) async {
  final authenticated = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => AuthGateScreen(reason: reason, intendedRole: intendedRole)),
  );
  return authenticated == true;
}

/// Chạy [action] - nếu đang là khách thì hỏi xác thực TRƯỚC (đặc tả Part 6); nếu phiên hết hạn
/// giữa chừng (401, đặc tả Part 7 "session expires during use") thì hỏi xác thực lại rồi TỰ ĐỘNG
/// thử lại đúng [action] một lần, không cần user lặp lại thao tác ban đầu. Trả về `null` khi user
/// từ chối xác thực (KHÔNG coi là lỗi - không hiện thông báo lỗi kỹ thuật), ném lại [ApiException]
/// gốc cho mọi lỗi khác (network, validation...) để caller tự hiển thị đúng thông báo.
Future<T?> runWithAuth<T>(
  BuildContext context, {
  required String reason,
  required Future<T> Function() action,
}) async {
  final session = context.read<Session>();
  if (!session.isLoggedIn) {
    final ok = await requireAuthentication(context, reason: reason);
    if (!ok) return null;
  }
  if (!context.mounted) return null;

  try {
    return await action();
  } on ApiException catch (e) {
    if (!e.isUnauthorized) rethrow;
    // Phiên đã hết hạn (refresh token cũng không còn hợp lệ - ApiClient đã tự đăng xuất cục bộ) -
    // hỏi xác thực lại NGAY TẠI ĐÂY thay vì chỉ báo lỗi, rồi thử lại đúng hành động ban đầu.
    if (!context.mounted) return null;
    final ok = await requireAuthentication(context, reason: reason);
    if (!ok) return null;
    if (!context.mounted) return null;
    return await action();
  }
}
