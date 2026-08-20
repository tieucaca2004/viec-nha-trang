import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/session.dart';
import '../../core/network/api_exception.dart';
import '../../features/auth/presentation/phone_login_screen.dart';

/// Xác thực THEO NGỮ CẢNH (đặc tả AUTH UX Part 6/Part 8) - dùng khi 1 khách (chưa đăng nhập) bấm
/// vào 1 hành động THỰC SỰ cần tài khoản (ứng tuyển, lưu việc, đăng tin...). Hiện lý do ngắn gọn +
/// 2 lựa chọn (TIẾP TỤC/ĐỂ SAU) trước khi đẩy sang màn OTP - không đẩy thẳng vào form đăng ký như
/// một "Đăng nhập" chung chung, và không bắt user hiểu khái niệm access token/refresh token/phiên.
/// Trả về true nếu xác thực thành công (OTP đúng) - PhoneLoginScreen ở chế độ [returnOnSuccess]
/// chỉ pop về đây, KHÔNG điều hướng sang MainNavScaffold, để caller tự tiếp tục đúng hành động ban
/// đầu (đặc tả Part 6 - không mất ngữ cảnh, không bị đá về Home).
Future<bool> requireAuthentication(BuildContext context, {required String reason}) async {
  final proceed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(reason, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('TIẾP TỤC'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('ĐỂ SAU'),
            ),
          ],
        ),
      ),
    ),
  );
  if (proceed != true) return false;
  if (!context.mounted) return false;

  final authenticated = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const PhoneLoginScreen(returnOnSuccess: true)),
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
